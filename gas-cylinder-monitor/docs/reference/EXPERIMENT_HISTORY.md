# EXPERIMENT_HISTORY.md
# HX711 Experiment Series — Consolidated Results
# Source: experiments/hx711/001 through 007
# Last updated: 2026-06-03
# Rule: append new rows when experiments complete. Do not copy raw sample dumps.

---

## Summary Table

| # | Name | What it tested | Outcome | Key locked value / finding |
|---|------|---------------|---------|---------------------------|
| 001 | freeze-test | Does HX711 hold last conversion during MCU pause, or refresh autonomously? | H1 CONFIRMED: HX711 freezes. DOUT stays LOW for entire pause. S2 = frozen value even after 30s with new weight on scale. | Each MCU read triggers exactly one new conversion. No background sampling. Missed reads delay conversions but don't lose data. |
| 002 | noise-baseline | Quantify single-sample noise at 10Hz vs 80Hz — effect of averaging on noise floor | NOT COMPLETED. Results template left empty. | No locked values from 002. |
| 003 | noise-characterisation | Measure real noise floor of HX711 + load cell. Derive statistically-justified detection threshold. | COMPLETE. float-only stats working. Threshold derivation verified. Two-run results prove self-characterisation is essential. | STD range: 1.33–2.36g. THRESHOLD range: 2.38–4.23g. CAL_FACTOR ~101–103. PP unreliable — use STD. double arithmetic broken on STM32U585 (use float). Blocking while loops in state cases cause Bridge interrupt accumulation. wait_ready timeout = 400ms. |
| 004 | modular-refactor | Refactor flat 003 sketch into isolated modules: hx711/tare/cal/noise/delta. Verify behaviour identical to 003. | COMPLETE. Modular architecture working. Physical WAIT states (detect stable empty scale) replace dumb timers. Zero false triggers on stable weight. | Module boundary: sketch.ino is pure orchestrator. Physical stability detection at every WAIT state. TARE has 5 status values: BUSY/RETRY/DEGRADED/SUCCESS/FAILED. CAL_FACTOR 103–106, THRESHOLD 5.87–7.03g. |
| 005 | calibration-linearity | Cal factor linearity across multiple known weights | NOT STARTED. No results file exists. | Pending. |
| 006 | water-spoon-test | Can the system detect small unknown weight changes (drops of water from a bowl)? Part A only. | COMPLETE Part A. 5–6g deltas cleanly detected — both consecutive removals negative, consistent magnitude. Signal >> noise. Part B (known weights) not run. | cal_factor ≈ 103 raw/g. 20-sample averaging sufficient for stable readings. Tare is mandatory — raw offset ~-13086, cannot interpret readings without it. First reading anomaly: settle before triggering W1. |
| 007 | event-driven | End-to-end event-driven architecture: MCU continuous loop → Bridge.notify → Python → WebUI | COMPLETE. Full pipeline validated. Self-validating tare works reliably. BSP symbols required for LEDs. | CAL_FACTOR = 106.7 raw/g (3 runs, 158g known weight, range 106.3–107.1). THRESHOLD = 6g (8× noise floor). TARE_STABILITY = 600 raw spread. TARE_SAMPLES = 5, TARE_RETRIES = 3. Blocking delay() in setup() corrupts HX711 reads — always use loop() state machine. |

---

## Derived locked constants (from 007, hardware-verified on AQ3)

```
CAL_FACTOR     = 106.7 raw/g   (3-run average, 158g ref weight)
TARE_STABILITY = 600 raw spread (max across 5 samples)
TARE_SAMPLES   = 5
TARE_RETRIES   = 3
THRESHOLD_MIN  = 6g            (8× noise floor)
```

## Noise characterisation constants (from 003, hardware-verified on AQ3)

```
STD range      = 1.33–2.36g   (self-characterise every boot)
THRESHOLD range= 2.38–4.23g   (derived from STD)
FALLBACK       = 8.0g         (if characterisation fails)
Formula        = √2 × (std / √10) × 4
```

## Pending experiments

| Exp | What to measure | Why needed |
|-----|----------------|-----------|
| 002 | Noise at 10Hz vs 80Hz; effect of N averaging | Quantify averaging benefit, choose optimal N |
| 005 | Cal factor across weight range 0–20kg | Verify linearity, confirm single-point cal is sufficient |
| 006B | Minimum physically detectable removal | Validate 16g design target vs actual hardware floor |
| 007B | Actual false positive rate over 30 min | Validate 4σ theoretical prediction |
| 008 | Temperature drift magnitude | Understand seasonal variation in cal_factor |
| 009 | Threshold stability over 6hr duty cycle | Confirm NOISE_MEASURE at boot is sufficient |
