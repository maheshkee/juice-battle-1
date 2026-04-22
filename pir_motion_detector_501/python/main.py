from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI
from datetime import datetime

motion_active = False
last_event_time = "Never"

def on_motion_event(state: bool):
    global motion_active, last_event_time

    motion_active = state
    last_event_time = datetime.now().strftime("%H:%M:%S")

    ui.send_message("motion_update", {
        "motion": motion_active,
        "time": last_event_time,
        "status": "DETECTED" if motion_active else "CLEAR"
    })

def on_client_connect(sid):
    ui.send_message("motion_update", {
        "motion": motion_active,
        "time": last_event_time,
        "status": "DETECTED" if motion_active else "CLEAR"
    }, sid)

Bridge.provide("motion_event", on_motion_event)

ui = WebUI()
ui.on_connect(on_client_connect)

App.run()