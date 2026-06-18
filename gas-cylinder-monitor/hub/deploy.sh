#!/bin/bash
# =============================================================================
# gas-cylinder-monitor -- Deploy script
# Run this to start, restart, or update the app.
# Usage: bash deploy.sh [--logs]
# =============================================================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$PROJECT_DIR/app.yaml" ]; then
    APP_NAME="$(grep '^name:' "$PROJECT_DIR/app.yaml" | head -1 | sed 's/name:[[:space:]]*//' | tr -d '"' | tr -d "'")"
fi
if [ -z "$APP_NAME" ]; then
    APP_NAME="$(basename "$PROJECT_DIR")"
fi
SERVICE_NAME="dbus-bridge-${APP_NAME}.service"
# App Lab ID = relative path from ~/ArduinoApps/ to this dir
APP_LAB_ID="$(realpath "$PROJECT_DIR" | sed "s|$HOME/ArduinoApps/||")"

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }

# Check setup has been run
if [ ! -f "$HOME/.gas-cylinder-monitor-setup-done" ]; then
    echo -e "${RED}[ERROR]${NC} Setup not complete. Run: bash setup.sh first."
    exit 1
fi

echo ""
echo "========================================================"
echo "  gas-cylinder-monitor -- Deploy"
echo "========================================================"
echo ""

# -- Stop app ------------------------------------------------------------------
log "Stopping $APP_NAME..."
arduino-app-cli app stop user:$APP_LAB_ID 2>/dev/null || true
sleep 2

# -- Clear cache ---------------------------------------------------------------
log "Clearing cache..."
rm -rf "$PROJECT_DIR/.cache"

# -- Restart dbus-bridge to guarantee fresh socket ----------------------------
log "Restarting $SERVICE_NAME (ensures fresh dbus.sock)..."
sudo systemctl restart "$SERVICE_NAME"
sleep 2
if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[ERR] $SERVICE_NAME failed to start"
    exit 1
fi
log "$SERVICE_NAME running. dbus.sock ready."

# -- Ensure BT adapter is powered ----------------------------------------------
echo "[DEPLOY] Restarting bluetooth..."
sudo -n systemctl restart bluetooth
sleep 5
bluetoothctl power on
sleep 2
echo "[DEPLOY] BT adapter ready"

# -- Start app -----------------------------------------------------------------
log "Starting $APP_NAME..."
arduino-app-cli app start user:$APP_LAB_ID

log "Waiting for app to be ready..."
sleep 20

# -- Show logs -----------------------------------------------------------------
echo ""
log "Recent logs:"
echo "----------------------------------------"
arduino-app-cli app logs user:$APP_LAB_ID 2>/dev/null | tail -20
echo "----------------------------------------"
echo ""

# -- Check status --------------------------------------------------------------
STATUS=$(arduino-app-cli app list 2>/dev/null | grep "user:$APP_LAB_ID" | awk '{print $3}')
if echo "$STATUS" | grep -q "running\|started"; then
    echo -e "${GREEN}[OK] App is running${NC}"
    echo ""
    echo "  WebUI: http://$(hostname -I | awk '{print $1}'):7000"
else
    warn "App may not be running (status: $STATUS)"
    warn "Check logs above for errors."
fi

echo ""

# -- Optional: follow logs -----------------------------------------------------
if [ "$1" = "--logs" ]; then
    log "Following logs (Ctrl+C to stop)..."
    arduino-app-cli app logs user:$APP_LAB_ID 2>/dev/null --follow
fi
