#!/usr/bin/env python3
import os
import socket
import subprocess
import threading
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOCK_PATH   = os.path.join(PROJECT_DIR, 'launcher.sock')
XENV        = {**os.environ, 'DISPLAY': ':0', 'XAUTHORITY': '/var/run/lightdm/root/:0'}

def handle_command(cmd: str) -> str:
    cmd = cmd.strip()
    if cmd == 'ping':
        return 'pong'
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
    # Launch the bash script which waits for port 7000 then opens Chromium
    subprocess.Popen(['bash', os.path.join(os.path.dirname(__file__), 'chromium-launcher.sh')],
        env=XENV)
    while True:
        time.sleep(60)
