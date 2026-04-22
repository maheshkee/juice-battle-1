#!/bin/bash
set -e

APP_NAME="motion-sesnor-webui"
APP_DIR="/home/arduino/ArduinoApps/$APP_NAME"
WHEELS_DIR="$APP_DIR/wheels"
TYPELIBS_DIR="$APP_DIR/typelibs"

log() { echo "[setup] $1"; }
ok()  { echo "[  OK  ] $1"; }
err() { echo "[ FAIL ] $1"; exit 1; }

log "Starting setup for $APP_NAME"
echo "============================================"

log "Step 1 — Installing system dependencies..."
sudo apt update -qq
MISSING=""
dpkg -l libcairo2-dev &>/dev/null || MISSING="$MISSING libcairo2-dev"
dpkg -l libgirepository-2.0-dev &>/dev/null || MISSING="$MISSING libgirepository-2.0-dev"
dpkg -l socat &>/dev/null || MISSING="$MISSING socat"
if [ -n "$MISSING" ]; then
    sudo apt install -y $MISSING
    ok "Installed:$MISSING"
else
    ok "System dependencies already installed — skipping"
fi

log "Step 2 — Building Python wheels..."
mkdir -p "$WHEELS_DIR"
if ls "$WHEELS_DIR"/dbus_python*.whl &>/dev/null; then
    ok "dbus-python wheel already built — skipping"
else
    log "  Building dbus-python wheel (this takes ~60 seconds)..."
    pip3 wheel dbus-python --wheel-dir "$WHEELS_DIR" --quiet
    ok "dbus-python wheel built"
fi
if ls "$WHEELS_DIR"/PyGObject*.whl &>/dev/null; then
    ok "PyGObject wheel already built — skipping"
else
    log "  Building PyGObject wheel (this takes ~90 seconds)..."
    pip3 wheel PyGObject --wheel-dir "$WHEELS_DIR" --quiet
    ok "PyGObject wheel built"
fi

log "Step 3 — Copying shared libraries..."
LIBS=(
    "/lib/aarch64-linux-gnu/libdbus-1.so.3"
    "/lib/aarch64-linux-gnu/libapparmor.so.1"
    "/lib/aarch64-linux-gnu/libexpat.so.1"
    "/lib/aarch64-linux-gnu/libsystemd.so.0"
    "/usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0"
)
for lib in "${LIBS[@]}"; do
    filename=$(basename "$lib")
    if [ -f "$WHEELS_DIR/$filename" ]; then
        ok "  $filename already copied — skipping"
    else
        if [ -f "$lib" ]; then
            cp "$lib" "$WHEELS_DIR/"
            ok "  Copied $filename"
        else
            err "  Library not found: $lib"
        fi
    fi
done

log "Step 4 — Copying GObject typelibs..."
mkdir -p "$TYPELIBS_DIR"
TYPELIBS=("GLib-2.0.typelib" "GLibUnix-2.0.typelib" "Gio-2.0.typelib" "GObject-2.0.typelib" "DBus-1.0.typelib")
TYPELIB_SRC="/usr/lib/aarch64-linux-gnu/girepository-1.0"
for typelib in "${TYPELIBS[@]}"; do
    if [ -f "$TYPELIBS_DIR/$typelib" ]; then
        ok "  $typelib already copied — skipping"
    else
        if [ -f "$TYPELIB_SRC/$typelib" ]; then
            cp "$TYPELIB_SRC/$typelib" "$TYPELIBS_DIR/"
            ok "  Copied $typelib"
        else
            err "  Typelib not found: $TYPELIB_SRC/$typelib"
        fi
    fi
done

log "Step 5 — Setting up D-Bus bridge service..."
if sudo systemctl is-active --quiet dbus-bridge.service; then
    ok "dbus-bridge.service already running — skipping"
else
    sudo tee /etc/systemd/system/dbus-bridge.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for App Lab ($APP_NAME)
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f $APP_DIR/dbus.sock
ExecStart=/usr/bin/socat UNIX-LISTEN:$APP_DIR/dbus.sock,fork,reuseaddr,mode=0777,unlink-early UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable dbus-bridge.service
    sudo systemctl start dbus-bridge.service
    sleep 2
    if sudo systemctl is-active --quiet dbus-bridge.service; then
        ok "dbus-bridge.service started and enabled"
    else
        err "dbus-bridge.service failed — check: sudo journalctl -u dbus-bridge"
    fi
fi

log "Step 6 — Updating app.yaml..."
cat > "$APP_DIR/app.yaml" << EOF
name: $APP_NAME
icon: 🟢
description: "PIR motion sensor with web dashboard and BLE advertising"
ports: [7000]
bricks:
  - arduino:web_ui: {}
network_mode: "host"
sockets:
  - "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
EOF
ok "app.yaml updated"

echo ""
echo "============================================"
log "Verification:"
echo -n "  System deps:     "; dpkg -l libcairo2-dev &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  dbus wheel:      "; ls "$WHEELS_DIR"/dbus_python*.whl &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  PyGObject wheel: "; ls "$WHEELS_DIR"/PyGObject*.whl &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  Shared libs:     "; [ -f "$WHEELS_DIR/libdbus-1.so.3" ] && echo "OK" || echo "MISSING"
echo -n "  Typelibs:        "; [ -f "$TYPELIBS_DIR/GLib-2.0.typelib" ] && echo "OK" || echo "MISSING"
echo -n "  D-Bus bridge:    "; sudo systemctl is-active --quiet dbus-bridge.service && echo "OK (running)" || echo "NOT RUNNING"
echo -n "  app.yaml:        "; grep -q "network_mode" "$APP_DIR/app.yaml" && echo "OK" || echo "MISSING"
echo "============================================"
echo "Setup complete. Run the app in App Lab."
