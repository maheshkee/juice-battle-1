#!/bin/bash
# Gas cylinder monitor — host watchdog
# Watches for trigger files written by the Docker container and acts on them.
# Runs as a systemd service under User=arduino.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
RESTART_TRIGGER="$DATA_DIR/restart.trigger"
REBOOT_TRIGGER="$DATA_DIR/reboot.trigger"

logger -t gas-cylinder-watchdog "Started. DATA_DIR=$DATA_DIR"

while true; do
    if [ -f "$RESTART_TRIGGER" ]; then
        logger -t gas-cylinder-watchdog "restart.trigger found — restarting bluetooth"
        sudo /usr/bin/systemctl restart bluetooth
        sleep 10
        rm -f "$RESTART_TRIGGER"
        logger -t gas-cylinder-watchdog "bluetooth restarted, trigger cleared"
    fi

    if [ -f "$REBOOT_TRIGGER" ]; then
        logger -t gas-cylinder-watchdog "reboot.trigger found — initiating reboot"
        rm -f "$REBOOT_TRIGGER"
        sudo /sbin/reboot
    fi

    sleep 30
done
