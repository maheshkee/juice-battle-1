#!/usr/bin/env bash
# setup_for_bt_audio.sh
# Complete Bluetooth audio setup for Arduino UNO Q - youtube-display project.
# Run this ONCE on the board.
#
# What it does:
#   1. Installs bt-autoconnect.py to /usr/local/bin/
#   2. Creates systemd user service to run it at boot
#   3. Creates WirePlumber rule - BT preferred over HDMI
#   4. Enables the service
#
# Usage (from project root):
#   chmod +x ~/ArduinoApps/youtube-display/setup_for_bt_audio.sh
#   bash ~/ArduinoApps/youtube-display/setup_for_bt_audio.sh

set -e

# Script lives at project root - so PROJECT_DIR is just dirname of this script
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

echo ""
echo "================================================"
echo "  BT Audio Setup"
echo "  Project : $PROJECT_NAME"
echo "  Path    : $PROJECT_DIR"
echo "================================================"
echo ""

# --- 1. Install bt-autoconnect.py ---
echo ">> Installing bt-autoconnect.py..."

if [ ! -f "$PROJECT_DIR/bt-autoconnect.py" ]; then
    echo "  ERROR: bt-autoconnect.py not found at $PROJECT_DIR/bt-autoconnect.py"
    echo "  Make sure bt-autoconnect.py is in the project root first."
    exit 1
fi

sudo cp "$PROJECT_DIR/bt-autoconnect.py" /usr/local/bin/bt-autoconnect.py
sudo chmod +x /usr/local/bin/bt-autoconnect.py
echo "  [OK] /usr/local/bin/bt-autoconnect.py installed"

# --- 2. Create systemd USER service ---
# Must run as arduino user to access PipeWire user session
echo ""
echo ">> Creating bt-autoconnect systemd user service..."

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
echo "  [OK] bt-autoconnect.service installed and enabled"

# --- 3. Create WirePlumber BT priority rule ---
echo ""
echo ">> Creating WirePlumber BT A2DP rule..."

sudo mkdir -p /etc/pipewire/wireplumber.conf.d

sudo tee /etc/pipewire/wireplumber.conf.d/51-bt-autoconnect.conf > /dev/null << 'WPEOF'
# Auto-connect BT devices using A2DP (high quality stereo audio)
# Applies to ALL Bluetooth audio devices - no device-specific config needed
# A2DP = high quality music streaming (vs HFP/HSP = low quality headset mode)
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

echo "  [OK] WirePlumber A2DP rule created"

# --- 4. Restart WirePlumber ---
echo ""
echo ">> Restarting WirePlumber..."

systemctl --user restart wireplumber
sleep 2

if systemctl --user is-active --quiet wireplumber; then
    echo "  [OK] WirePlumber restarted"
else
    echo "  WARNING: WirePlumber not running - check:"
    echo "    systemctl --user status wireplumber"
fi

# --- 5. Run auto-connect right now (no reboot needed) ---
echo ""
echo ">> Running bt-autoconnect now..."

python3 /usr/local/bin/bt-autoconnect.py

echo ""
echo "================================================"
echo "  BT Audio Setup Complete!"
echo "================================================"
echo ""
echo "  To pair a NEW Bluetooth speaker (one time only):"
echo ""
echo "    bluetoothctl"
echo "    scan on"
echo "    -- wait for your speaker name to appear --"
echo "    scan off"
echo "    pair <MAC>"
echo "    trust <MAC>"
echo "    connect <MAC>"
echo "    exit"
echo ""
echo "  After pairing once, speaker auto-connects on every reboot."
echo ""
echo "  Useful commands:"
echo "    wpctl status"
echo "    bluetoothctl devices Trusted"
echo "    systemctl --user status bt-autoconnect.service"
echo "    journalctl --user -u bt-autoconnect.service"
echo ""
