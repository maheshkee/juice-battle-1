from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI
import json

ui = WebUI()

def _on_weight_event(data):
    try:
        reading = json.loads(str(data))
        print(f"[WEIGHT] {reading}", flush=True)
        ui.send_message("weight_update", {
            "weight_g":  round(float(reading.get("weight_g",  0)), 1),
            "weight_kg": round(float(reading.get("weight_kg", 0)), 4),
            "stable":    bool(reading.get("stable",    False)),
            "sensor_ok": bool(reading.get("sensor_ok", False)),
        })
    except Exception as e:
        print(f"[ERROR] weight parse: {e}", flush=True)

def _on_tare(client, data):
    try:
        result = Bridge.call("do_tare")
        ok = (str(result).strip() == "ok")
        ui.send_message("tare_result", {"ok": ok})
    except Exception as e:
        ui.send_message("tare_result", {"ok": False})
        print(f"[ERROR] tare: {e}", flush=True)

def _on_connect(sid):
    pass

Bridge.provide("weight_event", _on_weight_event)
ui.on_connect(_on_connect)
ui.on_message("do_tare", _on_tare)

print("[SCALE] Ready", flush=True)
App.run()
