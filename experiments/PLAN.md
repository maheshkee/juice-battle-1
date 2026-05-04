# PLAN.md — Experiment Queue

Experiments run in order. Do not start the next experiment until CONCLUSION.md is written for the current one.

---

## Completed

### 001-freeze-test — DONE 2026-05-02
**Result**: H1 confirmed. HX711 freezes after one conversion. DOUT stays LOW until MCU reads. Next conversion starts only after the read. See `hx711/001-freeze-test/CONCLUSION.md`.

---

## Active

---

## Queued

### 002-noise-baseline
Measure the raw noise floor at 10 Hz vs 80 Hz. Identify noise sources. Quantify actual LSB variation on our hardware vs datasheet spec.

### 003-averaging-accuracy
Compare: single read vs N-sample average vs known weight. Find minimum N for acceptable accuracy.

### 004-stability-detection
Use max−min spread as a stability indicator. Find the threshold that reliably distinguishes settling from stable.

### 005-calibration
Derive calibration factor for the 20 kg load cell. Verify linearity across 0 kg, 5 kg, 10 kg, 20 kg.

### 006-water-bowl-spoon
Practical test: bowl of water on scale, remove spoon, add spoon back. Verify end-to-end system behavior with real-world usage pattern.

---

## Note

Experiments 001→006 build on each other. 001 determines the reading architecture. 002 determines filtering strategy. 003+004 determine the stable-detection algorithm. 005 is calibration. 006 is integration validation.
