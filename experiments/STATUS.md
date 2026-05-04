# Experiments Status
**Last updated:** 2026-05-02

## Board
AQ3 at 192.168.1.161

## Completed experiments
- 001-freeze-test: H1 confirmed. RESULTS.md and CONCLUSION.md filled.
  Learnings L1/L2/L3 graduated to LEARNINGS.md.

## Active experiments  
- 006-water-spoon-test Part A: COMPLETE
  Results: W1=130g, W2=123.71g, W3=118.36g
  Detections: -6.29g and -5.35g — both clean
  RESULTS.md and CONCLUSION.md need filling.

- 006-water-spoon-test Part B: PENDING
  Needs measuring tool (syringe or 10ml cup) — afternoon session.

## Queued experiments
- 002: Noise baseline (10Hz vs 80Hz spread)
- 003: Averaging accuracy
- 004: Stability detection threshold  
- 005: Calibration linearity
Note: 006 Part A partially covers 003/004.

## Calibration state (this hardware, 2026-05-02)
TARE = -13086 raw units
CAL_FACTOR = 103.02 raw/g
grams = (raw_value - (-13086)) / 103.02

## Next actions
1. Fill 006 Part A RESULTS.md and CONCLUSION.md
2. Run 006 Part B this afternoon
3. Run 002 noise baseline
4. Graduate all learnings to production home-hub
