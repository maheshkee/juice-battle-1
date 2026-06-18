#!/bin/bash
# Run once on AQ3 to allow deploy.sh to run without password prompts.
# Grants passwordless sudo ONLY for specific bluetooth commands — not blanket.

SUDOERS_FILE="/etc/sudoers.d/gas-cylinder-monitor"

echo "Setting up passwordless sudo for gas-cylinder-monitor deploy commands..."
sudo tee "$SUDOERS_FILE" > /dev/null << 'EOF'
# gas-cylinder-monitor deploy - passwordless sudo for BT management only
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bluetooth
arduino ALL=(ALL) NOPASSWD: /usr/bin/bluetoothctl
EOF

sudo chmod 440 "$SUDOERS_FILE"
sudo visudo -c -f "$SUDOERS_FILE" && echo "Sudoers rule installed OK" || (echo "ERROR - sudoers syntax failed, removing" && sudo rm "$SUDOERS_FILE")
echo "Done. deploy.sh will no longer prompt for password on BT commands."
