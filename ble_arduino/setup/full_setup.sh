#!/bin/bash
# Setup script for BLE GATT Dashboard on Arduino UNO Q
# Run this once on a new board after copying the project

set -e

PROJECT_DIR="$HOME/ArduinoApps/ble_arduino"
echo "=================================================="
echo " BLE GATT Dashboard - Setup Script"
echo "=================================================="
echo "Project directory: $PROJECT_DIR"
echo ""

# Step 1 - Install system dependencies
echo "[1/6] Installing system dependencies..."
sudo apt update -qq
sudo apt install -y libcairo2-dev libgirepository-2.0-dev socat
echo "✓ System dependencies installed"

# Step 2 - Build Python wheels
echo "[2/6] Building Python wheels..."
mkdir -p "$PROJECT_DIR/wheels"
pip3 wheel dbus-python --wheel-dir "$PROJECT_DIR/wheels" -q
pip3 wheel PyGObject --wheel-dir "$PROJECT_DIR/wheels" -q
echo "✓ Python wheels built"

# Step 3 - Copy shared libraries
echo "[3/6] Copying shared libraries..."
for lib in \
    /lib/aarch64-linux-gnu/libdbus-1.so.3 \
    /lib/aarch64-linux-gnu/libapparmor.so.1 \
    /lib/aarch64-linux-gnu/libexpat.so.1 \
    /lib/aarch64-linux-gnu/libselinux.so.1 \
    /lib/aarch64-linux-gnu/libaudit.so.1 \
    /lib/aarch64-linux-gnu/libcap-ng.so.0 \
    /lib/aarch64-linux-gnu/libsystemd.so.0 \
    /lib/aarch64-linux-gnu/libpcre2-8.so.0 \
    /lib/aarch64-linux-gnu/libcap.so.2 \
    /lib/aarch64-linux-gnu/libm.so.6 \
    /usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0 \
    /usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0.8400.4
do
    if [ -f "$lib" ]; then
        cp "$lib" "$PROJECT_DIR/wheels/"
        echo "  ✓ $(basename $lib)"
    else
        echo "  ✗ NOT FOUND: $lib"
    fi
done
echo "✓ Shared libraries copied"

# Step 4 - Copy typelibs
echo "[4/6] Copying typelibs..."
mkdir -p "$PROJECT_DIR/typelibs"
for typelib in \
    GLib-2.0.typelib \
    GLibUnix-2.0.typelib \
    Gio-2.0.typelib \
    GObject-2.0.typelib \
    DBus-1.0.typelib
do
    src="/usr/lib/aarch64-linux-gnu/girepository-1.0/$typelib"
    if [ -f "$src" ]; then
        cp "$src" "$PROJECT_DIR/typelibs/"
        echo "  ✓ $typelib"
    else
        echo "  ✗ NOT FOUND: $typelib"
    fi
done
echo "✓ Typelibs copied"

# Step 5 - Create symlink for Python
echo "[5/6] Setting up Python symlink..."
if [ ! -f /usr/local/bin/python ]; then
    sudo ln -s /usr/bin/python3 /usr/local/bin/python
    echo "✓ Python symlink created"
else
    echo "✓ Python symlink already exists"
fi

# Step 6 - Create dbus-bridge systemd service
echo "[6/6] Setting up dbus-bridge systemd service..."
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

# Verify service
sleep 2
if systemctl is-active --quiet dbus-bridge.service; then
    echo "✓ dbus-bridge service is running"
else
    echo "✗ dbus-bridge service failed to start"
    sudo systemctl status dbus-bridge.service
fi

# Clean venv so it rebuilds with new wheels
echo ""
echo "Cleaning venv cache..."
rm -rf "$PROJECT_DIR/.cache"
echo "✓ Cache cleared"

echo ""
echo "=================================================="
echo " Setup Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Open App Lab"
echo "2. Click Run"
echo "3. Open http://$(hostname -I | awk '{print $1}'):7000"
echo ""

# make it executable: chmod +x ~/ArduinoApps/ble_arduino/setup_s.sh
# before export run: sudo systemctl stop dbus-bridge.service