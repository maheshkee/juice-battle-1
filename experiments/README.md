# HX711 Experiments — AQ3 Board

Board: Arduino UNO Q (AQ3) | IP: 192.168.1.161
Hardware: 20 kg load cell, HX711 green PCB clone, 5V AVDD
Pins: DT=D7, SCK=D6 (only conflict-free pair on STM32U585)

Each experiment proves or disproves one hardware hypothesis.
Learnings graduate to `~/ArduinoApps/home-hub/` as production constants.

---

## Experiments

### 001 — freeze-test `COMPLETE`
**Question**: Does HX711 freeze after each conversion, or sample continuously?
**Answer**: Freezes. DOUT stays LOW indefinitely until MCU reads 24 bits + gain pulse.
**Key finding**: Skipping a read delays the next conversion — data is not lost, just paused.
Post-stall first conversion takes ~554 ms (settling). Subsequent reads back to 100 ms.
→ `LEARNINGS.md L1, L2, L3`

---

### 006 — water-spoon-test `COMPLETE`
**Question**: Can the system detect gram-level weight changes reliably?
**Answer**: Yes. 5.35 g removals detected cleanly with 20-sample averaging.
**Constants locked**: CAL_FACTOR=103.02 raw/g, TARE=-13086 raw (this mounting, 2026-05-02)
**Formula**: `grams = (raw - tare) / cal_factor`
Note: tare changes if load cell is remounted. CAL_FACTOR is hardware-stable.
→ `LEARNINGS.md L4, L5`

---

### 007-cal — calibration `COMPLETE`
**Question**: Recalibrate with known weight after remounting.
**Result**: CAL_FACTOR=106.7 raw/g (average of 3 runs, range 106.3–107.1)
Tare range: -13963 to -14055 raw. Self-validating tare strategy confirmed working.
→ `007-event-driven/cal/RESULTS.md`

---

### 007 — event-driven `COMPLETE`
**Question**: Can MCU → Bridge.notify → Python → WebUI pipeline drive real-time weight events?
**Answer**: Yes. Full pipeline validated end-to-end.
**Architecture**: MCU reads continuously, fires Bridge.notify only on delta > threshold.
**Constants locked**:
- CAL_FACTOR = 106.7 raw/g
- THRESHOLD = 6 g (8× above noise floor estimate)
- TARE_STABILITY = 600 raw spread across 5 samples
- TARE_SAMPLES = 5, TARE_RETRIES = 3
**Key findings**:
- Self-validating tare supersedes hardcoded range
- BSP symbols (LED3_G, LED3_R) required — never hardcode pin numbers
- blocking delay() in setup() corrupts HX711 reads — always use loop() state machine
- First placement event may split into two during bowl settling — expected, not a bug
→ `007-event-driven/RESULTS.md`

---

### 002 — noise-baseline `IN PROGRESS`
**Question**: What is the actual noise floor at 10 Hz? Single sample vs averaged.
**Status**: Debugging MCU interrupt interference with hx711_wait_ready() busy-wait.
Root cause: Bridge interrupt bursts after noInterrupts() block in bit-bang cause
MCU to miss next DOUT window. Fix: 150 ms inter-read guard in PHASE1/2/3.
Partial P1 result (run 2026-05-04): std=1.87 g, safe_threshold=5.61 g — P2/P3 pending.
→ `002-noise-baseline/` (not committed until complete)

---

## Locked Constants (production use)

| Constant | Value | Source |
|----------|-------|--------|
| DT pin | D7 | hardware constraint, all others conflict |
| SCK pin | D6 | hardware constraint |
| CAL_FACTOR | 106.7 raw/g | 007-cal, 3-run average |
| TARE_STABILITY | 600 raw | 007-event-driven |
| TARE_SAMPLES | 5 | 007-event-driven |
| TARE_RETRIES | 3 | 007-event-driven |
| Event threshold | 6 g | 007-event-driven (update after 002 completes) |

## Architecture Rules (never violate)

- Output: `Bridge.notify("log", buf)` from MCU — never Monitor.println()
- No external HX711 library — raw bit-bang only
- Never use blocking delay() in setup() — all reads in loop() state machine
- Self-validating tare every boot — never hardcode tare range
- 150 ms minimum between HX711 reads when Bridge is active (prevents interrupt interference)
