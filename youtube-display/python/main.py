from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI
import os

ui = WebUI()
CMD_FILE = "/app/cmd.txt"
LAUNCHER_SCRIPT = "/home/arduino/launcher.sh"

def install_launcher_if_needed():
    if os.path.exists(LAUNCHER_SCRIPT):
        print("[SETUP] Launcher already installed.", flush=True)
        return
    print("[SETUP] Writing launcher script...", flush=True)
    with open(LAUNCHER_SCRIPT, "w") as f:
        f.write('''#!/bin/bash
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
''')
    os.chmod(LAUNCHER_SCRIPT, 0o755)
    print("[SETUP] Launcher script written.", flush=True)

def on_play_video(sid, data):
    url = data.get("url", "")
    try:
        if "/shorts/" in url:
            video_id = url.split("/shorts/")[1].split("?")[0]
        else:
            video_id = url.split("v=")[1].split("&")[0]
    except (IndexError, AttributeError):
        ui.send_message("error", {"message": "Invalid YouTube URL"})
        return
    with open(CMD_FILE, "w") as f:
        f.write(video_id)
    print(f"[youtube-display] Playing: {video_id}", flush=True)
    ui.send_message("status", {"state": "playing", "video_id": video_id})

def on_control(sid, data):
    action = data.get("action", "")
    print(f"[youtube-display] Control: {action}", flush=True)
    if action == "stop":
        with open(CMD_FILE, "w") as f:
            f.write("STOP")
        ui.send_message("status", {"state": "stopped"})
    else:
        ui.send_message("player_control", {"action": action})

def on_admin(sid, data):
    action = data.get("action", "")
    if action == "show_splash":
        with open(CMD_FILE, "w") as f:
            f.write("STOP")

install_launcher_if_needed()
ui.on_message("play_video", on_play_video)
ui.on_message("control", on_control)
ui.on_message("admin", on_admin)
App.run()
