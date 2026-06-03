# Gas Cylinder Monitor — Technical Specification
# home-hub service | Arduino UNO Q AQ3 | Updated: 2026-04-30

---

## 1. Hardware Specification

| Component | Model | Specification | Notes |
|-----------|-------|--------------|-------|
| Load cell | YZC-161A | 20kg capacity, 2mV/V rated output, ±0.05% accuracy, ±0.05% repeatability | Aluminum alloy, compression type |
| ADC amplifier | HX711 module | 24-bit, gain 128 (channel A), 2×10Hz output rate, 1.5mA active / 10μA sleep | Industry standard for strain gauges |
| DT pin | D4 (PA12) | Input, no timer conflict | D2/D3 have PWM mux conflict in Zephyr — permanently unusable for INPUT |
| SCK pin | D3 (PB0) | Output only | Timer conflict acceptable on OUTPUT |
| MCU power | 3.3V from JDIGITAL header | VCC for HX711 | Do NOT use 5V — JDIGITAL is 3.3V |
| Bridge | LPUART1 | 9600 baud, MSGPACK | Bridge.call() blocks in Docker; Bridge.notify() is fire-and-forget |

### Load Cell Wiring

| Load cell wire | HX711 terminal |
|---------------|----------------|
| Red (E+) | E+ |
| Black (E-) | E- |
| Green (A+) | A+ |
| White (A-) | A- |

If readings are negative: A+ and A- are swapped, or load cell is upside down.

---

## 2. MCU Bridge RPC Interface

The MCU exposes these functions via `Bridge.call()`. All return types are primitives or JSON String — no structs.

| Function | Return type | Return value |
|----------|------------|--------------|
| `read_weight_packet` | JSON String | `{"weight_kg": float, "raw_kg": float, "stable": bool, "sensor_ok": bool}` |
| `get_raw` | float | Raw ADC count before scale factor — calibration use only |
| `read_battery_pct` | int | 0–100 |
| `set_led_red` | none | bool arg |
| `set_led_green` | none | bool arg |

Python call pattern:
```python
result = json.loads(bridge.call("read_weight_packet"))
weight_kg = result["weight_kg"]
stable    = result["stable"]
sensor_ok = result["sensor_ok"]
```

---

## 3. MCU Responsibilities

- Read HX711 via bit-bang GPIO (custom Zephyr implementation — no shiftIn())
- Average `SENSOR_SAMPLE_COUNT` (20) samples per reading
- Detect stability: if variance across samples exceeds threshold → `stable=false`
- Apply calibration factor (`cal`) to convert raw ADC counts to kg
- Tare (zero offset) runs once at boot on empty scale
- Expose `read_weight_packet` Bridge RPC returning JSON String
- Expose `get_raw` Bridge RPC for calibration mode
- Deep sleep between readings — MCU wakes on 6hr RTC timer (production) or on demand (demo)

### HX711 Bit-Bang Timing (critical)

Data is valid on the **falling edge** of SCK. Read DOUT after SCK goes LOW:
```cpp
digitalWrite(PD_SCK, HIGH);
delayMicroseconds(1);
digitalWrite(PD_SCK, LOW);
delayMicroseconds(1);
data = (data << 1) | digitalRead(DOUT);   // after falling edge
```
24 clock pulses = one 24-bit reading. Extra pulses set gain for next read: 1 pulse = gain 128.

### Calibration

```
cal = (raw_count_at_known_weight) / known_weight_kg
```
Set `cal = 1.0` to read raw ADC counts. Place known weight, read raw value, compute cal. `cal = 1.0` is TEMPORARY — revert to real value before production.

---

## 4. Linux Responsibilities

| Task | Implementation |
|------|---------------|
| Read sensor | `gas_monitor._read_sensor()` → Bridge.call("read_weight_packet") with 3s timeout, 3 retries |
| Store reading | SQLite `readings` table: timestamp, weight_kg, net_kg |
| Compute net weight | `net_kg = weight_kg - tare_kg` (tare from `cylinder_templates` table) |
| Predict days left | `days_left = net_kg / daily_rate` where daily_rate = 7-day rolling avg |
| Refill detection | Weight delta > 8kg between consecutive readings |
| Tare correction | Weighted avg: 70% previous tare + 30% inferred (from pre-refill minimum) |
| Push to screen | Socket.IO `weight_update` event → splash.html weight widget |
| Push to phone | BLE EVT `gas_status`, `gas_refill_alert`, `gas_prediction` |
| Alert | Push EVT when `net_kg <= REFILL_THRESHOLD_KG` (currently 8.0kg) |

---

## 5. Measurement Cycle

**Production target:** Every 6 hours, clock-aligned at 08:00, 14:00, 20:00, 02:00.

**Current state (v0.1 demo):** Polling loop every 2 seconds. `time.sleep(30)` in main.py gas cycle. Both must be reverted before production.

| Step | What happens |
|------|-------------|
| T+0s | MPU triggers `_on_measurement_cycle()` |
| T+1s | Calls `bridge.call("read_weight_packet")` — 3s timeout |
| T+2s | MCU wakes, reads HX711 20 times, averages, returns JSON |
| T+3s | MPU receives packet, validates sensor_ok and stable flags |
| T+4s | SQLite INSERT into readings |
| T+5s | Compute net_kg, check threshold, compute days_left prediction |
| T+6s | Push `weight_update` Socket.IO → splash.html |
| T+7s | Push `gas_prediction` BLE EVT → Flutter app |
| T+8s | Sleep until next cycle (21600s production / 30s demo) |

---

## 6. Accuracy Targets

| Phase | Prediction accuracy | Condition |
|-------|-------------------|-----------|
| v0.1–v0.2 | N/A (display only) | Calibration + storage only |
| v0.3 (first 2 weeks) | ±3–4 days | Template tare, system learning consumption |
| v0.3 (after 1–2 cycles) | ±2 days | Tare correction applied, consumption pattern learned |
| v1.0+ | ±2 days | Consistent with established pattern |

Minimum readings before prediction is valid: **4 readings** (MIN_READINGS_FOR_PREDICTION).

---

## 7. Power Budget

Mains-powered for v1.0. Battery operation is future scope.

| Processor | State | Current | Duration/day | Energy/day |
|-----------|-------|---------|-------------|-----------|
| STM32U585 | Active (reading) | 80mA | 1 min | 1.3mAh |
| STM32U585 | Deep sleep | 20μA | 23h 59m | 48mAh |
| QRB2210 | Active (processing) | 500mA | 5 min | 42mAh |
| QRB2210 | Idle / sleep | 50mA | ~23h 55m | ~480mAh |
| HX711 | Active | 1.5mA | 1 min | 25μAh |
| HX711 | Sleep | 10μA | 23h 59m | 240μAh |
| **Total** | | | | **~573mAh/day** |

Battery estimate if battery-powered: 4× AA alkaline (2500mAh) ≈ 4–5 days. Not suitable for v1.0 standalone use. Acceptable if Linux processor duty-cycled aggressively.

---

## 8. SQLite Schema

File: `data/gas_monitor.db` — auto-created on first run.

```sql
CREATE TABLE readings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   INTEGER NOT NULL,   -- Unix epoch seconds
    weight_kg   REAL    NOT NULL,   -- raw weight including tare
    net_kg      REAL    NOT NULL    -- weight_kg - tare_kg at time of reading
);

CREATE TABLE refill_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    detected_at     INTEGER NOT NULL,
    weight_before   REAL,
    weight_after    REAL,
    tare_estimate   REAL
);

CREATE TABLE predictions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    calculated_at   INTEGER NOT NULL,
    gas_left_kg     REAL,
    days_left       REAL,
    avg_daily_use   REAL,
    confidence      REAL
);

CREATE TABLE cylinder_templates (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    brand       TEXT    NOT NULL,
    tare_kg     REAL    NOT NULL,
    capacity_kg REAL    NOT NULL
);

-- Seed data (insert once at DB init)
INSERT INTO cylinder_templates VALUES (1, 'Indane 14.2kg',     15.5, 14.2);
INSERT INTO cylinder_templates VALUES (2, 'HP Gas 14.2kg',     15.7, 14.2);
INSERT INTO cylinder_templates VALUES (3, 'Bharat Gas 14.2kg', 15.3, 14.2);
INSERT INTO cylinder_templates VALUES (4, 'Indane 5kg',         6.5,  5.0);
INSERT INTO cylinder_templates VALUES (5, 'Indane 19kg',       15.5, 19.0);
```

Tare source: **`cylinder_templates` table only.** Never hardcode tare values in Python or sketch code.

---

## 9. BLE Interface (Gas Monitor Commands)

### CMD (phone → board)

| Command | Action |
|---------|--------|
| `GAS_STATUS` | Trigger immediate reading + push gas_status EVT |
| `GAS_HISTORY:N` | Push last N readings as EVT |
| `GAS_TARE` | Re-tare scale (must be empty) |
| `GAS_CAL:<value>` | Set calibration factor (dev use) |

### EVT (board → phone)

| Event | When | Key fields |
|-------|------|-----------|
| `gas_status` | Every cycle or on demand | weight_kg, net_kg, days_left, last_read |
| `gas_refill_alert` | net_kg ≤ REFILL_THRESHOLD_KG | weight_kg |
| `gas_prediction` | Every cycle | days_left (float or null) |
| `gas_refill` | Refill detected | weight_before, weight_after |

---

## 10. Locked Decisions

These are confirmed and must not be re-debated without explicit approval.

| Decision | Value | Reason |
|----------|-------|--------|
| Load cell | 1× YZC-161A 20kg | Prove concept. Upgrade to 4-cell in v1.5. |
| ADC | HX711 24-bit, gain 128 | Industry standard for 2mV strain gauges |
| DT pin | D4 (PA12) | D2/D3 have Zephyr PWM timer mux conflict |
| Sample count | 20 | Stable average, MCU awake < 1 min |
| Cycle interval | 6 hours | 4 readings/day, sufficient for gas monitoring |
| Communication | Bridge RPC → JSON String | Only supported return type for structs |
| Storage | SQLite, local only | No cloud in v1.0 |
| Tare source | cylinder_templates table | Never hardcode |
| Refill detect | > 8kg weight jump | Always valid for India replacement model |
| Alert threshold | 5 days remaining | Enough lead time for India delivery |
| Weight unit | kg everywhere internally | Convert only at display layer |
| Prediction | 7-day rolling average | Captures weekly patterns, simple and reliable |
