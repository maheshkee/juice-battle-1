#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
export DISPLAY=:0
export XAUTHORITY=/var/run/lightdm/root/:0
export XDG_RUNTIME_DIR=/run/user/1000
export PIPEWIRE_RUNTIME_DIR=/run/user/1000
BT_CMD_FILE="$PROJECT_DIR/bt_cmd.txt"
BT_RESULT_FILE="$PROJECT_DIR/bt_result.txt"
BT_CONNECTED_FILE="$PROJECT_DIR/bt_connected.txt"

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
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --autoplay-policy=no-user-gesture-required \
    --disable-session-crashed-bubble \
    --disable-features=Translate \
    --user-data-dir=/tmp/chrome-kiosk \
    "http://localhost:7000/display.html" &

echo "[LAUNCHER] Chromium started"

while true; do
    if [ -f "$BT_CMD_FILE" ]; then
        BT_CMD=$(cat "$BT_CMD_FILE")
        rm -f "$BT_CMD_FILE"
        echo "[BT] CMD: $BT_CMD"
        export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$PROJECT_DIR/dbus.sock
        case "$BT_CMD" in
            BT_CONNECT:*)
                MAC="${BT_CMD#BT_CONNECT:}"
                > "$BT_RESULT_FILE"
                if [ -f "$BT_CONNECTED_FILE" ]; then
                    OLD_ENTRY=$(cat "$BT_CONNECTED_FILE")
                    OLD_MAC="${OLD_ENTRY%%|*}"
                    if [ -n "$OLD_MAC" ] && [ "$OLD_MAC" != "$MAC" ]; then
                        echo "[BT] Disconnecting old speaker $OLD_MAC..." >> "$BT_RESULT_FILE"
                        bluetoothctl disconnect "$OLD_MAC" >> "$BT_RESULT_FILE" 2>&1
                        sleep 1
                    fi
                fi
                echo "[BT] Scanning to populate cache..." >> "$BT_RESULT_FILE"
                timeout 8 bluetoothctl scan on >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl scan off 2>/dev/null
                sleep 1
                bluetoothctl pair "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl trust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl connect "$MAC" >> "$BT_RESULT_FILE" 2>&1
                sleep 2
                NAME=$(bluetoothctl info "$MAC" 2>/dev/null | grep '^\s*Name:' | sed 's/.*Name: //' | xargs)
                [ -z "$NAME" ] && NAME="$MAC"
                SINK_ID=$(wpctl status 2>/dev/null | grep -E '^\s*[0-9]+\.' | grep -iv 'hdmi\|built-in\|source\|capture' | grep -i 'bluez\|pop\|fuzo\|hbts\|dubstep' | grep -o '^\s*[0-9]*\.' | tr -d ' .' | head -1)
                if [ -n "$SINK_ID" ]; then
                    wpctl set-default "$SINK_ID" 2>/dev/null
                    echo "[BT] Set default sink to $SINK_ID" >> "$BT_RESULT_FILE"
                fi
                echo "$MAC|$NAME" > "$BT_CONNECTED_FILE"
                echo "connected:$MAC|$NAME" >> "$BT_RESULT_FILE"
                ;;
            BT_DISCONNECT:*)
                MAC="${BT_CMD#BT_DISCONNECT:}"
                > "$BT_RESULT_FILE"
                bluetoothctl disconnect "$MAC" >> "$BT_RESULT_FILE" 2>&1
                rm -f "$BT_CONNECTED_FILE"
                echo "disconnected:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_PAIR:*)
                MAC="${BT_CMD#BT_PAIR:}"
                > "$BT_RESULT_FILE"
                bluetoothctl pair "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl trust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                echo "paired:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_FORGET:*)
                MAC="${BT_CMD#BT_FORGET:}"
                > "$BT_RESULT_FILE"
                bluetoothctl untrust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl remove "$MAC" >> "$BT_RESULT_FILE" 2>&1
                rm -f "$BT_CONNECTED_FILE"
                echo "forgotten:$MAC" >> "$BT_RESULT_FILE"
                ;;
        esac
    fi
    sleep 0.5
done
