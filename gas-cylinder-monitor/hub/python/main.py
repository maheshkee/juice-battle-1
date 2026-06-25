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

_SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
_CONFIG_PATH = os.path.join(_SCRIPT_DIR, '..', 'config.json')

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
    br  = result.get('burn_rate_g_per_day')
    dr  = result.get('days_remaining')
    pe  = result.get('predicted_empty')
    src = result.get('burn_rate_source', '-')
    print(f"[MAIN] weight_update: grams={grams:.1f} quality={quality} "
          f"state={result['cylinder_state']} "
          f"burn={br if br is not None else '-'} "
          f"days={dr if dr is not None else '-'} "
          f"empty={pe if pe is not None else '-'} "
          f"src={src}", flush=True)


def on_node_connected(name, mac):
    global g_node_name, g_node_mac, g_node_connected
    g_node_name      = name
    g_node_mac       = mac
    g_node_connected = True
    print(f'[MAIN] Node connected: {name} ({mac})', flush=True)
    hub_logger.log_ble('NODE_CONNECTED', name=name, mac=mac)
    ui.send_message('node_status', _node_status_payload())

    # TARE vs SKIP_TARE decision is handled in ble_subscriber._send_tare_commands()
    # Send DUMP_LOG after 5s — MTU and service discovery complete by then
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


def _on_log_transfer_complete():
    if not ble.last_boot_used_tare:
        return
    try:
        log_dir = log_transfer.LOG_DIR
        files   = sorted(
            [f for f in os.listdir(log_dir) if f.endswith('.log')],
            reverse=True,
        )
        if not files:
            print('[MAIN] tare update: no journal files found', flush=True)
            return
        journal_path = os.path.join(log_dir, files[0])
        tare_raw = domain.parse_tare_from_journal(journal_path)
        if tare_raw is not None:
            domain.update_tare_in_config(tare_raw, _CONFIG_PATH)
        else:
            print('[MAIN] tare update: TARE line not found in journal', flush=True)
    except Exception as e:
        print(f'[MAIN] tare update failed: {e}', flush=True)


def on_log_line_wrapper(line):
    log_transfer.on_log_line(line)
    if line.strip() == 'LOG_END':
        _on_log_transfer_complete()


ui.on_connect(on_ui_connect)
ui.on_message('setup', on_setup)

ble = BLESubscriber(
    on_weight=on_weight,
    on_log_line=on_log_line_wrapper,
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
