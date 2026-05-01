# SKILLS.md — home-hub
# Canonical implementation patterns. Generated code MUST follow these exactly.
# Updated: 2026-04-29

---

## 1. Socket.IO message pattern (WebUI Brick → splash.html)

`ui.send_message(event, dict)` sends from Python to the browser over Socket.IO.
Event names must match `socket.on('event', ...)` in the HTML.

```python
# python/main.py or any service — never fabricate new event names without adding the JS listener

ui.send_message("weight_update",   {"weight_kg": 1.234, "weight_g": 1234.0})
ui.send_message("gas_prediction",  {"days_left": 12.5, "low_confidence": False})
ui.send_message("status",          {"state": "playing", "video_id": "abc123"})
ui.send_message("player_control",  {"action": "stop"})
ui.send_message("ble_connected",   {"device": "iPhone"})
ui.send_message("ble_disconnected",{})
```

```javascript
// assets/splash.html — always use socket.on, never poll
socket.on('weight_update', function(data) {
  document.getElementById('weight-value').textContent = data.weight_g;
});
```

---

## 2. write_cmd() pattern — video routing (Socket.IO only, never file-based)

```python
# python/main.py — canonical, do not change routing logic

def write_cmd(cmd):
    if cmd == "STOP":
        ui.send_message("player_control", {"action": "stop"})
    elif cmd.startswith("LOCAL:"):
        ui.send_message("play_local_display", {"filename": cmd[6:]})
    else:
        ui.send_message("play_video_display", {"video_id": cmd})
```

Rules:
- Never write to cmd.txt or any file — Socket.IO only
- Local video path in HTML is `/videos/filename.mp4` NOT `/assets/videos/`
- YouTube cmd is bare video_id, not full URL

---

## 3. push_evt() pattern — BLE notify + Socket.IO broadcast

Sends to Flutter phone via BLE EVT characteristic AND mirrors to browser.

```python
# python/main.py

def push_evt(data):
    try:
        ble.push_evt(data)          # BLE → Flutter phone
    except Exception:
        pass
    ui.send_message(data.get("event", "evt"), data)   # Socket.IO → browser

# Usage examples
push_evt({"event": "gas_prediction", "days_left": 12.5})
push_evt({"event": "gas_refill_alert", "weight_kg": 7.8})
push_evt({"event": "bt_connected", "mac": "AA:BB:CC:DD:EE:FF", "name": "JBL"})
```

---

## 4. BLE D-Bus initialization pattern (EXACT — do not deviate)

Must run before any `import dbus`. Order matters.

```python
# Any file that needs BLE/D-Bus (currently: ble_gatt_serve.py)

import os, sys, ctypes

os.environ['GI_TYPELIB_PATH']          = '/app/typelibs'
os.environ['DBUS_SYSTEM_BUS_ADDRESS']  = 'unix:path=/app/dbus.sock'

for lib in ['libm.so.6','libcap.so.2','libpcre2-8.so.0','libselinux.so.1',
            'libaudit.so.1','libcap-ng.so.0','libexpat.so.1','libdbus-1.so.3',
            'libapparmor.so.1','libsystemd.so.0','libgirepository-2.0.so.0']:
    try:
        ctypes.CDLL(f'/app/wheels/{lib}')
    except Exception as e:
        print(f'[BLE] {lib}: {e}', flush=True)   # some absent libs are normal

sys.path.insert(0, '/usr/lib/python3/dist-packages')
import dbus, dbus.mainloop.glib
from gi.repository import GLib
```

Hard rules:
- Never `transport=auto` for BLE scan — kills WCBN3536A permanently, `sudo reboot` only recovery
- Never `sockets:` in app.yaml — does not work, use socat bridge at `/app/dbus.sock`
- BLE UUIDs are hardcoded in Flutter app — never change:
  - Service:  `a01c0000-0000-0000-0000-000000000000`
  - CMD char: `a01c0001-0000-0000-0000-000000000000` (WRITE)
  - EVT char: `a01c0002-0000-0000-0000-000000000000` (NOTIFY)

---

## 5. ~~ScaleHX711 driver pattern~~ — DEPRECATED

> **DO NOT USE.** ScaleHX711.cpp/.h and the D4/D3 pin assignments are wrong and superseded.
> Root cause: D4/D3 have PWM timer mux conflicts on STM32U585 → corrupt/saturated ADC reads.
> Replacement: inline raw bit-bang directly in sketch.ino using D7/D6 + Bridge.notify().
> Reference implementation: ~/ArduinoApps/digital-scale/sketch/sketch.ino (confirmed working).
> ScaleHX711.cpp/.h can be deleted from home-hub sketch/ after migration.

### Replacement pattern (use this instead)

```cpp
#define HX711_DT_PIN   7   // D7 — ONLY clean pin on STM32U585
#define HX711_SCK_PIN  6   // D6 — ONLY clean pin on STM32U585

// In setup():
pinMode(HX711_DT_PIN, INPUT_PULLUP);  // open-drain: PULLUP required
pinMode(HX711_SCK_PIN, OUTPUT);
digitalWrite(HX711_SCK_PIN, LOW);

// In loop() — Bridge.notify() every 500ms, never Bridge.provide_safe()
```

Full bit-bang recipe: see CLAUDE.md "The Working Bit-Bang Recipe" section.

---

## 5b. ScaleHX711 driver pattern (Zephyr MCU, bit-bang GPIO)

### Class interface

```cpp
// sketch/ScaleHX711.h — public API

void    begin(int dt, int sck, uint8_t gain = 128); // init pins, default gain 128
void    update();              // call in loop — refreshes cached reading if HX711 ready
void    tare(int samples = 10);        // zero offset with N-sample average
void    set_scale(float scale);        // set calibration factor (raw counts per kg)
void    calibrate(float known_weight, int samples = 10); // one-shot cal with known weight

float   get_weight();       // last cached weight in kg (after tare + scale applied)
int32_t get_raw();          // last cached raw ADC count
bool    is_stable();        // true if last two readings within stabilityThreshold counts
bool    available();        // true once any valid reading has been captured
bool    fresh();            // true if update() captured a NEW reading this call
```

### Sketch usage pattern

```cpp
// sketch/sketch.ino

#include "ScaleHX711.h"

#define DT_PIN   4   // PA12 — no PWM timer mux conflict
#define SCK_PIN  3   // PB0
#define CAL      1.0f  // TEMPORARY — replace after calibration

ScaleHX711 scale;

void setup() {
    Bridge.begin();
    scale.begin(DT_PIN, SCK_PIN);
    scale.tare(20);           // zero on empty scale
    scale.set_scale(CAL);
    Bridge.provide("read_weight_packet", read_weight_packet);
}

void loop() {
    scale.update();   // refresh cache; Bridge.call() will call read_weight_packet()
    delay(100);
}
```

### read_raw_internal() — bit-bang critical section

```cpp
// sketch/ScaleHX711.cpp — reads DOUT while SCK is HIGH (data stable at that point)

noInterrupts();
for (int i = 0; i < 24; ++i) {
    digitalWrite(_sck, HIGH);
    delayMicroseconds(1);
    value <<= 1;
    if (digitalRead(_dt)) value++;   // read while SCK HIGH — data is valid here
    digitalWrite(_sck, LOW);
    delayMicroseconds(1);
}
// extra pulses set gain for next conversion: _gain=1 → gain128
for (uint8_t i = 0; i < _gain; ++i) {
    digitalWrite(_sck, HIGH);
    digitalWrite(_sck, LOW);
}
interrupts();
if (value & 0x800000UL) value |= 0xFF000000UL;  // sign-extend 24→32 bit
```

### Calibration procedure

```
1. Empty scale, deploy, wait 25s (tare runs in setup())
2. Place known weight (e.g. 1kg water bottle)
3. Read raw counts from logs: arduino-app-cli app logs user:home-hub | grep WEIGHT
4. cal = raw_count / known_weight_kg
5. Update CAL in sketch.ino, redeploy, verify
```

---

## 6. Bridge RPC patterns (MCU ↔ Python)

Bridge.call() blocks until MCU responds. Bridge.notify() is fire-and-forget.
Return types: primitives and `String` only. For structs → JSON string → `json.loads()`.

```cpp
// sketch/sketch.ino — MCU side: return JSON String for multi-field data
// Uses ScaleHX711 — call scale.update() in loop() to refresh cached values

String read_weight_packet() {
    scale.update();   // ensure fresh reading when called via Bridge
    bool sensor_ok = scale.available();
    float weight_kg = sensor_ok ? scale.get_weight() : -1.0f;
    bool stable     = sensor_ok && scale.is_stable();
    String json = "{";
    json += "\"weight_kg\":" + String(weight_kg, 3) + ",";
    json += "\"raw_kg\":"    + String(scale.get_raw())  + ",";
    json += "\"stable\":"    + String(stable      ? "true" : "false") + ",";
    json += "\"sensor_ok\":" + String(sensor_ok   ? "true" : "false");
    json += "}";
    return json;
}

void setup() {
    Bridge.begin();
    scale.begin(DT_PIN, SCK_PIN);
    scale.tare(20);
    scale.set_scale(CAL);
    Bridge.provide("read_weight_packet", read_weight_packet);
}
```

```python
# python — MCU side: call + json.loads for JSON returns

import json, concurrent.futures

def _read_sensor(bridge, timeout=3):
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        future = ex.submit(bridge.call, "read_weight_packet")
        result = future.result(timeout=timeout)
    return json.loads(result)   # returns dict: weight_kg, raw_kg, stable, sensor_ok
```

---

## 7. SQLite patterns (gas_monitor.db)

Parameterized queries only. Never string-concatenate SQL.

### Full schema (all tables required)

```python
# python/services/gas_monitor.py

def _ensure_db():
    os.makedirs(os.path.dirname(config.GAS_DB_PATH), exist_ok=True)
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute("""CREATE TABLE IF NOT EXISTS readings (
            id INTEGER PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            weight_kg REAL NOT NULL,
            net_kg REAL NOT NULL)""")
        con.execute("""CREATE TABLE IF NOT EXISTS daily_aggregates (
            id INTEGER PRIMARY KEY,
            date_epoch INTEGER NOT NULL UNIQUE,
            avg_net_kg REAL NOT NULL,
            consumed_kg REAL NOT NULL,
            high_usage INTEGER DEFAULT 0)""")   -- 1 = flagged high-usage day
        con.execute("""CREATE TABLE IF NOT EXISTS refill_history (
            id INTEGER PRIMARY KEY,
            timestamp INTEGER NOT NULL,
            pre_net_kg REAL NOT NULL,
            post_net_kg REAL NOT NULL)""")
        con.execute("""CREATE TABLE IF NOT EXISTS cylinder_templates (
            id INTEGER PRIMARY KEY,
            brand TEXT,
            tare_kg REAL NOT NULL)""")
```

### Core read/write helpers

```python
def insert_reading(weight_kg, net_kg):
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute("INSERT INTO readings (timestamp, weight_kg, net_kg) VALUES (?,?,?)",
                    (int(time.time()), weight_kg, net_kg))

def insert_refill(pre_net_kg, post_net_kg):
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute("INSERT INTO refill_history (timestamp, pre_net_kg, post_net_kg) VALUES (?,?,?)",
                    (int(time.time()), pre_net_kg, post_net_kg))

def insert_daily_aggregate(date_epoch, avg_net_kg, consumed_kg, high_usage=False):
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        con.execute("""INSERT OR REPLACE INTO daily_aggregates
            (date_epoch, avg_net_kg, consumed_kg, high_usage) VALUES (?,?,?,?)""",
            (date_epoch, avg_net_kg, consumed_kg, 1 if high_usage else 0))

def query_window(days):
    cutoff = int(time.time()) - days * 86400
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        return con.execute(
            "SELECT timestamp, net_kg FROM readings WHERE timestamp >= ? ORDER BY timestamp ASC",
            (cutoff,)).fetchall()

def query_daily_window(days):
    cutoff = int(time.time()) - days * 86400
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        return con.execute(
            "SELECT date_epoch, consumed_kg FROM daily_aggregates WHERE date_epoch >= ? ORDER BY date_epoch ASC",
            (cutoff,)).fetchall()

def get_tare_kg():
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        row = con.execute(
            "SELECT tare_kg FROM cylinder_templates ORDER BY id DESC LIMIT 1").fetchone()
    return float(row[0]) if row else 0.0
```

---

## 8. Prediction algorithm — multi-window adaptive

### Design rationale

Simple 2-point linear fails for gas monitoring because:
- A single high-usage day (festival, guests) skews the 7-day rate
- Seasonal shifts (winter vs summer) change baseline over 30 days
- Both short-term responsiveness AND long-term baseline are needed

### Algorithm

```python
# python/services/gas_monitor.py

def _calc_daily_rate(days):
    rows = query_daily_window(days)
    if len(rows) < 2:
        return None
    total_consumed = sum(consumed for _, consumed in rows)
    days_covered = len(rows)
    rate = total_consumed / days_covered
    return rate if rate > 0 else None

def predict_refill_days(current_net_kg):
    rate_7d  = _calc_daily_rate(7)
    rate_30d = _calc_daily_rate(30)

    if rate_7d is None and rate_30d is None:
        return None, True   # no data at all

    # Use whichever windows we have; weight recent data heavier
    if rate_7d and rate_30d:
        weighted_rate = 0.7 * rate_7d + 0.3 * rate_30d
        divergence = abs(rate_7d - rate_30d)
        low_confidence = divergence > 0.2   # habits shifting
    elif rate_7d:
        weighted_rate = rate_7d
        low_confidence = True   # <30 days data — baseline not established
    else:
        weighted_rate = rate_30d
        low_confidence = True   # 7d window missing

    if weighted_rate <= 0:
        return None, True

    days_left = current_net_kg / weighted_rate
    return round(days_left, 1), low_confidence
```

### High-usage day detection

```python
def flag_high_usage(today_consumed_kg):
    rate_30d = _calc_daily_rate(30)
    if rate_30d is None:
        return False
    return today_consumed_kg > 2.0 * rate_30d
```

### Refill detection (call after every 6hr snapshot)

```python
_last_net_kg = None

def check_refill(new_net_kg):
    global _last_net_kg
    if _last_net_kg is not None and (new_net_kg - _last_net_kg) > 5.0:
        insert_refill(pre_net_kg=_last_net_kg, post_net_kg=new_net_kg)
        # Invalidate 7-day window: new cylinder, old rates don't apply
        # daily_aggregates before this timestamp should be ignored in next prediction
        print(f"[GAS] Refill detected: {_last_net_kg:.2f} → {new_net_kg:.2f} kg", flush=True)
    _last_net_kg = new_net_kg
```

### Edge cases — all must be handled

| Condition | Return |
|-----------|--------|
| < 2 daily rows in any window | `(None, True)` |
| weighted_rate ≤ 0 (sensor noise, weight increased) | `(None, True)` |
| 7d and 30d diverge by > 0.2 kg/day | `(days_left, low_confidence=True)` |
| < 7 days of data | `(days_left, low_confidence=True)` |
| Refill happened mid-window | use only post-refill data |

---

## 9. Zephyr deep sleep + RTC wake (STM32U585, 6-hour cycle)

STM32U585 supports STOP2 low-power mode via Zephyr PM subsystem.
Use `k_sleep()` for sketch-level sleep; configure RTC alarm for deep wake.

```cpp
// sketch/sketch.ino — 6-hour RTC wake cycle (CONFIG_PM must be enabled in prj.conf)

#include <zephyr/kernel.h>
#include <zephyr/pm/pm.h>

#define SLEEP_DURATION_SEC  (6 * 3600)

void loop() {
    // Take measurement, send over Bridge
    read_weight_packet();

    // Deep sleep — RTC wakes MCU after interval
    // State across sleep: HX711 reinitialised in setup() on wake
    k_sleep(K_SECONDS(SLEEP_DURATION_SEC));
}
```

Notes:
- HX711 must be re-tared after wake if power was cut — call `scale.tare()` in `setup()`
- `Bridge.begin()` must be called on every wake — resets the UART RPC session
- prj.conf must have `CONFIG_PM=y` and `CONFIG_PM_DEVICE=y`

---

## 10. gas_monitor.py service integration pattern

Service receives bridge + push_evt from main.py at init. Never imports main.py.

```python
# python/services/gas_monitor.py — init signature

_bridge    = None
_push_evt  = None
_last_net_kg = None   # for refill detection

def init(bridge, push_evt):
    global _bridge, _push_evt
    _bridge   = bridge
    _push_evt = push_evt
    _ensure_db()
    print("[GAS_MONITOR] initialized", flush=True)

def _on_measurement_cycle():
    global _last_net_kg
    weight_kg = _get_current_weight()   # latest from Bridge.on weight_event
    if weight_kg is None:
        return
    tare_kg = get_tare_kg()
    net_kg = weight_kg - tare_kg
    insert_reading(weight_kg, net_kg)
    check_refill(net_kg)                # updates _last_net_kg, logs refill event
    _update_daily_aggregate(net_kg)     # writes/updates today's daily_aggregates row
    if net_kg <= config.REFILL_THRESHOLD_KG:
        _push_evt({"event": "gas_refill_alert", "weight_kg": net_kg, "net_kg": net_kg})
    days, low_conf = predict_refill_days(net_kg)
    _push_evt({"event": "gas_prediction", "days_left": days, "low_confidence": low_conf,
               "net_kg": net_kg})
```

```python
# python/main.py — wiring (init only, no logic)

from services import gas_monitor
gas_monitor.init(Bridge, push_evt)
```

---

## 12. Gas analytics — daily aggregation and trend output

### Daily aggregate update (call at every 6hr snapshot)

```python
import time, datetime

def _update_daily_aggregate(current_net_kg):
    today_midnight = int(datetime.datetime.now().replace(
        hour=0, minute=0, second=0, microsecond=0).timestamp())
    # query today's readings to compute avg and consumed
    cutoff = today_midnight
    rows = []
    with sqlite3.connect(config.GAS_DB_PATH) as con:
        rows = con.execute(
            "SELECT net_kg FROM readings WHERE timestamp >= ?", (cutoff,)).fetchall()
    if not rows:
        return
    avg_net = sum(r[0] for r in rows) / len(rows)
    # consumed = first reading today - latest reading
    first_today = rows[0][0]
    consumed = max(0.0, first_today - current_net_kg)
    high = flag_high_usage(consumed)
    insert_daily_aggregate(today_midnight, avg_net, consumed, high)
```

### Trend summary for UI (Socket.IO payload)

```python
def get_trend_summary(current_net_kg):
    days, low_conf = predict_refill_days(current_net_kg)
    rate_7d  = _calc_daily_rate(7)
    rate_30d = _calc_daily_rate(30)
    recent_days = query_daily_window(7)
    return {
        "event":          "gas_trend",
        "net_kg":         round(current_net_kg, 3),
        "days_left":      days,
        "low_confidence": low_conf,
        "rate_7d_kg":     round(rate_7d,  3) if rate_7d  else None,
        "rate_30d_kg":    round(rate_30d, 3) if rate_30d else None,
        "daily_history":  [{"date": d, "consumed_kg": round(c, 3)}
                           for d, c in recent_days],
    }
```

### Socket.IO events for gas UI

| Event | Payload | When sent |
|-------|---------|-----------|
| `gas_prediction` | `days_left, low_confidence, net_kg` | Every 6hr measurement |
| `gas_refill_alert` | `weight_kg, net_kg` | When net_kg < REFILL_THRESHOLD |
| `gas_trend` | `net_kg, days_left, rate_7d, rate_30d, daily_history` | On demand or every 6hr |
| `gas_refill_event` | `pre_net_kg, post_net_kg, timestamp` | When refill detected |

All events also go via `push_evt()` → BLE notify to Flutter app.

---

## 11. Session debugging rules (learned 2026-04-29)

### Linker "undefined reference" after code change
1. Clear BOTH caches before anything else:
   `rm -rf ~/ArduinoApps/APP_NAME/.cache && rm -rf ~/.arduino15/internal`
2. Verify the file on disk is what you expect: `wc -l sketch/sketch.ino && head -5 sketch/sketch.ino`
3. If still failing — read the exact symbol that's undefined, trace to source file

### Local .cpp not being compiled
Symptom: header found (no compile error), but all methods are "undefined reference" at link time.
Cause: Arduino build system only compiles `.cpp` files flat in `sketch/` — subdirectories ignored.
Fix: move `.h` and `.cpp` flat into `sketch/`, use `#include "Lib.h"` (quotes, not angle brackets).

### Library not in Arduino registry (error code 9)
Symptom: `Library 'X' not found`, error code 9 during deploy.
Fix: remove from `sketch.yaml`, place `.h` + `.cpp` flat in `sketch/` as local files.

### Python app crashes at import with ModuleNotFoundError
Diagnose before creating the missing module:
1. Check if CLAUDE.md says the module is intentionally absent
2. Read ALL usages of the module in the importing file (`grep -n "module_name"`)
3. If module is intentionally absent but needed for imports → create a stub with no-op functions
4. Never create a full implementation without understanding why it was removed

### Bridge.provide() return type mismatch
Symptom: compiles fine, Python receives garbled data or exception on `json.loads()`.
Cause: returning a struct or non-String type from a Bridge RPC function.
Fix: return `String` containing JSON, call `json.loads()` on Python side.

### Diagnose before fixing (universal rule)
- Read the exact error line — not the summary, the line
- Identify what is missing or wrong at source level
- Apply one correct fix
- Never try → fail → try another → repeat
- Never guess at a fix without understanding the root cause

---

## Applies to projects
- home-hub (primary)
- Any future App Lab project on AQ2/AQ3 using Bridge RPC, BLE, or SQLite
