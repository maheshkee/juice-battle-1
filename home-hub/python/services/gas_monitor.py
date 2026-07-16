import concurrent.futures
import json
import os
import sqlite3
import time

import config

_bridge = None
_push_evt = None

_SENSOR_TIMEOUT_SEC     = 3
_SENSOR_MAX_RETRIES     = 3
_SENSOR_RETRY_DELAY_SEC = 1


def init(bridge, push_evt):
    global _bridge, _push_evt
    _bridge = bridge
    _push_evt = push_evt
    _ensure_db()
    print("[GAS_MONITOR] initialized", flush=True)


def start():
    _ensure_db()
    print("[GAS_MONITOR] started", flush=True)


def stop():
    print("[GAS_MONITOR] stopped", flush=True)


def _ensure_db():
    os.makedirs(os.path.dirname(config.GAS_DB_PATH), exist_ok=True)
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute("""
            CREATE TABLE IF NOT EXISTS readings (
                id        INTEGER PRIMARY KEY,
                timestamp INTEGER,
                weight_kg REAL,
                net_kg    REAL
            )
        """)
        con.execute("""
            CREATE TABLE IF NOT EXISTS cylinder_templates (
                id      INTEGER PRIMARY KEY,
                brand   TEXT,
                tare_kg REAL
            )
        """)


def _get_tare_kg():
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        row = con.execute(
            "SELECT tare_kg FROM cylinder_templates ORDER BY id DESC LIMIT 1"
        ).fetchone()
    return float(row[0]) if row else 0.0


def _read_sensor():
    for attempt in range(1, _SENSOR_MAX_RETRIES + 1):
        print(f"[GAS_MONITOR] read_sensor attempt {attempt}/{_SENSOR_MAX_RETRIES}", flush=True)
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                future = executor.submit(_bridge.call, "read_weight_packet")
                result = future.result(timeout=_SENSOR_TIMEOUT_SEC)
            return json.loads(result)
        except Exception as e:
            print(f"[GAS_MONITOR] read_sensor attempt {attempt} error: {e}", flush=True)
            if attempt < _SENSOR_MAX_RETRIES:
                time.sleep(_SENSOR_RETRY_DELAY_SEC)
    print(f"[GAS_MONITOR] read_sensor failed after {_SENSOR_MAX_RETRIES} retries", flush=True)
    return None


def _record_reading(weight_kg):
    net_kg = _net_weight_kg(weight_kg, _get_tare_kg())
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute(
            "INSERT INTO readings (timestamp, weight_kg, net_kg) VALUES (?, ?, ?)",
            (int(time.time()), weight_kg, net_kg)
        )
    print(f"[GAS_MONITOR] recorded weight_kg={weight_kg} net_kg={net_kg}", flush=True)


def _net_weight_kg(raw_kg, tare_kg):
    return raw_kg - tare_kg


def _predict_refill_days():
    cutoff = int(time.time()) - config.PREDICTION_WINDOW_DAYS * 86400
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        rows = con.execute(
            "SELECT timestamp, net_kg FROM readings WHERE timestamp >= ? ORDER BY timestamp ASC",
            (cutoff,)
        ).fetchall()
    if len(rows) < 2:
        return None
    t0, w0 = rows[0]
    t1, w1 = rows[-1]
    days_elapsed = (t1 - t0) / 86400
    if days_elapsed <= 0:
        return None
    daily_rate = (w0 - w1) / days_elapsed
    if daily_rate <= 0:
        return None
    return w1 / daily_rate


def _check_threshold(net_kg):
    if net_kg <= config.REFILL_THRESHOLD_KG:
        print(f"[GAS_MONITOR] refill alert triggered at {net_kg}kg", flush=True)
        _push_evt({"event": "gas_refill_alert", "weight_kg": net_kg})


def _on_measurement_cycle():
    try:
        packet = _read_sensor()
        if packet is None:
            print("[GAS_MONITOR] measurement cycle aborted: sensor read failed", flush=True)
            return
        weight_kg = packet["weight_kg"]
        _record_reading(weight_kg)
        net_kg = _net_weight_kg(weight_kg, _get_tare_kg())
        _check_threshold(net_kg)
        days = _predict_refill_days()
        _push_evt({"event": "gas_prediction", "days_left": days})
        print("[GAS_MONITOR] measurement cycle complete", flush=True)
    except Exception as e:
        print(f"[GAS_MONITOR] measurement cycle error: {e}", flush=True)
