# SESSION HANDOFF - 2026-06-08 Session 1 - E-002 Complete

## Session goal
Design and validate E-002 noise floor characterisation on ESP32-C3.
Three sketch versions built. Dynamic stability detection implemented and validated.
E-002 declared PASSED. Decision made to proceed to Group 2 BLE transport.

## Gate result
E-002: PASSED

## Hardware
ESP32-C3 SuperMini + GISLAB HX711 + YZC-161A 20kg load cell
Wiring unchanged: GPIO4=DOUT, GPIO3=SCK, 3V3=VDD, GND=GND

## Real measured outputs
| Run | STD | Threshold | Tare correction | Settle reads |
|---|---|---|---|---|
| Clean run 1 (3 min off)  | 0.67g | 2.67g | 38 raw (0.36g) | 22 |
| Clean run 2 (30 min off) | 0.62g | 2.48g | 17 raw (0.16g) | 22 |

Production threshold locked: 2.67g

## Sketches built this session
node/E002_noise_floor/E002_noise_floor.ino - v3 final (tare after settle + mean drift check)

## Key decisions made
- Transport confirmed BLE-only (TRANSPORT_DECISION_BLE_ONLY.md locked)
- 16g minimum event = planning estimate only - E-006B required post-install
- cal_factor ~105 raw/g valid at ~230g only - E-005 required for full range
- Tare must be derived after stability confirmed
- Two-condition stability: spread < 2.5g AND mean drift < 1.0g between windows
- Proceeding to Group 2 BLE transport. Group 1 remaining experiments parked.

## Group 1 parked experiments (not forgotten)
- E-003 - modular refactor
- E-004 - measurement stability
- E-005 - cal_factor linearity (most important - affects production accuracy)
- E-006B - minimum event measurement (needs real cylinder)
- E-007B - threshold stress test (needs real installation)

## Next session
Group 2 BLE transport design.
1. Read TRANSPORT_DECISION_BLE_ONLY.md fully before starting
2. Define service UUID + characteristic UUID in chat - lock before any code
3. Design ESP32 GATT server in chat, then CLI
4. Design hub BlueZ subscriber in chat, then CLI
