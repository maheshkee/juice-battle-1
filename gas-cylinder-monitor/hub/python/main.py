import os
import sys
import ctypes

os.environ["GI_TYPELIB_PATH"] = "/app/typelibs"
os.environ["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/app/dbus.sock"

for lib in [
    "libm.so.6", "libcap.so.2", "libpcre2-8.so.0",
    "libselinux.so.1", "libaudit.so.1", "libcap-ng.so.0",
    "libexpat.so.1", "libdbus-1.so.3", "libapparmor.so.1",
    "libsystemd.so.0", "libgirepository-2.0.so.0",
]:
    try:
        ctypes.CDLL(f"/app/wheels/{lib}")
    except Exception as e:
        print(f"[MAIN] lib load failed {lib}: {e}", flush=True)

sys.path.insert(0, "/usr/lib/python3/dist-packages")

from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI
import threading
import json
from datetime import datetime
from ble_subscriber import BLESubscriber

ui = WebUI()

def on_weight(grams, quality, sigma, hub_ts):
    ui.send_message('weight_update', {
        'grams':   round(grams, 1),
        'quality': quality,
        'sigma':   round(sigma, 2),
        'ts':      hub_ts
    })
    print(f"[MAIN] weight_update sent: grams={grams:.1f} quality={quality}", flush=True)

def on_ui_connect(sid):
    ui.send_message('weight_update', {
        'grams':   0,
        'quality': 'WAITING',
        'sigma':   0.0,
        'ts':      '--'
    })

ui.on_connect(on_ui_connect)

ble = BLESubscriber(on_weight=on_weight)
threading.Thread(target=ble.start, daemon=True).start()

print("[MAIN] Gas cylinder monitor hub started", flush=True)
App.run()
