# SENSOR_CHARACTERISATION.md
# Gas Cylinder Monitor — Sensor Characterisation Philosophy & Knowledge Base
# Arduino UNO Q AQ3 | Derived: 2026-05-05
# Status: LOCKED — do not modify without hardware verification

---

## Purpose of This Document

This document captures the reasoning, derivations, and locked decisions for how
the gas cylinder monitor characterises its own sensor behaviour at boot.

It answers three questions:
1. Why must the device measure its own noise floor — why can't we hardcode it?
2. What is the minimum gas change we need to detect, and why?
3. How should the production detection loop work given that answer?

Every number in this document is either derived from first principles or
hardware-verified on AQ3 (192.168.1.161). No guessing. No theory without evidence.

---

## 1. Philosophy — Why Self-Characterisation

The gas monitor will be deployed in Indian households. Each installation is different:

- Kitchen vibration levels vary (ground floor vs upstairs, near road vs quiet)
- Power supply quality varies (EMI, ripple)
- Load cell mounting varies (surface flatness, foot contact)
- Temperature varies (coastal Andhra vs inland)

A hardcoded threshold (e.g. `threshold_g = 8.0`) assumes all these environments
are identical. They are not.

**The correct approach — same as tare and cal_factor:**
The device measures its own reality at first boot. It computes the threshold
from that measurement. It writes the result to config.json. It never guesses.

This is the same philosophy applied to all three boot-time constants:

| Constant | What it measures | Status |
|----------|-----------------|--------|
| tare_raw | Zero offset of this load cell in this mounting | ✅ Self-computing |
| cal_factor | Raw-to-grams conversion for this cell | ✅ Self-computing |
| noise_floor_g | Minimum detectable weight change in this environment | ← THIS DOCUMENT |

All three must exist in config.json before normal operation begins.
None of them may be hardcoded.

---

## 2. LPG Consumption Derivation — Minimum Detectable Event

### Why this matters

The noise floor threshold must be below the smallest real event we care about.
If threshold > smallest event, that event is invisible to the system.

We must derive the smallest real event from the actual physics of Indian LPG usage —
not from a guess.

### Known facts (Indian LPG standard, government documented)

```
Cylinder capacity    : 14,200g (14.2kg standard household cylinder)
Typical duration     : 30 days per cylinder
Average daily cooking: 2.5 hours active flame (across all meals)
```

### Derivation

```
Daily consumption    = 14,200g ÷ 30 days         = 473g/day
Hourly consumption   = 473g ÷ 2.5 hours          = 189g/hour
Per-minute burn rate = 189g ÷ 60 minutes          = 3.15g/minute
```

### Real cooking events in Andhra Pradesh household

| Event | Duration | Gas consumed | Detectable? |
|-------|----------|-------------|-------------|
| Tea / coffee | 5 min | ~16g | Minimum target |
| Quick fry / tadka | 10 min | ~32g | Should detect |
| Rice / dal | 20 min | ~64g | Must detect |
| Full meal (3 dishes) | 45 min | ~144g | Easy |
| Full day cooking | 2.5 hr | ~473g | Trivial |

### The derived requirement

**Minimum detectable event = 16g (tea/coffee, 5 minutes)**

This is the design target. The system must reliably detect a 16g weight change
above whatever the noise floor is in the deployment environment.

Therefore: `noise_floor_pp << 16g` — peak-to-peak noise must be well below 16g.

### Why two signals, not one

The gas monitor captures both:

**Signal 1 — per-session event detection:**
Each individual cooking session detected as a weight drop event.
Stored with timestamp. Enables: session history, daily usage chart,
anomaly detection (unusual consumption on a given day).

**Signal 2 — trend-based days-remaining prediction:**
Rolling 7-day consumption rate → `days_left = gas_remaining / daily_rate`.
This is the primary user-facing output: "5 days remaining."

Signal 1 feeds Signal 2. Individual events accumulate into the daily rate.
Both require the same noise floor threshold — set by the smallest event (16g).

---

## 3. Noise Floor Theory

### What noise is

Even with a perfectly stable, unmoving load on the scale, every HX711 reading
is slightly different. Sources on the AQ3 system:

| Source | Characteristic | Effect |
|--------|---------------|--------|
| Mechanical vibration | Table, floor, air currents | Random, fast |
| Electrical (EMI, ripple) | Power supply, WiFi, nearby devices | Random, fast |
| HX711 ADC quantization | Internal to chip | Random, always present |
| Temperature drift | Strain gauge resistance change | Slow, directional |

The first three produce *random* noise — the key word.
Random noise has a statistical distribution we can measure and reason about.

### What we measure

From experiment 002 Phase 1 (200 samples, empty scale, AQ3 bench environment):

```
mean  = -1.32g   (offset from zero — absorbed by tare, irrelevant here)
std   =  1.87g   (standard deviation — spread of individual readings)
min   = -5.08g
max   =  2.63g
pp    =  7.50g   (peak-to-peak = max - min)
```

**Peak-to-peak of 7.50g** means: on a perfectly still scale, readings can
swing ±3.75g just from noise. A single-sample threshold must be above 7.5g
or false events fire constantly.

### The √N averaging law

Random noise reduces with averaging. This is the law of large numbers.

If single-sample std = σ, then after averaging N samples:

```
std_after_averaging = σ / √N
```

Applied to our hardware (σ = 1.87g):

```
N=1   → std = 1.87g    pp ≈ 7.50g
N=5   → std = 0.84g    pp ≈ 3.35g
N=10  → std = 0.59g    pp ≈ 2.36g
N=20  → std = 0.42g    pp ≈ 1.68g
N=50  → std = 0.26g    pp ≈ 1.06g
N=100 → std = 0.19g    pp ≈ 0.74g
```

**Diminishing returns above N=20.** Going from N=50 to N=100 costs 5 extra
seconds at 10Hz for only 0.07g improvement. Not justified.

**For noise characterisation at boot: N=20 samples.**
Gives reliable distribution estimate (std error of std ≈ σ/√(2×20) ≈ 0.30g).
Takes 2 seconds at 10Hz. User waits once at first boot.

---

## 4. Detection Strategy — Sliding Window Delta

### Why single-sample threshold fails

Single sample noise pp = 7.50g.
Minimum event = 16g.
Margin = 8.5g. Tight. In a noisier kitchen, this disappears entirely.

### Why heavy averaging fails for event detection

Gas consumption is slow: 3.15g/minute.
If we average N=20 samples → 2 second window.
In 2 seconds, weight drops only 3.15 × (2/60) = 0.105g.
But window std = 0.42g. Signal buried in noise.

**Averaging is correct for stable readings. Wrong for detecting slow change.**

### The solution — sliding window delta detector

Maintain two rolling windows of N samples each. Compare their averages.

```
Window A (past):    samples[0..N-1]    → avg_A
Window B (current): samples[N..2N-1]  → avg_B

delta = avg_A - avg_B   (positive = weight dropped = gas consumed)

if delta > threshold_g → real consumption detected → Bridge.notify()
```

Every 100ms (one new HX711 sample):
- Drop oldest sample from Window A
- Shift Window B's oldest into Window A
- Add new sample to Window B
- Recompute delta

### Why this works

Each window of N=10 samples has std = 0.59g (from averaging law).
The two windows are independent. Noise in the delta between them:

```
delta_std = √(window_std² + window_std²)
          = √(0.59² + 0.59²)
          = √(0.348 + 0.348)
          = √0.696
          = 0.83g
```

Effective peak-to-peak noise on the delta ≈ 3.3g.

Minimum real event: 16g.

**Detection margin = 16g / 3.3g = 4.8× — nearly 5× above noise.**

Compare to single-sample: 16g / 7.5g = 2.1× — barely 2×.

### Safety factor and threshold formula

Threshold must sit between noise ceiling and minimum signal.
Use 4σ confidence — a false trigger requires noise to hit 4 standard
deviations simultaneously in both windows in opposite directions.
Probability: < 1 in 15,000 readings. At 10Hz = once per 25 hours. Acceptable.

```
threshold_g = delta_std × 4
            = (√2 × window_std) × 4
            = (√2 × (single_std / √N_window)) × 4

Where:
  single_std  = measured at boot (noise characterisation)
  N_window    = 10 (samples per window)
  safety      = 4  (4σ confidence)
```

Applied to AQ3 bench measurement (single_std = 1.87g, N_window = 10):

```
window_std  = 1.87 / √10  = 0.591g
delta_std   = √2 × 0.591  = 0.836g
threshold_g = 0.836 × 4   = 3.34g
```

**But this is the bench value.** In a noisier kitchen, single_std might be 3-4g,
giving threshold_g = 5-7g. Still well below the 16g minimum event.

This is why self-measurement matters: the formula adapts to the environment.

### Window size N=10 — why not more

N=10 per window = 1 second of data per window, 2 seconds total look-back.

In 2 seconds, gas consumption = 3.15 × (2/60) = 0.105g across the full window.
The *delta* between windows accumulates as the event progresses:
- After 1 minute of cooking: delta ≈ 3.15g (approaching threshold)
- After 2 minutes: delta ≈ 6.3g (above threshold → event fires)
- After 5 minutes: delta ≈ 15.75g (strong signal)

A single cooking session triggers multiple consecutive events as the weight
drops. This is expected and correct. Python accumulates them into a session total.

---

## 5. Self-Computation Formula — Boot Sequence

### What the noise module must compute

Input:  N_char = 20 raw samples from HX711, scale empty, after tare
Output: noise_floor_g, threshold_g, written to config.json

```
Step 1: Collect 20 samples (valid only — reject LONG_MIN, -1, 0x7FFFFF)
Step 2: Convert to grams using tare and cal_factor (already computed)
Step 3: Compute mean, std, min, max, peak-to-peak
Step 4: Validate — std must be in sane range (see below)
Step 5: Compute threshold_g = √2 × (std / √N_window) × safety_factor
        where N_window = 10, safety_factor = 4
Step 6: Write to config.json
```

### Validation criteria (acceptance range)

The noise characterisation result must pass sanity checks before being accepted.
If it fails, retry up to 3 times. If all retries fail, use safe fallback.

```
std_min = 0.1g    (below this → something is wrong, HX711 frozen or stuck)
std_max = 10.0g   (above this → extreme environment, check mounting)
pp_max  = 40.0g   (above this → scale disturbed during characterisation)

threshold_min = 2.0g   (below this → too aggressive, will false-trigger)
threshold_max = 20.0g  (above this → too conservative, misses tea events)
```

If all retries fail:
```
fallback_threshold_g = 8.0g   (conservative safe value from early experiments)
Log: "NOISE_CHAR FAILED — using fallback threshold"
```

### config.json fields added by noise module

```json
{
  "noise_std_g":      1.87,
  "noise_pp_g":       7.50,
  "noise_char_date":  "2026-05-05",
  "threshold_g":      3.34,
  "threshold_source": "measured"
}
```

`threshold_source` distinguishes measured (self-computed) from fallback (hardcoded).
Log and flag if fallback is used — it means the environment needs investigation.

---

## 6. Modular Sketch Architecture

The noise characterisation is one module in the first-boot sequence.
All three modules are required before normal operation.

```
sketch/
├── sketch.ino      ← state machine: BOOT → TARE → NOISE_CHAR → CAL → RUNNING
├── hx711.h/.cpp    ← bit-bang read, wait_ready, corrupt filters
├── tare.h/.cpp     ← 5-sample self-validating tare
├── noise.h/.cpp    ← 20-sample noise characterisation, threshold derivation  ← THIS
└── cal.h/.cpp      ← known-weight calibration, cal_factor derivation
```

Each module:
- Has a single entry function called from sketch.ino state machine
- Returns a result struct with value + validity flag
- Never blocks — uses millis() pacing
- Writes its output to the shared config struct
- config struct is serialised to config.json by sketch.ino after all three complete

---

## 7. Experiment Protocol — Noise Characterisation

### Purpose

Verify the noise module computes a stable, consistent threshold across multiple
runs on the same hardware. Validate the acceptance criteria. Confirm the
self-computation formula matches manually calculated values.

### Setup

- Scale empty (no weight, no cylinder)
- Board powered and stable for > 60 seconds before run
- No vibration sources introduced during run
- HX711: DT=D7, SCK=D6, VCC=5V

### Phase A — baseline characterisation

Collect 200 samples (10× the boot-time N=20). Compute:
- mean, std, min, max, peak-to-peak
- derived threshold_g using formula above
- Compare to phase 1 data from experiment 002 (std=1.87g, pp=7.50g)

**Acceptance:** std within ±0.5g of previous measurement on same hardware.
Larger deviation = environment changed or hardware issue.

### Phase B — consistency across boots

Run the 20-sample characterisation 10 times consecutively.
Record threshold_g from each run.

**Acceptance:** threshold_g range across 10 runs < 1.0g.
Larger range = noise is non-stationary (something vibrating intermittently).

### Phase C — disturbed environment

Introduce deliberate vibration (tap table lightly) during one run.
Verify:
- pp_max check catches the disturbance
- Module retries
- Clean run follows

**Acceptance:** module self-recovers within 3 retries.

### Output

RESULTS.md in experiment folder with:
- Raw sample data from Phase A
- threshold_g values from all 10 Phase B runs
- Pass/fail for each acceptance criterion
- Final locked threshold_g for this board

---

## 8. Locked Values — AQ3 Board (192.168.1.161)

These are hardware-verified. Do not override with theory.

```
CAL_FACTOR          = 106.7 raw/g   (3 runs, 158g known weight, range 106.3–107.1)
TARE range          = -13744 to -14551 raw  (varies per session — always re-measure)
TARE spread         = 26–115 raw    (well within 600 stability threshold)
NOISE std           = 1.87g         (Phase 1, 200 samples, 10Hz, bench environment)
NOISE pp            = 7.50g
DERIVED threshold   = 3.34g         (formula: √2 × (1.87/√10) × 4)
MINIMUM EVENT       = 16g           (tea/coffee, 5 min, 3.15g/min burn rate)
DETECTION MARGIN    = 16 / 3.34     = 4.8× above noise  ✅ sufficient
FALLBACK threshold  = 8.0g          (if characterisation fails all retries)
```

---

## 9. What This Document Does NOT Cover

- HX711 bit-bang implementation → `loadcell_hx711_mcu_reference.docx`
- Tare self-validation algorithm → `HX711_CALIBRATION_ARCHITECTURE.md`
- Cal_factor derivation → `HX711_CALIBRATION_ARCHITECTURE.md`
- Bridge RPC patterns → `UNO_Q_Part2_AppLab_Bridge.md`
- Production measurement cycle (6hr) → `ARCHITECTURE.md`
- SQLite schema → `SPEC.md`

---

## Change Log

| Date | Change | Reason |
|------|--------|--------|
| 2026-05-05 | Created | Derived from session reasoning — LPG consumption, √N law, sliding window delta, 4σ safety factor |
