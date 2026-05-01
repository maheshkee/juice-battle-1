#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DISPLAY=:0
export XAUTHORITY=/var/run/lightdm/root/:0

xset s off
xset s noblank
xset -dpms

echo "[LAUNCHER] Waiting for port 7000..."
until curl -s http://localhost:7000 > /dev/null 2>&1; do
    sleep 1
done
echo "[LAUNCHER] Port 7000 ready, waiting 2s..."
sleep 2

pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
sleep 0.5
rm -rf /tmp/chrome-kiosk

echo "[LAUNCHER] Launching Chromium -> http://localhost:7000/display.html"
/usr/bin/chromium --kiosk \
    --no-sandbox \
    --disable-gpu \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --autoplay-policy=no-user-gesture-required \
    --disable-session-crashed-bubble \
    --disable-features=Translate \
    --user-data-dir=/tmp/chrome-kiosk \
    "http://localhost:7000/display.html" &

echo "[LAUNCHER] Chromium started"
