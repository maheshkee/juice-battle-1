# Session handoff - 2026-06-04 Session 2 (E-000 hardware bring-up)

## Session goal
ESP32-C3 + HX711 first raw read on real hardware. Gate: zero corrupt values, load cell responds to weight.

## Hardware confirmed in use
- ESP32-C3 SuperMini HW-466AB (COM11 on Windows)
- GISLAB HX711 module (green PCB, AVIAIC HX711 chip, Q1 transistor on VCC line)
- YZC-161A 20kg load cell
- Test weight: 30g block

## Wiring locked - do not change without re-verifying
### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Notes |
|---|---|---|
| 3V3 | VDD | NOT 5V - DOUT would swing to 5V and damage GPIO |
| GND | GND | |
| GPIO4 | SDO (DOUT) | Safe GPIO, not a strapping pin |
| GPIO3 | SCK | Safe GPIO, not a strapping pin |

### Load cell → HX711 (J2 right header)
| Load cell wire | HX711 pin |
|---|---|
| Red | E+ |
| Black | E- |
| Green | A+ |
| White | A- |

### Pins never to use for HX711
- GPIO2, GPIO8, GPIO9 - strapping pins, affect boot mode
- GPIO8 - also the onboard blue LED
- GPIO12-17 - internal flash (not broken out on SuperMini anyway)

## Arduino IDE setup - locked
- Board package: esp32 by Espressif Systems v3.0.7
- DO NOT USE v3.3.9 - flasher.exe missing bug confirmed on Windows 2026-06-04
- DO NOT USE Arduino ESP32 Boards by Arduino - wrong package
- Board: ESP32C3 Dev Module
- Port: COM11 (shows as "ESP32 Family Device, Ozobot DRVKit" in Windows - correct device)
- USB CDC On Boot: ENABLED - mandatory or Serial Monitor gets no output
- Add board URL in Preferences → Additional boards manager URLs (add on new line, do not replace existing):
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
- First flash only: hold BOOT button → click Upload → release after 2s
- All subsequent flashes: automatic, no BOOT button needed

## Real measured outputs - E-000
| Condition | Raw range | Spread |
|---|---|---|
| Unloaded (no weight) | -15200 to -15423 | ~223 raw |
| 30g weight on load cell | -11620 to -11872 | ~252 raw |
| Delta for 30g | ~3400 raw | - |
| Rough cal_factor | ~113 raw/g | rough only - E-001 derives properly |

## What was built this session
- node/E000_raw_read/E000_raw_read.ino - bit-bang raw read, three corrupt filters, no library
- node/HW_VERIFY/HW_VERIFY.ino - hardware verification LED blink sketch
- node/STOP/STOP.ino - blank stop sketch to halt ESP32

## Gate result
E-000: PASSED. Zero corrupt values. Load cell responds to weight. Ready for E-001.

## Next session: E-001
- Average N samples for stable tare
- Derive cal_factor from known weights (6x 10g blocks)
- Output in grams
- Self-characterise noise floor (std of N unloaded samples)
