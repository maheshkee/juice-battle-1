import time
import datetime
import threading
from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI
from arduino.app_bricks.audio_classification import AudioClassification

CONFIDENCE        = 0.90
CONSECUTIVE       = 3
COOLDOWN_SEC      = 4.0
CONSECUTIVE_GAP   = 2.0  # reset consecutive if gap > this between detections

whistle_count     = 0
consecutive_count = 0
last_action_time  = -999.0
last_detect_time  = -999.0
counting_active   = False
lock              = threading.Lock()

ui         = WebUI()
classifier = AudioClassification(confidence=CONFIDENCE)


def log(msg):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")
    ui.send_message('log', {'message': msg, 'time': ts})


def push_count():
    ui.send_message('whistle_count', {
        'count': whistle_count,
        'time': datetime.datetime.now().strftime("%H:%M:%S")
    })


def on_whistle():
    global whistle_count, consecutive_count, last_action_time, last_detect_time

    with lock:
        ts  = datetime.datetime.now().strftime("%H:%M:%S")
        now = time.time()

        # reset consecutive if too much time passed since last detection
        if now - last_detect_time > CONSECUTIVE_GAP:
            consecutive_count = 0

        last_detect_time = now

        # send detection pulse to UI
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


classifier.on_detect('cooker_whistle', on_whistle)
ui.on_message('start', on_start)
ui.on_message('stop',  on_stop)
ui.on_message('reset', on_reset)

classifier.start()

log('[WHISTLE COUNTER] Ready -- press Start to begin counting')
App.run()
