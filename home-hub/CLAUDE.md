# CLAUDE.md — home-hub + digital-scale | AQ3
# Board: Arduino UNO Q AQ3 (4GB) | IP: 192.168.1.161
# Last updated: 2026-04-30 | Read this fully before doing ANYTHING

---

## Board Architecture

```
SSH → MPU (QRB2210, Debian Linux) — Python, BLE, WebUI, App Lab Docker
         ↓ Bridge RPC (Arduino_RouterBridge)
      MCU (STM32U585, Zephyr @ 160MHz) — sketch.ino, GPIO, HX711
```

---

## HX711 — THE CONFIRMED WORKING CONFIGURATION

These facts were proven after a full day of R&D. Never deviate.

| Parameter     | Value       | Why                                              |
|---------------|-------------|--------------------------------------------------|
| DT pin        | D7          | Conflict-free. D2/D3/D4/D5 have timer mux issues |
| SCK pin       | D6          | Conflict-free. All others produced corrupt reads  |
| Library       | NONE        | Raw bit-bang in sketch.ino. No external lib.     |
| Bridge pattern| notify()    | MCU pushes every 500ms. NOT provide_safe+polling  |
| Cal factor    | 420.0f      | Starting point. Tune with known weight.           |
| Power         | 5V          | Green PCB HX711 clones need 5V AVDD              |
| DOUT pullup   | INPUT_PULLUP| Required — HX711 DOUT is open-drain              |

### The Working Bit-Bang Recipe (copy verbatim, never change timing)

```cpp
static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 1 gain pulse = gain 128 (Channel A)
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}
```

### Bridge.notify() Pattern (NOT provide_safe + Python polling)

```cpp
// In loop() — MCU pushes every PUSH_INTERVAL_MS
void loop() {
    static uint32_t last_push = 0;
    if (millis() - last_push < PUSH_INTERVAL_MS) return;
    last_push = millis();
    long raw = hx711_read_average(SAMPLE_COUNT);
    if (raw == LONG_MIN) {
        Bridge.notify("weight_event", String("{\"sensor_ok\":false}"));
        return;
    }
    float grams = (float)(raw - g_tare_offset) / CALIBRATION_FACTOR;
    // ... build JSON ...
    Bridge.notify("weight_event", json);
}
```

```python
# In Python main.py — listen, don't poll
@Bridge.on('weight_event')
def on_weight(data):
    ui.send_message('weight_update', data)
```

---

## Reference App — digital-scale (WORKING, DO NOT BREAK)

```
~/ArduinoApps/digital-scale/
├── sketch/sketch.ino      ← THE reference. DT=7, SCK=6, Bridge.notify()
├── sketch/sketch.yaml     ← Arduino_RouterBridge only
├── python/main.py         ← Bridge.on('weight_event') listener
├── assets/index.html      ← WebUI: kg, g, STABLE, TARE button
└── assets/socket.io.min.js
```

When in doubt about HX711 implementation — copy from digital-scale sketch verbatim.

---

## App Status

| App | Status | Notes |
|-----|--------|-------|
| digital-scale | ✅ WORKING | Live weight, tare, stable detection |
| home-hub BLE | ✅ WORKING | Advertising as YT-Display |
| home-hub YouTube | ✅ WORKING | Flutter app control |
| home-hub weight widget | ⚠ NEEDS UPDATE | Must use D7/D6 + Bridge.notify() |
| home-hub gas monitor | ❌ DEFERRED | 6hr cycles not active |
| home-hub BT speaker | ❌ STUB | bt_manager.py all no-ops |

---

## Gas Monitor — Smart System Design

This is NOT a simple weight scale. It is an advanced smart gas monitoring system for LPG cylinders.

### What it does

| Feature | Description |
|---------|-------------|
| Live weight | 500ms MCU readings → real-time kg/g display |
| 6hr snapshot | Every 6 hours Python records weight to SQLite |
| Daily usage | kg consumed per day from snapshot deltas |
| Weekly trend | Rolling 7-day avg daily consumption |
| Monthly trend | Rolling 30-day avg daily consumption |
| High-usage flag | Days where consumption > 2× 30-day baseline |
| Days-left prediction | Weighted 7d+30d avg → days until refill needed |
| Refill detection | Weight jump >5kg → new cylinder event, reset learning |
| Low-gas alert | BLE push + WebUI alert when net_kg < REFILL_THRESHOLD |

### Prediction Algorithm — Multi-Window Adaptive

NOT a simple 2-point linear extrapolation. Learning from history:

```
7-day avg  = total_consumed_7d / 7      ← responsive to recent habits
30-day avg = total_consumed_30d / 30    ← baseline, filters anomaly days

weighted_rate = (0.7 × 7day_avg) + (0.3 × 30day_avg)
days_left = net_kg_remaining / weighted_rate

confidence = HIGH  if |7day_avg - 30day_avg| < 0.2 kg/day
           = LOW   if diverging (seasonal shift, new household member, guests)
```

More data = better accuracy. First 7 days: low confidence. After 30 days: high confidence.

### High-Usage Day Detection

```
baseline_rate = 30-day rolling avg (kg/day)
today_consumed = today_start_weight - current_weight
if today_consumed > 2.0 × baseline_rate:
    flag as HIGH_USAGE_DAY
```

Surfaces: festival cooking, guests, cold weather heating, equipment malfunction.

### Refill Detection

```
if (new_weight - prev_snapshot_weight) > 5.0 kg:
    → log refill_history (timestamp, pre_net, post_net)
    → invalidate learning window (don't let pre-refill trend bias new cylinder)
    → recalculate baseline from fresh data only
```

### SQLite Schema — Full

```sql
readings (id, timestamp INTEGER, weight_kg REAL, net_kg REAL)
daily_aggregates (id, date_epoch INTEGER, avg_net_kg REAL, consumed_kg REAL)
refill_history (id, timestamp INTEGER, pre_net_kg REAL, post_net_kg REAL)
cylinder_templates (id, brand TEXT, tare_kg REAL)
```

### Target Cylinder Types (Indian market)

| Type | Gross | Tare | Net gas |
|------|-------|------|---------|
| 14.2 kg (standard) | ~28 kg | ~13.8 kg | 14.2 kg |
| 5 kg (small) | ~10.5 kg | ~5.5 kg | 5 kg |
| 19 kg (commercial) | ~35 kg | ~16 kg | 19 kg |

---

## home-hub File Map

```
~/ArduinoApps/home-hub/
├── CLAUDE.md                    ← this file
├── deploy.sh                    ← always use this
├── python/
│   ├── main.py                  ← weight_poll_loop here (NEEDS UPDATE to Bridge.on)
│   ├── config.py                ← REFILL_THRESHOLD_KG=8.0, GAS_DB_PATH
│   ├── bt_manager.py            ← STUB — do not delete
│   ├── ble_gatt_serve.py        ← DO NOT TOUCH
│   ├── queue_engine.py          ← DO NOT TOUCH
│   ├── local_engine.py          ← DO NOT TOUCH
│   └── services/gas_monitor.py  ← implemented, deferred
├── sketch/
│   ├── sketch.ino               ← NEEDS UPDATE: DT=7 SCK=6 + Bridge.notify()
│   ├── ScaleHX711.cpp/.h        ← CAN BE DELETED after migration
│   └── sketch.yaml
└── assets/
    └── splash.html              ← weight widget in #home div
```

---

## Critical Rules — Never Violate

1. HX711 DT = D7 ONLY. SCK = D6 ONLY. Any other pin = corrupt/no reads.
2. Bridge.notify() from loop() for weight. NOT Bridge.provide_safe() + Python polling.
3. No external HX711 library. Raw bit-bang only. digital-scale proves this.
4. BLE scan = le transport ONLY. Auto transport kills BT adapter on QRB2210.
5. Never add sockets: to app.yaml.
6. bt_manager.py EXISTS as stub — do not delete, do not recreate from scratch.
7. Never use sed/regex to edit Python files — use python3 read/replace/write.
8. JCTL = 1.8V ONLY. 3.3V on JCTL = hardware damage.
9. No hardcoded paths, usernames, hostnames in any script.
10. delayMicroseconds(1) after EVERY GPIO edge in HX711 bit-bang. Both HIGH and LOW.

---

## BLE UUIDs (never change)

- Service:  a01c0000-0000-0000-0000-000000000000
- CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
- EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)

---

## Deploy Commands

```bash
# Normal deploy
cd ~/ArduinoApps/home-hub && bash deploy.sh
cd ~/ArduinoApps/digital-scale && bash deploy.sh

# Force full recompile
rm -rf .cache && rm -rf ~/.arduino15/internal && bash deploy.sh

# Watch logs
arduino-app-cli app logs user:home-hub --follow
arduino-app-cli app logs user:digital-scale --follow

# Docker fallback (if app-cli logs empty)
sudo docker logs $(sudo docker ps | grep home-hub | awk '{print $1}') 2>&1 | tail -50
```

---

## Next Session Priorities

### Phase 1 — Hardware baseline (do first)
1. Calibrate digital-scale with known weight → real CALIBRATION_FACTOR (not 420.0f estimate)
2. Migrate home-hub sketch: DT=7, SCK=6 + Bridge.notify() copied from digital-scale verbatim
3. Update home-hub main.py: remove weight_poll_loop, add Bridge.on('weight_event') listener
4. Tare persistence: skip auto-tare on boot if weight > 2kg (cylinder already on scale)

### Phase 2 — Gas monitor smart features
5. Re-enable 6hr snapshot cycle: time.sleep(21600) + SQLite writes
6. Implement daily_aggregates table: Python aggregates snapshots at midnight
7. Multi-window prediction: 7-day + 30-day weighted average (see algorithm in Gas Monitor section)
8. High-usage day detection: flag days > 2× 30-day baseline
9. Refill detection: weight jump > 5kg → log to refill_history, reset learning window

### Phase 3 — UI + alerts
10. Gas dashboard in splash.html: days_left, weekly trend, high-usage flags, refill history
11. Low-gas BLE alert: push_evt when net_kg < REFILL_THRESHOLD
12. BT speaker: D-Bus A2DP (never bluetoothctl)

---

## Things to Revert Before Production

| File | Current | Should be |
|------|---------|-----------|
| home-hub python/main.py | time.sleep(30) gas cycle | time.sleep(21600) |
| home-hub sketch/sketch.ino | DT=4, SCK=3 (old) | DT=7, SCK=6 |

---

## Git State

Repo: git@github.com:gratiantechnologies/project13.git  
Branch: main  
Uncommitted: home-hub sketch changes, digital-scale new app  

```bash
git add -A
git commit -m "feat: digital-scale working, DT=D7 SCK=D6, Bridge.notify architecture"
git push
```

---

## HX711 + Load Cell — Confirmed Working (2026-05-01)

### Hardware Setup (CRITICAL — never change)
- DT = D7 (PB2) ONLY
- SCK = D6 (PB1) ONLY
- No external library — raw bit-bang only
- delayMicroseconds(1) after EVERY GPIO edge
- CALIBRATION_FACTOR = 100.0f (confirmed 2026-05-01 with 10g/20g/30g blocks)
- SAMPLE_COUNT = 5, TARE_SAMPLE_COUNT = 20, STABILITY_THRESHOLD = 5.0f
- PUSH_INTERVAL_MS = 500

### Load Cell Wiring (confirmed working)
- Red   → E+
- Black → E-
- White → A-
- Green → A+
- HX711 VCC → 5V pin (NOT 3.3V)
- HX711 GND → GND

### Load Cell Mounting (CRITICAL)
- One end FIXED (clamped/screwed to surface)
- Other end FREE (hangs over edge, nothing touching it)
- Weight placed on free end only
- If both ends rest on surface → corrupt readings (0.0/4.6/25.1 cycling)

### Architecture (confirmed working)
- MCU: Bridge.notify("weight_event", json) from loop() every 500ms
- Python: Bridge.provide("weight_event", handler) — NOT Bridge.on() (does not exist)
- JSON fields: grams (float), weight_kg (float), stable (bool), sensor_ok (bool)

### Calibration Procedure
1. Mount load cell properly (one end fixed, one end free)
2. Power on, wait for tare to complete in setup()
3. Note RAW values with nothing on scale (empty baseline)
4. Place known weight, note RAW values
5. net_units = RAW_with_weight - RAW_empty
6. cal_factor = net_units / actual_grams
7. Update CALIBRATION_FACTOR in sketch.ino, redeploy

### Debugging Reference
- RAW = -1 → HX711 not ready when MCU read it (add to filter in hx711_read_average)
- RAW = 0x7FFFFF → pin conflict (wrong pin, timer mux issue)
- RAW = 0x800000 → pin conflict (wrong pin, timer mux issue)
- Readings unresponsive to weight → check mounting (free end must be free)
- Ghost fixed value repeating → free end touching surface intermittently

### Working Reference
sketch/sketch_working_reference.ino — DO NOT MODIFY
digital-scale app at ~/ArduinoApps/digital-scale/ — DO NOT MODIFY
