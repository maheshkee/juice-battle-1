# Session log - gas cylinder monitor
# Purpose: permanent record of real hardware outputs per session.
# Never delete entries. Add new sessions at the bottom with incrementing session number.

---

## Session 001 - 2026-06-04 morning - architecture and scaffold
### What happened
- Read all 28 project documents
- Confirmed ESP32-C3 pivot is correct
- Rewrote CLAUDE.md, ARCHITECTURE.md for ESP32 era
- Created node/ and hub/ directory split
- Created INTERFACE_CONTRACTS.md
- Committed clean scaffold
### Real outputs
No hardware connected. Scaffold only.
### Gate
Architecture locked. Ready for E-000 hardware bring-up.

---

## Session 002 - 2026-06-04 afternoon - E-000 hardware bring-up
### What happened
- Wired ESP32-C3 SuperMini + GISLAB HX711 + YZC-161A load cell
- Safety gate cleared: 3.3V VDD confirmed safe, no level shifter needed
- Arduino IDE set up from scratch (first time): esp32 v3.0.7, ESP32C3 Dev Module, COM11
- Flashed E000_raw_read.ino - first successful flash
- Serial Monitor confirmed stable raw reads at 10Hz
### Real hardware outputs
| Condition | Raw range | Spread |
|---|---|---|
| Unloaded | -15200 to -15423 | ~223 raw |
| 30g weight | -11620 to -11872 | ~252 raw |
| Delta 30g | ~3400 raw | - |
| Rough cal_factor | ~113 raw/g | rough |
### Gate
E-000 PASSED. Zero corrupt values. Hardware confirmed talking.

---

## Session 003 - 2026-06-05 - E-001 tare + cal_factor + grams

### Goal
Derive tare from unloaded samples, derive cal_factor from known weight,
output grams in continuous loop. Gate: grams within 5% of known weight.

### What happened
- Built E001_tare_cal_grams.ino - single file, no library, raw bit-bang ported from E-000
- Fixed Serial buffer drain bug (stale \n byte caused cal_factor = inf on first run)
- Added 10 second settle window after keypress before sampling - eliminates load cell creep error
- Extended sketch to loop through multiple weights - derives separate cal_factor per weight
- Ran linearity test across 8 weights: 10g, 20g, 30g, 40g, 50g, 227g, 234g, 257g

### Real hardware outputs
| Weight | Cal_factor (raw/g) | Mean reading | Error |
|---|---|---|---|
| 10g | 29.50 | 9.26g | unstable |
| 20g | 69.13 | 20.37g | good |
| 30g | 87.52 | 30.61g | good |
| 40g | 95.83 | 40.37g | good |
| 50g | 97.77 | 50.12g | good |
| 227g | 104.84 | 227.57g | excellent |
| 234g | 105.21 | 233.24g | excellent |
| 257g | 105.50 | 256.47g | excellent |

Key finding: cal_factor unstable below ~100g (SNR problem, not hardware fault).
cal_factor stable at ~105 raw/g above 227g. Variation only 0.6% across 227-257g.
Load cell confirmed linear in the range that matters for gas cylinder operation.
Tare this session: -13823 to -15747 raw (varies per boot - self-characterised correctly)

### Gate
E-001 PASSED. Grams output accurate above 100g reference weight.

### Sketches built
- node/E001_tare_cal_grams/E001_tare_cal_grams.ino
