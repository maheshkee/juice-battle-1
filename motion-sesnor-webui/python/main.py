from arduino.app_utils import *
from arduino.app_bricks.web_ui import WebUI
from datetime import datetime

# Track current state so new browser connections get correct status immediately
motion_active = False
last_event_time = "Never"

def on_motion_event(state: bool):
    """Called by Bridge when MCU fires motion_event."""
    global motion_active, last_event_time

    motion_active = state
    last_event_time = datetime.now().strftime("%H:%M:%S")

    # Push to ALL connected browser clients
    ui.send_message("motion_update", {
        "motion": motion_active,
        "time": last_event_time,
        "status": "DETECTED" if motion_active else "CLEAR"
    })

def on_client_connect(sid):
    """New browser tab opened — send current state immediately."""
    ui.send_message("motion_update", {
        "motion": motion_active,
        "time": last_event_time,
        "status": "DETECTED" if motion_active else "CLEAR"
    }, sid)  # send only to this new client, not broadcast

# Register: Python exposes "motion_event" for the sketch to call
Bridge.provide("motion_event", on_motion_event)

# Initialize WebUI Brick
ui = WebUI()
ui.on_connect(on_client_connect)

App.run()