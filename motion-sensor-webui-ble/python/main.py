# main.py — entry point, wires all modules
from arduino.app_utils import App
import web_handler
import motion
from ble_manager import BLEManager
from ble_scanner import BLEScanner

print("[MAIN] Starting motion-sensor-webui-ble v1.3", flush=True)

# BLE peripheral — this board advertises to phone
ble = BLEManager()

# Web UI
ui = web_handler.setup()

def on_local_motion(state: bool):
    web_handler.broadcast_motion("Local", state)
    ble.update(state)

def on_remote_motion(name: str, state: bool):
    web_handler.broadcast_motion(name, state)

# BLE central — connects to remote sensors
scanner = BLEScanner(on_remote_motion)

# Local PIR via Bridge
motion.setup(on_local_motion)

print("[MAIN] All systems ready", flush=True)
App.run()
