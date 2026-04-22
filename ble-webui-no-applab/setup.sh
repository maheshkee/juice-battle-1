#!/bin/bash
# setup.sh - One-time prerequisites setup for BLE WebUI No AppLab
# Run once on a fresh board before using run.py

PASS=0
FAIL=0

ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
step() { echo ""; echo "--- $1"; }

echo "============================================"
echo "  BLE WebUI No AppLab - Prerequisites Setup"
echo "============================================"

# 1. Python dependencies
step "Installing Python dependencies"
pip install msgpack --break-system-packages -q && ok "msgpack installed" || fail "msgpack install failed"
pip install flask  --break-system-packages -q && ok "flask installed"   || fail "flask install failed"

# 2. Verify Python imports
step "Verifying Python imports"
python3 -c "import msgpack; print('  [OK]   msgpack', msgpack.__version__)"    || fail "msgpack import failed"
python3 -c "import flask;   print('  [OK]   flask',   flask.__version__)"      || fail "flask import failed"
python3 -c "import dbus;    print('  [OK]   dbus ok')"                         || fail "dbus import failed"
python3 -c "from gi.repository import GLib; print('  [OK]   GLib ok')"        || fail "GLib import failed"

# 3. System services
step "Checking system services"
systemctl is-active --quiet arduino-router && ok "arduino-router running" || fail "arduino-router NOT running - run: sudo systemctl start arduino-router"
systemctl is-active --quiet bluetooth      && ok "bluetooth running"      || fail "bluetooth NOT running - run: sudo systemctl start bluetooth"

# 4. Hardware
step "Checking hardware"
ls /var/run/arduino-router.sock &>/dev/null  && ok "Unix socket exists"   || fail "Socket missing - is arduino-router running?"
sudo fuser /dev/ttyHS1 &>/dev/null           && ok "UART owned by router" || fail "UART not locked - check arduino-router"
hciconfig 2>/dev/null | grep -q "UP RUNNING" && ok "BLE adapter UP"       || fail "BLE adapter not UP - run: sudo hciconfig hci0 up"

# 5. arduino-cli
step "Checking arduino-cli"
arduino-cli version &>/dev/null && ok "arduino-cli available" || fail "arduino-cli not found"
arduino-cli board list 2>/dev/null | grep -q "network" && ok "Board detected on network" || fail "Board not detected - check WiFi and arduino-router"

# Summary
echo ""
echo "============================================"
echo "  Setup complete"
echo "  Passed : $PASS"
echo "  Failed : $FAIL"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
    echo "  Fix the failed checks above before running run.py"
    exit 1
else
    echo "  All checks passed. Run: python3 run.py"
fi
