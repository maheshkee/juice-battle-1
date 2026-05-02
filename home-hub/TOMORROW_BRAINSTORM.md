# TOMORROW'S SESSION — Brainstorm + Plan
# home-hub weight integration + gas cylinder monitor + advanced features
# Based on: digital-scale working baseline (2026-04-30)

---

## PART 1 — TAKING WHAT WORKS INTO HOME-HUB

### What Works in digital-scale (the golden reference)

```
DT=D7, SCK=D6 — confirmed clean pins
Raw bit-bang — no library, direct GPIO
Bridge.notify() from loop() — MCU pushes every 500ms
Bridge.on() in Python — event listener, no polling
TARE via Bridge.provide_safe("do_tare") — called from UI button
Stability detection — compare two reads, diff < threshold
```

### Migration Plan: digital-scale → home-hub

Step 1: Copy the raw bit-bang functions from digital-scale sketch.ino verbatim
Step 2: Change DT=7, SCK=6 in home-hub sketch.ino
Step 3: Replace Bridge.provide_safe("read_weight_packet") with Bridge.notify("weight_event")
Step 4: Delete weight_poll_loop() from home-hub Python main.py
Step 5: Add Bridge.on('weight_event') listener in main.py
Step 6: Keep TARE as Bridge.provide_safe("do_tare") — UI button triggers it
Step 7: Remove ScaleHX711.cpp/.h — not needed
Step 8: Update sketch.yaml — no libraries needed
Step 9: Deploy and verify weight widget on splash.html updates

### What Might Go Wrong

- Loop timing conflict: home-hub sketch may have other loop() work — check if anything else is in loop()
- Python Docker D-Bus + weight_event conflict: Bridge.on() must be registered before App.run()
- splash.html weight_update handler: verify it accepts the new JSON fields (grams, weight_kg, stable, sensor_ok)
- Tare timing: home-hub setup() order matters — Bridge.begin() first, tare after settle

---

## PART 2 — ACCURATE WEIGHT MEASUREMENT

### Current State
- Cal factor = 420.0f (estimated, not measured)
- Readings approximate — showed ~10g and ~22g in testing
- Load cell is a 20kg cell being used for 5-14kg gas cylinder range

### How to Get Accurate Calibration

The proper calibration procedure:

```
1. Empty scale, tare → 0g
2. Place reference weight of KNOWN value (e.g. 500g, 1kg)
3. Note displayed value → call it D
4. actual_weight → call it A
5. new_cal = 420.0 × (D / A)
6. Update CALIBRATION_FACTOR, redeploy, verify
```

Best reference weights for gas cylinder scale (5-14kg range):
- A sealed 1L water bottle = exactly 1000g
- A 2kg bag of rice/sugar (check label)
- A kitchen scale verified object

### Why Calibration at Range Matters

The HX711 has slight non-linearity. Calibrating at 10g for a 10kg application gives worse accuracy than calibrating at 1-2kg. For gas cylinder monitoring:
- Calibrate with 1kg or 2kg reference minimum
- Verify at two points: 1kg and 5kg if possible
- This gives <1% error across the operating range

### Improving Reading Stability

Current issues:
- Readings jump between values even with weight sitting still
- Stability detection catches this but UI still flickers

Solutions to explore:
1. Increase SAMPLE_COUNT from 5 to 10 — more averaging, slower but smoother
2. Add moving average in Python: keep last N readings, average before pushing to UI
3. Increase STABILITY_THRESHOLD from 5.0f to 10.0f — less sensitive to noise
4. Add deadband: only push new weight if it changed by >1g from last pushed value
5. Mechanical: load cell needs proper mounting with defined support points — bare cell on table is unstable

---

## PART 3 — GAS CYLINDER CONTINUOUS MONITORING

### The Core Question: Continuous vs Triggered?

The cylinder sits on the scale 24/7. The MCU reads continuously at 500ms intervals.
But for gas monitoring we don't need 500ms updates — we need:
- A reading every 6 hours to track consumption trend
- An alert when weight drops below refill threshold (8kg)
- A "refill detected" event when weight suddenly increases

### Architecture Decision: Who Owns the Weight Logic?

Option A — MCU pushes raw weight, Python owns gas logic (RECOMMENDED)
```
MCU: Bridge.notify("weight_event") every 500ms (same as digital-scale)
Python: receives weight_event, runs gas logic:
  - 6hr snapshot: every 21600s, write to SQLite
  - Threshold check: if weight_kg < REFILL_THRESHOLD → alert
  - Refill detection: if weight_kg increases by >2kg → new refill event
  - Trend: compare current vs 6hr-ago reading
```

Option B — MCU does 6hr sleep, wakes to read, pushes result
```
MCU: sleeps in low-power mode, wakes every 6hr, reads, Bridge.notify()
Python: just records what MCU sends
```
Option A is better — MCU stays continuously reading (for UI), Python just samples from the stream.

### How MCU Measures Reduction Without Removing Cylinder

This is the key question. The answer is simple:

```
At time T1: weight = 12.450 kg (stored in SQLite)
At time T2: weight = 11.200 kg (6hr later)
Consumption = T1 - T2 = 1.250 kg over 6 hours
Rate = 1.250 / 6 = 0.208 kg/hour
Estimated empty = current_weight / rate = hours remaining
```

The cylinder never leaves the scale. The tare was set when scale was first installed (empty scale, before cylinder placed). Then cylinder placed → weight = cylinder_weight. Every 6hr snapshot captures the reduction.

### Tare Strategy for Gas Cylinder

Current: tare runs on boot with empty scale
Problem: if board reboots with cylinder on scale, tare captures cylinder weight → all readings show 0

Solution options:
1. Store tare offset in persistent storage (EEPROM/flash on STM32U585) — survives reboot
2. Never auto-tare on boot if weight > 1kg detected — assume cylinder is on scale
3. Manual tare only via UI button — never auto

Best approach for production:
```cpp
// On boot: check if weight > 2kg — if yes, skip tare, restore saved offset
// If weight < 0.5kg — run fresh tare, save offset
// Provide manual TARE button in UI for override
```

### 6-Hour Cycle Implementation (Python side)

```python
import sqlite3, time, threading

def gas_monitor_loop():
    while True:
        time.sleep(21600)  # 6 hours
        weight_kg = get_current_weight()  # from latest weight_event
        record_snapshot(weight_kg)
        check_threshold(weight_kg)

def check_threshold(weight_kg):
    if weight_kg < REFILL_THRESHOLD_KG:
        push_notification("Gas cylinder low: {:.2f}kg remaining".format(weight_kg))

def detect_refill(old_kg, new_kg):
    if new_kg - old_kg > 2.0:  # sudden increase = refill
        log_refill_event(new_kg)
```

---

## PART 4 — ADVANCED FEATURES BRAINSTORM

### From Previous Sessions (already planned)

From documents in project knowledge:
- BT speaker real implementation (D-Bus A2DP)
- Gas dashboard UI on splash.html
- YouTube + weight coexistence on home screen
- Prediction engine: days remaining based on consumption rate
- Refill history: SQLite log of all refill events
- WhatsApp/Telegram alert when gas low

### New Ideas from Today's Learning

**1. Weight calibration UI**
- Add calibration mode to web UI
- User enters known weight, system auto-calculates cal factor
- Stores cal factor persistently so it survives redeploy

**2. Multi-point calibration**
- Calibrate at 2 points (e.g. 1kg and 5kg)
- Linear interpolation between points
- Better accuracy across full range

**3. Temperature compensation**
- HX711 ADC output drifts with temperature
- Add NTC thermistor or use MCU internal temp sensor
- Compensate cal factor based on temperature

**4. Consumption graph on web UI**
- SQLite data → JavaScript chart on splash.html
- Show last 30 days of daily consumption
- Predict empty date

**5. Tare persistence**
- Save tare offset to MCU flash (EEPROM emulation on STM32U585)
- Survives power cycles and redeployments
- Critical for production where cylinder stays on scale forever

**6. Smart refill detection**
- Detect when cylinder is removed (weight drops to ~0)
- Detect when new cylinder placed (weight jumps to 12-14kg)
- Automatically re-tare after refill
- Log refill event with timestamp

---

## PART 5 — WHAT TO AVOID (LESSONS FROM TODAY)

Never:
- Use D2, D3, D4, D5 for HX711 on STM32U585
- Use external HX711 library (ScaleHX711, HX711Zephyr, HX711_ADC)
- Use Bridge.provide_safe() + Python polling for continuous sensor data
- Power HX711 from 3.3V on green PCB clone modules
- Skip delayMicroseconds(1) on any GPIO edge in bit-bang
- Call Bridge functions from multiple threads simultaneously
- Tare automatically on boot without checking if load is present
- Use sed/regex to edit Python files

---

## PART 6 — TOMORROW'S SESSION SEQUENCE

### Morning: Calibration + home-hub migration (2-3 hours)
1. Calibrate digital-scale with known weight, get real cal factor
2. Migrate home-hub sketch: D7/D6 + Bridge.notify()
3. Update home-hub Python: Bridge.on() listener
4. Verify weight widget on splash.html live
5. Commit working state

### Afternoon: Gas monitor architecture (2-3 hours)
6. Design tare persistence strategy (EEPROM vs skip-if-loaded)
7. Re-enable gas_monitor.py 6hr cycles
8. Build gas dashboard UI in splash.html
9. Test refill detection logic

### Evening: Advanced features (if time permits)
10. BT speaker D-Bus A2DP implementation
11. Low gas notification (Telegram or WhatsApp)
12. Consumption trend graph

---

## PART 7 — DIGITAL-SCALE AS PERMANENT REFERENCE

The digital-scale app must be preserved forever as the canonical working example.
Never modify it for other purposes. Copy FROM it, never into it.

Key things it proves:
- HX711 works on AQ3 with D7/D6
- Bridge.notify() architecture works
- Tare via provide_safe() works
- Stability detection works
- WebUI Socket.IO weight display works

If anything breaks in home-hub — digital-scale is the working reference to compare against.
