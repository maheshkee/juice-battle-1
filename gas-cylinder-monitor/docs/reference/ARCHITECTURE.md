# Gas Cylinder Monitor — Architecture Reference
# home-hub service | Arduino UNO Q AQ3 | Updated: 2026-04-30

---

## System Summary

The gas monitor is a service within home-hub. The STM32U585 MCU reads an HX711 24-bit ADC connected to a 20kg load cell and exposes the result via Bridge RPC. The QRB2210 Linux MPU calls that RPC every 6 hours, stores the result in SQLite, computes remaining gas and days-until-empty from a rolling 7-day consumption average, and pushes the result to the LCD via Socket.IO and to the phone via BLE. The MCU owns sensor timing. Linux owns all computation, storage, and output.

---

## Data Flow

```
Load Cell (YZC-161A 20kg)
    │ millivolt signal (2mV/V)
    ▼
HX711 ADC Module (24-bit, gain 128)
    │ DT→D4(PA12), SCK→D3(PB0)
    ▼
STM32U585 MCU (sketch.ino, Zephyr RTOS)
    │ bit-bang read, 20 samples, average, stability check
    │ Bridge.provide("read_weight_packet") returns JSON String
    ▼
Bridge RPC (LPUART1, 9600 baud, MSGPACK)
    │ Bridge.call() blocks in Docker container
    ▼
QRB2210 MPU — gas_monitor.py (Python, Docker)
    │ json.loads(bridge.call("read_weight_packet"))
    │ INSERT INTO readings
    │ net_kg = weight_kg - tare_kg
    │ days_left = net_kg / 7-day-rolling-avg-rate
    ├─→ Socket.IO "weight_update" → splash.html weight widget (LCD)
    └─→ BLE EVT "gas_prediction" → Flutter app (phone)
```

---

## MCU Responsibilities

- Configure HX711: DT=D4(PA12), SCK=D3(PB0), 3.3V power
- Execute tare (zero offset) once at boot — scale must be empty
- On `read_weight_packet` call: collect 20 ADC samples, average, stability-check, return JSON
- Apply calibration factor `cal` to convert raw counts → kg
- Return `sensor_ok=false` if HX711 not ready or reading invalid
- Return `stable=false` if sample variance exceeds threshold
- Expose `get_raw` for calibration mode (returns raw ADC count, cal=1.0)
- Deep sleep between measurement cycles (Zephyr RTC wakeup)

---

## Linux (gas_monitor.py) Responsibilities

- `init(bridge, push_evt)`: store bridge and push_evt references, call `_ensure_db()`
- `_ensure_db()`: create tables if not exist (readings, cylinder_templates)
- `_read_sensor()`: call `bridge.call("read_weight_packet")`, 3s timeout, 3 retries
- `_get_tare_kg()`: query `cylinder_templates` for latest tare
- `_record_reading(weight_kg)`: INSERT into readings with net_kg computed
- `_predict_refill_days()`: 7-day rolling average → days_left formula
- `_check_threshold(net_kg)`: push `gas_refill_alert` EVT if net_kg ≤ REFILL_THRESHOLD_KG
- `_on_measurement_cycle()`: orchestrate read → record → check → predict → push
- All outbound events via `push_evt()` which calls both BLE and Socket.IO

---

## Bridge RPC — Packet Format

`read_weight_packet` returns a JSON String. Python parses with `json.loads()`.

| Field | Type | Description |
|-------|------|-------------|
| weight_kg | float | Total weight (cylinder + gas), calibration applied |
| raw_kg | float | Weight before calibration factor (debugging) |
| stable | bool | True if 20-sample variance below threshold |
| sensor_ok | bool | False if HX711 not ready or read error |

Example:
```json
{"weight_kg": 28.4, "raw_kg": 28397.2, "stable": true, "sensor_ok": true}
```

---

## SQLite Schema

File: `data/gas_monitor.db`

```sql
readings(id, timestamp INTEGER, weight_kg REAL, net_kg REAL)
  -- raw weight and net weight per measurement cycle

cylinder_templates(id, brand TEXT, tare_kg REAL, capacity_kg REAL)
  -- tare source of truth — never hardcode tare anywhere else

refill_events(id, detected_at INTEGER, weight_before REAL, weight_after REAL, tare_estimate REAL)
  -- logged when weight jump > 8kg detected

predictions(id, calculated_at INTEGER, gas_left_kg REAL, days_left REAL, avg_daily_use REAL, confidence REAL)
  -- logged each measurement cycle
```

Tare selection: `SELECT tare_kg FROM cylinder_templates ORDER BY id DESC LIMIT 1`

---

## 6-Hour Measurement Cycle

| Time | Event |
|------|-------|
| T+0s | `_on_measurement_cycle()` called by main loop |
| T+1s | `_read_sensor()` → `bridge.call("read_weight_packet")` dispatched |
| T+2s | MCU wakes (if sleeping), reads HX711 20× at 50ms intervals |
| T+3s | MCU computes average, variance, builds JSON, returns over Bridge |
| T+4s | Python receives JSON string, calls `json.loads()` |
| T+5s | `_record_reading()` → SQLite INSERT |
| T+6s | `_check_threshold()` → push alert if below threshold |
| T+7s | `_predict_refill_days()` → compute days_left |
| T+8s | `push_evt()` → Socket.IO `weight_update` to LCD, BLE `gas_prediction` to phone |
| T+9s | Sleep 21600s (6h) until next cycle |

**Current demo state:** `time.sleep(30)` in main.py. Must be changed to `time.sleep(21600)` for production.

---

## Prediction Algorithm

```
net_kg = weight_kg - tare_kg           # gas only (no cylinder shell)

# From readings table, last 7 days:
daily_rate = (weight_oldest - weight_newest) / days_elapsed   # kg/day

days_left = net_kg / daily_rate
```

Guards:
- Fewer than 2 readings in window → return None (show "not enough data")
- `daily_rate <= 0` → return None (consumption not established)
- `days_elapsed <= 0` → return None (timestamp error)

Minimum readings before prediction is meaningful: 4 (approximately 1 day of data).

---

## Tare Learning (v0.5+, not yet implemented)

```
On refill detected (weight jump > 8kg):
  1. Find minimum weight across previous cycle readings
  2. inferred_tare = that minimum
  3. learned_tare = current_tare × 0.7 + inferred_tare × 0.3
  4. UPDATE cylinder_templates SET tare_kg = learned_tare WHERE id = (latest)
```

Converges to actual tare within 2–3 refill cycles. For v0.1–v0.4: tare is fixed from cylinder_templates seed data.

---

## Failure Modes

| Failure | Detection | Recovery |
|---------|-----------|---------|
| HX711 not ready | `sensor_ok=false` in packet | Log, skip cycle, retry next cycle |
| Unstable reading | `stable=false` in packet | Log, record anyway, flag in DB |
| Bridge call timeout | Exception after 3s | 3 retries × 1s delay, then abort cycle |
| Bridge call fails 3× | `_read_sensor()` returns None | Log "measurement cycle aborted", skip |
| SQLite write fails | Exception in `_record_reading()` | Log error, continue (no crash) |
| No readings for prediction | `len(rows) < 2` | Return None, push `days_left: null` |
| consumption_rate = 0 | Guard in `_predict_refill_days()` | Return None, no division by zero |
| net_kg negative | tare_kg > weight_kg | Possible wrong template — log, show raw weight |
| Weight jump > 8kg | `_check_refill()` (v0.5) | Log refill event, reset consumption baseline |

---

## Module Boundaries

`gas_monitor.py` owns:
- Sensor reading via Bridge RPC
- SQLite storage
- Prediction calculation
- Threshold alerting
- Socket.IO push (weight_update)
- BLE EVT push (gas_prediction, gas_refill_alert)

`gas_monitor.py` must NOT:
- Touch any other service (queue_engine, local_engine, bt_manager)
- Hardcode tare or thresholds (use config.py and cylinder_templates)
- Manage Bridge lifecycle (bridge is passed in via init())
- Manage BLE connection (push_evt is passed in via init())

---

## Socket.IO Events

| Event | Direction | Payload |
|-------|-----------|---------|
| `weight_update` | gas_monitor → splash.html | `{weight_g: int, net_g: int, stable: bool}` |
| `gas_prediction` | gas_monitor → splash.html | `{days_left: float or null}` |

---

## BLE EVT Events

| Event | Trigger | Key fields |
|-------|---------|-----------|
| `gas_status` | On demand (GAS_STATUS cmd) | weight_kg, net_kg, days_left, stable |
| `gas_prediction` | Every measurement cycle | days_left |
| `gas_refill_alert` | net_kg ≤ REFILL_THRESHOLD_KG | weight_kg |
| `gas_refill` | Weight jump > 8kg (v0.5) | weight_before, weight_after |
