import os
import json
import subprocess
import threading
import logging
from logging.handlers import RotatingFileHandler

_BASE_DIR     = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
_SESSION_PATH = os.path.join(_BASE_DIR, 'data', 'hub_session.json')
_LOG_PATH     = os.path.join(_BASE_DIR, 'logs', 'hub', 'hub.log')

_lock    = threading.Lock()
_seq     = 0
_session = 0
_logger  = None


def _init():
    global _seq, _session, _logger
    os.makedirs(os.path.dirname(_LOG_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(_SESSION_PATH), exist_ok=True)
    _logger = logging.getLogger('hub')
    _logger.setLevel(logging.DEBUG)
    if not _logger.handlers:
        handler = RotatingFileHandler(
            _LOG_PATH,
            maxBytes=10 * 1024 * 1024,
            backupCount=5
        )
        _logger.addHandler(handler)
    try:
        with open(_SESSION_PATH) as f:
            _session = json.load(f).get('session', 0) + 1
    except Exception:
        _session = 1
    try:
        with open(_SESSION_PATH, 'w') as f:
            json.dump({'session': _session}, f)
    except Exception as e:
        print(f'[HUB_LOGGER] session file write failed: {e}', flush=True)
    _seq = 0
    print(f'[HUB_LOGGER] session={_session}', flush=True)


def _get_ts():
    try:
        result = subprocess.run(
            ['date', '+%Y-%m-%d %H:%M:%S'],
            capture_output=True, text=True
        )
        return result.stdout.strip() + ' IST'
    except Exception:
        return 'unknown IST'


def _write(tag, event, kwargs):
    global _seq
    with _lock:
        _seq += 1
        ts   = _get_ts()
        kv   = ' '.join(f'{k}={v}' for k, v in kwargs.items())
        line = f'#{_seq:04d} ts={ts} session={_session} [{tag}] event={event}'
        if kv:
            line += f' {kv}'
        line += '\n'
        try:
            _logger.info(line.rstrip('\n'))
        except Exception as e:
            print(f'[HUB_LOGGER] write failed: {e}', flush=True)


def log_ble(event, **kwargs):      _write('BLE',      event, kwargs)
def log_weight(event, **kwargs):   _write('WEIGHT',   event, kwargs)
def log_domain(event, **kwargs):   _write('DOMAIN',   event, kwargs)
def log_watchdog(event, **kwargs): _write('WATCHDOG', event, kwargs)
def log_hub(event, **kwargs):      _write('HUB',      event, kwargs)


_init()
