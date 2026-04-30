#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
/usr/bin/chromium --kiosk \
    --no-sandbox --disable-gpu \
    --noerrdialogs --disable-infobars \
    --autoplay-policy=no-user-gesture-required \
    --user-data-dir=/tmp/chrome-kiosk \
    "http://localhost:7000/splash.html" &

# BT command bridge -- untouched
BT_CMD_FILE="$PROJECT_DIR/bt_cmd.txt"
BT_RESULT_FILE="$PROJECT_DIR/bt_result.txt"
while true; do
    if [ -f "$BT_CMD_FILE" ]; then
        BT_CMD=$(cat "$BT_CMD_FILE")
        rm -f "$BT_CMD_FILE"
        echo "[LAUNCHER] BT cmd: $BT_CMD"
        export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$PROJECT_DIR/dbus.sock
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
