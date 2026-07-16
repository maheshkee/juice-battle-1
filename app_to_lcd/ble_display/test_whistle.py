#!/usr/bin/env python3
# test_whistle.py -- fixed for edge_impulse_linux 1.2.2 classify() API
# Usage: python3 test_whistle.py path/to/audio.wav
# Usage: python3 test_whistle.py --mic

import sys
import time
import wave
import numpy as np
from edge_impulse_linux.runner import ImpulseRunner

# --- CONFIG ---
MODEL_PATH     = "models/cooker_whistle_v1.eim"
THRESHOLD      = 0.90   # confidence to count as whistle
CONSECUTIVE    = 3      # consecutive windows before confirming
COOLDOWN_SEC   = 2.5    # ignore after confirmed whistle
GAP_SEC        = 3.0    # silence gap before finalizing count
SAMPLE_RATE    = 16000
WINDOW_SAMPLES = 16000  # 1 second -- must match input_features_count
STRIDE_SAMPLES = 4000   # 250ms stride -- matches slice_size

# --- STATE ---
consecutive_count = 0
whistle_count     = 0
last_whistle_time = 0.0
last_action_time  = -999.0
count_finalized   = False
inference_count   = 0


def process_result(result, now):
    global consecutive_count, whistle_count, last_whistle_time
    global last_action_time, count_finalized, inference_count

    if not result or "result" not in result:
        return
    if "classification" not in result["result"]:
        return

    inference_count += 1
    cls     = result["result"]["classification"]
    bg_conf = cls.get("background", 0)
    wh_conf = cls.get("cooker_whistle", 0)

    print(f"  [{now:.2f}s] bg={bg_conf:.2f}  whistle={wh_conf:.2f}  "
          f"consec={consecutive_count}  count={whistle_count}")

    # cooldown check
    if now - last_action_time < COOLDOWN_SEC:
        remaining = COOLDOWN_SEC - (now - last_action_time)
        print(f"  >> cooldown {remaining:.1f}s remaining")
        consecutive_count = 0
        return

    # threshold check
    if wh_conf >= THRESHOLD:
        consecutive_count += 1
        print(f"  >> ABOVE threshold -- consecutive={consecutive_count}/{CONSECUTIVE}")
    else:
        if consecutive_count > 0:
            print(f"  >> below threshold -- resetting consecutive")
        consecutive_count = 0

    # consecutive confirmation
    if consecutive_count >= CONSECUTIVE:
        consecutive_count = 0
        whistle_count    += 1
        last_whistle_time = now
        last_action_time  = now
        count_finalized   = False
        print(f"\n  {'*'*40}")
        print(f"  WHISTLE CONFIRMED -- total count = {whistle_count}")
        print(f"  {'*'*40}\n")

    # gap finalization
    if whistle_count > 0 and not count_finalized:
        gap = now - last_whistle_time
        if gap >= GAP_SEC:
            count_finalized = True
            print(f"\n{'='*50}")
            print(f"  FINAL COUNT: {whistle_count} whistle(s)")
            print(f"{'='*50}\n")
            whistle_count = 0


def load_wav(wav_path, target_rate):
    with wave.open(wav_path, "r") as wf:
        orig_rate    = wf.getframerate()
        n_channels   = wf.getnchannels()
        n_frames     = wf.getnframes()
        sample_width = wf.getsampwidth()
        raw          = wf.readframes(n_frames)

    print(f"  Rate: {orig_rate}Hz  Channels: {n_channels}  "
          f"Duration: {n_frames/orig_rate:.1f}s  Width: {sample_width} bytes")

    # decode
    if sample_width == 2:
        samples = np.frombuffer(raw, dtype=np.int16)
    elif sample_width == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.int16)
    else:
        samples = np.frombuffer(raw, dtype=np.uint8).astype(np.int16)

    # mono mix
    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1).astype(np.int16)

    # resample if needed
    if orig_rate != target_rate:
        ratio   = target_rate / orig_rate
        new_len = int(len(samples) * ratio)
        indices = np.linspace(0, len(samples) - 1, new_len)
        samples = np.interp(indices, np.arange(len(samples)), samples).astype(np.int16)
        print(f"  Resampled: {orig_rate}Hz -> {target_rate}Hz ({len(samples)} samples)")

    return samples


def test_with_wav(wav_path):
    print(f"\nLoading model: {MODEL_PATH}")
    runner     = ImpulseRunner(MODEL_PATH)
    model_info = runner.init()
    labels     = model_info["model_parameters"]["labels"]
    freq       = model_info["model_parameters"]["frequency"]
    n_features = model_info["model_parameters"]["input_features_count"]

    print(f"Model loaded")
    print(f"  Labels:         {labels}")
    print(f"  Frequency:      {freq} Hz")
    print(f"  Input features: {n_features} (= {n_features/freq*1000:.0f}ms window)")
    print(f"\nReading: {wav_path}")

    samples = load_wav(wav_path, freq)

    n_windows = (len(samples) - n_features) // STRIDE_SAMPLES + 1

    print(f"\n  Window:  {n_features} samples ({n_features/freq*1000:.0f}ms)")
    print(f"  Stride:  {STRIDE_SAMPLES} samples ({STRIDE_SAMPLES/freq*1000:.0f}ms)")
    print(f"  Windows: {n_windows}")
    print(f"\n  Settings:")
    print(f"    Threshold:   {THRESHOLD}")
    print(f"    Consecutive: {CONSECUTIVE}")
    print(f"    Cooldown:    {COOLDOWN_SEC}s")
    print(f"    Gap:         {GAP_SEC}s")
    print(f"\n{'='*50}")
    print(f"  Running inference...")
    print(f"{'='*50}\n")

    for i in range(n_windows):
        start  = i * STRIDE_SAMPLES
        window = samples[start : start + n_features]

        # pad last window if needed
        if len(window) < n_features:
            window = np.pad(window, (0, n_features - len(window)))

        # classify expects list of raw int16 values (not normalized)
        features = window.tolist()
        result   = runner.classify(features)
        now      = (start + n_features) / freq

        process_result(result, now)

    # finalize if count pending at end of file
    if whistle_count > 0 and not count_finalized:
        print(f"\n{'='*50}")
        print(f"  FINAL COUNT (end of file): {whistle_count} whistle(s)")
        print(f"{'='*50}\n")

    runner.stop()
    print(f"\nDone. Ran {inference_count} inferences over {n_windows} windows.")


def test_with_mic():
    import pyaudio

    print(f"\nLoading model: {MODEL_PATH}")
    runner     = ImpulseRunner(MODEL_PATH)
    model_info = runner.init()
    labels     = model_info["model_parameters"]["labels"]
    freq       = model_info["model_parameters"]["frequency"]
    n_features = model_info["model_parameters"]["input_features_count"]

    print(f"Model loaded. Labels: {labels}")
    print(f"Live mic test. Ctrl+C to stop.")
    print(f"Settings: threshold={THRESHOLD}  consecutive={CONSECUTIVE}  "
          f"cooldown={COOLDOWN_SEC}s  gap={GAP_SEC}s\n")

    pa             = pyaudio.PyAudio()
    rolling_buffer = np.zeros(n_features, dtype=np.int16)

    stream = pa.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=freq,
        input=True,
        frames_per_buffer=STRIDE_SAMPLES
    )

    start_time = time.time()
    print("Listening...\n")

    try:
        while True:
            raw    = stream.read(STRIDE_SAMPLES, exception_on_overflow=False)
            chunk  = np.frombuffer(raw, dtype=np.int16)

            # slide rolling buffer
            rolling_buffer = np.roll(rolling_buffer, -STRIDE_SAMPLES)
            rolling_buffer[-STRIDE_SAMPLES:] = chunk

            features = rolling_buffer.tolist()
            result   = runner.classify(features)
            now      = time.time() - start_time

            process_result(result, now)

    except KeyboardInterrupt:
        print("\nStopped.")
        if whistle_count > 0:
            print(f"Unfinalised count: {whistle_count}")

    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()
        runner.stop()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 test_whistle.py path/to/audio.wav")
        print("  python3 test_whistle.py --mic")
        sys.exit(1)

    if sys.argv[1] == "--mic":
        test_with_mic()
    else:
        test_with_wav(sys.argv[1])
