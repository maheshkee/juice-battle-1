#!/bin/bash
# =============================================================================
# hx711-001-freeze-test — Deploy script
# Usage: bash deploy.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="hx711-001-freeze-test"

GREEN='\033[0;32m'
AMBER='\033[0;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }

echo ""
echo "========================================================"
echo "  $APP_NAME — Deploy"
echo "========================================================"
echo ""

log "Stopping $APP_NAME..."
arduino-app-cli app stop user:$APP_NAME 2>/dev/null || true
sleep 2

log "Clearing cache..."
rm -rf "$SCRIPT_DIR/.cache"

log "Starting $APP_NAME..."
arduino-app-cli app start user:$APP_NAME

log "Waiting for app to be ready..."
sleep 20

echo ""
log "Recent logs:"
echo "----------------------------------------"
arduino-app-cli app logs user:$APP_NAME 2>/dev/null | tail -20
echo "----------------------------------------"
echo ""

STATUS=$(arduino-app-cli app list 2>/dev/null | grep "user:$APP_NAME" | awk '{print $3}')
if echo "$STATUS" | grep -q "running\|started"; then
    echo -e "${GREEN}[OK] App is running${NC}"
else
    warn "App may not be running (status: $STATUS)"
    warn "Check logs above for errors."
fi

echo ""
