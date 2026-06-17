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
WIFI_CMD_FILE="$PROJECT_DIR/wifi_cmd.txt"
WIFI_RESULT_FILE="$PROJECT_DIR/wifi_result.txt"

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

bt_connect() {
    local MAC="$1"
    > "$BT_RESULT_FILE"

    if [ -f "$BT_CONNECTED_FILE" ]; then
        OLD_ENTRY=$(cat "$BT_CONNECTED_FILE")
        OLD_MAC="${OLD_ENTRY%%|*}"
        if [ -n "$OLD_MAC" ] && [ "$OLD_MAC" != "$MAC" ]; then
            echo "[BT] Disconnecting old: $OLD_MAC" >> "$BT_RESULT_FILE"
            bluetoothctl disconnect "$OLD_MAC" >> "$BT_RESULT_FILE" 2>&1
            sleep 1
        fi
    fi

    echo "[BT] Scanning for $MAC..." >> "$BT_RESULT_FILE"

    FIFO=$(mktemp -u /tmp/btfifo.XXXXXX)
    mkfifo "$FIFO"
    bluetoothctl < "$FIFO" >> "$BT_RESULT_FILE" 2>&1 &
    BT_PID=$!
    exec 3>"$FIFO"
    echo "scan on" >&3

    FOUND=0
    for i in $(seq 1 20); do
        sleep 0.5
        if grep -q "$MAC" "$BT_RESULT_FILE" 2>/dev/null; then
            FOUND=1
            break
        fi
    done

    echo "scan off" >&3
    sleep 0.5
    exec 3>&-
    wait $BT_PID 2>/dev/null
    rm -f "$FIFO"

    if [ $FOUND -eq 0 ]; then
        echo "[BT] Device $MAC not found in scan" >> "$BT_RESULT_FILE"
    fi

    echo "[BT] Connecting $MAC..." >> "$BT_RESULT_FILE"
    bluetoothctl pair    "$MAC" >> "$BT_RESULT_FILE" 2>&1
    bluetoothctl trust   "$MAC" >> "$BT_RESULT_FILE" 2>&1
    CONNECT_OUT=$(bluetoothctl connect "$MAC" 2>&1)
    echo "$CONNECT_OUT" >> "$BT_RESULT_FILE"

    if echo "$CONNECT_OUT" | grep -q "Connection successful"; then
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
    else
        echo "[BT] Connection failed for $MAC" >> "$BT_RESULT_FILE"
        echo "error:$MAC" >> "$BT_RESULT_FILE"
    fi
}

wifi_provision() {
    local SSID="$1"
    local PASSWORD="$2"
    > "$WIFI_RESULT_FILE"
    echo "[WIFI] Connecting to: $SSID"
    unset DBUS_SYSTEM_BUS_ADDRESS
    CONNECT_OUT=$(nmcli con up "$SSID" 2>&1)
    if echo "$CONNECT_OUT" | grep -qE "successfully activated|Connection successfully activated"; then
        printf "method:saved_profile
" >> "$WIFI_RESULT_FILE"
        printf "wifi_ok:%s
" "$SSID" >> "$WIFI_RESULT_FILE"
        printf "%s||%s
" "$SSID" "$(date '+%Y-%m-%d %H:%M:%S')" > "$PROJECT_DIR/wifi_last.txt"
        echo "[WIFI] Connected to $SSID via saved profile"
        return
    fi
    echo "[WIFI] No saved profile, scanning for: $SSID"
    nmcli dev wifi rescan ifname wlan0 2>/dev/null || true
    FOUND=0
    for i in $(seq 1 20); do
        sleep 1
        if nmcli dev wifi list 2>/dev/null | grep -qF "$SSID"; then
            FOUND=1
            break
        fi
        nmcli dev wifi rescan ifname wlan0 2>/dev/null || true
    done
    if [ $FOUND -eq 0 ]; then
        printf "wifi_fail:%s
" "$SSID" >> "$WIFI_RESULT_FILE"
        echo "[WIFI] Network not found: $SSID"
        return
    fi
    echo "[WIFI] Network found, connecting..."
    CONNECT_OUT=$(nmcli dev wifi connect "$SSID" password "$PASSWORD" 2>&1)
    if echo "$CONNECT_OUT" | grep -qE "successfully activated|Connection successfully activated"; then
        printf "method:fresh_connect
" >> "$WIFI_RESULT_FILE"
        printf "wifi_ok:%s
" "$SSID" >> "$WIFI_RESULT_FILE"
        printf "%s||%s
" "$SSID" "$(date '+%Y-%m-%d %H:%M:%S')" > "$PROJECT_DIR/wifi_last.txt"
        echo "[WIFI] Connected to $SSID via fresh connect"
    else
        printf "wifi_fail:%s
" "$SSID" >> "$WIFI_RESULT_FILE"
        echo "[WIFI] Failed to connect to $SSID"
    fi
}

while true; do
    if [ -f "$BT_CMD_FILE" ]; then
        BT_CMD=$(cat "$BT_CMD_FILE")
        rm -f "$BT_CMD_FILE"
        echo "[BT] CMD: $BT_CMD"
        export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$PROJECT_DIR/dbus.sock
        case "$BT_CMD" in
            BT_CONNECT:*)
                MAC="${BT_CMD#BT_CONNECT:}"
                bt_connect "$MAC"
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
                bluetoothctl pair  "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl trust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                echo "paired:$MAC" >> "$BT_RESULT_FILE"
                ;;
            BT_FORGET:*)
                MAC="${BT_CMD#BT_FORGET:}"
                > "$BT_RESULT_FILE"
                bluetoothctl untrust "$MAC" >> "$BT_RESULT_FILE" 2>&1
                bluetoothctl remove  "$MAC" >> "$BT_RESULT_FILE" 2>&1
                rm -f "$BT_CONNECTED_FILE"
                echo "forgotten:$MAC" >> "$BT_RESULT_FILE"
                ;;
        esac
    fi

    if [ -f "$WIFI_CMD_FILE" ]; then
        WIFI_CMD=$(cat "$WIFI_CMD_FILE")
        rm -f "$WIFI_CMD_FILE"
        echo "[WIFI] CMD: $WIFI_CMD"
        case "$WIFI_CMD" in
            WIFI_PROVISION:*)
                PAYLOAD="${WIFI_CMD#WIFI_PROVISION:}"
                SSID="${PAYLOAD%%||*}"
                PASSWORD="${PAYLOAD#*||}"
                wifi_provision "$SSID" "$PASSWORD"
                ;;
        esac
    fi

    sleep 0.5
done