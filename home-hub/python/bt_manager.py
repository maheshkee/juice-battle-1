# bt_manager.py — stub only. BT management is not implemented.
# Provides the interface expected by ble_gatt_serve.py.

_bus          = None
_evt_char_ref = None


def set_bus(bus):
    global _bus
    _bus = bus
    print("[BT_MANAGER] stub: set_bus called", flush=True)


def set_evt_char(evt_char):
    global _evt_char_ref
    _evt_char_ref = evt_char
    print("[BT_MANAGER] stub: set_evt_char called", flush=True)


def bt_list_trusted():
    print("[BT_MANAGER] stub: bt_list_trusted — not implemented", flush=True)
    return {"event": "bt_list", "devices": []}


def bt_scan_start(callback):
    print("[BT_MANAGER] stub: bt_scan_start — not implemented", flush=True)
    return {"event": "bt_scan_started"}


def bt_scan_stop():
    print("[BT_MANAGER] stub: bt_scan_stop — not implemented", flush=True)
    return {"event": "bt_scan_stopped"}


def bt_pair(mac):
    print(f"[BT_MANAGER] stub: bt_pair({mac}) — not implemented", flush=True)


def bt_connect(mac):
    print(f"[BT_MANAGER] stub: bt_connect({mac}) — not implemented", flush=True)


def bt_disconnect(mac):
    print(f"[BT_MANAGER] stub: bt_disconnect({mac}) — not implemented", flush=True)


def bt_forget(mac):
    print(f"[BT_MANAGER] stub: bt_forget({mac}) — not implemented", flush=True)


def get_all_devices():
    print("[BT_MANAGER] stub: get_all_devices — not implemented", flush=True)
    return {}
