import os
import sys
import time
import queue
import threading
import numpy as np

sys.path.insert(0, '/app/wheels')

WAKEWORD_MODEL_PATH = '/app/models/wakeword.eim'
WAKE_THRESHOLD      = 0.85
WAKE_FRAME          = 4000
WAKE_FEATURES       = 16000

VOICE_RATE          = 16000
SILENCE_THRESH      = 350
SILENCE_SECS        = 1.0
MAX_LISTEN_SECS     = 7.0

WHISPER_PROMPT = (
    "start stop pause resume clock youtube whistle whistles "
    "count counting reset goodbye bye volume up down mute unmute "
    "one two three four five six seven eight nine"
)

WHISTLE_WORDS = {'whistle', 'whistles', 'wistle', 'wistles'}

NUMBER_WORDS = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
}

_voice_queue    = None
_alarm_playing  = False
_in_session     = False
_launcher_send  = None
_whisper_model  = None
_ww_runner      = None


def _speak(text: str):
    print(f'[VOICE] Speaking: {text}', flush=True)
    try:
        if _launcher_send:
            _launcher_send(f'speak:{text}')
            time.sleep(0.8)
    except Exception as e:
        print(f'[VOICE] Speak failed: {e}', flush=True)


def _play_thinking():
    """Play a short beep/sound to signal processing started."""
    try:
        if _launcher_send:
            _launcher_send('speak:mm')
    except Exception:
        pass


def _drain_queue():
    while not _voice_queue.empty():
        try: _voice_queue.get_nowait()
        except: break


def _extract_number(words: list) -> int:
    for w in words:
        if w in NUMBER_WORDS:
            return NUMBER_WORDS[w]
        if w.isdigit():
            return int(w)
    return -1


def _parse_command(text: str):
    text  = text.lower().strip()
    # remove punctuation
    text  = ''.join(c for c in text if c.isalpha() or c.isspace())
    words = text.split()
    print(f'[VOICE] Parsing: "{text}"', flush=True)

    if not words:
        return None, None

    # goodbye
    if any(w in words for w in ['goodbye', 'bye', 'exit', 'close']):
        return 'GOODBYE', 'Goodbye'

    # whistle target -- number + whistle word in same sentence
    has_whistle = any(w in WHISTLE_WORDS for w in words)
    n           = _extract_number(words)

    if has_whistle and n > 0:
        return f'CMD:WHISTLE_TARGET:{n}', f'Whistle target set to {n}'

    if has_whistle and any(w in words for w in ['start', 'begin', 'count']):
        return 'CMD:WHISTLE_START', 'Whistle counting started'

    if has_whistle and any(w in words for w in ['stop', 'end', 'finish']):
        return 'CMD:WHISTLE_STOP', 'Whistle counting stopped'

    if has_whistle and 'reset' in words:
        return 'CMD:WHISTLE_RESET', 'Whistle count reset'

    if any(w in words for w in ['start', 'begin']) and 'count' in words:
        return 'CMD:WHISTLE_START', 'Whistle counting started'

    if 'reset' in words and 'count' in words:
        return 'CMD:WHISTLE_RESET', 'Whistle count reset'

    # player
    if 'pause' in words:
        return 'CMD:PLAYER_PAUSE', 'Video paused'
    if 'resume' in words:
        return 'CMD:PLAYER_RESUME', 'Video resumed'
    if 'stop' in words and any(w in words for w in ['video', 'youtube', 'playing']):
        return 'CMD:PLAYER_STOP', 'Video stopped'
    if 'mute' in words and 'unmute' not in words:
        return 'CMD:PLAYER_MUTE', 'Muted'
    if 'unmute' in words:
        return 'CMD:PLAYER_UNMUTE', 'Unmuted'
    if 'volume' in words or 'vol' in words:
        if any(w in words for w in ['up', 'increase', 'louder', 'higher']):
            return 'CMD:PLAYER_VOL_UP', 'Volume up'
        if any(w in words for w in ['down', 'decrease', 'lower', 'quieter']):
            return 'CMD:PLAYER_VOL_DOWN', 'Volume down'

    # mode
    if 'clock' in words:
        return 'CMD:MODE_CLOCK', 'Showing clock'
    if 'youtube' in words:
        return 'CMD:MODE_YOUTUBE', 'Showing YouTube'
    if 'idle' in words:
        return 'CMD:MODE_IDLE', 'Showing idle screen'

    return None, None


def _trim_audio(audio: np.ndarray) -> np.ndarray:
    """Trim trailing silence from audio."""
    indices = np.where(np.abs(audio) > SILENCE_THRESH)[0]
    if len(indices) == 0:
        return audio
    # keep 0.1s (1600 samples) after last speech
    end = min(indices[-1] + 1600, len(audio))
    return audio[:end]


def _record_until_silence() -> np.ndarray:
    """Record audio until silence detected or max time reached."""
    print('[VOICE] Listening...', flush=True)
    frames       = []
    start        = time.time()
    silence_from = None
    got_speech   = False

    while time.time() - start < MAX_LISTEN_SECS:
        try:
            chunk = _voice_queue.get(timeout=0.3)
        except queue.Empty:
            continue

        frames.append(chunk)
        rms = float(np.sqrt(np.mean(chunk.astype(np.float32) ** 2)))
        print(f'[VOICE] RMS: {rms:.1f}', flush=True)

        if rms > SILENCE_THRESH:
            got_speech   = True
            silence_from = None
        elif got_speech:
            if silence_from is None:
                silence_from = time.time()
            elif time.time() - silence_from >= SILENCE_SECS:
                break

    if not frames:
        return np.zeros(0, dtype=np.int16)

    audio = np.concatenate(frames)
    return _trim_audio(audio)


def _transcribe(audio: np.ndarray) -> str:
    """Transcribe audio using preloaded faster-whisper."""
    if _whisper_model is None or len(audio) < 1600:
        return ''
    try:
        audio_f32   = audio.astype(np.float32) / 32768.0
        segments, _ = _whisper_model.transcribe(
            audio_f32,
            language       = 'en',
            beam_size      = 1,
            best_of        = 1,
            initial_prompt = WHISPER_PROMPT,
            vad_filter     = True,
            vad_parameters = dict(min_silence_duration_ms=300),
        )
        text = ' '.join(s.text.strip() for s in segments).strip()
        print(f'[VOICE] Heard: "{text}"', flush=True)
        return text.lower()
    except Exception as e:
        print(f'[VOICE] Transcribe failed: {e}', flush=True)
        return ''


def _run_session(handle_cmd_fn, set_voice_flag_fn):
    global _in_session
    _in_session = True

    _speak('Yes?')
    _drain_queue()

    while True:
        audio = _record_until_silence()

        if len(audio) < 1600:
            _speak('I did not hear anything')
            audio = _record_until_silence()
            if len(audio) < 1600:
                _speak('Closing session')
                break

        # check if audio has enough energy to be speech
        rms = float(np.sqrt(np.mean(audio.astype(np.float32) ** 2)))
        if rms < 300:
            print(f'[VOICE] Audio too quiet (rms={rms:.0f}), ignoring', flush=True)
            _drain_queue()
            continue

        # immediate feedback -- user knows board heard them
        _play_thinking()

        text = _transcribe(audio)

        if not text:
            _speak("Sorry, I didn't catch that")
            _drain_queue()
            continue

        cmd, response = _parse_command(text)

        if cmd == 'GOODBYE':
            _speak('Goodbye')
            break
        elif cmd:
            print(f'[VOICE] Executing: {cmd}', flush=True)
            set_voice_flag_fn(True)
            handle_cmd_fn(cmd)
            set_voice_flag_fn(False)
            time.sleep(0.2)
            _speak(response)
            _drain_queue()
        else:
            _speak("Sorry, I didn't understand")
            _drain_queue()

    _in_session = False


def voice_assistant_loop(voice_queue, launcher_send_fn, handle_cmd_fn, set_voice_flag_fn=None):
    global _voice_queue, _launcher_send, _in_session
    global _whisper_model, _ww_runner

    _voice_queue   = voice_queue
    _launcher_send = launcher_send_fn

    # load whisper
    print('[VOICE] Loading Whisper tiny model...', flush=True)
    try:
        from faster_whisper import WhisperModel
        _whisper_model = WhisperModel(
            'tiny',
            device       = 'cpu',
            compute_type = 'int8',
            cpu_threads  = 2,
            num_workers  = 1,
        )
        # warmup dummy inference
        print('[VOICE] Warming up Whisper...', flush=True)
        dummy       = np.zeros(16000, dtype=np.float32)
        list(_whisper_model.transcribe(dummy, language='en', beam_size=1)[0])
        print('[VOICE] Whisper ready', flush=True)
    except Exception as e:
        print(f'[VOICE] Whisper load failed: {e}', flush=True)
        return

    # load wakeword model
    print('[VOICE] Loading wakeword model...', flush=True)
    try:
        from edge_impulse_linux.runner import ImpulseRunner
        _ww_runner = ImpulseRunner(WAKEWORD_MODEL_PATH)
        ww_info    = _ww_runner.init()
        ww_labels  = ww_info['model_parameters']['labels']
        print(f'[VOICE] Wakeword model loaded. Labels: {ww_labels}', flush=True)
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
