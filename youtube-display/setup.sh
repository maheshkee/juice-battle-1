#!/bin/bash
# =============================================================================
# youtube-display — One-time setup script
# Run this ONCE on a fresh Arduino UNO Q board after cloning the repo.
# Usage: bash setup.sh
# =============================================================================

set -e

APP_NAME="youtube-display"
APP_DIR="/home/arduino/ArduinoApps/youtube-display"
WHEELS_DIR="$APP_DIR/wheels"
TYPELIBS_DIR="$APP_DIR/typelibs"
LAUNCHER="$HOME/launcher.sh"

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${AMBER}[WARN]${NC}  $1"; }
fail() { echo -e "${RED}[FAIL]${NC}  $1"; exit 1; }

echo ""
echo "========================================================"
echo "  youtube-display — Board Setup"
echo "  Arduino UNO Q (AQ2)"
echo "========================================================"
echo ""

# ── 1. Verify we are on the right board ──────────────────────────────────────
log "Checking board..."
if [ ! -f /etc/arduino-release ] && ! uname -r | grep -q "g0dd6551"; then
    warn "This doesn't look like an Arduino UNO Q board. Proceeding anyway..."
fi

# ── 2. Install system packages ────────────────────────────────────────────────
log "Installing system packages..."
sudo apt update -qq
sudo apt install -y \
    socat \
    libcairo2-dev \
    libgirepository-2.0-dev \
    curl \
    xdotool \
    x11-utils \
    2>/dev/null
log "System packages installed."

# ── 3. Build Python wheels (if not already present) ───────────────────────────
log "Checking Python wheels..."
mkdir -p "$WHEELS_DIR"

if [ ! -f "$WHEELS_DIR/dbus_python"*.whl ] 2>/dev/null; then
    log "Building dbus-python wheel..."
    pip3 wheel dbus-python --wheel-dir "$WHEELS_DIR" --quiet
    pip3 wheel PyGObject --wheel-dir "$WHEELS_DIR" --quiet
    log "Wheels built."
else
    log "Wheels already present — skipping build."
fi

# ── 4. Copy required shared libraries into wheels/ ────────────────────────────
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

# ── 5. Copy GObject typelibs ──────────────────────────────────────────────────
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

# ── 6. Create dbus-bridge systemd service ─────────────────────────────────────
log "Creating dbus-bridge service..."
sudo tee /etc/systemd/system/dbus-bridge.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for youtube-display App Lab
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
log "dbus-bridge service created and started."

# ── 7. Configure LightDM auto-login ──────────────────────────────────────────
log "Configuring LightDM auto-login..."
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if ! grep -q "autologin-user=arduino" "$LIGHTDM_CONF"; then
    sudo sed -i '/^\[Seat:\*\]/a autologin-user=arduino\nautologin-user-timeout=0\ngreeter-session=lightdm-gtk-greeter' "$LIGHTDM_CONF"
    log "LightDM auto-login configured."
else
    log "LightDM auto-login already configured."
fi

# ── 8. Disable Arduino App Lab GUI autostart ──────────────────────────────────
log "Disabling App Lab GUI autostart..."
mkdir -p "$HOME/.config/autostart"
if [ -f /etc/xdg/autostart/ArduinoAppLab.desktop ]; then
    cp /etc/xdg/autostart/ArduinoAppLab.desktop "$HOME/.config/autostart/ArduinoAppLab.desktop"
    echo "Hidden=true" >> "$HOME/.config/autostart/ArduinoAppLab.desktop"
    log "App Lab GUI autostart disabled."
else
    log "App Lab autostart file not found — skipping."
fi

# ── 9. Create launcher.sh ─────────────────────────────────────────────────────
log "Creating launcher.sh..."
cat > "$LAUNCHER" << 'LAUNCHEREOF'
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/arduino/.Xauthority
CMD_FILE="/home/arduino/ArduinoApps/youtube-display/cmd.txt"

xset s off
xset s noblank
xset -dpms

xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/color-style -s 0 2>/dev/null
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor1/image-show -s false 2>/dev/null
xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior -s 1 2>/dev/null

echo "[LAUNCHER] Waiting for port 7000..."
until curl -s http://localhost:7000 > /dev/null 2>&1; do
    sleep 1
done
echo "[LAUNCHER] Ready."

pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
sleep 0.5
rm -rf /tmp/chrome-splash
/usr/bin/chromium --kiosk \
    --no-sandbox --disable-gpu \
    --noerrdialogs --disable-infobars \
    --user-data-dir=/tmp/chrome-splash \
    "http://localhost:7000/splash.html" &

while true; do
    if [ -f "$CMD_FILE" ]; then
        CMD=$(cat "$CMD_FILE")
        rm -f "$CMD_FILE"
        pkill -f "/usr/lib/chromium/chromium" 2>/dev/null
        sleep 0.3
        if [ "$CMD" = "STOP" ]; then
            rm -rf /tmp/chrome-splash
            /usr/bin/chromium --kiosk \
                --no-sandbox --disable-gpu \
                --noerrdialogs --disable-infobars \
                --user-data-dir=/tmp/chrome-splash \
                "http://localhost:7000/splash.html" &
        else
            rm -rf /tmp/chrome-player
            /usr/bin/chromium --kiosk \
                --no-sandbox --disable-gpu \
                --noerrdialogs --disable-infobars \
                --autoplay-policy=no-user-gesture-required \
                --user-data-dir=/tmp/chrome-player \
                "http://localhost:7000/player.html?v=$CMD" &
        fi
    fi
    sleep 0.5
done
LAUNCHEREOF
chmod +x "$LAUNCHER"
log "launcher.sh created."

# ── 10. Create XFCE autostart entry ──────────────────────────────────────────
log "Creating XFCE autostart entry..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/youtube-display-launcher.desktop" << EOF
[Desktop Entry]
Type=Application
Name=YouTube Display Launcher
Exec=$LAUNCHER
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
log "XFCE autostart entry created."

# ── 11. Set timezone ──────────────────────────────────────────────────────────
log "Setting timezone to Asia/Kolkata..."
sudo timedatectl set-ntp true
sudo timedatectl set-timezone Asia/Kolkata
log "Timezone set."

# ── 12. Set youtube-display as default app ────────────────────────────────────
log "Setting youtube-display as default App Lab app..."
arduino-app-cli properties set default user:youtube-display
log "Default app set."

# ── 13. Set shell aliases ─────────────────────────────────────────────────────
log "Adding shell aliases..."
if ! grep -q "alias debug-mode" "$HOME/.bashrc"; then
    echo "" >> "$HOME/.bashrc"
    echo "# youtube-display developer aliases" >> "$HOME/.bashrc"
    echo "alias debug-mode='pkill -f /usr/lib/chromium/chromium && echo Desktop restored'" >> "$HOME/.bashrc"
    echo "alias kiosk-mode='$LAUNCHER &'" >> "$HOME/.bashrc"
    log "Aliases added to .bashrc."
else
    log "Aliases already in .bashrc."
fi

# ── 14. Mark setup complete ───────────────────────────────────────────────────
touch "$HOME/.youtube-display-setup-done"

echo ""
echo "========================================================"
echo "  Setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Reboot the board:  sudo reboot"
echo "  2. After reboot, run: bash deploy.sh"
echo "  3. Open phone browser: http://$(hostname -I | awk '{print $1}'):7000"
echo ""
echo "  Developer commands (via SSH):"
echo "  debug-mode  — show desktop"
echo "  kiosk-mode  — return to splash screen"
echo "  bash deploy.sh  — restart app"
echo "========================================================"
echo ""
