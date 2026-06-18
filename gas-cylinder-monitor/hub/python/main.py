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
from ble_subscriber import BLESubscriber
from db import (db_init, db_insert_reading, db_get_starting_weight,
                db_set_starting_weight, db_get_latest_reading,
                db_get_dev_mode, db_set_dev_mode)

# ── Alert and burn-rate constants ────────────────────────────────────────────
# V1: population prior. Replace with measured value in Group 5 analytics.
# WARNING: ALERT_AMBER_G and ALERT_RED_G were derived from this value.
# Do not change DAILY_USE_DEFAULT_G without re-validating both alert thresholds.
DAILY_USE_DEFAULT_G = 350.0   # g/day — conservative middle of Indian household range
ALERT_AMBER_G       = 2000.0  # gas_remaining threshold — "book a refill" (~5-6 days)
ALERT_RED_G         = 1000.0  # gas_remaining threshold — "order now" (~2-3 days)
MIN_HISTORY_DAYS    = 7       # minimum days of data before V2 burn rate is trusted
# ─────────────────────────────────────────────────────────────────────────────

ui = WebUI()

g_starting_weight    = None
g_sw_candidate       = None
g_sw_candidate_val   = 0.0
g_weight_was_removed = False
g_dev_mode           = True   # overwritten from DB after db_init()
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
    global g_starting_weight, g_sw_candidate, g_sw_candidate_val, g_weight_was_removed

    db_insert_reading(hub_ts, grams, quality, sigma)

    if g_dev_mode:
        # DEV: re-anchor only on first load or after weight was removed+replaced
        if grams > 500.0:
            if g_starting_weight is None or g_weight_was_removed:
                if g_sw_candidate is None:
                    g_sw_candidate     = True
                    g_sw_candidate_val = grams
                    print(f'[MAIN] [DEV] anchor candidate: {grams:.1f}g waiting...', flush=True)
                else:
                    if abs(grams - g_sw_candidate_val) <= 2.0 * sigma:
                        settled_val = round((grams + g_sw_candidate_val) / 2.0, 1)
                        db_set_starting_weight(settled_val)
                        g_starting_weight    = settled_val
                        g_sw_candidate       = None
                        g_sw_candidate_val   = 0.0
                        g_weight_was_removed = False
                        print(f'[MAIN] [DEV] anchor re-set: {settled_val}g', flush=True)
                    else:
                        g_sw_candidate_val = grams
                        print(f'[MAIN] [DEV] anchor candidate updated: {grams:.1f}g settling...', flush=True)
        else:
            if g_sw_candidate is not None:
                print('[MAIN] [DEV] anchor candidate reset — weight < 500g', flush=True)
            g_sw_candidate       = None
            g_sw_candidate_val   = 0.0
            g_weight_was_removed = True
    else:
        # PRODUCTION: load anchor once from DB, never auto-reset
        if g_starting_weight is None:
            g_starting_weight = db_get_starting_weight()
        # TODO hub Group 4: steel subtraction → real gas%

    pct = None
    if g_dev_mode and g_starting_weight and g_starting_weight > 0 \
            and quality != 'WAITING':
        pct = round((grams / g_starting_weight) * 100, 1)
    # production pct: None until hub Group 4 built

    alert = None
    days_remaining = None

    if g_dev_mode:
        # DEV simulation alerts — relative to anchor weight
        if grams < 50.0:
            alert = 'empty'
        elif pct is not None and pct < 20.0:
            alert = 'low_gas'
            days_remaining = max(1, round(
                (g_starting_weight * 0.20) / DAILY_USE_DEFAULT_G
            ))

    else:
        # PRODUCTION alerts — absolute gas remaining
        # steel_g = None until Group 4 built
        steel_g = None  # TODO Group 4: load from config

        if steel_g is not None:
            gas_remaining = grams - steel_g
            if gas_remaining < ALERT_RED_G:
                alert = 'critical'
                days_remaining = max(1, round(gas_remaining / DAILY_USE_DEFAULT_G))
            elif gas_remaining < ALERT_AMBER_G:
                alert = 'low_gas'
                days_remaining = max(1, round(gas_remaining / DAILY_USE_DEFAULT_G))
        # else: steel unknown → alert stays None, pct stays None (Option B)

    ui.send_message('weight_update', {
        'grams':          round(grams, 1),
        'quality':        quality,
        'sigma':          round(sigma, 2),
        'ts':             hub_ts,
        'pct':            pct,
        'alert':          alert,
        'days_remaining': days_remaining,
    })
    print(f"[MAIN] weight_update: grams={grams:.1f} quality={quality}", flush=True)


def on_node_connected(name, mac):
    global g_node_name, g_node_mac, g_node_connected
    g_node_name      = name
    g_node_mac       = mac
    g_node_connected = True
    print(f'[MAIN] Node connected: {name} ({mac})', flush=True)
    ui.send_message('node_status', _node_status_payload())


def on_node_disconnected():
    global g_node_connected
    g_node_connected = False
    print('[MAIN] Node disconnected', flush=True)
    ui.send_message('node_status', _node_status_payload())


def on_set_dev_mode(data):
    global g_dev_mode, g_starting_weight, g_sw_candidate, g_sw_candidate_val, g_weight_was_removed
    enabled = bool(data.get('enabled', True))
    g_dev_mode = enabled
    db_set_dev_mode(enabled)
    g_starting_weight    = None
    g_sw_candidate       = None
    g_sw_candidate_val   = 0.0
    g_weight_was_removed = False
    print(f'[MAIN] dev_mode → {enabled}', flush=True)
    ui.send_message('dev_mode_ack', {'enabled': enabled})


def on_ui_connect(sid):
    latest = db_get_latest_reading()
    sw = db_get_starting_weight()
    pct = None
    if latest and sw and sw > 0:
        pct = round((latest['grams'] / sw) * 100, 1)
    alert = None
    days_remaining = None

    if latest:
        if g_dev_mode:
            if latest['grams'] < 50.0:
                alert = 'empty'
            elif pct is not None and pct < 20.0:
                alert = 'low_gas'
                days_remaining = max(1, round(
                    (sw * 0.20) / DAILY_USE_DEFAULT_G
                ))
        else:
            steel_g = None  # TODO Group 4: load from config
            if steel_g is not None:
                gas_remaining = latest['grams'] - steel_g
                if gas_remaining < ALERT_RED_G:
                    alert = 'critical'
                    days_remaining = max(1, round(gas_remaining / DAILY_USE_DEFAULT_G))
                elif gas_remaining < ALERT_AMBER_G:
                    alert = 'low_gas'
                    days_remaining = max(1, round(gas_remaining / DAILY_USE_DEFAULT_G))

    if latest:
        ui.send_message('weight_update', {
            'grams':          round(latest['grams'], 1),
            'quality':        latest['quality'],
            'sigma':          round(latest['sigma'], 2),
            'ts':             latest['ts'],
            'pct':            pct,
            'alert':          alert,
            'days_remaining': days_remaining,
            'prod_ready':     False,
            'dev_mode':       g_dev_mode,
        })
    else:
        ui.send_message('weight_update', {
            'grams':          0,
            'quality':        'WAITING',
            'sigma':          0.0,
            'ts':             '--',
            'pct':            None,
            'alert':          None,
            'days_remaining': None,
            'prod_ready':     False,
            'dev_mode':       g_dev_mode,
        })
    ui.send_message('node_status',  _node_status_payload())
    ui.send_message('dev_mode_ack', {'enabled': g_dev_mode})


ui.on_connect(on_ui_connect)
ui.on_message('set_dev_mode', on_set_dev_mode)

ble = BLESubscriber(
    on_weight=on_weight,
    on_connected=on_node_connected,
    on_disconnected=on_node_disconnected,
)
threading.Thread(target=ble.start, daemon=True).start()

print("[MAIN] Gas cylinder monitor hub started", flush=True)
db_init()
g_dev_mode = db_get_dev_mode()
print(f"[MAIN] dev_mode loaded from DB: {g_dev_mode}", flush=True)
App.run()
