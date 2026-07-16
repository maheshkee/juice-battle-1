#!/usr/bin/env python3
import sys
import time
import wave
import numpy as np
from scipy import signal
from edge_impulse_linux.runner import ImpulseRunner

MODEL_PATH     = "/home/arduino/ArduinoApps/whistle/models/whistle.eim"
THRESHOLD      = 0.95
CONSECUTIVE    = 5
COOLDOWN_SEC   = 4.0
WINDOW_SAMPLES = 16000
STRIDE_SAMPLES = 4000
MODEL_RATE     = 16000
MIC_RATE       = 44100
HP_CUTOFF      = 1000   # high-pass cutoff Hz -- removes fan/exhaust noise

consecutive_count = 0
whistle_count     = 0
last_action_time  = -999.0
last_detect_time  = -999.0
count_finalized   = False
inference_count   = 0

# build high-pass filter once
_hp_b, _hp_a = signal.butter(4, HP_CUTOFF / (MODEL_RATE / 2), btype='high')


def highpass(data):
    return signal.lfilter(_hp_b, _hp_a, data).astype(np.int16)


def resample(data, from_rate, to_rate):
    if from_rate == to_rate:
        return data
    ratio   = to_rate / from_rate
    new_len = int(len(data) * ratio)
    indices = np.linspace(0, len(data) - 1, new_len)
    return np.interp(indices, np.arange(len(data)), data).astype(np.int16)


def process_result(result, now):
    global consecutive_count, whistle_count, last_action_time
    global last_detect_time, count_finalized, inference_count

    if not result or "result" not in result:
        return
    if "classification" not in result["result"]:
        return

    inference_count += 1
    cls     = result["result"]["classification"]
    bg_conf = cls.get("background", 0)
    wh_conf = cls.get("cooker_whistle", 0)
    hs_conf = cls.get("hiss", 0)

    print(f"  [{now:.2f}s] bg={bg_conf:.2f}  whistle={wh_conf:.2f}  hiss={hs_conf:.2f}  "
          f"consec={consecutive_count}  count={whistle_count}")

    # reset consecutive if gap too long
    if now - last_detect_time > 2.0:
        consecutive_count = 0

    if now - last_action_time < COOLDOWN_SEC:
        remaining = COOLDOWN_SEC - (now - last_action_time)
        print(f"  >> cooldown {remaining:.1f}s remaining")
        consecutive_count = 0
        return

    if wh_conf >= THRESHOLD:
        last_detect_time   = now
        consecutive_count += 1
        print(f"  >> ABOVE threshold -- consecutive={consecutive_count}/{CONSECUTIVE}")
    else:
        if consecutive_count > 0:
            print(f"  >> below threshold -- resetting")
        consecutive_count = 0

    if consecutive_count >= CONSECUTIVE:
        consecutive_count = 0
        whistle_count    += 1
        last_action_time  = now
        count_finalized   = False
        print(f"\n  {'*'*40}")
        print(f"  WHISTLE CONFIRMED -- total count = {whistle_count}")
        print(f"  {'*'*40}\n")

    if whistle_count > 0 and not count_finalized:
        if now - last_action_time >= 3.0:
            count_finalized = True
            print(f"\n{'='*50}")
            print(f"  FINAL COUNT: {whistle_count} whistle(s)")
            print(f"{'='*50}\n")
            whistle_count = 0


def test_with_mic():
    import pyaudio

    print(f"\nLoading model: {MODEL_PATH}")
    runner     = ImpulseRunner(MODEL_PATH)
    model_info = runner.init()
    freq       = model_info["model_parameters"]["frequency"]
    n_features = model_info["model_parameters"]["input_features_count"]
    labels     = model_info["model_parameters"]["labels"]

    print(f"Model loaded. Labels: {labels}")
    print(f"High-pass filter: {HP_CUTOFF}Hz cutoff")
    print(f"Threshold: {THRESHOLD}  Consecutive: {CONSECUTIVE}  Cooldown: {COOLDOWN_SEC}s\n")

    pa = pyaudio.PyAudio()

    usb_device_index = None
    print("Available input devices:")
    for i in range(pa.get_device_count()):
        info = pa.get_device_info_by_index(i)
        if info["maxInputChannels"] > 0:
            print(f"  [{i}] {info['name']}")
            if "usb" in info["name"].lower() or "USB" in info["name"]:
                usb_device_index = i

    if usb_device_index is not None:
        print(f"\nUsing USB device [{usb_device_index}]")
    else:
        print(f"\nNo USB device found -- using default")

    mic_stride  = int(MIC_RATE * STRIDE_SAMPLES / MODEL_RATE)
    rolling_buf = np.zeros(n_features, dtype=np.int16)

    stream = pa.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=MIC_RATE,
        input=True,
        input_device_index=usb_device_index,
        frames_per_buffer=mic_stride
    )

    start_time = time.time()
    print("Listening... Ctrl+C to stop.\n")

    try:
        while True:
            raw   = stream.read(mic_stride, exception_on_overflow=False)
            chunk = np.frombuffer(raw, dtype=np.int16)

            # resample 44100 -> 16000
            chunk = resample(chunk, MIC_RATE, MODEL_RATE)[:STRIDE_SAMPLES]

            # apply high-pass filter -- removes fan/exhaust noise
            chunk = highpass(chunk)

            # slide rolling buffer
            rolling_buf[:-STRIDE_SAMPLES] = rolling_buf[STRIDE_SAMPLES:]
            rolling_buf[-STRIDE_SAMPLES:] = chunk

            result = runner.classify(rolling_buf.tolist())
            now    = time.time() - start_time
            process_result(result, now)

    except KeyboardInterrupt:
        print("\nStopped.")
        if whistle_count > 0:
            print(f"Final count: {whistle_count}")
    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()
        runner.stop()


def test_with_wav(wav_path):
    print(f"\nLoading model: {MODEL_PATH}")
    runner     = ImpulseRunner(MODEL_PATH)
    model_info = runner.init()
    freq       = model_info["model_parameters"]["frequency"]
    n_features = model_info["model_parameters"]["input_features_count"]
    labels     = model_info["model_parameters"]["labels"]

    print(f"Model loaded. Labels: {labels}")

    with wave.open(wav_path, "r") as wf:
        orig_rate    = wf.getframerate()
        n_channels   = wf.getnchannels()
        n_frames     = wf.getnframes()
        sample_width = wf.getsampwidth()
        raw          = wf.readframes(n_frames)

    print(f"  Rate: {orig_rate}Hz  Channels: {n_channels}  Duration: {n_frames/orig_rate:.1f}s")

    if sample_width == 2:
        samples = np.frombuffer(raw, dtype=np.int16)
    elif sample_width == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.int16)
    else:
        samples = np.frombuffer(raw, dtype=np.uint8).astype(np.int16)

    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1).astype(np.int16)

    if orig_rate != freq:
        samples = resample(samples, orig_rate, freq)

    n_windows = (len(samples) - n_features) // STRIDE_SAMPLES + 1
    print(f"  Windows: {n_windows}\n")

    for i in range(n_windows):
        start  = i * STRIDE_SAMPLES
        window = samples[start : start + n_features]
        if len(window) < n_features:
            window = np.pad(window, (0, n_features - len(window)))

        window = highpass(window)
        result = runner.classify(window.tolist())
        now    = (start + n_features) / freq
        process_result(result, now)

    if whistle_count > 0 and not count_finalized:
        print(f"\n{'='*50}")
        print(f"  FINAL COUNT (end of file): {whistle_count} whistle(s)")
        print(f"{'='*50}\n")

    runner.stop()
    print(f"\nDone. {inference_count} inferences.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 test_whistle.py --mic")
        print("  python3 test_whistle.py path/to/audio.wav")
        sys.exit(1)

    if sys.argv[1] == "--mic":
        test_with_mic()
    else:
        test_with_wav(sys.argv[1])
