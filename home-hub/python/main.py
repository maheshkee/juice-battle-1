from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI
import os
import sys
import ctypes
import time

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
from local_engine import LocalEngine
from services import gas_monitor

ui = WebUI()
import pathlib
_APP_ROOT = pathlib.Path(__file__).resolve().parent.parent  # /app/ inside Docker
LAUNCHER_SCRIPT = str(_APP_ROOT / "launcher.sh")


def write_cmd(cmd):
    """Central dispatcher — routes commands to display via Socket.IO.
    No more cmd.txt for video. BT bridge (bt_cmd.txt) untouched in launcher.sh.
    """
    if cmd == "STOP":
        ui.send_message("player_control", {"action": "stop"})
    elif cmd.startswith("LOCAL:"):
        filename = cmd[6:]
        ui.send_message("play_local_display", {"filename": filename})
        print(f"[MAIN] Local play: {filename}", flush=True)
    else:
        # YouTube video_id
        ui.send_message("play_video_display", {"video_id": cmd})
        ui.send_message("status", {"state": "playing", "video_id": cmd})
        print(f"[MAIN] YT play: {cmd}", flush=True)


def push_evt(data):
    # Send via BLE EVT characteristic to phone
    # ble may not be initialized yet at module load time
    # so we use a late-binding approach
    try:
        ble.push_evt(data)
    except Exception:
        pass
    # Also send via Socket.IO for web dashboard
    ui.send_message(data.get("event", "evt"), data)


queue_engine = LocalEngine_ref = None

def _init_engines():
    global queue_engine, LocalEngine_ref
    queue_engine     = QueueEngine(write_cmd_fn=write_cmd, push_evt_fn=push_evt)
    LocalEngine_ref  = LocalEngine(write_cmd_fn=write_cmd, push_evt_fn=push_evt)
    gas_monitor.init(Bridge, push_evt)


def install_launcher_if_needed():
    if os.path.exists(LAUNCHER_SCRIPT):
        print("[SETUP] Launcher already installed.", flush=True)
        return
    print("[SETUP] Writing launcher script...", flush=True)
    launcher_content = """#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/arduino/.Xauthority

xset s off
xset s noblank
xset -dpms
xset dpms 0 0 0

xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/color-style -s 0
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/image-show -s false
xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior -s 1

unclutter -idle 0 -root &

echo "[LAUNCHER] Waiting for port 7000..."
until curl -s http://localhost:7000 > /dev/null 2>&1; do
    sleep 1
done
echo "[LAUNCHER] Ready."

pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
sleep 0.5
rm -rf /tmp/chrome-kiosk
/usr/bin/chromium --kiosk \\
    --no-sandbox --disable-gpu \\
    --noerrdialogs --disable-infobars \\
    --autoplay-policy=no-user-gesture-required \\
    --user-data-dir=/tmp/chrome-kiosk \\
    "http://localhost:7000/splash.html" &

# BT command bridge — unchanged
BT_CMD_FILE="$SCRIPT_DIR/bt_cmd.txt"
BT_RESULT_FILE="$SCRIPT_DIR/bt_result.txt"
while true; do
    if [ -f "$BT_CMD_FILE" ]; then
        BT_CMD=$(cat "$BT_CMD_FILE")
        rm -f "$BT_CMD_FILE"
        echo "[LAUNCHER] BT cmd: $BT_CMD"
        export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$SCRIPT_DIR/dbus.sock
        case "$BT_CMD" in
            BT_LIST)
                bluetoothctl devices Trusted > "$BT_RESULT_FILE" 2>&1
                ;;
            BT_SCAN_START)
                echo "scanning" > "$BT_RESULT_FILE"
                timeout 12 bluetoothctl scan on 2>&1 | grep -E "Device|NEW|CHG" >> "$BT_RESULT_FILE" &
                ;;
            BT_SCAN_STOP)
                bluetoothctl scan off > /dev/null 2>&1
                echo "scan_stopped" > "$BT_RESULT_FILE"
                ;;
            BT_PAIR:*)
                MAC="${BT_CMD#BT_PAIR:}"
                bluetoothctl pair "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl trust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                echo "paired:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_CONNECT:*)
                MAC="${BT_CMD#BT_CONNECT:}"
                bluetoothctl connect "$MAC" > "$BT_RESULT_FILE" 2>&1
                sleep 3
                SINK=$(wpctl status | grep -i bluez | head -1 | awk -F. '{print $1}' | xargs)
                if [ -n "$SINK" ]; then
                    wpctl set-default "$SINK"
                    echo "sink_set:$SINK" >> "$BT_RESULT_FILE"
                fi
                echo "connected:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_DISCONNECT:*)
                MAC="${BT_CMD#BT_DISCONNECT:}"
                bluetoothctl disconnect "$MAC" > "$BT_RESULT_FILE" 2>&1
                echo "disconnected:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_FORGET:*)
                MAC="${BT_CMD#BT_FORGET:}"
                bluetoothctl untrust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl remove "$MAC" >> "$BT_RESULT_FILE" 2>&1
                echo "forgotten:$MAC" >> "$BT_RESULT_FILE"
                ;;
        esac
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


# ── BLE callbacks ─────────────────────────────────────────────────────────────

def on_ble_url(url):
    print(f"[BLE] URL received: {url}", flush=True)
    video_id = extract_video_id(url)
    if not video_id:
        print(f"[BLE] Invalid URL: {url}", flush=True)
        return
    write_cmd(video_id)

def on_ble_connected(device_name):
    print(f"[BLE] Connected: {device_name}", flush=True)
    ui.send_message("ble_connected", {"device": device_name})

def on_ble_disconnected():
    print("[BLE] Phone disconnected", flush=True)
    ui.send_message("ble_disconnected", {})

def on_ble_cmd(cmd):
    print(f"[BLE] CMD received: {cmd}", flush=True)
    raw = cmd.replace("CMD:", "").strip()

    # Queue commands
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
        ui.send_message("player_control", {"action": "pause"})
    elif raw == "QUEUE_RESUME":
        queue_engine.resume()
        ui.send_message("player_control", {"action": "resume"})
    elif raw == "QUEUE_STOP":
        queue_engine.stop()
    elif raw.startswith("QUEUE_SET:"):
        queue_engine.set_queue(raw[10:])
    elif raw == "QUEUE_GET":
        push_evt(queue_engine.get_status())
        push_evt(queue_engine.get_history())

    # Local storage commands
    elif raw == "LOCAL_LIST":
        LocalEngine_ref.list_files()
    elif raw.startswith("LOCAL_PLAY:"):
        LocalEngine_ref.play_file(raw[11:])
    elif raw.startswith("LOCAL_QUEUE_SET:"):
        LocalEngine_ref.set_playlist(raw[16:])
    elif raw == "LOCAL_QUEUE_PLAY":
        LocalEngine_ref.play_playlist()
    elif raw == "LOCAL_USB_IMPORT":
        LocalEngine_ref.usb_import()

    # Playback commands
    elif raw.lower() == "stop":
        write_cmd("STOP")
        ui.send_message("status", {"state": "stopped"})
    elif raw.lower() in ("pause", "resume", "vol_up", "vol_down"):
        ui.send_message("player_control", {"action": raw.lower()})
    else:
        print(f"[BLE] Unknown command: {raw}", flush=True)


# ── WebUI callbacks ───────────────────────────────────────────────────────────

def on_play_video(sid, data):
    url = data.get("url", "")
    video_id = extract_video_id(url)
    if not video_id:
        ui.send_message("error", {"message": "Invalid YouTube URL"})
        return
    write_cmd(video_id)

def on_control(sid, data):
    action = data.get("action", "")
    print(f"[WebUI] Control: {action}", flush=True)
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
    filename = data.get("filename", "")
    print(f"[MAIN] media_ended: yt={video_id} local={filename}", flush=True)
    if video_id:
        queue_engine.on_video_ended(video_id)
    elif filename:
        LocalEngine_ref.on_video_ended(filename)


# ── Start ─────────────────────────────────────────────────────────────────────

install_launcher_if_needed()
_init_engines()

ble = BLEGattServer(
    on_url=on_ble_url,
    on_cmd=on_ble_cmd,
    on_connected=on_ble_connected,
    on_disconnected=on_ble_disconnected
)

ui.on_message("play_video",   on_play_video)
ui.on_message("control",      on_control)
ui.on_message("admin",        on_admin)
ui.on_message("video_ended",  on_video_ended)

import threading

def on_weight_event(data):
    import json
    try:
        if isinstance(data, str):
            data = json.loads(data)
        if not data.get('sensor_ok', False):
            return
        ui.send_message('weight_update', data)
        print(f"[WEIGHT] {data.get('grams',0):.1f}g / {data.get('weight_kg',0):.4f}kg stable={data.get('stable')}", flush=True)
    except Exception as e:
        print(f"[WEIGHT] parse error: {e}", flush=True)

Bridge.provide('weight_event', on_weight_event)

App.run()
