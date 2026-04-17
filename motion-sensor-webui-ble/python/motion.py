# motion.py — PIR sensor state and Bridge registration
import datetime
from arduino.app_utils import Bridge

motion_active   = False
last_event_time = "Never"
_on_change_cb   = None   # callback set by main.py

def get_state():
    return {
        "motion": motion_active,
        "time":   last_event_time,
        "status": "DETECTED" if motion_active else "CLEAR"
    }

def _on_motion_event(state: bool):
    global motion_active, last_event_time
    motion_active   = state
    last_event_time = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"[PIR] State -> {"DETECTED" if state else "CLEAR"}", flush=True)
    if _on_change_cb:
        _on_change_cb(state)

def setup(on_change_callback):
    """Register Bridge handler and store callback."""
    global _on_change_cb
    _on_change_cb = on_change_callback
    Bridge.provide("motion_event", _on_motion_event)
    print("[PIR] Motion handler registered", flush=True)
