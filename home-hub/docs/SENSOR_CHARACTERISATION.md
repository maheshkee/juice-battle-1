# SENSOR_CHARACTERISATION.md
# Gas Cylinder Monitor — Sensor Characterisation Philosophy & Knowledge Base
# Arduino UNO Q AQ3 | Created: 2026-05-05 | Updated: 2026-05-05
# Status: LOCKED — do not modify without hardware verification

---

## Purpose of This Document

This document captures the reasoning, derivations, and locked decisions for how
the gas cylinder monitor characterises its own sensor behaviour at boot.

Every number is explicitly marked as one of:
- ✅ PROVEN — hardware-verified on AQ3
- 📐 DERIVED — calculated from documented sources, not yet measured on hardware
- ❓ PENDING — requires experiment to verify

---

## 1. Philosophy — Why Self-Characterisation

The gas monitor will be deployed in Indian households. Each installation is different:
- Kitchen vibration levels vary
- Power supply quality varies
- Load cell mounting varies
- Temperature varies

A hardcoded threshold assumes all environments are identical. They are not.

**Hardware proof from experiment 003 — same board, same bench, two runs same day:**

```
Run 1 STD = 2.3636g → THRESHOLD = 4.2281g
Run 2 STD = 1.3315g → THRESHOLD = 2.3819g
```

Nearly 2× difference in STD on same hardware same day. Self-characterisation is essential.

| Constant | Status |
|----------|--------|
| tare_raw | ✅ Self-computing, verified |
| cal_factor | ✅ Self-computing, verified |
| noise_floor / threshold | ✅ Self-computing, verified |

---

## 2. LPG Consumption Estimate — Minimum Event Size

### Status: 📐 DERIVED — not yet hardware-verified

### Source data (Indian LPG standard, government documented)

```
Cylinder capacity    : 14,200g
Typical duration     : 30 days per cylinder
Average daily cooking: 2.5 hours active flame
```

### Calculation

```
Daily consumption    = 14,200g ÷ 30 days    = 473g/day
Hourly consumption   = 473g ÷ 2.5 hours     = 189g/hour
Per-minute burn rate = 189g ÷ 60 minutes    = 3.15g/minute
```

### Derived event sizes

| Event | Duration | Estimated gas | Status |
|-------|----------|--------------|--------|
| Tea / coffee | 5 min | ~16g | 📐 Derived estimate |
| Quick fry | 10 min | ~32g | 📐 Derived estimate |
| Rice / dal | 20 min | ~64g | 📐 Derived estimate |
| Full meal | 45 min | ~144g | 📐 Derived estimate |

### Important caveat

These are averages. Actual consumption depends on:
- Stove BTU rating (varies widely)
- Burner size used
- Flame intensity
- Actual cooking duration

**16g is a working estimate for design purposes. It is NOT a measured fact.**
Experiment 006B will measure the actual minimum detectable removal on real hardware.
Until then, 16g is the design target — not a locked value.

### Why two signals

**Signal 1 — per-session event detection:** Each cooking session as a weight drop event.
**Signal 2 — trend prediction:** Rolling rate → days remaining.
Signal 1 feeds Signal 2.

---

## 3. Noise Floor Theory

### Sources on AQ3

| Source | Characteristic |
|--------|---------------|
| Mechanical vibration | Random, fast |
| Electrical (EMI, ripple) | Random, fast |
| HX711 ADC quantization | Always present |
| Temperature drift | Slow, directional |

### The √N averaging law

```
std_after_averaging = σ / √N

AQ3 measured range (σ = 1.33–2.36g):
N=1   → std = 1.33–2.36g
N=10  → std = 0.42–0.75g
N=20  → std = 0.30–0.53g
```

For noise characterisation at boot: N=200 samples (reliable distribution estimate).

---

## 4. Detection Strategy — Sliding Window Delta

### Why single-sample threshold fails

Single sample noise pp = 5.4–7.5g measured on AQ3. ✅ PROVEN
Margin vs 16g estimate = 2.1–3.0× — too tight.

### Why heavy averaging fails

Gas consumption ≈ 3.15g/min. 📐 DERIVED
At N=20 samples (2.4s), weight drops only 0.126g — buried in noise.

### The solution

```
Window A (past 10 samples):    avg_A
Window B (current 10 samples): avg_B
delta = avg_A - avg_B
if |delta| > threshold_g → Bridge.notify("weight_event")
```

### Threshold derivation formula ✅ PROVEN working on AQ3

```
window_std  = single_std / √10
delta_std   = √2 × window_std
threshold_g = delta_std × 4    (4σ safety factor)
```

### 4σ safety factor

At 4σ: false trigger probability ≈ 1 in 15,000 readings.
At 120ms pacing: ≈ 1 false trigger per 25 hours.
**Actual false positive rate: ❓ PENDING — experiment 007B will measure this.**

---

## 5. Self-Computation Formula — Boot Sequence

```
BOOT → TARE_MEASURE → CAL_MEASURE → NOISE_MEASURE → RUNNING
```

### NOISE_MEASURE algorithm

```
Step 1: Collect 200 samples — one per loop() iteration (non-blocking)
        Reject raw: LONG_MIN, -1, 0x7FFFFF, < -5000000L, > 5000000L
        Reject grams: < -50g or > 50g

Step 2: Two-pass variance — FLOAT ONLY (double broken on STM32U585)
        Pass 1: mean_g = sum(samples[i]) / 200
        Pass 2: std_g  = sqrt(sum((samples[i] - mean_g)²) / 200)

Step 3: Derive threshold
        window_std  = std_g / sqrt(10.0f)
        delta_std   = sqrt(2.0f) × window_std
        threshold_g = delta_std × 4.0f

Step 4: Validate
        std_g < 0.1g or > 10.0g → retry (up to 3, 2s between)
        threshold_g < 2.0g or > 20.0g → retry
        all retries fail → fallback_threshold = 8.0g

Step 5: Write to config.json
```

### config.json fields

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

## 6. Platform Findings — STM32U585 Zephyr/Arduino Core ✅ PROVEN

### double arithmetic broken — use float only

```
Array values confirmed: s0=-0.7046, s100=-0.4761, s199=-0.1290
double accumulator loop → sum = 0.000000  ← WRONG
float  accumulator loop → sum = correct   ← RIGHT
```

Rule: Never use double anywhere in MCU sketch on AQ2/AQ3.

### double array on stack causes hang

`double arr[N]` inside loop() corrupts stack frame.
Rule: Never declare double variables in MCU sketch.

### wait_ready timeout

400ms working. Root cause: Zephyr scheduler holds after noInterrupts/interrupts.

### Blocking while loops in state cases

Causes Bridge interrupt accumulation → timeouts.
Rule: One sample per loop() iteration.

---

## 7. Locked Values — AQ3 Board (192.168.1.161)

### ✅ PROVEN — hardware-verified

```
DT=D7, SCK=D6                     ← never change
wait_ready timeout  = 400ms        ← tuned for AQ3 under Bridge load
millis() pacing     = 120ms        ← at TOP of loop() only
TARE range          = -12799 to -13737 raw (varies — always self-compute)
TARE spread         = 37–174 raw (within 600 threshold)
CAL_FACTOR range    = 100–107 raw/g (varies — always self-compute)
NOISE STD range     = 1.33–2.36g  (varies — always self-compute)
THRESHOLD range     = 2.38–4.23g  (derived from STD)
FALLBACK threshold  = 8.0g        (if characterisation fails)
```

### 📐 DERIVED — calculated, not yet measured on hardware

```
Burn rate           = 3.15g/min   (from 14.2kg ÷ 30 days ÷ 2.5hr)
Min event estimate  = 16g         (tea/coffee, 5 min × 3.15g/min)
Detection margin    = 3.8–6.7×    (16g / threshold range)
```

### ❓ PENDING — requires experiment

```
Actual minimum detectable removal    → experiment 006B
Actual false positive rate           → experiment 007B
Temperature drift magnitude          → experiment 008
Threshold stability over 6hr         → experiment 009
Cal_factor linearity across weights  → experiment 005
```

---

## 8. What This Document Does NOT Cover

- HX711 bit-bang implementation → loadcell_hx711_mcu_reference.docx
- Tare algorithm → HX711_CALIBRATION_ARCHITECTURE.md
- Bridge RPC patterns → UNO_Q_Part2_AppLab_Bridge.md
- Production cycle (6hr) → ARCHITECTURE.md
- SQLite schema → SPEC.md

---

## Change Log

| Date | Change |
|------|--------|
| 2026-05-05 | Created — LPG derivation, √N law, sliding window delta, 4σ safety factor |
| 2026-05-05 | Updated — experiment 003 two-run results, platform findings |
| 2026-05-05 | Corrected — distinguished proven vs derived vs pending values |
