import sys
import os
sys.path.insert(0, '/app/wheels')
import time
import datetime
import threading
import numpy as np
from edge_impulse_linux.runner import ImpulseRunner
from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI

MODEL_PATH      = "/app/models/whistle.eim"
THRESHOLD       = 0.95
CONSECUTIVE     = 5
COOLDOWN_SEC    = 4.0
CONSECUTIVE_GAP = 2.0
MIC_RATE        = 44100
MODEL_RATE      = 16000
WINDOW_SAMPLES  = 16000
STRIDE_SAMPLES  = 4000
HP_CUTOFF       = 1000

whistle_count     = 0
consecutive_count = 0
last_action_time  = -999.0
last_detect_time  = -999.0
counting_active   = False
lock              = threading.Lock()

ui = WebUI()



def log(msg):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")
    ui.send_message('log', {'message': msg, 'time': ts})


def push_count():
    ui.send_message('whistle_count', {
        'count': whistle_count,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })



def resample(data, from_rate, to_rate):
    if from_rate == to_rate:
        return data
    ratio   = to_rate / from_rate
    new_len = int(len(data) * ratio)
    indices = np.linspace(0, len(data) - 1, new_len)
    return np.interp(indices, np.arange(len(data)), data).astype(np.int16)


def on_detection():
    global whistle_count, consecutive_count, last_action_time, last_detect_time
    with lock:
        ts  = datetime.datetime.now().strftime("%H:%M:%S")
        now = time.time()

        if now - last_detect_time > CONSECUTIVE_GAP:
            consecutive_count = 0
        last_detect_time = now

        ui.send_message('detection_pulse', {
            'consecutive': consecutive_count + 1,
            'needed':      CONSECUTIVE,
            'cooldown':    now - last_action_time < COOLDOWN_SEC,
            'active':      counting_active,
            'time':        ts
        })

        if not counting_active:
            return

        if now - last_action_time < COOLDOWN_SEC:
            remaining = COOLDOWN_SEC - (now - last_action_time)
            print(f'[WHISTLE] cooldown {remaining:.1f}s remaining')
            consecutive_count = 0
            return

        consecutive_count += 1
        print(f'[WHISTLE] detection {consecutive_count}/{CONSECUTIVE}')

        if consecutive_count >= CONSECUTIVE:
            consecutive_count = 0
            last_action_time  = now
            whistle_count    += 1
            log(f'WHISTLE CONFIRMED -- total = {whistle_count}')
            push_count()


def audio_loop():
    import pyaudio

    print(f"\n[AUDIO] Loading model: {MODEL_PATH}")
    runner     = ImpulseRunner(MODEL_PATH)
    model_info = runner.init()
    n_features = model_info["model_parameters"]["input_features_count"]
    labels     = model_info["model_parameters"]["labels"]
    print(f"[AUDIO] Model loaded. Labels: {labels}")

    pa = pyaudio.PyAudio()

    usb_device_index = None
    for i in range(pa.get_device_count()):
        info = pa.get_device_info_by_index(i)
        if info["maxInputChannels"] > 0:
            if "usb" in info["name"].lower() or "USB" in info["name"]:
                usb_device_index = i
                break

    if usb_device_index is not None:
        print(f"[AUDIO] Using USB device [{usb_device_index}]")
    else:
        print(f"[AUDIO] No USB device found -- using default")

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

    print("[AUDIO] Listening...\n")

    try:
        while True:
            raw   = stream.read(mic_stride, exception_on_overflow=False)
            chunk = np.frombuffer(raw, dtype=np.int16)

            chunk = resample(chunk, MIC_RATE, MODEL_RATE)[:STRIDE_SAMPLES]

            rolling_buf[:-STRIDE_SAMPLES] = rolling_buf[STRIDE_SAMPLES:]
            rolling_buf[-STRIDE_SAMPLES:] = chunk

            result = runner.classify(rolling_buf.tolist())

            if not result or "result" not in result:
                continue
            if "classification" not in result["result"]:
                continue

            cls     = result["result"]["classification"]
            bg_conf = cls.get("background", 0)
            wh_conf = cls.get("cooker_whistle", 0)
            hs_conf = cls.get("hiss", 0)

            print(f"  bg={bg_conf:.2f}  whistle={wh_conf:.2f}  hiss={hs_conf:.2f}  "
                  f"consec={consecutive_count}  count={whistle_count}")

            if wh_conf >= THRESHOLD:
                on_detection()

    except Exception as e:
        print(f"[AUDIO] Error: {e}")
    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()
        runner.stop()


def on_start(sid, data=None):
    global whistle_count, consecutive_count, last_action_time, last_detect_time, counting_active
    with lock:
        whistle_count     = 0
        consecutive_count = 0
        last_action_time  = -999.0
        last_detect_time  = -999.0
        counting_active   = True
    log('Counting STARTED -- listening for whistles')
    push_count()


def on_stop(sid, data=None):
    global counting_active
    with lock:
        counting_active = False
    log(f'Counting STOPPED -- final count = {whistle_count}')
    push_count()


def on_reset(sid, data=None):
    global whistle_count, consecutive_count, last_action_time, last_detect_time
    with lock:
        whistle_count     = 0
        consecutive_count = 0
        last_action_time  = -999.0
        last_detect_time  = -999.0
    log('Count RESET')
    push_count()


ui.on_message('start', on_start)
ui.on_message('stop',  on_stop)
ui.on_message('reset', on_reset)

t = threading.Thread(target=audio_loop, daemon=True)
t.start()

log('[WHISTLE COUNTER] Ready -- press Start to begin counting')
App.run()