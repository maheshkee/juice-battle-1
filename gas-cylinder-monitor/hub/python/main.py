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
import domain
import log_transfer
from ble_subscriber import BLESubscriber
from db import (db_init, db_insert_reading)
import hub_logger
from hub_watchdog import HubWatchdog

ui = WebUI()

g_node_name        = None
g_node_mac         = None
g_node_connected   = False


def _node_status_payload():
    return {
        'connected': g_node_connected,
        'name':      g_node_name or '',
        'mac':       g_node_mac  or '',
    }


def on_weight(grams, quality, sigma, hub_ts):
    _watchdog.update_last_reading(hub_ts)
    result = domain.process_reading(grams, quality, sigma, hub_ts)
    db_insert_reading(
        hub_ts, grams, quality, sigma,
        gas_pct=result.get('gas_pct'),
        gas_g=result.get('gas_g'),
        alert_level=result.get('alert_level'),
        cylinder_state=result.get('cylinder_state'),
    )
    ui.send_message('weight_update', result)
    print(f"[MAIN] weight_update: grams={grams:.1f} quality={quality} "
          f"state={result['cylinder_state']}", flush=True)


def on_node_connected(name, mac):
    global g_node_name, g_node_mac, g_node_connected
    g_node_name      = name
    g_node_mac       = mac
    g_node_connected = True
    print(f'[MAIN] Node connected: {name} ({mac})', flush=True)
    hub_logger.log_ble('NODE_CONNECTED', name=name, mac=mac)
    ui.send_message('node_status', _node_status_payload())

    cfg        = domain.get_config()
    saved_cal  = cfg.get('cal_factor')
    saved_tare = cfg.get('tare_raw')

    if saved_cal and saved_tare:
        # Hub has saved calibration — tell node to skip fresh tare and use saved cal
        threading.Timer(1.0, lambda: (ble.write_command('SKIP_TARE\n'),
                                      hub_logger.log_ble('CMD_SENT', cmd='SKIP_TARE'))).start()
        threading.Timer(2.0, lambda: (ble.write_command(f"SET_CAL:{saved_cal:.4f}\n"),
                                      hub_logger.log_ble('CMD_SENT', cmd=f'SET_CAL:{saved_cal:.4f}'))).start()
        print(f'[MAIN] sent SKIP_TARE + SET_CAL:{saved_cal:.4f}', flush=True)
    else:
        # No saved calibration — first install, node must do fresh tare
        threading.Timer(1.0, lambda: (ble.write_command('TARE\n'),
                                      hub_logger.log_ble('CMD_SENT', cmd='TARE'))).start()
        print('[MAIN] sent TARE (no saved cal — first install)', flush=True)

    # Send DUMP_LOG after 5s delay — MTU and service discovery complete by then
    # Node ignores DUMP_LOG outside STATE_RUNNING so early arrival is safe
    threading.Timer(5.0, lambda: (ble.write_command('DUMP_LOG\n'),
                                  hub_logger.log_ble('CMD_SENT', cmd='DUMP_LOG'))).start()


def on_node_disconnected():
    global g_node_connected
    g_node_connected = False
    print('[MAIN] Node disconnected', flush=True)
    hub_logger.log_ble('NODE_DISCONNECTED')
    ui.send_message('node_status', _node_status_payload())


def on_ui_connect(sid):
    snapshot = domain.get_state_snapshot()
    ui.send_message('weight_update', snapshot)
    ui.send_message('node_status', _node_status_payload())


def on_setup(sid, data):
    mode  = data.get('mode')
    brand = data.get('brand')
    valid_modes = ('FRESH', 'PARTIAL_BRAND', 'PARTIAL_PRIOR')
    if mode not in valid_modes:
        print(f'[MAIN] on_setup: invalid mode={mode}', flush=True)
        ui.send_message('setup_ack', {'ok': False, 'error': 'invalid mode'})
        return
    if mode == 'PARTIAL_BRAND' and brand not in ('Indane', 'HP', 'Bharat'):
        print(f'[MAIN] on_setup: invalid brand={brand}', flush=True)
        ui.send_message('setup_ack', {'ok': False, 'error': 'invalid brand'})
        return
    domain.set_install_mode(mode, brand)
    ui.send_message('setup_ack', {'ok': True, 'state': domain.get_state_snapshot()})
    print(f'[MAIN] setup complete: mode={mode} brand={brand}', flush=True)


ui.on_connect(on_ui_connect)
ui.on_message('setup', on_setup)

ble = BLESubscriber(
    on_weight=on_weight,
    on_log_line=log_transfer.on_log_line,
    on_connected=on_node_connected,
    on_disconnected=on_node_disconnected,
)
log_transfer.init(ble.write_command)
threading.Thread(target=ble.start, daemon=True).start()

_watchdog = HubWatchdog()
_watchdog.start()

print("[MAIN] Gas cylinder monitor hub started", flush=True)
hub_logger.log_hub('START')
db_init()
domain.load_config()
App.run()
