import sys
import time
import queue
import threading
import numpy as np

sys.path.insert(0, '/app/wheels')

WAKEWORD_MODEL_PATH  = '/app/models/wakeword.eim'
DIGITS_MODEL_PATH    = '/app/models/digits.eim'
COMMANDS_MODEL_PATH  = '/app/models/commands.eim'

WAKE_THRESHOLD       = 0.85
WAKE_FRAME           = 4000
WAKE_FEATURES        = 16000

CMD_THRESHOLD        = 0.7
DIGIT_THRESHOLD      = 0.7
SESSION_TIMEOUT      = 8.0
SLICE                = 4000
FEATURES             = 16000

LABEL_TO_INT = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
}

_voice_queue    = None
_alarm_playing  = False
_in_session     = False
_launcher_send  = None
_ww_runner      = None
_digit_runner   = None
_cmd_runner     = None


def _speak(text: str):
    print(f'[VOICE] Speaking: {text}', flush=True)
    try:
        if _launcher_send:
            _launcher_send(f'speak:{text}')
            time.sleep(0.8)
    except Exception as e:
        print(f'[VOICE] Speak failed: {e}', flush=True)


def _drain_queue():
    while not _voice_queue.empty():
        try: _voice_queue.get_nowait()
        except: break


def _run_session(handle_cmd_fn, set_voice_flag_fn):
    """
    Listen for 8 seconds collecting all detections from both
    commands.eim and digits.eim simultaneously on the same audio.
    Then decide what command to execute based on what was detected.
    """
    global _in_session
    _in_session = True

    _speak('Yes?')
    _drain_queue()

    print('[VOICE] Session started -- listening for commands and numbers...', flush=True)

    # rolling buffers for each model
    cmd_buf   = np.zeros(FEATURES, dtype=np.int16)
    digit_buf = np.zeros(FEATURES, dtype=np.int16)

    # detections collected during session
    detected_cmd    = None   # 'start' / 'stop' / 'go'
    detected_number = -1

    deadline = time.time() + SESSION_TIMEOUT

    while time.time() < deadline:
        try:
            chunk = _voice_queue.get(timeout=0.3)
        except queue.Empty:
            continue

        # update both rolling buffers with same chunk
        cmd_buf[:-SLICE]   = cmd_buf[SLICE:]
        cmd_buf[-SLICE:]   = chunk[:SLICE]
        digit_buf[:-SLICE] = digit_buf[SLICE:]
        digit_buf[-SLICE:] = chunk[:SLICE]

        # classify commands
        try:
            result = _cmd_runner.classify(cmd_buf.tolist())
            if result and 'result' in result and 'classification' in result['result']:
                cls  = result['result']['classification']
                best = max(cls, key=cls.get)
                score = cls[best]
                if best != 'z_openset' and score >= CMD_THRESHOLD:
                    print(f'[VOICE] Command detected: {best} ({score:.2f})', flush=True)
                    if best in ('start', 'go') and detected_cmd != 'stop':
                        detected_cmd = 'start'
                    elif best == 'stop':
                        detected_cmd = 'stop'
        except Exception as e:
            print(f'[VOICE] Cmd classify error: {e}', flush=True)

        # classify digits
        try:
            result = _digit_runner.classify(digit_buf.tolist())
            if result and 'result' in result and 'classification' in result['result']:
                cls  = result['result']['classification']
                best = max(cls, key=cls.get)
                score = cls[best]
                if best != 'silence' and score >= DIGIT_THRESHOLD:
                    n = LABEL_TO_INT.get(best, -1)
                    if n > 0:
                        print(f'[VOICE] Number detected: {best} ({score:.2f})', flush=True)
                        detected_number = n
        except Exception as e:
            print(f'[VOICE] Digit classify error: {e}', flush=True)

    # session ended -- decide command
    print(f'[VOICE] Session end -- cmd={detected_cmd} number={detected_number}', flush=True)

    set_voice_flag_fn(True)

    if detected_cmd == 'stop':
        handle_cmd_fn('CMD:WHISTLE_STOP')
        _speak('Counting stopped')

    elif detected_cmd == 'start' and detected_number > 0:
        handle_cmd_fn(f'CMD:WHISTLE_TARGET:{detected_number}')
        handle_cmd_fn('CMD:WHISTLE_START')
        _speak(f'Starting {detected_number} whistles')

    elif detected_cmd == 'start':
        handle_cmd_fn('CMD:WHISTLE_START')
        _speak('Counting started')

    elif detected_number > 0:
        handle_cmd_fn(f'CMD:WHISTLE_TARGET:{detected_number}')
        _speak(f'Whistle target set to {detected_number}')

    else:
        _speak('No command heard')

    set_voice_flag_fn(False)
    _in_session = False


def voice_assistant_loop(voice_queue, launcher_send_fn, handle_cmd_fn, set_voice_flag_fn=None):
    global _voice_queue, _launcher_send, _in_session
    global _ww_runner, _digit_runner, _cmd_runner

    _voice_queue   = voice_queue
    _launcher_send = launcher_send_fn

    from edge_impulse_linux.runner import ImpulseRunner

    # load digits model
    print('[VOICE] Loading digits model...', flush=True)
    try:
        _digit_runner = ImpulseRunner(DIGITS_MODEL_PATH)
        info = _digit_runner.init()
        print(f'[VOICE] Digits loaded. Labels: {info["model_parameters"]["labels"]}', flush=True)
    except Exception as e:
        print(f'[VOICE] Digits load failed: {e}', flush=True)
        return

    # load commands model
    print('[VOICE] Loading commands model...', flush=True)
    try:
        _cmd_runner = ImpulseRunner(COMMANDS_MODEL_PATH)
        info = _cmd_runner.init()
        print(f'[VOICE] Commands loaded. Labels: {info["model_parameters"]["labels"]}', flush=True)
    except Exception as e:
        print(f'[VOICE] Commands load failed: {e}', flush=True)
        return

    # load wakeword model
    print('[VOICE] Loading wakeword model...', flush=True)
    try:
        _ww_runner = ImpulseRunner(WAKEWORD_MODEL_PATH)
        info = _ww_runner.init()
        print(f'[VOICE] Wakeword loaded. Labels: {info["model_parameters"]["labels"]}', flush=True)
    except Exception as e:
        print(f'[VOICE] Wakeword load failed: {e}', flush=True)
        return

    oww_buf    = np.zeros(0, dtype=np.int16)
    ww_rolling = np.zeros(WAKE_FEATURES, dtype=np.int16)

    print('[VOICE] Listening for "Marvin"...', flush=True)

    while True:
        try:
            if _alarm_playing or _in_session:
                time.sleep(0.1)
                continue

            try:
                chunk = _voice_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            oww_buf  = np.concatenate([oww_buf, chunk])
            detected = False
            score    = 0.0

            while len(oww_buf) >= WAKE_FRAME:
                frame      = oww_buf[:WAKE_FRAME]
                oww_buf    = oww_buf[WAKE_FRAME:]
                ww_rolling[:-WAKE_FRAME] = ww_rolling[WAKE_FRAME:]
                ww_rolling[-WAKE_FRAME:] = frame
                result = _ww_runner.classify(ww_rolling.tolist())
                if result and 'result' in result and 'classification' in result['result']:
                    cls   = result['result']['classification']
                    score = cls.get('marvin', 0.0)
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