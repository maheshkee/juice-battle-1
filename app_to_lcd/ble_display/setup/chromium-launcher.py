#!/usr/bin/env python3
import os
import socket
import subprocess
import threading
import time
PROJECT_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK_PATH      = os.path.join(PROJECT_DIR, 'launcher.sock')
BT_CMD_FILE    = os.path.join(PROJECT_DIR, 'bt_cmd.txt')
BT_RESULT_FILE = os.path.join(PROJECT_DIR, 'bt_result.txt')
XENV           = {**os.environ, 'DISPLAY': ':0', 'XAUTHORITY': '/var/run/lightdm/root/:0'}
ALARM_PATH     = os.path.join(PROJECT_DIR, 'assets', 'alarm.wav')
PW_ENV         = {**os.environ,
                  'DISPLAY':              ':0',
                  'XAUTHORITY':           '/var/run/lightdm/root/:0',
                  'XDG_RUNTIME_DIR':      '/run/user/1000',
                  'PIPEWIRE_RUNTIME_DIR': '/run/user/1000',
                  'HOME':                 '/home/arduino'}

_alarm_stop   = threading.Event()
_alarm_thread = None

def _alarm_loop():
    print('[ALARM] Loop started', flush=True)
    while not _alarm_stop.is_set():
        try:
            p = subprocess.Popen(['pw-play', ALARM_PATH], env=PW_ENV)
            while p.poll() is None:
                if _alarm_stop.is_set():
                    p.terminate()
                    print('[ALARM] Stopped', flush=True)
                    return
                time.sleep(0.1)
        except Exception as e:
            print(f'[ALARM] Error: {e}', flush=True)
            break
    print('[ALARM] Loop ended', flush=True)

def bt_run(cmd, timeout=15):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception as e:
        return f'error:{e}'

def handle_command(cmd: str) -> str:
    global _alarm_thread
    cmd = cmd.strip()
    if cmd == 'ping':
        return 'pong'
    if cmd.startswith('play:') or cmd.startswith('mode:') or cmd == 'launch':
        return 'ok'
    if cmd == 'alarm':
        _alarm_stop.clear()
        if _alarm_thread is None or not _alarm_thread.is_alive():
            _alarm_thread = threading.Thread(target=_alarm_loop, daemon=True)
            _alarm_thread.start()
        return 'ok'
    if cmd == 'alarm_stop':
        _alarm_stop.set()
        return 'ok'
    if cmd.startswith('speak:'):
        text = cmd[6:].strip()
        if text:
            import subprocess
            subprocess.Popen(['espeak', text], env=PW_ENV)
        return 'ok'
    if cmd == 'BT_LIST':
        paired  = bt_run(['bluetoothctl', 'devices', 'Paired'])
        trusted = bt_run(['bluetoothctl', 'devices', 'Trusted'])
        combined = set()
        result = []
        for line in (paired + '\n' + trusted).split('\n'):
            if line.startswith('Device '):
                parts = line.split(' ', 2)
                if len(parts) >= 3 and parts[1] not in combined:
                    combined.add(parts[1])
                    result.append(line)
        return '\n'.join(result) or 'none'
    if cmd in ('BT_SCAN_START', 'BT_SCAN_STOP'):
        with open(BT_CMD_FILE, 'w') as f:
            f.write(cmd)
        return 'ok'
    if cmd.startswith('BT_PAIR:') or cmd.startswith('BT_CONNECT:') or \
       cmd.startswith('BT_DISCONNECT:') or cmd.startswith('BT_FORGET:'):
        with open(BT_CMD_FILE, 'w') as f:
            f.write(cmd)
        return 'ok'
    return 'ok'

def handle_client(conn):
    try:
        data = b''
        while True:
            chunk = conn.recv(1024)
            if not chunk: break
            data += chunk
            if b'\n' in data: break
        cmd = data.decode('utf-8', errors='ignore').strip()
        if cmd:
            response = handle_command(cmd)
            conn.sendall((response + '\n').encode('utf-8'))
    except Exception: pass
    finally: conn.close()

def run_unix_server():
    if os.path.exists(SOCK_PATH):
        os.remove(SOCK_PATH)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o777)
    server.listen(5)
    print(f'[SERVER] Listening on {SOCK_PATH}', flush=True)
    while True:
        try:
            conn, _ = server.accept()
            threading.Thread(target=handle_client, args=(conn,), daemon=True).start()
        except Exception: pass

if __name__ == '__main__':
    print('[LAUNCHER] Starting', flush=True)
    threading.Thread(target=run_unix_server, daemon=True).start()
    subprocess.Popen(['bash',
        os.path.join(os.path.dirname(__file__), 'chromium-launcher.sh')],
        env=XENV)
    while True:
        time.sleep(60)
