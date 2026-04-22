# web_handler.py — WebUI server and socket events
from arduino.app_bricks.web_ui import WebUI
import motion

ui = WebUI()
remote_states = {}

def _on_client_connect(sid):
    ui.send_message("motion_update", motion.get_state(), sid)
    for name, state in remote_states.items():
        ui.send_message("remote_update", {
            "name": name,
            "motion": state,
            "status": "DETECTED" if state else "CLEAR"
        }, sid)

def broadcast_motion(source: str, state: bool):
    if source == "Local":
        ui.send_message("motion_update", {
            "motion": state,
            "time": motion.last_event_time,
            "status": "DETECTED" if state else "CLEAR"
        })
    else:
        remote_states[source] = state
        ui.send_message("remote_update", {
            "name":   source,
            "motion": state,
            "status": "DETECTED" if state else "CLEAR"
        })
        print(f"[WEB] {source} -> {"DETECTED" if state else "CLEAR"}", flush=True)

def setup():
    ui.on_connect(_on_client_connect)
    print("[WEB] WebUI handler ready", flush=True)
    return ui
