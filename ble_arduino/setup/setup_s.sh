#!/bin/bash
set -e

PROJECT_DIR="$HOME/ArduinoApps/ble_arduino"

echo "=================================================="
echo " BLE GATT Dashboard - Setup Script"
echo "=================================================="
echo "Project directory: $PROJECT_DIR"
echo ""

# Step 1 - Install socat (only thing needed from system)
echo "[1/2] Installing socat..."
sudo apt update -qq
sudo apt install -y socat
echo "✓ socat installed"

# Step 2 - Create dbus-bridge systemd service
echo "[2/2] Setting up dbus-bridge systemd service..."
sudo tee /etc/systemd/system/dbus-bridge.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for App Lab
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
sudo systemctl enable dbus-bridge.service
sudo systemctl start dbus-bridge.service
echo "✓ dbus-bridge service created and started"

# Verify
sleep 2
if systemctl is-active --quiet dbus-bridge.service; then
    echo "✓ dbus-bridge service is running"
    ls -la "$PROJECT_DIR/dbus.sock" && echo "✓ dbus.sock created" || echo "✗ dbus.sock not found"
else
    echo "✗ dbus-bridge service failed"
    sudo systemctl status dbus-bridge.service
    exit 1
fi

# Clean venv cache
rm -rf "$PROJECT_DIR/.cache"
echo "✓ Cache cleared"

echo ""
echo "=================================================="
echo " Setup Complete!"
echo "=================================================="
echo "1. Open App Lab"
echo "2. Click Run"
echo "3. Open http://$(hostname -I | awk '{print $1}'):7000"
echo ""

# make it executable: chmod +x ~/ArduinoApps/ble_arduino/setup_s.sh
# before export run: "sudo systemctl stop dbus-bridge.service"  / delete the dbus.sock
# to check if the service is running: "sudo systemctl status dbus-bridge.service"
# to start the service: "sudo systemctl start dbus-bridge.service"