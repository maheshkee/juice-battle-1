# RESULTS - experiment 003-noise-characterisation
# Date: 2026-05-05
# Board: AQ3 at 192.168.1.161
# Status: COMPLETE

## Run 1
CAL_FACTOR  = 103.2721 raw/g
TARE        = -13456 raw
STD         = 2.3636g
PP          = 40.99g (outliers present)
THRESHOLD_G = 4.2281g
MEAN        = -1.714g

## Run 2
CAL_FACTOR  = 101.9114 raw/g
TARE        = -13039 raw
STD         = 1.3315g
PP          = 5.4557g (clean)
THRESHOLD_G = 2.3819g
MEAN        = -1.685g

## Summary
STD range        : 1.33-2.36g
THRESHOLD range  : 2.38-4.23g
MIN EVENT        : 16g (tea/coffee)
MARGIN worst case: 3.8x
MARGIN best case : 6.7x
PP unreliable    : use STD for threshold derivation
Self-characterise essential: 2x STD variation same board same day

## Platform finding
double arithmetic broken on STM32U585 - use float only in all MCU sketches

## Experiment status
COMPLETE. Noise module validated. Detector validated.
Next: experiment 004 modular sketch refactor.
