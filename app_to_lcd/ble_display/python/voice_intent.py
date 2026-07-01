import sys
import time
import queue
import threading
import numpy as np

sys.path.insert(0, '/app/wheels')

WAKEWORD_MODEL_PATH  = '/app/models/wakeword.eim'
INTENT_MODEL_PATH    = '/home/app/.cache/moonshine_voice/download.moonshine.ai/model/embeddinggemma-300m'
MOONSHINE_MODEL_PATH = '/home/app/.cache/moonshine_voice/download.moonshine.ai/model/tiny-streaming-en/quantized'

WAKE_THRESHOLD  = 0.85
WAKE_FRAME      = 4000
WAKE_FEATURES   = 16000
SESSION_TIMEOUT = 8.0

# intent → command mapping
INTENT_COMMANDS = {
    'pause the video':       'CMD:PLAYER_PAUSE',
    'play the video':        'CMD:PLAYER_RESUME',
    'resume the video':      'CMD:PLAYER_RESUME',
    'stop the video':        'CMD:PLAYER_STOP',
    'mute':                  'CMD:PLAYER_MUTE',
    'unmute':                'CMD:PLAYER_UNMUTE',
    'volume up':             'CMD:PLAYER_VOL_UP',
    'volume down':           'CMD:PLAYER_VOL_DOWN',
    'show clock':            'CMD:MODE_CLOCK',
    'show youtube':          'CMD:MODE_YOUTUBE',
    'show idle screen':      'CMD:MODE_IDLE',
    'start counting':        'CMD:WHISTLE_START',
    'stop counting':         'CMD:WHISTLE_STOP',
    'reset count':           'CMD:WHISTLE_RESET',
    'count one whistle':     'CMD:WHISTLE_TARGET:1',
    'count two whistles':    'CMD:WHISTLE_TARGET:2',
    'count three whistles':  'CMD:WHISTLE_TARGET:3',
    'count four whistles':   'CMD:WHISTLE_TARGET:4',
    'count five whistles':   'CMD:WHISTLE_TARGET:5',
    'count six whistles':    'CMD:WHISTLE_TARGET:6',
    'count seven whistles':  'CMD:WHISTLE_TARGET:7',
    'count eight whistles':  'CMD:WHISTLE_TARGET:8',
    'count nine whistles':   'CMD:WHISTLE_TARGET:9',
    'goodbye':               'GOODBYE',
}

INTENT_RESPONSES = {
    'CMD:PLAYER_PAUSE':     'Video paused',
    'CMD:PLAYER_RESUME':    'Video resumed',
    'CMD:PLAYER_STOP':      'Video stopped',
    'CMD:PLAYER_MUTE':      'Muted',
    'CMD:PLAYER_UNMUTE':    'Unmuted',
    'CMD:PLAYER_VOL_UP':    'Volume up',
    'CMD:PLAYER_VOL_DOWN':  'Volume down',
    'CMD:MODE_CLOCK':       'Showing clock',
    'CMD:MODE_YOUTUBE':     'Showing YouTube',
    'CMD:MODE_IDLE':        'Showing idle screen',
    'CMD:WHISTLE_START':    'Counting started',
    'CMD:WHISTLE_STOP':     'Counting stopped',
    'CMD:WHISTLE_RESET':    'Count reset',
    'CMD:WHISTLE_TARGET:1': 'Target set to one',
    'CMD:WHISTLE_TARGET:2': 'Target set to two',
    'CMD:WHISTLE_TARGET:3': 'Target set to three',
    'CMD:WHISTLE_TARGET:4': 'Target set to four',
    'CMD:WHISTLE_TARGET:5': 'Target set to five',
    'CMD:WHISTLE_TARGET:6': 'Target set to six',
    'CMD:WHISTLE_TARGET:7': 'Target set to seven',
    'CMD:WHISTLE_TARGET:8': 'Target set to eight',
    'CMD:WHISTLE_TARGET:9': 'Target set to nine',
}

_voice_queue     = None
_alarm_playing   = False
_in_session      = False
_launcher_send   = None
_ww_runner       = None
_transcriber     = None
_intent_rec      = None


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
    global _in_session
    _in_session = True

    _speak('Yes?')
    _drain_queue()

    print('[VOICE] Session started -- listening for intent...', flush=True)

    detected_cmd      = None
    detected_response = None
    result_lock       = threading.Lock()

    class _IntentListener:
        def on_line_completed(self, event):
            nonlocal detected_cmd, detected_response
            text = event.line.text.strip()
            if not text:
                return
            print(f'[VOICE] Heard: "{text}"', flush=True)
            matches = _intent_rec.get_closest_intents(text)
            if matches:
                best = matches[0]
                print(f'[VOICE] Intent: "{best.canonical_phrase}" similarity={best.similarity:.2f}', flush=True)
                if best.similarity >= 0.65:
                    cmd = INTENT_COMMANDS.get(best.canonical_phrase)
                    if cmd:
                        with result_lock:
                            detected_cmd      = cmd
                            detected_response = INTENT_RESPONSES.get(cmd, 'Done')

    from moonshine_voice import TranscriptEventListener, ModelArch

    class _Listener(_IntentListener, TranscriptEventListener):
        pass

    listener = _Listener()
    _transcriber.add_listener(listener)
    _transcriber.start()

    deadline = time.time() + SESSION_TIMEOUT
    while time.time() < deadline:
        try:
            chunk = _voice_queue.get(timeout=0.3)
        except queue.Empty:
            continue
        chunk_f32 = chunk.astype(np.float32) / 32768.0
        _transcriber.add_audio(chunk_f32, 16000)
        with result_lock:
            if detected_cmd:
                break

    _transcriber.stop()
    _transcriber.remove_listener(listener)

    if detected_cmd:
        if detected_cmd == 'GOODBYE':
            _speak('Goodbye')
            _in_session = False
            return
        else:
            set_voice_flag_fn(True)
            handle_cmd_fn(detected_cmd)
            set_voice_flag_fn(False)
            _speak(detected_response)
            # keep session open -- listen for next command
            _drain_queue()
            _run_session(handle_cmd_fn, set_voice_flag_fn)
            return
    else:
        _speak('No command heard')

    _in_session = False


def voice_assistant_loop(voice_queue, launcher_send_fn, handle_cmd_fn, set_voice_flag_fn=None):
    global _voice_queue, _launcher_send, _in_session
    global _ww_runner, _transcriber, _intent_rec

    _voice_queue   = voice_queue
    _launcher_send = launcher_send_fn

    print('[VOICE] Loading intent recognizer...', flush=True)
    try:
        from moonshine_voice import IntentRecognizer, ModelArch, Transcriber
        from moonshine_voice.download import EmbeddingModelArch
        _intent_rec = IntentRecognizer(
            model_path=INTENT_MODEL_PATH,
            model_arch=EmbeddingModelArch.GEMMA_300M,
            model_variant='q4',
            threshold=0.65,
        )
        for phrase in INTENT_COMMANDS:
            _intent_rec.register_intent(phrase)
        print(f'[VOICE] Registered {len(INTENT_COMMANDS)} intents', flush=True)
    except Exception as e:
        print(f'[VOICE] Intent load failed: {e}', flush=True)
        return

    print('[VOICE] Loading Moonshine transcriber...', flush=True)
    try:
        from moonshine_voice import Transcriber, ModelArch
        _transcriber = Transcriber(
            model_path=MOONSHINE_MODEL_PATH,
            model_arch=ModelArch.TINY_STREAMING,
            options={
                'identify_speakers': 'false',
                'return_audio_data': 'false',
                'max_tokens_per_second': '4.0',
                'vad_window_duration': '0.2',
            },
        )
        print('[VOICE] Transcriber ready', flush=True)
    except Exception as e:
        print(f'[VOICE] Transcriber load failed: {e}', flush=True)
        return

    print('[VOICE] Loading wakeword model...', flush=True)
    try:
        from edge_impulse_linux.runner import ImpulseRunner
        _ww_runner = ImpulseRunner(WAKEWORD_MODEL_PATH)
        info       = _ww_runner.init()
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
