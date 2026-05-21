#!/usr/bin/env bash
# ble-display - Board setup script
#
# Run this ONCE on the board after importing the project in App Lab.
#
# What it does:
#   1. Verifies wheels + typelibs are present (imported with project)
#   2. Installs dbus-bridge systemd service
#   3. Installs chromium-launcher systemd service
#   4. Disables unwanted autostart entries (App Lab browser, blueman)
#   5. Configures lightdm autologin
#   6. Verifies dependencies
#
# Usage:
#   dos2unix setup/setup.sh        (only needed if script came from Windows)
#   chmod +x setup/setup.sh
#   bash setup/setup.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
DBUS_SERVICE="dbus-bridge-${PROJECT_NAME}.service"
LAUNCHER_SERVICE="chromium-launcher-${PROJECT_NAME}.service"

echo ""
echo "================================================"
echo "  ble-display - Setup"
echo "  Project : $PROJECT_NAME"
echo "  Path    : $PROJECT_DIR"
echo "================================================"
echo ""

# --- 1. Verify wheels and typelibs ---
echo ">> Checking wheels and typelibs..."

if [ ! -d "$PROJECT_DIR/wheels" ]; then
    echo ""
    echo "  ERROR: wheels/ not found at $PROJECT_DIR/wheels"
    echo "  Make sure wheels/ and typelibs/ are included in the project zip"
    echo "  before importing into App Lab."
    echo ""
    exit 1
fi

if [ ! -d "$PROJECT_DIR/typelibs" ]; then
    echo ""
    echo "  ERROR: typelibs/ not found at $PROJECT_DIR/typelibs"
    echo "  Make sure typelibs/ is included in the project zip"
    echo "  before importing into App Lab."
    echo ""
    exit 1
fi

echo "  [OK] wheels/  found"
echo "  [OK] typelibs/ found"

# --- 2. Install dbus-bridge service ---
echo ""
echo ">> Installing $DBUS_SERVICE..."

sudo tee /etc/systemd/system/${DBUS_SERVICE} > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for App Lab (${PROJECT_NAME})
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
sudo systemctl enable "$DBUS_SERVICE"
sudo systemctl restart "$DBUS_SERVICE"
sleep 2

if [ -S "$PROJECT_DIR/dbus.sock" ]; then
    echo "  [OK] dbus.sock created"
else
    echo "  WARNING: dbus.sock not found - check: sudo systemctl status $DBUS_SERVICE"
fi

# --- 3. Install chromium-launcher service ---
echo ""
echo ">> Installing $LAUNCHER_SERVICE..."

sudo tee /etc/systemd/system/${LAUNCHER_SERVICE} > /dev/null << SVCEOF
[Unit]
Description=Chromium Launcher for ${PROJECT_NAME}
After=graphical.target lightdm.service
Wants=graphical.target

[Service]
User=arduino
Environment=DISPLAY=:0
Environment=XAUTHORITY=/var/run/lightdm/root/:0
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=PIPEWIRE_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/bin/python3 ${PROJECT_DIR}/setup/chromium-launcher.py
ExecStopPost=/bin/rm -f ${PROJECT_DIR}/launcher.sock
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable "$LAUNCHER_SERVICE"
sudo systemctl restart "$LAUNCHER_SERVICE"
echo "  [OK] $LAUNCHER_SERVICE installed"

# --- 4. Disable unwanted autostart entries ---
echo ""
echo ">> Configuring autostart..."

mkdir -p "$HOME/.config/autostart"

# Disable App Lab browser window
cat > "$HOME/.config/autostart/ArduinoAppLab.desktop" << EOF
[Desktop Entry]
Name=Arduino App Lab
Exec=/usr/bin/app-lab
Type=Application
Hidden=true
EOF
echo "  [OK] App Lab browser window disabled"

# Disable blueman tray
cat > "$HOME/.config/autostart/blueman.desktop" << EOF
[Desktop Entry]
Name=Blueman Applet
Exec=blueman-applet
Type=Application
Hidden=true
OnlyShowIn=
EOF
pkill blueman-applet 2>/dev/null || true
pkill blueman-tray   2>/dev/null || true
echo "  [OK] Blueman notifications disabled"

# --- 5. Configure lightdm autologin ---
echo ""
echo ">> Configuring autologin..."

LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if grep -q "autologin-user=arduino" "$LIGHTDM_CONF" 2>/dev/null; then
    echo "  [OK] Autologin already configured"
else
    sudo sed -i '/\[Seat:\*\]/a autologin-user=arduino\nautologin-user-timeout=0' "$LIGHTDM_CONF" 2>/dev/null || \
    echo "  WARNING: Could not configure autologin - edit $LIGHTDM_CONF manually"
    echo "  [OK] Autologin configured"
fi

# --- 6. Check dependencies ---
echo ""
echo ">> Checking dependencies..."

command -v chromium  &>/dev/null && echo "  [OK] chromium"  || echo "  WARNING: chromium not found  - sudo apt install chromium"
command -v socat     &>/dev/null && echo "  [OK] socat"     || echo "  WARNING: socat not found     - sudo apt install socat"
command -v dos2unix  &>/dev/null && echo "  [OK] dos2unix"  || echo "  INFO:    dos2unix not found  - sudo apt install dos2unix (needed if scripts came from Windows)"
command -v nmcli     &>/dev/null && echo "  [OK] nmcli"     || echo "  WARNING: nmcli not found     - required for WiFi management"
command -v bluetoothctl &>/dev/null && echo "  [OK] bluetoothctl" || echo "  WARNING: bluetoothctl not found"

# --- Done ---
echo ""
echo "================================================"
echo "  Setup complete!"
echo "================================================"
echo ""
echo "  Next steps:"
echo "  1. Enable Run at startup in App Lab"
echo "  2. IMPORTANT - app.yaml must have network_mode: host"
echo "     Edit inside the zip BEFORE importing into App Lab."
echo "     App Lab resets app.yaml on import and locks it afterward."
echo "  3. Reboot the board"
echo "  4. Open dashboard at http://<board-ip>:7000"
echo ""
echo "  Optional - BT audio auto-connect on boot:"
echo "    Run setup/setup_for_bt_audio.sh after pairing a speaker"
echo ""
echo "  If scripts came from Windows, run first:"
echo "    dos2unix setup/setup.sh"
echo "    dos2unix setup/chromium-launcher.sh"
echo ""
echo "  Service status commands:"
echo "    sudo systemctl status $DBUS_SERVICE"
echo "    sudo systemctl status $LAUNCHER_SERVICE"
echo ""
