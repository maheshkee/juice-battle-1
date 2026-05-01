#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="$(basename "$SCRIPT_DIR")"
echo "========================================"
echo "  $APP_NAME — Deploy"
echo "========================================"
echo "[DEPLOY] Stopping $APP_NAME..."
arduino-app-cli app stop "user:$APP_NAME" 2>/dev/null || true
sleep 2
echo "[DEPLOY] Starting $APP_NAME..."
arduino-app-cli app start "user:$APP_NAME"
echo "[DEPLOY] Done."
