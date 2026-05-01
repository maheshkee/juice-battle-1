#!/bin/bash
# =============================================================================
# youtube-display -- One-time setup script
# Run this ONCE on a fresh Arduino UNO Q board after cloning the repo.
# Usage: bash setup.sh
# =============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="$(basename "$PROJECT_DIR")"
SERVICE_NAME="dbus-bridge-${APP_NAME}.service"
WHEELS_DIR="$PROJECT_DIR/wheels"
TYPELIBS_DIR="$PROJECT_DIR/typelibs"
LAUNCHER="$PROJECT_DIR/launcher.sh"

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

echo ""
echo "========================================================"
echo "  youtube-display -- Board Setup"
echo "  Arduino UNO Q"
echo "  Project : $APP_NAME"
echo "  Path    : $PROJECT_DIR"
echo "========================================================"
echo ""

# -- 1. Verify board ----------------------------------------------------------
log "Checking board..."
if [ ! -f /etc/arduino-release ] && ! uname -r | grep -q "g0dd6551"; then
    warn "This doesn't look like an Arduino UNO Q board. Proceeding anyway..."
fi

# -- 2. Install system packages -----------------------------------------------
log "Installing system packages..."
sudo apt update -qq
sudo apt install -y \
    socat \
    unclutter \
    libcairo2-dev \
    libgirepository-2.0-dev \
    curl \
    xdotool \
    x11-utils \
    bluetooth \
    bluez \
    pipewire \
    pipewire-pulse \
    wireplumber \
    libspa-0.2-bluetooth \
    2>/dev/null
log "System packages installed."

# -- 3. Build Python wheels (if not already present) --------------------------
log "Checking Python wheels..."
mkdir -p "$WHEELS_DIR"

if ls "$WHEELS_DIR"/dbus_python*.whl > /dev/null 2>&1; then
    log "Wheels already present -- skipping build."
else
    log "Building dbus-python wheel..."
    pip3 wheel dbus-python --wheel-dir "$WHEELS_DIR" --quiet
    pip3 wheel PyGObject --wheel-dir "$WHEELS_DIR" --quiet
    log "Wheels built."
fi

# -- 4. Copy required shared libraries ----------------------------------------
log "Copying shared libraries..."
for lib in \
    /lib/aarch64-linux-gnu/libdbus-1.so.3 \
    /lib/aarch64-linux-gnu/libapparmor.so.1 \
    /lib/aarch64-linux-gnu/libexpat.so.1 \
    /lib/aarch64-linux-gnu/libsystemd.so.0 \
    /lib/aarch64-linux-gnu/libm.so.6 \
    /lib/aarch64-linux-gnu/libcap.so.2 \
    /lib/aarch64-linux-gnu/libpcre2-8.so.0 \
    /lib/aarch64-linux-gnu/libselinux.so.1 \
    /lib/aarch64-linux-gnu/libaudit.so.1 \
    /lib/aarch64-linux-gnu/libcap-ng.so.0 \
    /usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0; do
    if [ -f "$lib" ]; then
        cp "$lib" "$WHEELS_DIR/"
    else
        warn "Library not found: $lib"
    fi
done
log "Shared libraries copied."

# -- 5. Copy GObject typelibs -------------------------------------------------
log "Copying typelibs..."
mkdir -p "$TYPELIBS_DIR"
for typelib in \
    GLib-2.0.typelib \
    GLibUnix-2.0.typelib \
    Gio-2.0.typelib \
    GObject-2.0.typelib \
    DBus-1.0.typelib; do
    SRC="/usr/lib/aarch64-linux-gnu/girepository-1.0/$typelib"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$TYPELIBS_DIR/"
    else
        warn "Typelib not found: $typelib"
    fi
done
log "Typelibs copied."

# -- 6. Create dbus-bridge systemd service ------------------------------------
log "Creating $SERVICE_NAME..."
sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null << SVCEOF
[Unit]
Description=DBus Unix Bridge for $APP_NAME App Lab
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f $PROJECT_DIR/dbus.sock
ExecStart=/usr/bin/socat UNIX-LISTEN:$PROJECT_DIR/dbus.sock,fork,reuseaddr,mode=0777,unlink-early UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"
log "$SERVICE_NAME created and started."

# -- 7. Configure LightDM auto-login ------------------------------------------
log "Configuring LightDM auto-login..."
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if ! grep -q "autologin-user=arduino" "$LIGHTDM_CONF"; then
    sudo sed -i '/^\[Seat:\*\]/a autologin-user=arduino\nautologin-user-timeout=0\ngreeter-session=lightdm-gtk-greeter' "$LIGHTDM_CONF"
    log "LightDM auto-login configured."
else
    log "LightDM auto-login already configured."
fi

# -- 8. Disable Arduino App Lab GUI autostart ---------------------------------
log "Disabling App Lab GUI autostart..."
mkdir -p "$HOME/.config/autostart"
if [ -f /etc/xdg/autostart/ArduinoAppLab.desktop ]; then
    cp /etc/xdg/autostart/ArduinoAppLab.desktop "$HOME/.config/autostart/ArduinoAppLab.desktop"
    echo "Hidden=true" >> "$HOME/.config/autostart/ArduinoAppLab.desktop"
    log "App Lab GUI autostart disabled."
else
    log "App Lab autostart file not found -- skipping."
fi

# -- 9. Create XFCE autostart entry for launcher ------------------------------
log "Creating XFCE autostart entry..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/youtube-display-launcher.desktop" << DESKEOF
[Desktop Entry]
Type=Application
Name=YouTube Display Launcher
Exec=bash $LAUNCHER
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
DESKEOF
log "XFCE autostart entry created."

# -- 10. Set timezone ---------------------------------------------------------
log "Setting timezone to Asia/Kolkata..."
sudo timedatectl set-ntp true
sudo timedatectl set-timezone Asia/Kolkata
log "Timezone set."

# -- 11. Set youtube-display as default app -----------------------------------
log "Setting $APP_NAME as default App Lab app..."
arduino-app-cli properties set default user:$APP_NAME 2>/dev/null || \
    warn "Could not set default app -- set manually after reboot"
log "Default app set."

# -- 12. Install bt-autoconnect service ---------------------------------------
log "Setting up Bluetooth auto-connect service..."
if [ -f "$PROJECT_DIR/bt-autoconnect.py" ]; then
    sudo cp "$PROJECT_DIR/bt-autoconnect.py" /usr/local/bin/bt-autoconnect.py
    sudo chmod +x /usr/local/bin/bt-autoconnect.py
    log "bt-autoconnect.py installed to /usr/local/bin/"
else
    warn "bt-autoconnect.py not found -- skipping BT auto-connect"
fi

mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/bt-autoconnect.service" << 'SVCEOF'
[Unit]
Description=Bluetooth Auto-Connect for trusted audio devices
After=bluetooth.target pipewire.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/bin/bt-autoconnect.py
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=default.target
SVCEOF

systemctl --user daemon-reload
systemctl --user enable bt-autoconnect.service
log "bt-autoconnect.service installed and enabled."

# -- 13. Create WirePlumber BT A2DP rule --------------------------------------
log "Creating WirePlumber A2DP auto-connect rule..."
sudo mkdir -p /etc/pipewire/wireplumber.conf.d
sudo tee /etc/pipewire/wireplumber.conf.d/51-bt-autoconnect.conf > /dev/null << 'WPEOF'
monitor.bluez.rules = [
  {
    matches = [
      {
        device.name = "~bluez_card.*"
      }
    ]
    actions = {
      update-props = {
        bluez5.auto-connect  = [ a2dp_sink ]
        bluez5.hw-volume     = [ a2dp_sink ]
      }
    }
  }
]
WPEOF
log "WirePlumber A2DP rule created."

# -- 14. Set shell aliases ----------------------------------------------------
log "Adding shell aliases..."
if ! grep -q "alias debug-mode" "$HOME/.bashrc"; then
    cat >> "$HOME/.bashrc" << ALIASEOF

# youtube-display developer aliases
alias debug-mode='pkill -f /usr/lib/chromium/chromium && echo Desktop restored'
alias kiosk-mode='bash $LAUNCHER &'
alias yt-logs='arduino-app-cli app logs user:$APP_NAME 2>/dev/null | tail -30'
alias yt-restart='arduino-app-cli app stop user:$APP_NAME && rm -rf $PROJECT_DIR/.cache && arduino-app-cli app start user:$APP_NAME'
alias yt-stop='arduino-app-cli app stop user:$APP_NAME'
alias yt-start='arduino-app-cli app start user:$APP_NAME'
ALIASEOF
    log "Aliases added to .bashrc."
else
    log "Aliases already in .bashrc."
fi

# -- 15. Mark setup complete --------------------------------------------------
touch "$HOME/.youtube-display-setup-done"

echo ""
echo "========================================================"
echo "  Setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Reboot the board:  sudo reboot"
echo "  2. Pair your Bluetooth speaker (one time only):"
echo "     bluetoothctl"
echo "     scan on"
echo "     -- wait for speaker name to appear --"
echo "     scan off"
echo "     pair <MAC>"
echo "     trust <MAC>"
echo "     connect <MAC>"
echo "     exit"
echo ""
echo "  3. Deploy the app:    bash deploy.sh"
echo "  4. Install Flutter app on phone"
echo "  5. Open app, tap SCAN, connect to YT-Display"
echo ""
echo "  Developer commands (via SSH after reboot):"
echo "  debug-mode   -- show desktop"
echo "  kiosk-mode   -- return to splash screen"
echo "  yt-logs      -- view live app logs"
echo "  yt-restart   -- stop, clear cache, restart app"
echo "  bash deploy.sh  -- restart app"
echo "========================================================"
echo ""
