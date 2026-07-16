# HX711 Calibration Architecture
**Hardware-verified: 2026-05-02 | AQ3 board | STM32U585 + HX711 + 20kg load cell**

---

## The two-variable model

Every weight measurement depends on exactly two values:

```
grams = (raw_value - TARE) / CAL_FACTOR
```

These two variables have fundamentally different lifetimes and sources.

---

## TARE — session variable

**What it is:** Raw ADC reading when the load cell platform has zero load.

**What it depends on:**
- Physical mounting state of the load cell beam
- Ambient temperature (strain gauge resistance changes with temp)
- Power supply stability at startup
- Anything touching or pressing on the platform

**How often it changes:** Every session. Every power cycle. With temperature.

**Typical range on AQ3 hardware:** -12000 to -14000 raw units

**Rule:** Always re-derive tare at the start of every measurement session.
Never load tare from a config file — it will be stale.

**Stability check:** Take two consecutive tare readings. If they differ
by more than 500 raw units (~5g), the platform is not settled. Retry.

---

## CAL_FACTOR — hardware constant

**What it is:** Raw ADC units produced per gram of load. Converts the
sensor's arbitrary unit system into real-world grams.

**What it depends on:**
- Load cell sensitivity (mV/V at rated load) — physical property of the cell
- HX711 gain setting (128 for Channel A — fixed in this project)
- Wiring topology (how many cells connected, how they are wired)
- Supply voltage stability

**How often it changes:** Almost never. Only when:
- Load cell is physically damaged or permanently deformed
- Wiring topology changes (single cell → four cell bridge etc.)
- HX711 gain setting is changed

**Verified value on this hardware:**
```
Single 20kg load cell + HX711 gain 128 = 103.0 raw/g
Verified range across all clean runs: 94-105 raw/g (±5%)
```

**Rule:** Derive once on first boot from a known weight. Store to config.
Load from config on every subsequent boot. Never hardcode in source code.

---

## Wiring topology effect on CAL_FACTOR

This is critical for the gas-cylinder-monitor 4-cell upgrade path:

| Topology | Cells wired to HX711 | CAL_FACTOR |
|----------|---------------------|------------|
| Single cell, gain 128 | 1 of 1 | ~103 raw/g |
| 4 cells, full Wheatstone bridge, 1 HX711 | 4 of 4 | ~103 raw/g |
| 4 cells, only 1 cell wired, 1 HX711 | 1 of 4 | ~412 raw/g |
| 4 cells, 4 HX711s, readings summed | 1 each | each ~412, sum ÷ 4 = ~103 |

**Key insight:** In a full Wheatstone bridge with 4 cells, each cell sees
only 1/4 of the load but contributes its signal additively — the signals
cancel the force division and sensitivity stays the same as a single cell.

---

## Production calibration architecture

### First boot sequence
```
1. Prompt user for known weight (g)
   → Any object whose weight is known from a reliable scale
   → Heavier known weight = more accurate cal_factor
   → Recommended: 200g-2kg range for best accuracy

2. Take tare (empty platform)
   → Stability check: two readings within 500 raw units
   → Use average of two readings

3. Place known weight, take reading
   → Stability check: two readings within 10% of span
   → Sanity check: derived cal_factor within 50% of 103.0
   → If outside range: warn, ask to retry

4. Compute cal_factor
   cal_factor = (raw_w1 - tare) / known_weight_g

5. Store to config file
   ~/ArduinoApps/<app-name>/config.json:
   {
     "cal_factor": 103.02,
     "cal_date": "2026-05-02",
     "cal_weight_g": 500,
     "topology": "single_cell_gain128"
   }

6. Confirm to user: "Calibration complete. cal_factor = 103.02 raw/g"
```

### Every subsequent boot sequence
```
1. Load config.json
   → If missing: run first-boot calibration
   → If cal_factor outside 50-500: warn, suggest recalibration

2. Take fresh tare (empty platform)
   → Stability check always
   → Warn if tare differs >2000 raw from last session
     (may indicate mounting change or damage)

3. Ready to measure
   grams = (raw_value - tare) / cal_factor
```

### Recalibration trigger
User can request recalibration at any time:
- After replacing load cell
- After changing wiring topology
- After physical remounting
- If readings seem systematically off

---

## Stability checks — required at every reading point

These were derived from real failures during experiment 006.
Every reading point must validate before accepting the value.

### Tare stability check
```python
raw_t1 = take_reading()
raw_t2 = take_reading()
if abs(raw_t2 - raw_t1) > 500:
    # platform not settled, retry
    return

tare = (raw_t1 + raw_t2) // 2

# range check
if tare > 0 or tare < -100000:
    # something on platform or hardware fault
    return
```

### W1 (calibration weight) stability check
```python
raw_w1_a = take_reading()
raw_w1_b = take_reading()
span = raw_w1_a - tare

if abs(raw_w1_b - raw_w1_a) > abs(span) * 0.10:
    # still settling, retry
    return

cal_factor = span / known_weight_g

# sanity check against hardware constant
REFERENCE_CAL = 103.0
if cal_factor / REFERENCE_CAL < 0.5 or cal_factor / REFERENCE_CAL > 2.0:
    # hand on scale during reading, or wrong known weight
    return
```

### W2/W3 (measurement readings) stability check
```python
raw_a = take_reading()
raw_b = take_reading()
if abs(raw_b - raw_a) > 2000:  # ~20g threshold
    # scale disturbed during reading, retry
    return

raw = (raw_a + raw_b) // 2
grams = (raw - tare) / cal_factor
```

---

## MCU sketch — golden read function

```cpp
#define DT  7   // D7 ONLY — D2/D3/D4/D5 forbidden (STM32U585 timer conflicts)
#define SCK 6   // D6 ONLY

static long hx711_read_raw() {
    // PRECONDITION: caller must verify DOUT==LOW before calling
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK, HIGH);
        delayMicroseconds(1);           // T3 minimum
        value = (value << 1) | digitalRead(DT);
        digitalWrite(SCK, LOW);
        delayMicroseconds(1);           // T4 minimum
    }
    // 25th pulse: selects Channel A gain 128 for NEXT conversion
    // This pulse also resets HX711 — DOUT goes HIGH at +0ms
    digitalWrite(SCK, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;  // sign extend 24-bit
    return value;
}
```

---

## Event-driven production loop (target architecture)

For gas-cylinder-monitor continuous monitoring:

```cpp
// MCU side — runs in loop() at 10Hz
long last_grams = 0;
const long THRESHOLD_RAW = 824;  // 8g × 103 raw/g

void loop() {
    if (digitalRead(DT) == LOW) {
        long raw = hx711_read_raw();
        long delta = abs(raw - last_raw);
        if (delta > THRESHOLD_RAW) {
            float grams = (raw - tare) / 103.0;
            Bridge.notify("weight_event", String(grams));
            last_raw = raw;
        }
    }
}
```

```python
# Python side
def on_weight_event(data):
    grams = float(data)
    timestamp = datetime.now().isoformat()
    log_event(timestamp, grams)
    print(f"[{timestamp}] Weight: {grams:.1f}g", flush=True)

Bridge.provide("weight_event", on_weight_event)
App.run()
```

**Threshold rule:** Set threshold above the noise floor.
Noise floor (mechanical drift) = ±4g on this hardware.
Recommended threshold = 8-10g minimum.

---

## Config file format (production)

```json
{
  "cal_factor": 103.02,
  "cal_date": "2026-05-02",
  "cal_weight_g": 500,
  "topology": "single_cell_gain128",
  "threshold_g": 8.0,
  "notes": "20kg load cell, AQ3 board, D7/D6 pins"
}
```

---

## Checklist before writing any weight measurement code

- [ ] DT = D7, SCK = D6 — no other pins
- [ ] D2/D3/D4/D5 never used for HX711
- [ ] delayMicroseconds(1) after every GPIO edge
- [ ] noInterrupts() wraps 24-bit read loop
- [ ] 25 total pulses per read (24 data + 1 gain)
- [ ] Tare re-derived fresh every session
- [ ] Cal_factor loaded from config, not hardcoded
- [ ] Stability checks on tare AND every reading
- [ ] Event threshold set above noise floor (min 8g)
- [ ] Bridge.notify() for MCU output — never Monitor.println()
- [ ] Bridge.provide_safe() for handlers blocking >100ms
- [ ] No threading in Python — use user_loop pattern
- [ ] App.run(user_loop=fn) is last line of main.py
