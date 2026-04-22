#!/bin/bash

PROJECT_DIR="$HOME/ArduinoApps/pir_ble_501"
DBUS_SOCK="$PROJECT_DIR/dbus.sock"
SERVICE_FILE="/etc/systemd/system/dbus-bridge.service"

echo "=== PIR BLE 501 Setup ==="

# Step 1 — Write dbus-bridge service
echo "[1/4] Writing dbus-bridge.service..."
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=DBus Unix Bridge for App Lab
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f $DBUS_SOCK
ExecStart=/usr/bin/socat UNIX-LISTEN:$DBUS_SOCK,fork,reuseaddr,mode=0777,unlink-early UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Step 2 — Reload and restart service
echo "[2/4] Reloading systemd and starting dbus-bridge..."
sudo systemctl daemon-reload
sudo systemctl enable dbus-bridge.service
sudo systemctl restart dbus-bridge.service

# Step 3 — Verify socket
echo "[3/4] Waiting for socket to be created..."
sleep 2
if [ -S "$DBUS_SOCK" ]; then
    echo "      dbus.sock created successfully"
else
    echo "      ERROR: dbus.sock not found — check service status"
    sudo systemctl status dbus-bridge.service
    exit 1
fi

# Step 4 — Verify service
echo "[4/4] Service status:"
sudo systemctl status dbus-bridge.service --no-pager

echo ""
echo "=== Setup complete ==="
echo "dbus.sock: $DBUS_SOCK"
echo "You can now hit Run in App Lab."