#!/bin/bash
set -e

# ==================================================
#  AUTO-DETECT PROJECT DIRECTORY
# ==================================================
detect_project_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 1. Use CLI argument if provided
    if [ -n "$1" ]; then
        echo "$1"
        return
    fi

    # 2. Use the directory where this script lives
    echo "$script_dir"
}

PROJECT_DIR=$(detect_project_dir "$1")

# ==================================================
#  CONFIGURATION - Edit these if needed
# ==================================================
APP_NAME="BLE GATT Dashboard"
SERVICE_NAME="dbus-bridge"
SERVICE_USER="${SUDO_USER:-$(whoami)}"
SOCK_FILE="$PROJECT_DIR/dbus.sock"
SYSTEM_BUS_SOCKET="/run/dbus/system_bus_socket"
PORT=7000

# ==================================================
#  VALIDATION
# ==================================================
echo "=================================================="
echo " $APP_NAME - Setup Script"
echo "=================================================="
echo "Project directory : $PROJECT_DIR"
echo "Service user      : $SERVICE_USER"
echo "Service name      : $SERVICE_NAME"
echo "Socket file       : $SOCK_FILE"
echo "Dashboard port    : $PORT"
echo ""

# Ensure project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "[!] Project directory not found: $PROJECT_DIR"
    echo "    Create it first or pass the correct path as an argument:"
    echo "    $0 /path/to/your/project"
    exit 1
fi

# Ensure system D-Bus socket exists
if [ ! -S "$SYSTEM_BUS_SOCKET" ]; then
    echo "[!] System D-Bus socket not found at $SYSTEM_BUS_SOCKET"
    echo "    Is D-Bus running? Try: sudo systemctl start dbus"
    exit 1
fi

# ==================================================
#  STEP 1 - Install socat
# ==================================================
echo "[1/2] Installing socat..."
sudo apt update -qq
sudo apt install -y socat
echo "✔ socat installed"

# ==================================================
#  STEP 2 - Create systemd service
# ==================================================
echo "[2/2] Setting up $SERVICE_NAME systemd service..."

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for $APP_NAME
After=network.target

[Service]
User=$SERVICE_USER
ExecStartPre=/bin/rm -f $SOCK_FILE
ExecStart=/usr/bin/socat \
    UNIX-LISTEN:$SOCK_FILE,fork,reuseaddr,mode=0777,unlink-early \
    UNIX-CONNECT:$SYSTEM_BUS_SOCKET
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl start ${SERVICE_NAME}.service
echo "✔ $SERVICE_NAME service created and started"

# ==================================================
#  VERIFICATION
# ==================================================
sleep 2

if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo "✔ $SERVICE_NAME service is running"
    ls -la "$SOCK_FILE" && echo "✔ $(basename $SOCK_FILE) created" \
                        || echo "? $(basename $SOCK_FILE) not found"
else
    echo "✘ $SERVICE_NAME service failed to start"
    sudo systemctl status ${SERVICE_NAME}.service
    exit 1
fi

# Clear venv cache if present
CACHE_DIR="$PROJECT_DIR/.cache"
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "✔ Cache cleared: $CACHE_DIR"
fi

# ==================================================
#  DONE
# ==================================================
HOST_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=================================================="
echo " Setup Complete!"
echo "=================================================="
echo "1. Open App Lab"
echo "2. Click Run"
echo "3. Open http://$HOST_IP:$PORT"
echo ""
echo "--- Useful commands ---"
echo "chmod +x $0                                       # make executable"
echo "sudo systemctl status  ${SERVICE_NAME}.service    # check status"
echo "sudo systemctl start   ${SERVICE_NAME}.service    # start service"
echo "sudo systemctl stop    ${SERVICE_NAME}.service    # stop service"
echo "rm -f $SOCK_FILE                                  # delete socket manually"
