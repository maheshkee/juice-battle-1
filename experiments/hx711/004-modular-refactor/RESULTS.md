# RESULTS - Experiment 004 Modular Refactor
# Date: 2026-05-06
# Board: AQ3

## Objective
Refactor flat 003 sketch into modular hx711/tare/noise/cal/delta modules.
Verify identical behaviour to 003.

## Run 1
CAL_FACTOR  : 103.6392
TARE        : -14292
STD         : 3.2837g
PP          : 14.9750g
THRESHOLD   : 5.8741g
False triggers on stable weight: 0

## Run 2
CAL_FACTOR  : 105.6519
TARE        : -13550
STD         : 3.9286g
PP          : 15.6836g
THRESHOLD   : 7.0276g
False triggers on stable weight: 0

## Verdict
PASS - modular architecture working
PASS - physical WAIT state detection working
PASS - weight detection in CAL_WAIT working
PASS - no false triggers on stable weight
PASS - AVG values track actual placed weights accurately
PASS - self-characterisation produces different threshold each run (correct)

## Key improvements over 003
- TARE_WAIT: detects stable empty scale physically, not dumb timer
- CAL_WAIT: detects weight placement physically, not dumb timer
- NOISE_WAIT: detects stable empty scale physically, not dumb timer
- TARE has 5 correct status values: BUSY/RETRY/DEGRADED/SUCCESS/FAILED
- All modules isolated - sketch.ino is pure orchestrator
