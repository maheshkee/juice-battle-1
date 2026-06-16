# HANDOFF — 2026-06-16 Session 2 (Design Session)
# gas-cylinder-monitor

---

## Session type
Design / architecture review. No hardware touched. No sketches built or modified.

---

## Session goal
- Full backlog audit: identify and order all remaining work
- Consolidate V1/V2/V3 cold-start strategies
- Lock all threshold values from first principles
- Define hub state machine for V1
- Validate water container simulation approach

---

## What was completed this session

### Architecture review
- Transport confirmed: BLE only. Any WiFi references in older docs are void.
- Platform confirmed: 3-cell (3× YZC-161A, fibre plate)
- Production sketch: 3E004_cal_and_run.ino (PASSED 2026-06-16, ±7g accuracy)
- cal_factor: NOT hardcoded — self-derived every boot (~36 raw/g nominal)

### V1/V2/V3 cold-start strategies locked
| Version | Strategy | Gas% accuracy | Notes |
|---------|---------|--------------|-------|
| V1 | Delta tracking only | N/A (rate + days_remaining only) | Ships first |
| V2 | Stamped tare from cylinder label | Full absolute gas% | User input at install |
| V3 | Self-heal anchor across complete refill cycle | Full absolute gas%, no user input | Long-cycle self-learning |

### Threshold values derived from first principles
| Threshold | Value | Basis |
|-----------|-------|-------|
| CYLINDER_REMOVED | < 2 kg | Kitchen object upper bound ~5kg |
| FRESH_CYLINDER_MIN | > 26 kg | BIS IS 3196 full cylinder minimum |
| REFILL_THRESHOLD | ΔG > 6 kg | Above max kitchen object; two-condition AND with FRESH_CYLINDER_MIN |
| LOW_GAS | gas% < 20% | ~2.84kg gas, ~9 days at average consumption |
| CRITICAL_GAS | gas% < 5% | ~710g gas, ~2 days |

### Key design decisions
1. Two-condition AND gate for anchor event: ΔG > 6kg AND G_new > 26kg (see L-040)
2. Conservative bias locked: always round gas estimate downward when uncertain (see L-043)
3. Delta tracking is reference-free — all rate analytics exact from boot 1 (see L-042)
4. Cold-start is mathematically unsolvable from sensor alone — V1 does not claim otherwise (see L-041)
5. 4-step calibration on cylinder change: remove cylinder → re-tare → place new cylinder → anchor event → locked

### Backlog ordered
| Priority | Item | Next action |
|----------|------|------------|
| 1 | 1A modular sketch port | NEXT SESSION |
| 2 | 1B structured Serial journal | After 1A |
| 3 | 1C timing instrumentation | After 1B |
| 4 | 1D noise floor recheck | After 1C |
| 5 | 3E-006B minimum event experiment | Post-install |
| 6-10 | 3E-007 to 3E-010 sensor experiments | After 3E-006B |
| 11-14 | Hub Groups 4-7 (SQLite, analytics, WebUI, alerts) | After sensor experiments |

---

## What was NOT done this session
- No code written
- No hardware touched
- No sketches modified
- 3E-005 self-deriving cal_factor without user input — still pending

---

## Next session — what to do first

**Task: 1A modular sketch port**

Port 3E004_cal_and_run.ino to modular structure:
- hx711.cpp / hx711.h — bit-bang, corrupt filters, wait_ready
- tare.cpp / tare.h — Phase 0+1 stability detection, tare derivation
- cal.cpp / cal.h — Phase 3 cal_factor derivation
- weight.cpp / weight.h — live weight loop, threshold, quality
- sketch.ino — pure orchestrator, calls module functions

Target board: ESP32-C3 SuperMini (unchanged)
cal_factor baseline: ~36 raw/g, self-derived each boot
Must include load cell health check before tare

Gate: modular sketch output identical to 3E004_cal_and_run.ino on real hardware.

---

## Reference
Full architecture decisions: GasCylMonitor_SessionDecisions_2026_06_16.docx
