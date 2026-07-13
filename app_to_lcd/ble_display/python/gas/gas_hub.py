import os
import threading

from gas import domain
from gas import log_transfer
from gas.ble_subscriber import BLESubscriber
from gas.db import db_init, db_insert_reading
from gas import hub_logger
from gas.hub_watchdog import HubWatchdog

_CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
               '..', '..', 'gas_config.json')

_ui           = None
_ble          = None
_watchdog     = None

g_node_name      = None
g_node_mac       = None
g_node_connected = False


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
    print(f'[GAS] sending gas_update: {result}', flush=True)
    _ui.send_message('gas_update', result)
    br  = result.get('burn_rate_g_per_day')
    dr  = result.get('days_remaining')
    pe  = result.get('predicted_empty')
    src = result.get('burn_rate_source', '-')
    print(f'[GAS] weight: grams={grams:.1f} quality={quality} '
          f'state={result["cylinder_state"]} '
          f'burn={br if br is not None else "-"} '
          f'days={dr if dr is not None else "-"} '
          f'empty={pe if pe is not None else "-"} '
          f'src={src}', flush=True)


def on_node_connected(name, mac):
    global g_node_name, g_node_mac, g_node_connected
    g_node_name      = name
    g_node_mac       = mac
    g_node_connected = True
    print(f'[GAS] Node connected: {name} ({mac})', flush=True)
    hub_logger.log_ble('NODE_CONNECTED', name=name, mac=mac)
    _ui.send_message('gas_node_status', _node_status_payload())
    threading.Timer(5.0, lambda: (
        _ble.write_command('DUMP_LOG\n'),
        hub_logger.log_ble('CMD_SENT', cmd='DUMP_LOG')
    )).start()


def on_node_disconnected():
    global g_node_connected
    g_node_connected = False
    print('[GAS] Node disconnected', flush=True)
    hub_logger.log_ble('NODE_DISCONNECTED')
    _ui.send_message('gas_node_status', _node_status_payload())


def on_ui_connect(sid):
    snapshot = domain.get_state_snapshot()
    _ui.send_message('gas_update', snapshot)
    _ui.send_message('gas_node_status', _node_status_payload())


def on_setup(sid, data):
    mode  = data.get('mode')
    brand = data.get('brand')
    valid_modes = ('FRESH', 'PARTIAL_BRAND', 'PARTIAL_PRIOR')
    if mode not in valid_modes:
        _ui.send_message('gas_setup_ack', {'ok': False, 'error': 'invalid mode'})
        return
    if mode == 'PARTIAL_BRAND' and brand not in ('Indane', 'HP', 'Bharat'):
        _ui.send_message('gas_setup_ack', {'ok': False, 'error': 'invalid brand'})
        return
    domain.set_install_mode(mode, brand)
    _ui.send_message('gas_setup_ack', {'ok': True, 'state': domain.get_state_snapshot()})
    print(f'[GAS] setup: mode={mode} brand={brand}', flush=True)


def _on_log_transfer_complete():
    if not _ble.last_boot_used_tare:
        return
    try:
        log_dir = log_transfer.LOG_DIR
        files   = sorted(
            [f for f in os.listdir(log_dir) if f.endswith('.log')],
            reverse=True,
        )
        if not files:
            print('[GAS] tare update: no journal files found', flush=True)
            return
        journal_path = os.path.join(log_dir, files[0])
        tare_raw = domain.parse_tare_from_journal(journal_path)
        if tare_raw is not None:
            domain.update_tare_in_config(tare_raw, _CONFIG_PATH)
        else:
            print('[GAS] tare update: TARE line not found in journal', flush=True)
    except Exception as e:
        print(f'[GAS] tare update failed: {e}', flush=True)


def on_log_line_wrapper(line):
    log_transfer.on_log_line(line)
    if line.strip() == 'LOG_END':
        _on_log_transfer_complete()


def start(bus, ui, scan_trigger=None):
    global _ui, _ble, _watchdog
    _ui = ui
    print('[GAS] start() called', flush=True)

    try:
        _ui.on_connect(on_ui_connect)
        _ui.on_message('gas_setup', on_setup)
        print('[GAS] ui hooks OK', flush=True)

        db_init()
        print('[GAS] db_init OK', flush=True)

        domain.load_config()
        print('[GAS] domain.load_config OK', flush=True)

        hub_logger.log_hub('START')
        print('[GAS] hub_logger OK', flush=True)

        _ble = BLESubscriber(
            on_weight=on_weight,
            on_log_line=on_log_line_wrapper,
            on_connected=on_node_connected,
            on_disconnected=on_node_disconnected,
        )
        log_transfer.init(_ble.write_command)
        _ble.start(bus, scan_trigger=scan_trigger)
        print('[GAS] BLE subscriber started', flush=True)

        _watchdog = HubWatchdog()
        _watchdog.start()
        print('[GAS] Watchdog started', flush=True)

        print('[GAS] Gas hub started', flush=True)
    except Exception as e:
        import traceback
        print(f'[GAS] start() FAILED: {e}', flush=True)
        traceback.print_exc()
