import time
from datetime import datetime
from arduino.app_bricks.web_ui import WebUI
from arduino.app_utils import App, Bridge

ui = WebUI()
previous_weight = 0.0
last_event_time = None

def on_weight_event(data):
    global previous_weight, last_event_time
    current_weight = float(data)
    delta = current_weight - previous_weight
    previous_weight = current_weight
    timestamp = datetime.now().strftime("%H:%M:%S")

    now = time.time()
    if last_event_time is not None:
        elapsed_str = f"{now - last_event_time:.1f}s since last event"
    else:
        elapsed_str = "first event"
    last_event_time = now

    print(f"[EVENT] {timestamp} weight={current_weight:.1f}g delta={delta:+.1f}g {elapsed_str}", flush=True)
    ui.send_message("weight_event", {
        "weight_g": current_weight,
        "delta_g": delta,
        "timestamp": timestamp,
        "elapsed": elapsed_str
    })

def on_log(data):
    print(str(data), flush=True)

Bridge.provide("weight_event", on_weight_event)
Bridge.provide("log", on_log)

App.run()
