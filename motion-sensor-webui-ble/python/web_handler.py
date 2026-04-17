# web_handler.py — WebUI server and socket event handlers
from arduino.app_bricks.web_ui import WebUI
import motion

ui = WebUI()

def _on_client_connect(sid):
    """Send current state to newly connected browser."""
    ui.send_message("motion_update", motion.get_state(), sid)

def broadcast_motion(state: bool):
    """Called by main.py when motion changes."""
    ui.send_message("motion_update", motion.get_state())

def setup():
    ui.on_connect(_on_client_connect)
    print("[WEB] WebUI handler ready", flush=True)
    return ui
