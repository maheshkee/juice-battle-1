# Experiment 007 Results
Date: 2026-05-04
Board: AQ3 at 192.168.1.161

## 007-cal — Calibration
Known weight: 158g (water in plastic cup)
CAL_FACTOR = 106.7 raw/g (average of 3 runs, range 106.3–107.1)
Tare range: -13744 to -14153 raw (consistent across sessions)
Tare spread: 26–93 raw (well within 600 stability threshold)
Self-validating tare strategy: CONFIRMED WORKING
- Rejected unstable first attempt in 2 of 3 runs correctly
- Accepted on retry with tight spread

## 007 event-driven — Architecture Validation
Threshold: 6g (reduced from 10g — still 8x above noise floor)
Architecture: MCU continuous loop → Bridge.notify → Python → WebUI

### Confirmed working
- Event-driven pipeline end to end: PASS
- WebUI live updates via Socket.IO: PASS
- Timestamp and elapsed time per event: PASS
- LED3_G/LED3_R via BSP symbols: PASS
- Self-validating tare on startup: PASS

### Observed behaviour
- First event after bowl placement splits into two events during settling — expected, not a bug
- Time intervals between events = physical action time, not system latency — confirmed
- MCU reads continuously even during silent periods — HX711 never freezes

### Sample run (clean)
TARE OK=-13744 spread=26
07:32:47 weight=110.5g delta=+110.5g first event
07:33:10 weight=155.1g delta=+44.6g 22.9s
07:33:35 weight=146.2g delta=-8.9g 24.6s
07:33:54 weight=131.7g delta=-14.5g 19.0s
07:34:18 weight=123.0g delta=-8.7g 24.1s

## Locked constants
CAL_FACTOR     = 106.7 raw/g
THRESHOLD      = 6g minimum (8x above noise floor)
TARE_STABILITY = 600 raw spread
TARE_SAMPLES   = 5
TARE_RETRIES   = 3

## Conclusions
1. Event-driven architecture validated — ready for production integration
2. Self-validating tare works reliably — supersedes hardcoded range approach
3. BSP symbols (LED3_G, LED3_R) required — never hardcode pin numbers
4. Most bad readings during session were code/timing issues not hardware
5. Blocking delay() in setup() corrupts HX711 reads — always use loop() state machine
6. First placement event is expected noise — Python can filter delta>0 if needed

## Next experiments
002 — noise baseline (10Hz vs 80Hz characterization) — still pending
005 — calibration linearity (multiple known weights) — still pending
