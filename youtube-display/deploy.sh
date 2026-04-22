#!/bin/bash
# =============================================================================
# youtube-display — Deploy script
# Run this to start, restart, or update the app.
# Usage: bash deploy.sh [--logs]
# =============================================================================

APP_NAME="youtube-display"
GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }

# Check setup has been run
if [ ! -f "$HOME/.youtube-display-setup-done" ]; then
    echo -e "${RED}[ERROR]${NC} Setup not complete. Run: bash setup.sh first."
    exit 1
fi

echo ""
echo "========================================================"
echo "  youtube-display — Deploy"
echo "========================================================"
echo ""

# ── Stop app ──────────────────────────────────────────────────────────────────
log "Stopping $APP_NAME..."
arduino-app-cli app stop user:$APP_NAME 2>/dev/null || true
sleep 2

# ── Clear cache ───────────────────────────────────────────────────────────────
log "Clearing cache..."
rm -rf "$HOME/ArduinoApps/$APP_NAME/.cache"

# ── Ensure dbus-bridge is running ─────────────────────────────────────────────
log "Checking dbus-bridge..."
if ! systemctl is-active --quiet dbus-bridge.service; then
    warn "dbus-bridge not running — starting it..."
    sudo systemctl start dbus-bridge.service
fi

# ── Start app ─────────────────────────────────────────────────────────────────
log "Starting $APP_NAME..."
arduino-app-cli app start user:$APP_NAME

log "Waiting for app to be ready..."
sleep 20

# ── Show logs ─────────────────────────────────────────────────────────────────
echo ""
log "Recent logs:"
echo "────────────────────────────────────────"
arduino-app-cli app logs user:$APP_NAME 2>/dev/null | tail -20
echo "────────────────────────────────────────"
echo ""

# ── Check status ──────────────────────────────────────────────────────────────
STATUS=$(arduino-app-cli app list 2>/dev/null | grep "user:$APP_NAME" | awk '{print $3}')
if echo "$STATUS" | grep -q "running\|started"; then
    echo -e "${GREEN}✓ App is running${NC}"
    echo ""
    echo "  Phone UI:    http://$(hostname -I | awk '{print $1}'):7000"
    echo "  Admin panel: http://$(hostname -I | awk '{print $1}'):7000/admin.html"
else
    warn "App may not be running (status: $STATUS)"
    warn "Check logs above for errors."
fi

echo ""

# ── Optional: follow logs ─────────────────────────────────────────────────────
if [ "$1" = "--logs" ]; then
    log "Following logs (Ctrl+C to stop)..."
    arduino-app-cli app logs user:$APP_NAME 2>/dev/null --follow
fi
