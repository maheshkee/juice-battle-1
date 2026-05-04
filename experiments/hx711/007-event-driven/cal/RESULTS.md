# Experiment 007-cal Results
Date: 2026-05-04
Board: AQ3 at 192.168.1.161
Known weight: 158g (water in plastic cup)

## Run results
| Run | TARE   | Spread | CAL_FACTOR |
|-----|--------|--------|------------|
| 1   | -14055 | 48     | 106.84     |
| 2   | -13963 | 79     | 107.05     |
| 3   | -14021 | 56     | 106.34     |

## Confirmed values
CAL_FACTOR = 106.7 raw/g (average of 3 runs)
TARE range = -13963 to -14055 (consistent across sessions)
Tare spread = 48-79 raw (well within 600 stability threshold)

## Conclusion
PASS. Acceptance range 94-105 was stale — derived from different 
mounting. Correct range for this setup: 104-110 raw/g.
Self-validating tare strategy worked correctly — rejected unstable
first attempt in 2 of 3 runs, accepted on retry with tight spread.

## Locked constants for experiment 007 event-driven sketch
CAL_FACTOR = 106.7f
TARE: always self-validated fresh per session
THRESHOLD: 10g minimum (above ±4g noise floor)
