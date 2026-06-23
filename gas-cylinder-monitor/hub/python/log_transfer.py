import os
import shutil
from datetime import datetime

_APP_ROOT = os.path.dirname(os.path.abspath(__file__))
LOG_DIR   = os.path.join(_APP_ROOT, '..', 'logs', 'node')
LOG_TMP   = '/tmp/node_log_incoming.txt'

os.makedirs(LOG_DIR, exist_ok=True)

_write_command   = None   # injected by main.py via init()
_log_tmp_file    = None   # open file handle during active transfer
_log_transfer_on = False  # True between LOG_START and LOG_END


def init(write_command_fn):
    global _write_command
    _write_command = write_command_fn


def on_log_line(line):
    global _log_tmp_file, _log_transfer_on
    line = line.strip()
    if line == 'LOG_START':
        if _log_transfer_on:
            print('[LOG] LOG_START ignored — transfer already active', flush=True)
            return
        _log_transfer_on = True
        _log_tmp_file    = open(LOG_TMP, 'w')
        print('[LOG] transfer started — temp file opened', flush=True)
        return
    if line == 'LOG_END':
        if _log_tmp_file:
            _log_tmp_file.close()
            _log_tmp_file = None
        _log_transfer_on = False
        if os.path.exists(LOG_TMP) and os.path.getsize(LOG_TMP) > 0:
            ts  = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
            dst = os.path.join(LOG_DIR, f'node_{ts}.log')
            shutil.move(LOG_TMP, dst)
            print(f'[LOG] saved: {dst}', flush=True)
            if _write_command:
                _write_command('CLEAR_LOG')
        else:
            print('[LOG] LOG_END received but temp file empty — CLEAR_LOG withheld', flush=True)
        return
    if _log_transfer_on and _log_tmp_file:
        _log_tmp_file.write(line + '\n')
