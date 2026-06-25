import os
import sys
import time
import queue
import threading
import numpy as np

sys.path.insert(0, '/app/wheels')

WAKEWORD_MODEL_PATH = '/app/models/wakeword.eim'
DIGITS_MODEL_PATH   = '/app/models/digits.eim'
WAKE_THRESHOLD      = 0.90
WAKE_FRAME          = 4000
WAKE_FEATURES       = 16000
VOICE_RATE       = 16000
DIGIT_FEATURES   = 16000   # 1 second at 16000Hz
DIGIT_THRESHOLD  = 0.7
DIGIT_TIMEOUT    = 8.0     # seconds to wait for a number

LABEL_TO_INT = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
}

_voice_queue   = None
_alarm_playing = False
_in_session    = False
_launcher_send = None
_digit_runner  = None
_oww_model     = None


def _speak(text: str):
    print(f'[VOICE] Speaking: {text}', flush=True)
    try:
        if _launcher_send:
            _launcher_send(f'speak:{text}')
            time.sleep(1.0)
    except Exception as e:
        print(f'[VOICE] Speak failed: {e}', flush=True)


def _drain_queue():
    while not _voice_queue.empty():
        try: _voice_queue.get_nowait()
        except: break


def _listen_for_digit() -> int:
    """Listen for a spoken digit using digits.eim rolling buffer. Returns 1-9 or -1 if none detected."""
    if _digit_runner is None:
        return -1

    print('[VOICE] Listening for number...', flush=True)
    rolling_buf = np.zeros(DIGIT_FEATURES, dtype=np.int16)
    deadline    = time.time() + DIGIT_TIMEOUT
    SLICE       = 4000

    while time.time() < deadline:
        try:
            chunk = _voice_queue.get(timeout=0.5)
        except queue.Empty:
            continue

        # update rolling buffer
        rolling_buf[:-SLICE] = rolling_buf[SLICE:]
        rolling_buf[-SLICE:] = chunk[:SLICE]

        try:
            result = _digit_runner.classify(rolling_buf.tolist())
            if not result or 'result' not in result:
                continue
            if 'classification' not in result['result']:
                continue

            cls   = result['result']['classification']
            best  = max(cls, key=cls.get)
            score = cls[best]

            if best != 'silence' and score >= DIGIT_THRESHOLD:
                print(f'[VOICE] Digit detected: {best} ({score:.2f})', flush=True)
                return LABEL_TO_INT.get(best, -1)

        except Exception as e:
            print(f'[VOICE] Digit classify error: {e}', flush=True)

    print('[VOICE] No digit detected', flush=True)
    return -1


def _run_session(handle_cmd_fn, set_voice_flag_fn):
    global _in_session
    _in_session = True

    _speak('Yes?')
    _drain_queue()

    _speak('How many whistles?')
    _drain_queue()

    n = _listen_for_digit()

    if n > 0:
        print(f'[VOICE] Setting whistle target: {n}', flush=True)
        set_voice_flag_fn(True)
        handle_cmd_fn(f'CMD:WHISTLE_TARGET:{n}')
        handle_cmd_fn('CMD:WHISTLE_START')
        set_voice_flag_fn(False)
        _speak(f'Whistle target set to {n}, counting started')
    else:
        _speak('No number heard')

    _in_session = False


def voice_assistant_loop(voice_queue, launcher_send_fn, handle_cmd_fn, set_voice_flag_fn=None):
    global _voice_queue, _launcher_send, _in_session
    global _digit_runner, _oww_model

    _voice_queue   = voice_queue
    _launcher_send = launcher_send_fn

    # load digits model
    print('[VOICE] Loading digits model...', flush=True)
    try:
        from edge_impulse_linux.runner import ImpulseRunner
        _digit_runner = ImpulseRunner(DIGITS_MODEL_PATH)
        info = _digit_runner.init()
        print(f'[VOICE] Digits model loaded. Labels: {info["model_parameters"]["labels"]}', flush=True)
    except Exception as e:
        print(f'[VOICE] Digits model load failed: {e}', flush=True)
        return

    # load wake word model
    print('[VOICE] Loading wakeword model...', flush=True)
    try:
        ww_runner     = ImpulseRunner(WAKEWORD_MODEL_PATH)
        ww_info       = ww_runner.init()
        ww_labels     = ww_info['model_parameters']['labels']
        ww_n_features = ww_info['model_parameters']['input_features_count']
        print(f'[VOICE] Wakeword model loaded. Labels: {ww_labels}', flush=True)
        _oww_model = ww_runner
    except Exception as e:
        print(f'[VOICE] Wakeword load failed: {e}', flush=True)
        return

    oww_buf    = np.zeros(0, dtype=np.int16)
    ww_rolling = np.zeros(WAKE_FEATURES, dtype=np.int16)

    while True:
        try:
            if _alarm_playing or _in_session:
                time.sleep(0.1)
                continue

            try:
                chunk = _voice_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            # accumulate and process in WAKE_FRAME chunks
            oww_buf  = np.concatenate([oww_buf, chunk])
            detected = False
            score    = 0.0

            while len(oww_buf) >= WAKE_FRAME:
                frame      = oww_buf[:WAKE_FRAME]
                oww_buf    = oww_buf[WAKE_FRAME:]
                ww_rolling[:-WAKE_FRAME] = ww_rolling[WAKE_FRAME:]
                ww_rolling[-WAKE_FRAME:] = frame
                result = _oww_model.classify(ww_rolling.tolist())
                if result and "result" in result and "classification" in result["result"]:
                    cls   = result["result"]["classification"]
                    score = cls.get("marvin", 0.0)
                    if score >= WAKE_THRESHOLD:
                        detected = True
                        oww_buf  = np.zeros(0, dtype=np.int16)
                        break
            if not detected:
                continue

            print(f'[VOICE] Wake word detected (score={score:.2f})', flush=True)
            ww_rolling = np.zeros(WAKE_FEATURES, dtype=np.int16)
            _drain_queue()

            threading.Thread(
                target=_run_session,
                args=(handle_cmd_fn, set_voice_flag_fn),
                daemon=True
            ).start()

        except Exception as e:
            print(f'[VOICE] Loop error: {e}', flush=True)
            _in_session = False
            time.sleep(1)


def set_alarm_playing(state: bool):
    global _alarm_playing
    _alarm_playing = state