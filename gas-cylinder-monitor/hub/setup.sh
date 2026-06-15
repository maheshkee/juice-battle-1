#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$PROJECT_DIR/app.yaml" ]; then
    APP_NAME="$(grep '^name:' "$PROJECT_DIR/app.yaml" | head -1 | sed 's/name:[[:space:]]*//' | tr -d '"' | tr -d "'")"
fi
if [ -z "$APP_NAME" ]; then
    APP_NAME="$(basename "$PROJECT_DIR")"
fi
SERVICE_NAME="dbus-bridge-${APP_NAME}.service"
WHEELS_DIR="$PROJECT_DIR/wheels"
TYPELIBS_DIR="$PROJECT_DIR/typelibs"

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERR]${NC}   $1"; exit 1; }

echo ""
echo "========================================================"
echo "  ${APP_NAME} -- Board Setup"
echo "  Self-contained. No external project dependencies."
echo "========================================================"
echo ""

# -- 1. System packages -------------------------------------------------------
log "Step 1 -- Installing system packages..."
sudo apt update -qq
sudo apt install -y \
    socat \
    libdbus-1-dev \
    libcairo2-dev \
    libgirepository-2.0-dev \
    2>/dev/null
log "System packages installed."

# -- 2. Build Python wheels ---------------------------------------------------
log "Step 2 -- Building Python wheels..."
mkdir -p "$WHEELS_DIR"

if ls "$WHEELS_DIR"/dbus_python*.whl > /dev/null 2>&1; then
    log "dbus-python wheel already built -- skipping."
else
    log "Building dbus-python wheel (~60s)..."
    pip3 wheel dbus-python --wheel-dir "$WHEELS_DIR" --quiet
    log "dbus-python wheel built."
fi

if ls "$WHEELS_DIR"/PyGObject*.whl > /dev/null 2>&1; then
    log "PyGObject wheel already built -- skipping."
else
    log "Building PyGObject wheel (~90s)..."
    pip3 wheel PyGObject --wheel-dir "$WHEELS_DIR" --quiet
    log "PyGObject wheel built."
fi

# -- 3. Copy shared libraries -------------------------------------------------
log "Step 3 -- Copying shared libraries..."
mkdir -p "$WHEELS_DIR"

for lib in \
    /lib/aarch64-linux-gnu/libm.so.6 \
    /lib/aarch64-linux-gnu/libcap.so.2 \
    /lib/aarch64-linux-gnu/libpcre2-8.so.0 \
    /lib/aarch64-linux-gnu/libselinux.so.1 \
    /lib/aarch64-linux-gnu/libaudit.so.1 \
    /lib/aarch64-linux-gnu/libcap-ng.so.0 \
    /lib/aarch64-linux-gnu/libexpat.so.1 \
    /lib/aarch64-linux-gnu/libdbus-1.so.3 \
    /lib/aarch64-linux-gnu/libapparmor.so.1 \
    /lib/aarch64-linux-gnu/libsystemd.so.0 \
    /usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0; do
    fname="$(basename "$lib")"
    if [ -f "$WHEELS_DIR/$fname" ]; then
        log "  $fname -- already present, skipping"
    elif [ -f "$lib" ]; then
        cp "$lib" "$WHEELS_DIR/"
        log "  $fname -- copied"
    else
        warn "  $fname -- not found on host"
    fi
done
log "Shared libraries done."

# -- 4. Copy GObject typelibs -------------------------------------------------
log "Step 4 -- Copying typelibs..."
mkdir -p "$TYPELIBS_DIR"
TYPELIB_SRC="/usr/lib/aarch64-linux-gnu/girepository-1.0"

for typelib in \
    GLib-2.0.typelib \
    GLibUnix-2.0.typelib \
    Gio-2.0.typelib \
    GObject-2.0.typelib \
    DBus-1.0.typelib; do
    if [ -f "$TYPELIBS_DIR/$typelib" ]; then
        log "  $typelib -- already present, skipping"
    elif [ -f "$TYPELIB_SRC/$typelib" ]; then
        cp "$TYPELIB_SRC/$typelib" "$TYPELIBS_DIR/"
        log "  $typelib -- copied"
    else
        warn "  $typelib -- not found on host"
    fi
done
log "Typelibs done."

# -- 5. Create dbus-bridge systemd service ------------------------------------
log "Step 5 -- Checking $SERVICE_NAME..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "$SERVICE_NAME already active -- skipping."
else
    sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for ${APP_NAME}
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f ${PROJECT_DIR}/dbus.sock
ExecStart=/usr/bin/socat UNIX-LISTEN:${PROJECT_DIR}/dbus.sock,fork,reuseaddr,mode=0777,unlink-early UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "$SERVICE_NAME started and enabled."
    else
        err "$SERVICE_NAME failed to start. Check: sudo journalctl -u $SERVICE_NAME"
    fi
fi

# Clean up old incorrectly-named service if it exists
if systemctl is-active --quiet "dbus-bridge-hub.service" 2>/dev/null; then
    log "Removing old dbus-bridge-hub.service..."
    sudo systemctl stop dbus-bridge-hub.service 2>/dev/null || true
    sudo systemctl disable dbus-bridge-hub.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/dbus-bridge-hub.service
    sudo systemctl daemon-reload
    log "Old service removed."
fi

# -- 6. Copy socket.io.min.js from system pip or fail gracefully --------------
log "Step 6 -- Checking socket.io.min.js..."
mkdir -p "$PROJECT_DIR/assets"
SOCKETIO_DST="$PROJECT_DIR/assets/socket.io.min.js"

if [ -f "$SOCKETIO_DST" ]; then
    log "socket.io.min.js already present -- skipping."
else
    # Try to find it from any other installed app on this board
    FOUND=$(find /home/arduino/ArduinoApps -name "socket.io.min.js" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        cp "$FOUND" "$SOCKETIO_DST"
        log "socket.io.min.js copied from: $FOUND"
    else
        warn "socket.io.min.js not found on board."
        warn "Download manually and place at: $SOCKETIO_DST"
        warn "URL: https://cdn.socket.io/4.7.5/socket.io.min.js"
    fi
fi

# -- 7. Auto-generate python/requirements.txt from actual wheel filenames -----
log "Step 7 -- Generating requirements.txt from wheels..."
REQS_FILE="$PROJECT_DIR/python/requirements.txt"
> "$REQS_FILE"
for whl in "$WHEELS_DIR"/*.whl; do
    fname="$(basename "$whl")"
    echo "/app/wheels/$fname" >> "$REQS_FILE"
done
log "requirements.txt written:"
cat "$REQS_FILE"

# -- 8. Mark setup complete ---------------------------------------------------
touch "$HOME/.${APP_NAME}-setup-done"

# -- 9. Set default App Lab app -----------------------------------------------
log "Step 9 -- Setting gas-cylinder-monitor as default app..."
arduino-app-cli properties set default user:gas-cylinder-monitor/hub 2>/dev/null && \
    log "Default app set to gas-cylinder-monitor." || \
    warn "Could not set default app -- set manually in App Lab if needed."

echo ""
echo "========================================================"
log "Verification:"
echo -n "  System deps:     "; dpkg -l libdbus-1-dev &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  dbus wheel:      "; ls "$WHEELS_DIR"/dbus_python*.whl &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  PyGObject wheel: "; ls "$WHEELS_DIR"/PyGObject*.whl &>/dev/null && echo "OK" || echo "MISSING"
echo -n "  Shared libs:     "; [ -f "$WHEELS_DIR/libdbus-1.so.3" ] && echo "OK" || echo "MISSING"
echo -n "  Typelibs:        "; [ -f "$TYPELIBS_DIR/GLib-2.0.typelib" ] && echo "OK" || echo "MISSING"
echo -n "  D-Bus bridge:    "; systemctl is-active --quiet "$SERVICE_NAME" && echo "OK (running)" || echo "NOT RUNNING"
echo -n "  socket.io:       "; [ -f "$SOCKETIO_DST" ] && echo "OK" || echo "MISSING (see warn above)"
echo "========================================================"
echo ""
echo "Setup complete. Run: bash deploy.sh"
