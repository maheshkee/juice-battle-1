# PLAN.md
# Master Plan — Arduino UNO Q AQ3 Projects
# Last updated: 2026-05-06
# Rule: update this file at the end of every session

---

## Active Board

AQ3 at 192.168.1.161 (password: arduino)

---

## Overall Goal

Build a production gas cylinder monitor for Indian households.
Secondary products: motion-sensor-webui, youtube-display — parked until
gas monitor experiments conclude.

---

## Critical Path

```
003 noise characterisation ✅ COMPLETE
    ↓
003 cleanup (remove DBG lines)
    ↓
004 modular sketch refactor
    ↓
005 calibration linearity
    ↓
006B measured removal ← POSTPONED (no measuring cup)
    ↓
007B threshold stress test ← PROVES false positive rate (currently theoretical)
    ↓
008 temperature drift
    ↓
009 long-run stability
    ↓
010 power cycle recovery
    ↓
011 on-boot calibration flow → config.json
    ↓
012 hybrid architecture
    ↓
home-hub integration
    ↓
gas-cylinder-monitor v0.1
```

---

## What We Know vs What We Don't

### ✅ PROVEN on hardware (AQ3, 2026-05-05)

```
Noise STD range     : 1.33–2.36g (same board, same day, two runs)
Self-computed threshold works : 2.38–4.23g, adapts correctly per session
Detector validated  : TRIGGERED=0 on stable weight, TRIGGERED=1 on weight change
Self-characterise essential : 2× STD variation proves hardcoding is wrong
double = broken on STM32U585 : float only in all MCU sketches
wait_ready = 400ms  : tuned for AQ3 under Bridge load
```

### 📐 DERIVED (calculated from documented sources, not yet measured)

```
Burn rate           : 3.15g/min (14.2kg ÷ 30 days ÷ 2.5hr ÷ 60min)
Min event estimate  : 16g (tea, 5 min × 3.15g/min)
Detection margin    : 3.8–6.7× (16g ÷ threshold range)
```

**16g is a working design estimate. It is NOT a measured fact.**
Experiment 006B will determine the actual minimum detectable removal.

### ❓ PENDING (requires experiment)

```
Actual min detectable removal   → experiment 006B (postponed — bring measuring cup)
Actual false positive rate      → experiment 007B
Temperature drift magnitude     → experiment 008
Threshold stability over 6hr    → experiment 009
Cal_factor linearity            → experiment 005
```

---

## Calibration Architecture — LOCKED (2026-05-06)

### The three quantities the system must know

```
1. Tare       — what does "empty platform, no cylinder" read in raw?
2. Cal factor — how many raw ADC units = 1 gram?
3. Noise      — what is the noise floor of this environment right now?
```

### When each is measured

| Quantity    | When measured                        | Stored in       |
|-------------|--------------------------------------|-----------------|
| Tare        | First install + cylinder replacement | config.json     |
| Cal factor  | First install (bootstrap) → refined  | config.json     |
| Noise/STD   | Every boot (environment changes)     | RAM only        |

### Tare flow

Tare is NOT measured on every normal boot. It is a setup-time operation.

```
Tare measured at:
1. First install      — before cylinder placed, platform only
2. Cylinder replacement — old cylinder removed, before new one placed

Normal boot → read tare_raw from config.json
```

**Why tare cannot be permanently fixed:**
- Different cylinder brands have different empty weights (±700g between brands)
- Platform may shift or get damaged
- User may add/remove something from platform

**Tare result struct (locked):**
```cpp
struct TareResult {
    bool     success;       // clean tare achieved?
    float    tare_raw;      // best available tare value
    float    spread_raw;    // actual spread achieved
    enum     quality;       // GOOD / DEGRADED / FAILED
    int      attempts;      // how many attempts needed
};
```

**Tare retry strategy — adaptive backoff (no halt in production):**
```
Attempt 1: measure, check spread → FAIL → wait 2s
Attempt 2: measure, check spread → FAIL → wait 10s
Attempt 3: measure, check spread → FAIL → wait 30s
Attempt 4: measure, check spread → FAIL → wait 60s
Attempt 5: measure, check spread → FAIL → use DEGRADED tare
```

On persistent failure:
- Track attempt with lowest spread
- Use lowest-spread attempt as degraded tare
- Flag: tare_quality = "DEGRADED"
- Dashboard shows: "Sensor calibrating — readings may be approximate"
- Retry tare silently in background every 5 minutes
- Recover automatically when environment settles
- If spread always > 3× threshold across all attempts → flag "Check load cell connection"

**Tare spread threshold — NOT hardcoded:**
```
Current: 600 raw = 5.62g (empirical, from digital-scale era)
Problem: 600 was picked on a different board/environment
         If env noise STD = 4g, spread will always exceed 600 → infinite retry

Correct approach (implement in 004):
    spread_threshold_raw = N × noise_std_raw × factor
    Derived from noise characterisation that runs on every boot
    Adapts to environment automatically
```

### Cal factor flow

**Two approaches — both locked:**

**Approach A — User input (first install bootstrap)**
```
User reads stamped empty weight off cylinder collar
User inputs value into dashboard
System has: tare_raw (just measured) + raw_with_full_cylinder (just measured)
cal_factor = (raw_with_full_cylinder - tare_raw) / (14200 + stamped_empty_weight_g)

Advantage: immediate, accurate
Problem: not all cylinders have readable stamps
         cylinder-to-cylinder variation within same brand exists
```

**Approach B — Brand average bootstrap (fallback for first install)**
```
User selects brand: HP / Bharat / Indane
System uses known average empty weight for that brand:
    HP Gas    ≈ 15,500g empty
    Bharat    ≈ 15,000g empty
    Indane    ≈ 14,800g empty

Error introduced: ±200-400g per cylinder within same brand
On 14,200g net gas: ~1-2% cal_factor error
Acceptable for v0.1 bootstrap — replaced by precise value after first cycle
```

**Approach C — Self-derived cal factor from 30-day gas consumption (v0.3+)**
```
System records raw_full at cylinder install
System records raw_empty when user taps "Cylinder Empty"
Problem: user replaces at 95-98% empty, not 100%

Solution: trend line extrapolation
    System has 120 weight readings over 30 days (6hr intervals)
    Fit a line through all readings
    Extrapolate where weight = tare_raw (true empty)
    raw_true_empty = extrapolated value

cal_factor = (raw_full - raw_true_empty) / 14200g

Advantage:
    - No user input ever again
    - Immune to cylinder-to-cylinder variation
    - Works regardless of when user replaces cylinder
    - Trend line slope = household burn rate (personalised, not average)
```

**Bootstrap then refine lifecycle:**
```
Day 0       : brand average bootstrap cal_factor
              2-minute setup, device works immediately
Day ~30     : user taps "Cylinder Empty"
              system extrapolates true empty from trend
              computes precise cal_factor
              overwrites config.json silently
Day 30+     : accurate, self-derived, no user input ever again
              every replacement recalibrates automatically
```

**Cal factor sanity bounds:**
```
cal_factor_min = 50.0   raw/g  (below = hardware problem)
cal_factor_max = 300.0  raw/g  (above = wrong weight entered)
```

**Cal result struct (locked):**
```cpp
struct CalResult {
    bool    success;
    float   cal_factor;
    float   raw_delta;         // raw_with_weight - tare_raw
    float   known_weight_g;    // what was used as reference
    enum    quality;           // GOOD / OUT_OF_RANGE / NEGATIVE / UNSTABLE
    char    error_msg[64];     // human readable diagnosis
};
```

**Cal failure messages:**
```
NEGATIVE cal_factor  → "Place weight AFTER tare completes"
TOO LOW cal_factor   → "Is weight placed on scale? Check placement"
TOO HIGH cal_factor  → "Check weight value entered — seems incorrect"
UNSTABLE             → "Keep scale still during calibration"
```

**Cal factor variation — why it matters:**
```
Measured range on AQ3: 100–107 raw/g = 6.5% variation
On 14,200g cylinder: 923g error if ignored
Causes: temperature (load cell resistance), mechanical creep, mounting stress
Must recalibrate on every cylinder replacement — not just first install
```

### Noise characterisation flow

```
Runs: every boot (after reading config.json, before RUNNING)
Purpose: derive threshold_g for THIS environment RIGHT NOW
Output: threshold_g stored in RAM only (not config.json — remeasured each boot)

Boot sequence (normal):
    read config.json → NOISE_CHAR → RUNNING

Boot sequence (first install / cylinder replacement):
    TARE_MEASURE → NOISE_CHAR → CAL_MEASURE → write config.json → RUNNING
```

### Complete product lifecycle (locked)

```
FIRST INSTALL
→ User places empty platform (no cylinder)
→ System measures tare_raw (adaptive retry)
→ System runs noise characterisation
→ User selects brand OR inputs stamped empty weight
→ User places full cylinder
→ System records raw_full
→ System computes bootstrap cal_factor
→ Saves tare_raw, cal_factor, raw_full to config.json
→ RUNNING

NORMAL BOOT
→ Read tare_raw, cal_factor, raw_full from config.json
→ Noise characterisation (fresh, every boot)
→ RUNNING immediately

CYLINDER EMPTY EVENT
→ User taps "Cylinder Empty" in dashboard
→ System saves raw_empty
→ System fits trend line through 30-day history
→ Extrapolates raw_true_empty
→ Computes precise cal_factor = (raw_full - raw_true_empty) / 14200
→ Computes empty_cylinder_g as bonus (brand verification)
→ Overwrites cal_factor in config.json
→ Prompts: "Place new cylinder when ready"

CYLINDER REPLACEMENT
→ Old cylinder removed (user confirms in dashboard)
→ System measures new tare_raw
→ Noise characterisation
→ User places new full cylinder
→ System records new raw_full
→ RUNNING with precise cal_factor from previous cycle
```

---

## Modular Sketch Architecture — LOCKED (2026-05-06)

**Target structure (Experiment 004):**
```
sketch/
├── sketch.ino     ← state machine ONLY — no sensor logic here
├── hx711.h/.cpp   ← bit-bang read, wait_ready, all 4 corrupt filters
├── tare.h/.cpp    ← adaptive retry tare, returns TareResult
├── noise.h/.cpp   ← 200-sample characterisation, threshold derivation
└── cal.h/.cpp     ← cal_factor derivation, returns CalResult
```

**Why modular (locked reasons):**
```
1. Scalability     — 4 load cells: instantiate hx711.cpp 4 times, not 4× code
2. Isolation       — tare fails → open tare.cpp only, not 300 lines of mixed code
3. Single source   — hx711.cpp shared across ALL experiments AND home-hub
                     fix once → fixed everywhere
4. One .ino rule   — Arduino compiles all .cpp in sketch folder automatically
5. State machine purity — sketch.ino reads result structs, routes flow
                          never knows internal logic of any module
```

**Module contract (locked):**
Every module returns a result struct containing:
```
value     → the computed number
quality   → GOOD / DEGRADED / FAILED (never just bool)
diagnosis → what went wrong and why (human readable)
```

State machine reads quality and routes. Never reads internals.

---

## Experiment Queue

### ✅ COMPLETE

| # | Name | Key result |
|---|------|-----------|
| 003 | noise-characterisation | STD=1.33–2.36g, THRESHOLD=2.38–4.23g, detector validated |

### 🔜 NEXT SESSION (priority order)

| # | Task | Purpose | Need |
|---|------|---------|------|
| 1 | 003 cleanup | Remove DBG lines, remove delay(1) from sketch | CLI only |
| 2 | 004 | Modular sketch refactor | hx711/tare/noise/cal as .h/.cpp | Nothing extra |
| 3 | 005 | Calibration linearity | Verify cal_factor across 158g, 300g, 500g | Known weights |
| 4 | 007B | Threshold stress test | Count false positives over 30 min | 30 min uninterrupted |
| 5 | 006B | Measured water removal | ACTUAL minimum detectable removal | **BRING MEASURING CUP** |

### 📋 QUEUED (after above)

| # | Name | Dependency |
|---|------|-----------|
| 008 | temperature-drift | After 007B |
| 009 | long-run-stability (6hr) | After 008 |
| 010 | power-cycle-recovery | After 009 |
| 011 | on-boot-calibration-flow | After 010 |
| 012 | hybrid-architecture | After 011 |

---

## Experiment 006B — Measured Water Removal (POSTPONED)

**Bring next session: measuring cup or syringe**

**Protocol:**
1. Place container of water (~500g) on scale
2. Confirm stable baseline — TRIGGERED=0
3. Remove water in steps: 50g, 30g, 20g, 16g, 10g, 5g
4. Each step: wait for delta to stabilise, record TRIGGERED result
5. Find boundary — smallest removal that reliably triggers

**Output:** Actual minimum detectable removal replaces 16g estimate

---

## Experiment 007B — Threshold Stress Test

**Protocol:**
1. Place stable weight on scale
2. Run DELTA_RUNNING for 30 minutes
3. Count TRIGGERED=1 events with no weight change
4. Target: < 2 false triggers per hour

---

## Gas Cylinder Monitor — Product Roadmap (updated 2026-05-06)

| Version | Scope | Status |
|---------|-------|--------|
| v0.1 | HX711 reading, self-characterising boot, brand-average bootstrap cal, weight widget | Experiments phase |
| v0.2 | 6hr measurement cycle, SQLite storage, days_left from hardcoded 473g/day | After experiments |
| v0.3 | Trend line from history, extrapolated true empty, precise self-derived cal_factor, personalised burn rate, accurate days_left | After v0.2 |
| v0.4 | BLE alert when days_left < 5 | After v0.3 |
| v0.5 | Refill detection (>8kg jump) | After v0.4 |
| v1.0 | Complete sellable product | — |
| v1.5 | 4-cell upgrade, improved BLE | — |
| v2.0 | Smart alerts, anomaly detection | — |
| v3.0 | Multi-cylinder IoT network | — |

---

## Data Intelligence Roadmap — LOCKED (2026-05-06)

Once 30-day data collection is running (v0.2+), the system has a rich dataset:
120 weight readings per cylinder cycle, burn rate, cooking session events,
refill dates, cylinder brands. This data must be used to its full potential.

### v0.3 — Statistical intelligence
```
- Trend line extrapolation for precise cal_factor
- Personalised burn rate from actual consumption history
- Accurate days_remaining = current_gas / personal_burn_rate
- Session detection: cooking events from delta spikes
```

### v1.0 — Pattern intelligence
```
- Cooking session count per day
- Peak usage hours (morning / evening patterns)
- Day-of-week consumption patterns
- Anomaly detection: unusual consumption spike = stove left on?
- Confidence intervals on days_remaining prediction
```

### v2.0 — AI/ML layer
```
- On-device lightweight model (TensorFlow Lite on QRB2210 Cortex-A53)
- Personalised consumption prediction:
    accounts for weekdays vs weekends
    accounts for seasonal variation
    accounts for household size changes
- Anomaly detection model: distinguish cooking events from vibration/noise
- Predictive refill alert:
    not just "X days left" but "order by Thursday — delivery takes 2 days"
- Auto-improve cal_factor using Kalman filter on successive cylinder cycles
```

### v3.0 — Agent layer
```
- LLM agent running on MPU (cloud API or on-device quantised model)
- Natural language queries: "how much gas did we use this week?"
- Proactive insights: "you used 20% more gas this week — did you have guests?"
- Gas ordering agent: integrates with HP/Bharat/Indane booking APIs
- Multi-cylinder network: aggregate data from multiple homes
- Fleet management for LPG distributors
```

### Data collection philosophy (locked)
```
Every reading is valuable. Store everything.
Raw weight, timestamp, temperature (future), session flags.
Never discard history — aggregated summaries lose information.
The model gets better with every cylinder cycle.
Every household that uses this device contributes to
a better model for all households (opt-in, anonymised).
```

---

## Home-Hub Integration (after all experiments)

### MCU sketch additions

```cpp
// First-boot state machine
BOOT → TARE → NOISE_CHAR → CAL → write config.json → RUNNING

// RUNNING continuous loop
// Sliding window delta → Bridge.notify("weight_event", data)
// Scheduled 6hr snapshot → Bridge.notify("weight_snapshot", data)
```

### Python additions

```python
Bridge.provide("weight_event", on_weight_event)
Bridge.provide("weight_snapshot", on_weight_snapshot)
```

### splash.html gas dashboard

- Current weight
- Days remaining (with confidence interval)
- Last refill date
- Consumption trend chart
- "Replace Cylinder" button → triggers tare + cal flow
- "Cylinder Empty" button → triggers trend extrapolation + cal refinement

---

## Other Active Products (parked)

### motion-sensor-webui

| Version | Status |
|---------|--------|
| v1.0 PIR + web dashboard | ✅ Complete |
| v1.1 MCU LEDs | ✅ Complete |
| v1.2 BLE advertisement from Linux | 🔵 Parked |
| v1.3 AQ1 MCU BLE beacon | 🔵 Parked |

### youtube-display

| Version | Status |
|---------|--------|
| v1.3 Queue + local MP4 + BLE | ✅ Complete |
| v2.0 Date-scheduled queues | 🔵 Parked until home-hub complete |

---

## What to Bring Next Session

- **Measuring cup or syringe** — essential for experiment 006B
- Known weights for 300g and 500g (for 005) — or improvise with water + scale

---

## Change Log

| Date | Change |
|------|--------|
| 2026-05-05 | Created — experiment 003 complete, full queue, product roadmap |
| 2026-05-05 | Corrected — distinguished proven vs derived vs pending throughout |
| 2026-05-06 | Major update — full calibration architecture locked: tare lifecycle, adaptive retry, brand bootstrap, 30-day self-derived cal_factor, trend extrapolation, modular sketch contracts, data intelligence roadmap v0.3→v3.0 |
