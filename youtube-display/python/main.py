from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI
import os
import sys
import ctypes

os.environ["GI_TYPELIB_PATH"] = "/app/typelibs"
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/app/dbus.sock"

for lib in [
    "libm.so.6", "libcap.so.2", "libpcre2-8.so.0",
    "libselinux.so.1", "libaudit.so.1", "libcap-ng.so.0",
    "libexpat.so.1", "libdbus-1.so.3", "libapparmor.so.1",
    "libsystemd.so.0", "libgirepository-2.0.so.0",
]:
    try:
        ctypes.CDLL(f"/app/wheels/{lib}")
    except Exception as e:
        print(f"[MAIN] lib load failed {lib}: {e}", flush=True)

sys.path.insert(0, "/usr/lib/python3/dist-packages")

from ble_gatt_serve import BLEGattServer
from queue_engine import QueueEngine

ui = WebUI()
CMD_FILE        = "/app/cmd.txt"
LAUNCHER_SCRIPT = "/home/arduino/launcher.sh"

def write_cmd(cmd):
    with open(CMD_FILE, "w") as f:
        f.write(cmd)

def push_evt(data):
    ui.send_message(data.get("event", "evt"), data)

queue_engine = QueueEngine(write_cmd_fn=write_cmd, push_evt_fn=push_evt)


def install_launcher_if_needed():
    if os.path.exists(LAUNCHER_SCRIPT):
        print("[SETUP] Launcher already installed.", flush=True)
        return
    print("[SETUP] Writing launcher script...", flush=True)
    launcher_content = """#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/arduino/.Xauthority
CMD_FILE="/home/arduino/ArduinoApps/youtube-display/cmd.txt"
xset s off
xset s noblank
xset -dpms
echo "[LAUNCHER] Waiting for port 7000..."
until curl -s http://localhost:7000 > /dev/null 2>&1; do
    sleep 1
done
echo "[LAUNCHER] Ready."
pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
sleep 0.5
rm -rf /tmp/chrome-splash
/usr/bin/chromium --kiosk \\
    --no-sandbox --disable-gpu \\
    --noerrdialogs --disable-infobars \\
    --user-data-dir=/tmp/chrome-splash \\
    "http://localhost:7000/splash.html" &
while true; do
    if [ -f "$CMD_FILE" ]; then
        CMD=$(cat "$CMD_FILE")
        rm -f "$CMD_FILE"
        pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
        sleep 0.3
        if [ "$CMD" = "STOP" ]; then
            rm -rf /tmp/chrome-splash
            /usr/bin/chromium --kiosk \\
                --no-sandbox --disable-gpu \\
                --noerrdialogs --disable-infobars \\
                --user-data-dir=/tmp/chrome-splash \\
                "http://localhost:7000/splash.html" &
        else
            rm -rf /tmp/chrome-player
            /usr/bin/chromium --kiosk \\
                --no-sandbox --disable-gpu \\
                --noerrdialogs --disable-infobars \\
                --autoplay-policy=no-user-gesture-required \\
                --user-data-dir=/tmp/chrome-player \\
                "http://localhost:7000/player.html?v=$CMD" &
        fi
    fi
    sleep 0.5
done
"""
    with open(LAUNCHER_SCRIPT, "w") as f:
        f.write(launcher_content)
    os.chmod(LAUNCHER_SCRIPT, 0o755)
    print("[SETUP] Launcher script written.", flush=True)


def extract_video_id(url):
    if "/shorts/" in url:
        return url.split("/shorts/")[1].split("?")[0]
    elif "youtu.be/" in url:
        return url.split("youtu.be/")[1].split("?")[0]
    elif "v=" in url:
        return url.split("v=")[1].split("&")[0]
    return None


def on_ble_url(url):
    print(f"[BLE] URL received: {url}", flush=True)
    video_id = extract_video_id(url)
    if not video_id:
        print(f"[BLE] Invalid URL: {url}", flush=True)
        return
    write_cmd(video_id)
    ui.send_message("status", {"state": "playing", "video_id": video_id})

def on_ble_connected(device_name):
    print(f"[BLE] Connected: {device_name}", flush=True)
    ui.send_message("ble_connected", {"device": device_name})

def on_ble_disconnected():
    print("[BLE] Phone disconnected", flush=True)
    ui.send_message("ble_disconnected", {})

def on_ble_cmd(cmd):
    print(f"[BLE] CMD received: {cmd}", flush=True)
    raw = cmd.replace("CMD:", "").strip()
    if raw == "QUEUE_PLAY":
        queue_engine.play()
    elif raw == "QUEUE_REPLAY":
        queue_engine.replay()
    elif raw == "QUEUE_SKIP":
        queue_engine.skip()
    elif raw.startswith("QUEUE_GOTO:"):
        queue_engine.goto(raw.split(":", 1)[1])
    elif raw == "QUEUE_PAUSE":
        queue_engine.pause()
    elif raw == "QUEUE_RESUME":
        queue_engine.resume()
    elif raw == "QUEUE_STOP":
        queue_engine.stop()
    elif raw.startswith("QUEUE_SET:"):
        queue_engine.set_queue(raw[10:])
    elif raw == "QUEUE_GET":
        push_evt(queue_engine.get_status())
        push_evt(queue_engine.get_history())
    elif raw.lower() == "stop":
        write_cmd("STOP")
        ui.send_message("status", {"state": "stopped"})
    elif raw.lower() in ("pause", "resume", "vol_up", "vol_down"):
        ui.send_message("player_control", {"action": raw.lower()})
    else:
        print(f"[BLE] Unknown command: {raw}", flush=True)


def on_play_video(sid, data):
    url = data.get("url", "")
    video_id = extract_video_id(url)
    if not video_id:
        ui.send_message("error", {"message": "Invalid YouTube URL"})
        return
    write_cmd(video_id)
    print(f"[youtube-display] Playing: {video_id}", flush=True)
    ui.send_message("status", {"state": "playing", "video_id": video_id})

def on_control(sid, data):
    action = data.get("action", "")
    print(f"[youtube-display] Control: {action}", flush=True)
    if action == "stop":
        write_cmd("STOP")
        ui.send_message("status", {"state": "stopped"})
    else:
        ui.send_message("player_control", {"action": action})

def on_admin(sid, data):
    action = data.get("action", "")
    if action == "show_splash":
        write_cmd("STOP")

def on_video_ended(sid, data):
    video_id = data.get("videoId", "")
    print(f"[QUEUE] video_ended: {video_id}", flush=True)
    queue_engine.on_video_ended(video_id)


install_launcher_if_needed()

ble = BLEGattServer(
    on_url=on_ble_url,
    on_cmd=on_ble_cmd,
    on_connected=on_ble_connected,
    on_disconnected=on_ble_disconnected
)

ui.on_message("play_video",  on_play_video)
ui.on_message("control",     on_control)
ui.on_message("admin",       on_admin)
ui.on_message("video_ended", on_video_ended)

App.run()
