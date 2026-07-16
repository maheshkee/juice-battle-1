# SESSION HANDOFF - 2026-06-05 SESSION 1
# Gas Cylinder Monitor - E-001 complete

## Current position
Group 1 - WEIGHT. E-001 PASSED. E-002 is next.

## Gate result
E-001 PASSED 2026-06-05.
Grams output accurate to within 1% above 100g reference weight.
cal_factor confirmed ~105 raw/g on ESP32-C3 hardware.

## Real outputs this session
| Weight | Cal_factor | Mean reading | Verdict |
|---|---|---|---|
| 10g | 29.50 raw/g | 9.26g | unstable - SNR too low |
| 20g | 69.13 raw/g | 20.37g | good |
| 30g | 87.52 raw/g | 30.61g | good |
| 40g | 95.83 raw/g | 40.37g | good |
| 50g | 97.77 raw/g | 50.12g | good |
| 227g | 104.84 raw/g | 227.57g | excellent |
| 234g | 105.21 raw/g | 233.24g | excellent |
| 257g | 105.50 raw/g | 256.47g | excellent |

## Key rules confirmed this session
- Serial buffer drain mandatory before every user input prompt
- 10 second settle window mandatory after weight placement before sampling
- cal_factor reference weight must be above 100g for reliable derivation
- cal_factor ~105 raw/g locked for this hardware combination

## Next: E-002 noise floor characterisation
Objective: measure noise floor STD on ESP32-C3. Derive event detection threshold.
Same approach as STM32 experiment 003 but fresh derivation on new platform.
Expected: STD ~1-3g, threshold 4× STD.

## Sketches on board
- node/E000_raw_read/E000_raw_read.ino - DONE
- node/E001_tare_cal_grams/E001_tare_cal_grams.ino - DONE
- node/STOP/STOP.ino
- node/HW_VERIFY/HW_VERIFY.ino
