# main.py — entry point only
# Imports all modules and wires them together

from arduino.app_utils import App
import web_handler
import motion
from ble_manager import BLEManager

print("[MAIN] Starting motion-sensor-webui-ble", flush=True)

# Start BLE (blocks up to 10s waiting for registration)
ble = BLEManager()

# Setup web UI
ui = web_handler.setup()

def on_motion_change(state: bool):
    """Called by motion.py when PIR fires."""
    web_handler.broadcast_motion(state)
    ble.update(state)

# Wire motion sensor to web + BLE
motion.setup(on_motion_change)

print("[MAIN] All systems ready", flush=True)
App.run()
