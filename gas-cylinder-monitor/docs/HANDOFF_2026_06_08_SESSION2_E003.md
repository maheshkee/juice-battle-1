# SESSION HANDOFF - 2026-06-08 Session 2
# E-003 BLE Transport PASSED
# This is the session record. For next chat entry point, use HANDOFF_2026_06_08_FINAL.md

## Session goal
Design and validate BLE transport: ESP32-C3 GATT server → UNO Q hub BlueZ subscriber.

## Gate result
E-003 PASSED.
[2026-06-08T17:14:25] grams=246.2g  quality=GOOD  sigma=0.49g

## Real hardware outputs
| Parameter | Value |
|---|---|
| Tare | -15588 raw |
| Noise STD (BLE running) | 1.81g |
| Noise threshold | 7.24g |
| Speaker weight confirmed | 244-247g |
| DEGRADED sigma (transition) | 97.65g |
| ESP32 MAC | 10:00:3B:CD:63:32 |

## Files created
node/E003_ble_transport/E003_ble_transport.ino
hub/e003_ble_test.py
hub/config.json
hub/requirements.txt

## Key findings
- bleak service_uuids filter ignored on QRB2210 - name filter in app layer (L-020)
- MAC self-provisioning pattern - null → discover → cache (L-021)
- Noise 3× higher with BLE running (L-022) - 1.81g is production value
- DEGRADED correctly fired during transition (L-023)

## Next session
Modular refactor: hx711/tare/noise/weight/ble as separate .h/.cpp modules.
sketch.ino = pure orchestrator.
Gate: behaviour identical to E-003 single file.
