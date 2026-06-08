# SESSION HANDOFF — 2026-06-08 FINAL
# Gas Cylinder Monitor — New Chat Entry Point
# Paste this into the next chat session to restore full context instantly.
# Also read docs/TRANSPORT_DECISION_BLE_ONLY.md — transport has changed from WiFi to BLE-only.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.

---

## Current position
Group 1 — WEIGHT. E-002 PASSED. E-003 (BLE transport) is next.

| Experiment | Status | Date |
|---|---|---|
| E-000 raw read | PASSED | 2026-06-04 |
| E-001 tare + cal_factor + grams | PASSED | 2026-06-05 |
| E-002 noise floor characterisation | PASSED | 2026-06-08 |
| E-003 BLE transport validation | NEXT | — |

---

## What this product is
LPG gas cylinder weight monitor. ESP32-C3 sensor node reads load cell via HX711,
computes gross weight in grams, sends over BLE to Arduino UNO Q hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

Pipeline:
```
Load cell → HX711 → ESP32-C3 (BLE) → UNO Q hub (Python, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely. See TRANSPORT_DECISION_BLE_ONLY.md.
The seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp on receipt.
Gas% is computed on hub only (needs steel from history). Node never computes gas%.

---

## Hardware
| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (use hostname, not IP — IP changes) |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, Q1 on VCC line |
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
- All subsequent flashes: automatic, no BOOT button needed

---

## Confirmed hardware values — ESP32-C3 era (all VERIFIED on real hardware)

### cal_factor (E-001)
~105 raw/g — derived at ~230g reference weight only.
CAUTION: single-point derivation. E-005 linearity check across full range pending.
If E-005 shows cal_factor changes materially at higher loads, E-002 must be re-run.

### Tare range (self-derived every boot)
-11582 to -16156 raw — varies with temperature and mechanical state. Never hardcode.

### Noise floor (E-002, locked 2026-06-08)
| Parameter | Value | Notes |
|---|---|---|
| Noise STD | 0.62–0.67g | two clean runs (3 min and 30 min power off) |
| Peak-to-peak | 3.18–3.47g | same conditions |
| Threshold 4×STD | 2.67g | production value (conservative upper bound) |
| Settle reads | 22 (2.2 seconds) | dynamic stability detection |
| HX711 sample rate | 10Hz | RATE pin LOW on GISLAB module |
| vs STM32 | better | STM32 was 1.87g STD |

### Stability detection parameters (locked)
| Parameter | Value |
|---|---|
| STAB_WINDOW | 20 samples |
| STAB_SPREAD | 2.5g |
| STAB_MEAN_DIFF | 1.0g |
| STAB_CONFIRM | 3 consecutive windows |
| TARE_SAMPLES | 20 (derived after stability) |

---

## Transport — BLE only (locked 2026-06-05)
WiFi removed entirely. See docs/TRANSPORT_DECISION_BLE_ONLY.md for full decision record.
- ESP32 advertises, hub connects and subscribes via BlueZ
- Seam contract unchanged: {grams, quality, sigma}
- Hub stamps timestamp on receipt
- Best-effort delivery, no local storage on ESP32
- UUIDs: not yet defined — define in chat before any Group 2 code

---

## Sketches built so far
| Sketch | Location | Purpose |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | raw bit-bang read, E-000 experiment |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | tare + cal_factor + grams loop |
| E002_noise_floor.ino | node/E002_noise_floor/ | noise characterisation v3 — FINAL |
| STOP.ino | node/STOP/ | flash to halt ESP32 when rewiring |
| HW_VERIFY.ino | node/HW_VERIFY/ | hardware verification |

---

## What Group 2 must build (next)
BLE transport — ESP32-C3 GATT server + UNO Q hub BlueZ subscriber.

Before writing any code:
1. Read TRANSPORT_DECISION_BLE_ONLY.md fully
2. Define service UUID and characteristic UUID in chat (128-bit, random, project-specific)
3. Lock UUIDs in TRANSPORT_DECISION_BLE_ONLY.md before any code is written
4. Design ESP32 side in chat, then CLI
5. Design hub side in chat, then CLI

ESP32 side:
- BLE GATT server, one service, one notify characteristic
- Advertise forever, hub connects and subscribes
- On subscribe: send weight notifications at heartbeat rhythm
- Library: Arduino ESP32 BLE (BLEDevice, BLEServer, BLECharacteristic)

Hub side:
- BlueZ scan for ESP32 service UUID
- Connect + subscribe to weight characteristic
- On notification: parse JSON {grams, quality, sigma}, stamp timestamp
- Auto-reconnect within 30 seconds
- socat D-Bus forwarding (pattern from motion-sensor-webui)
- Language: Python (App Lab)

Gate condition for Group 2:
One weight reading travels from ESP32-C3 to UNO Q hub via BLE and arrives correctly
in hub Python process with hub-stamped timestamp.
Auto-reconnect after hub reboot completes within 30 seconds automatically.

## Group 1 remaining experiments — parked, not forgotten
These are not blocking Group 2. Will revisit after Group 2 gate passes.
- E-003 — modular refactor (hx711/tare/cal/noise as .h/.cpp modules)
- E-004 — measurement stability, plateau detection
- E-005 — cal_factor linearity across full 0–20kg range (important before production)
- E-006B — minimum detectable consumption (needs real cylinder installed)
- E-007B — threshold stress test, false positive rate (needs real installation)

---

## Key rules — never violate
| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare, threshold — always derived |
| No library | raw bit-bang only for HX711 |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory — open-drain line |
| Sign-extend bit 23 | mandatory — two's complement |
| Tare after stability | never derive tare before stability confirmed |
| Two-condition stability | spread < 2.5g AND mean drift < 1.0g between windows |
| node/hub seam | node outputs grams only, never gas% |
| cal_factor caveat | ~105 raw/g valid at 230g only — E-005 pending |
| 16g minimum event | planning estimate only — E-006B needed post-install |
| SCP hostname | always arduino@AQ3 — never use IP address directly |

---

## Key learnings from 2026-06-08 session (L-008 to L-017)
- L-008: Why noise differs across MCUs (5 sources: power, SCK timing, GPIO drive, interrupts, wiring)
- L-009: Load cell physics — creep vs noise — completely different phenomena
- L-010: Why fixed timer fails for stability detection
- L-011: Dynamic stability — two conditions required (spread + mean drift)
- L-012: Tare must be derived after stability, not before
- L-013: Why N=200 samples (SE formula derivation — 5% accuracy vs boot time tradeoff)
- L-014: Why 4×STD threshold (Gaussian statistics, 0.0063% false positive rate)
- L-015: Why 500ms in live loop (hardware floor 100ms + human readability)
- L-016: 16g minimum event is unvalidated estimate — E-006B required
- L-017: cal_factor must be re-verified across full 0–20kg range (E-005)

---

## Folder structure
```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── E000_raw_read/E000_raw_read.ino          ← DONE
│   ├── E001_tare_cal_grams/E001_tare_cal_grams.ino ← DONE
│   ├── E002_noise_floor/E002_noise_floor.ino    ← DONE v3
│   ├── STOP/STOP.ino
│   └── HW_VERIFY/HW_VERIFY.ino
├── hub/                                         ← not started
└── docs/
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── TRANSPORT_DECISION_BLE_ONLY.md           ← READ THIS for Group 2
    ├── HANDOFF_2026_06_08_SESSION1_E002.md
    └── HANDOFF_2026_06_08_FINAL.md              ← this file
```

---

## Session start checklist for new chat
Before answering anything, confirm:
1. This document is read fully
2. TRANSPORT_DECISION_BLE_ONLY.md is read — BLE only, no WiFi
3. Working mode: chat = design only, CLI = code only
4. Current position: E-003 next (Group 2 BLE transport)
5. Next = Group 2 BLE transport — design UUIDs in chat before any code
6. Wiring unchanged — verify before powering hardware

---

## SCP command to save this file to the board
From Windows laptop terminal:
```
scp HANDOFF_2026_06_08_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_08_FINAL.md
```

Then on the board commit:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs(E-002): session close — E-002 PASSED, dynamic stability detection locked" && git push
```

---

*End of handoff. Next chat is ready to design E-003 BLE transport.*
