# SESSION HANDOFF — 2026-06-08 FINAL
# Gas Cylinder Monitor — New Chat Entry Point
# Paste this into the next chat session to restore full context instantly.
# Read TRANSPORT_DECISION_BLE_ONLY.md on the board — transport is BLE-only, WiFi removed.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.

---

## Current position
Group 1 sensing COMPLETE. Group 2 transport COMPLETE.
Next: modular refactor → production node sketch.

| Experiment | Status | Date |
|---|---|---|
| E-000 raw read | PASSED | 2026-06-04 |
| E-001 tare + cal_factor + grams | PASSED | 2026-06-05 |
| E-002 noise floor characterisation | PASSED | 2026-06-08 |
| E-003 BLE transport validation | PASSED | 2026-06-08 |

---

## What this product is
LPG gas cylinder weight monitor. ESP32-C3 sensor node reads load cell via HX711,
computes gross weight in grams, sends over BLE to Arduino UNO Q hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

Pipeline:
```
Load cell → HX711 → ESP32-C3 (BLE GATT notify) → UNO Q hub (Python, BlueZ, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp on receipt.
Gas% computed on hub only. Node never computes gas%.

---

## Hardware
| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (use hostname — IP changes) |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip |
| YZC-161A 20kg load cell | single cell dev unit |
| Test weights | five ~10g blocks, speaker1 ~227g, speaker2 ~257g, mobile ~234g |

---

## Wiring — locked, do not change without re-verifying

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NOT 5V — DOUT would swing to 5V and damage GPIO |
| GND | GND | |
| GPIO4 | SDO (DOUT) | safe GPIO, not strapping pin |
| GPIO3 | SCK | safe GPIO, not strapping pin |

### Load cell → HX711 (J2 right header)
| Wire colour | HX711 pin |
|---|---|
| Red | E+ |
| Black | E- |
| Green | A+ |
| White | A- |

### Pins never to use for HX711
- GPIO2, GPIO8, GPIO9 — strapping pins, affect boot mode
- GPIO8 — also the onboard blue LED
- GPIO12-17 — internal flash (not broken out on SuperMini)

---

## Arduino IDE — locked setup
- Package: esp32 by Espressif Systems v3.0.7
- DO NOT use v3.3.9 — flasher.exe missing on Windows (confirmed bug)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory for Serial output
- First flash only: hold BOOT → click Upload → release after 2s
- All subsequent flashes: automatic

---

## BLE — locked
| Item | Value |
|---|---|
| Service UUID | aa206b91-235b-42aa-b370-453a3feedf35 |
| Weight Char UUID | b9b25bb1-f2a9-4545-b48f-295ab2789f41 |
| Device name | GasCylMonitor |
| Device MAC | 10:00:3B:CD:63:32 (cached in hub/config.json — not in code) |
| Characteristic props | NOTIFY |
| Payload | {"grams": float, "quality": "GOOD|DEGRADED|FAILED", "sigma": float} |

---

## Confirmed hardware values — ESP32-C3 era (all VERIFIED on real hardware)

### cal_factor (E-001)
~105 raw/g — derived at ~230g reference weight only.
CAUTION: single-point derivation. E-005 linearity check across full range pending.

### Tare range (self-derived every boot)
-11582 to -16156 raw — varies with temperature and mechanical state. Never hardcode.

### Noise floor — PRODUCTION VALUES (E-003, BLE running)
| Parameter | Value | Notes |
|---|---|---|
| Noise STD | 1.81g | BLE radio running — this is production condition |
| Threshold 4×STD | 7.24g | production value |
| vs E-002 (BLE off) | 0.67g | superseded — BLE-off is not production condition |

### Stability detection parameters (locked from E-002)
| Parameter | Value |
|---|---|
| STAB_WINDOW | 20 samples |
| STAB_SPREAD | 2.5g |
| STAB_MEAN_DIFF | 1.0g |
| STAB_CONFIRM | 3 consecutive windows |
| TARE_SAMPLES | 20 (derived after stability) |
| NOISE_SAMPLES | 200 |

---

## Boot sequence — locked (must be preserved in modular refactor)
```
1. Stability check (sliding window size=20, 2 conditions, 3 confirms)
2. Tare derivation (mean of stable window — AFTER stability only)
3. Noise characterisation (N=200 → STD → threshold = 4×STD)
4. BLE advertising starts (service UUID aa206b91-...)
5. Main loop (every 15s: N=20 samples → grams/quality/sigma → notify if connected)
```
Advertising starts only after tare AND noise are both derived.
Never start BLE before characterisation is complete.

---

## Hub — locked setup
Install: pip3 install -r hub/requirements.txt --break-system-packages
Run: python3 hub/e003_ble_test.py

### Critical platform notes (QRB2210)
- bleak service_uuids filter IGNORED on QRB2210 BlueZ — returns all nearby devices.
  Fix: application-layer name filter (implemented in e003_ble_test.py).
- BlueZ scan transport: "le" ONLY. "auto" kills QRB2210 Bluetooth adapter.
- BLE runs on QRB2210 Linux side via BlueZ — NOT on STM32 MCU.
- App Lab Docker cannot access BlueZ directly — socat D-Bus forwarding required.
  (Not needed for plain Python on host. Needed when moving to App Lab.)

### Hub self-provisioning (zero human intervention)
config.json starts with device_address: null.
First run: discovers ESP32 by name, caches MAC automatically.
Subsequent runs: uses cached MAC directly (Phase 1).
If ESP32 replaced: delete device_address from config.json → re-provisions.

---

## Sketches and hub files
| File | Location | Purpose |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | raw bit-bang read — E-000 |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | tare + cal_factor + grams — E-001 |
| E002_noise_floor.ino | node/E002_noise_floor/ | noise characterisation — E-002 |
| E003_ble_transport.ino | node/E003_ble_transport/ | BLE GATT server + full boot — E-003 |
| STOP.ino | node/STOP/ | flash to halt ESP32 when rewiring |
| HW_VERIFY.ino | node/HW_VERIFY/ | hardware verification |
| e003_ble_test.py | hub/ | BLE subscriber, self-provisioning |
| config.json | hub/ | device config, MAC cached after first run |
| requirements.txt | hub/ | bleak>=0.21.0 |

---

## What next session must build — modular refactor

Single-file E-003 sketch proven working. Now refactor into production modular structure.

### Module files to create (all in node/gas_cylinder_node/)
| File | Responsibility |
|---|---|
| hx711.h/.cpp | raw 24-bit bit-bang read, 3 corrupt filters, sign extension |
| tare.h/.cpp | sliding window stability check, tare derivation |
| noise.h/.cpp | N=200 characterisation, STD, threshold derivation |
| weight.h/.cpp | grams computation, quality assessment, sigma |
| ble.h/.cpp | GATT server, advertising, notify, connection callbacks |
| sketch.ino | pure orchestrator — setup/loop only, no sensor math |

### Module contract (non-negotiable)
Every module returns: {value, quality (GOOD/DEGRADED/FAILED), diagnosis string}
No module calls hx711_read() except hx711.cpp.
No blocking. No String class. No global variables shared across modules.
Orchestrator makes all decisions based on result.quality — never on raw values.

### Gate condition
Modular sketch behaviour identical to E-003 single file.
Same boot sequence. Same serial output. Same BLE payload format.
Same readings on hub terminal.

---

## Key rules — never violate
| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare, threshold — always derived |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory — open-drain line |
| Sign-extend bit 23 | mandatory — two's complement |
| Tare after stability | never derive tare before stability confirmed |
| Two-condition stability | spread < 2.5g AND mean drift < 1.0g between windows |
| Noise with BLE running | always characterise with BLE active — not BLE-off |
| node/hub seam | node outputs grams only, never gas% |
| bleak name filter | service_uuids filter ignored on QRB2210 — filter by name in app |
| BlueZ transport | "le" only — "auto" kills QRB2210 adapter |
| MAC in config.json | never hardcode MAC in source code |
| SCP hostname | always arduino@AQ3 — never IP address directly |

---

## Folder structure
```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── E000_raw_read/E000_raw_read.ino              ← DONE
│   ├── E001_tare_cal_grams/E001_tare_cal_grams.ino  ← DONE
│   ├── E002_noise_floor/E002_noise_floor.ino        ← DONE
│   ├── E003_ble_transport/E003_ble_transport.ino    ← DONE
│   ├── STOP/STOP.ino
│   └── HW_VERIFY/HW_VERIFY.ino
├── hub/
│   ├── e003_ble_test.py                             ← DONE
│   ├── config.json                                  ← DONE (MAC cached)
│   └── requirements.txt                             ← DONE
└── docs/
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── TRANSPORT_DECISION_BLE_ONLY.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_08_FINAL.md   ← this file
```

---

## Session start checklist for new chat
Before answering anything, confirm:
1. This document is read fully
2. TRANSPORT_DECISION_BLE_ONLY.md read — BLE only, no WiFi
3. Working mode: chat = design only, CLI = code only
4. Current position: E-003 PASSED, next = modular refactor
5. Noise production values: STD 1.81g, threshold 7.24g (BLE running)
6. Wiring unchanged — verify before powering hardware

---

## SCP command to save this file to the board
From Windows laptop terminal:
```
scp HANDOFF_2026_06_08_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_08_FINAL.md
```

---

*End of handoff. Next chat is ready to design modular refactor.*
