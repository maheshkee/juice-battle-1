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
