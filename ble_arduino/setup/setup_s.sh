#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
SERVICE_NAME="dbus-bridge-${PROJECT_NAME}"

echo "=================================================="
echo " BLE GATT Dashboard - Setup Script"
echo "=================================================="
echo "Project directory: $PROJECT_DIR"
echo "Project name: $PROJECT_NAME"
echo "Service name: $SERVICE_NAME"
echo ""

# Step 1 - Install socat (only thing needed from system)
echo "[1/2] Installing socat..."
sudo apt update -qq
sudo apt install -y socat
echo "✓ socat installed"

# Step 2 - Create dbus-bridge systemd service
echo "[2/2] Setting up ${SERVICE_NAME} systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for ${PROJECT_NAME}
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
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl start ${SERVICE_NAME}.service
echo "✓ ${SERVICE_NAME} service created and started"

# Verify
sleep 2
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo "✓ ${SERVICE_NAME} service is running"
    ls -la "$PROJECT_DIR/dbus.sock" && echo "✓ dbus.sock created" || echo "✗ dbus.sock not found"
else
    echo "✗ ${SERVICE_NAME} service failed"
    sudo systemctl status ${SERVICE_NAME}.service
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

# to check if the service is running: sudo systemctl status dbus-bridge-<your-project>.service
# to start the service: sudo systemctl start dbus-bridge-<your-project>.service
# before export run: sudo systemctl stop dbus-bridge-<your-project>.service and delete dbus.sock