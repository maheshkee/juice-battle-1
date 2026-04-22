#!/usr/bin/env python3
# chromium-launcher.py
# Launches Chromium on boot and keeps it running.
# Serves assets/ on port 8080 so display.html is always available
# regardless of whether App Lab is running.
# Receives commands from App Lab container via Unix socket.
#
# Commands:
#   ping            -- health check, responds with "pong"
#   play:<id>       -- ensure Chromium is open
#   mode:<mode>     -- ensure Chromium is open
#   stop            -- no-op (handled by display.js via Socket.IO)
#   launch          -- launch Chromium if not running

import os
import socket
import subprocess
import threading
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler

# --- config ---

PROJECT_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR   = os.path.join(PROJECT_DIR, 'assets')
SOCK_PATH    = os.path.join(PROJECT_DIR, 'launcher.sock')
XENV         = {**os.environ, 'DISPLAY': ':0', 'XAUTHORITY': '/var/run/lightdm/root/:0'}
HTTP_PORT    = 8080
DISPLAY_URL  = f'http://localhost:{HTTP_PORT}/display.html'


def _get_board_ip():
    import socket as _s
    try:
        s = _s.socket(_s.AF_INET, _s.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'


BOARD_IP   = _get_board_ip()
WEBUI_PORT = 7000
WEBUI_URL  = f'http://{BOARD_IP}:{WEBUI_PORT}'

# --- state ---

chromium_proc = None


# --- HTTP server ---

class AssetsHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ASSETS_DIR, **kwargs)

    def log_message(self, format, *args):
        pass  # suppress access logs


def run_http_server():
    server = HTTPServer(('0.0.0.0', HTTP_PORT), AssetsHandler)
    print(f'[HTTP] Serving {ASSETS_DIR} on port {HTTP_PORT}', flush=True)
    server.serve_forever()


# --- xset ---

def disable_screen_blanking():
    for cmd in [['xset', 's', 'off'], ['xset', '-dpms'], ['xset', 's', 'noblank']]:
        try:
            subprocess.Popen(cmd, env=XENV)
            print(f'[XSET] {" ".join(cmd)}', flush=True)
        except Exception as e:
            print(f'[XSET] Failed: {e}', flush=True)


# --- Chromium ---

def chromium_running():
    return chromium_proc is not None and chromium_proc.poll() is None


def launch_chromium():
    global chromium_proc
    if chromium_running():
        return
    print(f'[CHROMIUM] Launching: {DISPLAY_URL}', flush=True)
    try:
        chromium_proc = subprocess.Popen([
            'chromium',
            '--kiosk',
            '--noerrdialogs',
            '--disable-infobars',
            '--no-first-run',
            '--autoplay-policy=no-user-gesture-required',
            '--disable-session-crashed-bubble',
            '--disable-features=Translate',
            DISPLAY_URL
        ], env=XENV)
        print(f'[CHROMIUM] Started (PID {chromium_proc.pid})', flush=True)
    except Exception as e:
        print(f'[CHROMIUM] Launch failed: {e}', flush=True)


# --- command handler ---

def handle_command(cmd: str) -> str:
    cmd = cmd.strip()
    print(f'[CMD] {cmd}', flush=True)

    if cmd == 'ping':
        return 'pong'

    if cmd == 'stop':
        return 'ok'

    if cmd.startswith('play:') or cmd.startswith('mode:') or cmd == 'launch':
        if not chromium_running():
            launch_chromium()
        return 'ok'

    return f'unknown:{cmd}'


# --- Unix socket server ---

def handle_client(conn):
    try:
        data = b''
        while True:
            chunk = conn.recv(1024)
            if not chunk:
                break
            data += chunk
            if b'\n' in data:
                break
        cmd = data.decode('utf-8', errors='ignore').strip()
        if cmd:
            response = handle_command(cmd)
            conn.sendall((response + '\n').encode('utf-8'))
    except Exception as e:
        print(f'[CLIENT] Error: {e}', flush=True)
    finally:
        conn.close()


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
        except Exception as e:
            print(f'[SERVER] Accept error: {e}', flush=True)


# --- wait for X display ---

def wait_for_display(timeout=60):
    print('[DISPLAY] Waiting for X server on :0...', flush=True)
    for i in range(timeout):
        try:
            result = subprocess.run(
                ['xset', 'q'],
                env=XENV,
                capture_output=True,
                timeout=2
            )
            if result.returncode == 0:
                print(f'[DISPLAY] X server ready (after {i}s)', flush=True)
                return
        except Exception:
            pass
        time.sleep(1)
    print('[DISPLAY] X server did not become ready in time', flush=True)


# --- entry point ---

if __name__ == '__main__':
    print('[LAUNCHER] Starting', flush=True)
    print(f'[LAUNCHER] Project dir : {PROJECT_DIR}', flush=True)
    print(f'[LAUNCHER] Assets dir  : {ASSETS_DIR}', flush=True)
    print(f'[LAUNCHER] Socket path : {SOCK_PATH}', flush=True)
    print(f'[LAUNCHER] Display URL : {DISPLAY_URL}', flush=True)
    print(f'[LAUNCHER] WebUI URL   : {WEBUI_URL}', flush=True)

    # Start HTTP server immediately - serves assets independent of App Lab
    threading.Thread(target=run_http_server, daemon=True).start()

    # Start Unix socket server immediately - App Lab can connect right away
    threading.Thread(target=run_unix_server, daemon=True).start()

    # Wait for X server before touching display
    wait_for_display()

    disable_screen_blanking()

    # Launch Chromium - idle screen shows right away from local HTTP server
    launch_chromium()

    # Block main thread
    while True:
        time.sleep(60)