# SESSION HANDOFF - 2026-06-15 SESSION 1
# Gas Cylinder Monitor - 3E-002 Noise Floor Complete

## Session goal
Complete 3E-002 noise floor characterisation on 3-cell platform.
Lock production noise_std_g and threshold_g.
Verify BLE EMI penalty on this hardware configuration.

## Gate result
3E-002 PASSED.

## Hardware used
ESP32-C3 SuperMini + GISLAB HX711 + 3x YZC-161A 20kg load cells
3-cell parallel, fibre plate (food plate), triangle arrangement
Twisted/soldered wiring - NOT breadboard

## Wiring (locked)
GPIO4 = DOUT (INPUT_PULLUP), GPIO3 = SCK
HX711 VDD = 3V3
All reds → E+, blacks → E-, greens → A+, whites → A-

## Real measured outputs this session

### HW_VERIFY_3CELL result
Raw stability CV: 0.108% - PASS
Cell 1 lift delta: -116.4g - PASS
Cell 2 lift delta: -119.0g - PASS
Cell 3 lift delta: -93.3g  - PASS
Derived cal_factor: 35.63 raw/g - PASS (consistent with locked 36.1)

### 3E-002 BLE OFF - all runs summary
| Run | noise_std_g | threshold_g |
|---|---|---|
| 1 | 2.22g | 8.87g  (outlier - cold boot) |
| 2 | 4.13g | 16.52g |
| 3 | 4.02g | 16.09g |
| 4 | 3.23g | 12.93g |
| 5 | 3.23g | 12.93g |
| 6 | 4.93g | 19.71g |

### 3E-002 BLE ON - all runs
| Run | noise_std_g | threshold_g | BLE penalty |
|---|---|---|---|
| B1 | 4.64g | 18.54g | ~1.0x |
| B2 | 3.51g | 14.03g | ~1.0x |

## Locked production constants
cal_factor        = 36.1 raw/g       LOCKED 2026-06-12
noise_std_g BLE-on = 4.64g           LOCKED 2026-06-15
threshold_g BLE-on = 18.54g          LOCKED 2026-06-15
BLE penalty        = ~1.0x            LOCKED 2026-06-15

## Sketches built this session
node/3E002_noise_floor_v1/         BLE off noise characterisation
node/3E002_noise_floor_v1_ble/     BLE on noise characterisation
node/HW_VERIFY_3CELL/              3-cell hardware diagnostic - permanent tool

## Next session targets
1. Design modular sketch architecture (hx711, tare, noise, weight, ble modules)
2. 3E-003: BLE transport - ESP32 sends {grams, quality, sigma} to hub
3. Hub Python BLE subscriber using bleak + socat (reuse motion-sensor-webui pattern)
4. Minimal WebUI: weight in grams on screen
5. DEMO: boss places weight → WebUI shows grams
Target: demo within 2 days
