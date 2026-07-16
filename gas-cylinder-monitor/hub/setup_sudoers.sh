#!/bin/bash
# Gas Cylinder Monitor - One-time device setup script
#
# Run ONCE on first setup with sudo:
#     sudo bash hub/setup_sudoers.sh
#
# After this runs, all future deploys and re-runs of this script
# work without password prompts:
#     bash hub/deploy.sh    (every deploy, no password ever)

SUDOERS_FILE="/etc/sudoers.d/gas-cylinder-monitor"

echo "Setting up passwordless sudo for gas-cylinder-monitor deploy commands..."
sudo tee "$SUDOERS_FILE" > /dev/null << 'EOF'
# gas-cylinder-monitor deploy - passwordless sudo for BT management only
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/bluetoothctl
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dbus-bridge-gas-cylinder-monitor.service
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop dbus-bridge-gas-cylinder-monitor.service
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl start dbus-bridge-gas-cylinder-monitor.service
arduino ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/sudoers.d/gas-cylinder-monitor
arduino ALL=(ALL) NOPASSWD: /usr/sbin/visudo
arduino ALL=(ALL) NOPASSWD: /bin/chmod 440 /etc/sudoers.d/gas-cylinder-monitor
# HUB-WATCHDOG Level 3 - container writes /tmp/reboot_requested, host watchdog calls reboot
arduino ALL=(ALL) NOPASSWD: /sbin/reboot
EOF

sudo chmod 440 "$SUDOERS_FILE"
sudo visudo -c -f "$SUDOERS_FILE" && echo "Sudoers rule installed OK" || (echo "ERROR - sudoers syntax failed, removing" && sudo rm "$SUDOERS_FILE")
echo "Done. deploy.sh will no longer prompt for password on BT commands."
