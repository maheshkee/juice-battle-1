# SENSOR_CHARACTERISATION.md
# Gas Cylinder Monitor — Sensor Characterisation Philosophy & Knowledge Base
# Arduino UNO Q AQ3 | Created: 2026-05-05 | Updated: 2026-05-05
# Status: LOCKED — do not modify without hardware verification

---

## Purpose of This Document

This document captures the reasoning, derivations, and locked decisions for how
the gas cylinder monitor characterises its own sensor behaviour at boot.

It answers three questions:
1. Why must the device measure its own noise floor — why can't we hardcode it?
2. What is the minimum gas change we need to detect, and why?
3. How should the production detection loop work given that answer?

Every number is either derived from first principles or hardware-verified on
AQ3 (192.168.1.161). No guessing. No theory without evidence.

---

## 1. Philosophy — Why Self-Characterisation

The gas monitor will be deployed in Indian households. Each installation is different:
- Kitchen vibration levels vary (ground floor vs upstairs, near road vs quiet)
- Power supply quality varies (EMI, ripple)
- Load cell mounting varies (surface flatness, foot contact)
- Temperature varies (coastal Andhra vs inland)

A hardcoded threshold assumes all environments are identical. They are not.

**Hardware proof from experiment 003 — same board, same bench, two runs same day:**

```
Run 1 STD = 2.3636g → THRESHOLD = 4.2281g
Run 2 STD = 1.3315g → THRESHOLD = 2.3819g
```

Nearly 2× difference in STD between runs on the same hardware. If we hardcoded
Run 1's threshold for Run 2's environment, the threshold would be 1.77× too high.

**The correct approach — same as tare and cal_factor:**
The device measures its own reality at first boot. It computes the threshold
from that measurement. It writes the result to config.json. It never guesses.

| Constant | What it measures | Status |
|----------|-----------------|--------|
| tare_raw | Zero offset of this load cell in this mounting | ✅ Self-computing |
| cal_factor | Raw-to-grams conversion for this cell | ✅ Self-computing |
| noise_floor_g | Minimum detectable weight change in this environment | ✅ Self-computing |

---

## 2. LPG Consumption Derivation — Minimum Detectable Event

### Known facts (Indian LPG standard, government documented)

```
Cylinder capacity    : 14,200g (14.2kg standard household cylinder)
Typical duration     : 30 days per cylinder
Average daily cooking: 2.5 hours active flame (across all meals)
```

### Derivation

```
Daily consumption    = 14,200g ÷ 30 days    = 473g/day
Hourly consumption   = 473g ÷ 2.5 hours     = 189g/hour
Per-minute burn rate = 189g ÷ 60 minutes    = 3.15g/minute
```

### Real cooking events — Andhra Pradesh household

| Event | Duration | Gas consumed | Status |
|-------|----------|-------------|--------|
| Tea / coffee | 5 min | ~16g | Minimum target |
| Quick fry / tadka | 10 min | ~32g | Should detect |
| Rice / dal | 20 min | ~64g | Must detect |
| Full meal (3 dishes) | 45 min | ~144g | Easy |
| Full day cooking | 2.5 hr | ~473g | Trivial |

**Minimum detectable event = 16g.** Threshold must be well below 16g.

### Why two signals

**Signal 1 — per-session event detection:**
Each cooking session detected as a weight drop event. Stored with timestamp.
Enables: session history, daily usage chart, anomaly detection.

**Signal 2 — trend-based days-remaining prediction:**
Rolling 7-day rate → days_left = gas_remaining / daily_rate.
Primary user-facing output: "5 days remaining."

Signal 1 feeds Signal 2. Both require threshold set by the 16g minimum event.

---

## 3. Noise Floor Theory

### Sources on AQ3

| Source | Characteristic |
|--------|---------------|
| Mechanical vibration | Table, floor, air currents — random, fast |
| Electrical (EMI, ripple) | Power supply, WiFi, nearby devices — random, fast |
| HX711 ADC quantization | Internal to chip — always present |
| Temperature drift | Strain gauge resistance — slow, directional |

### The √N averaging law

```
std_after_averaging = σ / √N

AQ3 hardware (σ range 1.33–2.36g):
N=1   → std = 1.33–2.36g   pp ≈ 5.3–9.4g
N=10  → std = 0.42–0.75g   pp ≈ 1.7–3.0g
N=20  → std = 0.30–0.53g   pp ≈ 1.2–2.1g
```

Diminishing returns above N=20.
For noise characterisation at boot: N=200 samples (gives reliable distribution).

---

## 4. Detection Strategy — Sliding Window Delta

### Why single-sample threshold fails

Single sample noise pp = 5.4–7.5g measured on AQ3.
Minimum event = 16g. Margin = 2.1–3.0× — too tight.

### Why heavy averaging fails

Gas consumption = 3.15g/min. At N=20 samples (2.4s), weight drops only 0.126g.
Window std = 0.30–0.53g. Signal buried in noise.

### The solution

Two rolling windows of N=10 samples. Compare averages.

```
Window A (past 10):    avg_A
Window B (current 10): avg_B
delta = avg_A - avg_B   (positive = weight dropped)

if |delta| > threshold_g → Bridge.notify("weight_event")
```

Every 120ms: oldest sample drops from A, B's oldest moves to A, new sample enters B.

### Threshold derivation formula

```
window_std  = single_std / √10
delta_std   = √2 × window_std
threshold_g = delta_std × 4    (4σ safety factor)
```

### Why 4σ

At 4σ: false trigger probability ≈ 1 in 15,000 readings.
At 120ms pacing: ≈ 1 false trigger per 25 hours. Acceptable.

### Why N=10 per window

- 10 samples × 120ms = 1.2 seconds per window
- Gas consumption in 1.2s = 0.063g — negligible
- Detection latency: event detectable within ~2 minutes of cooking start

---

## 5. Self-Computation Formula — Boot Sequence

### State machine sequence

```
BOOT → TARE_MEASURE → CAL_MEASURE → NOISE_MEASURE → RUNNING
```

### NOISE_MEASURE algorithm

```
Input:  200 raw HX711 samples, scale empty, after tare
Output: std_g, threshold_g → written to config.json

Step 1: Collect 200 samples — one per loop() iteration (non-blocking)
        Reject raw: LONG_MIN, -1, 0x7FFFFF, < -5000000L, > 5000000L
        Reject grams: < -50g or > 50g (after conversion)

Step 2: Two-pass variance — FLOAT ONLY (double broken on STM32U585)
        Pass 1: mean_g = sum(samples[i]) / 200
        Pass 2: std_g  = sqrt(sum((samples[i] - mean_g)²) / 200)

Step 3: Derive threshold
        window_std  = std_g / sqrt(10.0f)
        delta_std   = sqrt(2.0f) × window_std
        threshold_g = delta_std × 4.0f

Step 4: Validate
        std_g < 0.1g or > 10.0g → retry (up to 3 times, 2s between)
        threshold_g < 2.0g or > 20.0g → retry
        all retries fail → fallback_threshold = 8.0g
        log "threshold_source=fallback" if fallback used

Step 5: Write to config.json
```

### config.json fields added by noise module

```json
{
  "noise_std_g":      1.33,
  "noise_pp_g":       5.46,
  "noise_char_date":  "2026-05-05",
  "threshold_g":      2.38,
  "threshold_source": "measured"
}
```

---

## 6. Platform Findings — STM32U585 Zephyr/Arduino Core

### CRITICAL: double arithmetic broken — use float only

**Symptom:** Sum of float array using double accumulator = 0.000000 exactly,
despite confirmed non-zero values in array.

**Proof (2026-05-05 diagnostic):**
```
Array values confirmed: s0=-0.7046, s100=-0.4761, s199=-0.1290
double accumulator loop → sum = 0.000000  ← WRONG
float  accumulator loop → sum = correct   ← RIGHT
```

**Rule:** All accumulator variables must be float. Never use double in MCU
sketch code on AQ2/AQ3. Not in setup(), not in loop(), not in state cases.

### double array on stack causes hang

`double arr[N]` inside loop() corrupts the stack frame on this platform.
Symptom: state machine hangs forever after setup, no log output.
Rule: Never declare double variables of any kind in MCU sketch.

### wait_ready timeout

Tested: 150ms (too tight, 87% timeouts), 300ms (still slow), 400ms (working).
Root cause: Zephyr scheduler holds after noInterrupts/interrupts cycle in
hx711_read_raw(). Bridge interrupt accumulation delays DOUT LOW detection.
Current working value: 400ms.

### Blocking while loops in state cases

Never use while(count < N) to collect samples inside a switch state case.
Causes Bridge interrupt accumulation → scheduler delay → wait_ready timeouts.
Rule: One sample per loop() iteration. Accumulate using global counters.

---

## 7. Modular Sketch Architecture

```
sketch/
├── sketch.ino      ← state machine: BOOT→TARE→CAL→NOISE→RUNNING
├── hx711.h/.cpp    ← bit-bang read, wait_ready, corrupt filters
├── tare.h/.cpp     ← 5-sample self-validating tare
├── noise.h/.cpp    ← 200-sample noise characterisation + threshold derivation
└── cal.h/.cpp      ← known-weight calibration, cal_factor derivation
```

---

## 8. Locked Values — AQ3 Board (192.168.1.161)

Hardware-verified from experiment 003 (2026-05-05).

### CAL_FACTOR (158g known weight, experiment 003)

```
Run 1: 103.2721 raw/g
Run 2: 101.9114 raw/g
Typical range: 100–107 raw/g
Sanity check acceptance range: 80–140 raw/g
Note: varies per mounting — always self-compute at boot
```

### Tare

```
Range across sessions: -12799 to -13737 raw
Spread within session: 37–174 raw (all within 600 threshold)
Note: always re-measure at boot — never hardcode
```

### Noise characterisation (200 samples, 120ms pacing, bench environment)

| Metric | Run 1 | Run 2 | Notes |
|--------|-------|-------|-------|
| STD | 2.3636g | 1.3315g | Varies — self-characterise is essential |
| PP | 40.99g | 5.4557g | Run 1 had outliers — PP unreliable metric |
| THRESHOLD_G | 4.2281g | 2.3819g | Self-computed from STD via formula |
| MEAN | -1.714g | -1.685g | Tare drift ~1.7g between phases |
| MIN | -15.34g | -4.68g | Run 1 had outlier at -15g |
| MAX | 25.65g | 0.78g | Run 1 had outlier at +25g |

```
STD range on AQ3 bench     : 1.33g – 2.36g
THRESHOLD range            : 2.38g – 4.23g
MINIMUM EVENT              : 16g (tea/coffee, 5 min, 3.15g/min)
DETECTION MARGIN worst case: 16g / 4.23g = 3.8× ✅
DETECTION MARGIN best case : 16g / 2.38g = 6.7× ✅
FALLBACK threshold         : 8.0g (if characterisation fails all retries)
```

---

## 9. What This Document Does NOT Cover

- HX711 bit-bang implementation → loadcell_hx711_mcu_reference.docx
- Tare self-validation algorithm → HX711_CALIBRATION_ARCHITECTURE.md
- Cal_factor derivation → HX711_CALIBRATION_ARCHITECTURE.md
- Bridge RPC patterns → UNO_Q_Part2_AppLab_Bridge.md
- Production measurement cycle (6hr) → ARCHITECTURE.md
- SQLite schema → SPEC.md

---

## Change Log

| Date | Change |
|------|--------|
| 2026-05-05 | Created — LPG derivation, √N law, sliding window delta, 4σ safety factor |
| 2026-05-05 | Updated — experiment 003 two-run results, platform findings, locked values |
