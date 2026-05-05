# 003 — HX711 Noise Characterisation

**Date:** 2026-05-05  
**Board:** Arduino UNO Q (AQ3) — STM32U585 MCU + QRB2210 MPU  
**Status:** Complete — float-only stats working, threshold derivation verified

---

## Purpose

Measure the real noise floor of the HX711 + load cell on this hardware.
Derive a statistically justified detection threshold for the event-driven
weight monitor in home-hub.

---

## What the Sketch Does

Full automated sequence — no human intervention after start:

```
IDLE (3s)
  → TARE_WAIT (10s settle)
  → TARE_MEASURE (5 samples, spread < 600 raw)
  → CAL_WAIT (10s settle, place 158g weight)
  → CAL_MEASURE (20 samples → cal_factor)
  → NOISE_WAIT (10s settle, remove weight)
  → NOISE_MEASURE (200 samples → stats)
  → DELTA_WAIT (5s, place test weight)
  → DELTA_RUNNING (sliding window delta detection)
```

---

## Threshold Derivation

```
noise_std   = stddev of 200 empty-scale samples (grams)
window_std  = noise_std / sqrt(10)      ← std of 10-sample window average
delta_std   = sqrt(2) * window_std      ← std of difference between two windows
threshold_g = delta_std * 4.0           ← 4-sigma detection threshold
```

---

## Key Bugs Found and Fixed

| Bug | Symptom | Fix |
|-----|---------|-----|
| `double` accumulator in for loop | `sum=0` despite real array values | Replace with `float pass1_sum`, `float pass2_sum` |
| `while(count < N)` in state case | Bridge interrupt accumulation → app timeout | One sample per `loop()` iteration, `break` to yield |
| `hx711_wait_ready(150)` | Timeout under Bridge load | Increased to 400ms |
| No Bridge yield after read | Missed notifications | `delay(1)` after corrupt filters in NOISE + DELTA states |
| Grams range filter missing | Corrupt raw reads inflated noise stats | `if (g < -50.0f || g > 50.0f) break` |

### Root Cause: double arithmetic on STM32U585

`double` accumulators in `for` loops produce `sum=0.000000` even when the
array contains real non-zero values. `MIN`/`MAX` (updated per-sample from a
local `float`) were correct. Only the post-collection loops were broken.

Confirmed by diagnostic: `pass1_sum` (float) gave correct mean; switching
pass 2 to `float dev` and `float pass2_sum` gave correct STD.

Root cause is not fully understood — could be toolchain, Zephyr FPU mode,
or a `double`=`float` alias on this target. Documented as open question in
`home-hub/docs/LEARNINGS_AND_INSIGHTS.md`.

**Rule added to all CLAUDE.md files:** never use `double` in MCU sketch.

---

## Results

```
CAL_FACTOR  = ~100–106 raw/g (varies with mounting)
TARE spread = 42–132 raw (stable)
THRESHOLD   = derived per run — not hardcoded
```

Threshold successfully detected weight placement and removal in DELTA_RUNNING.

---

## Files

```
003-noise-characterisation/
├── README.md                  ← this file
├── RESULTS.md                 ← raw log output from session
└── app/
    ├── app.yaml
    ├── python/main.py         ← Bridge listener, logs all channels
    └── sketch/
        ├── sketch.ino         ← full state machine
        └── sketch.yaml
```

---

## Deploy

```bash
cd ~/ArduinoApps/hx711-003-noise
arduino-app-cli app start user:hx711-003-noise
arduino-app-cli app logs user:hx711-003-noise --follow
```
