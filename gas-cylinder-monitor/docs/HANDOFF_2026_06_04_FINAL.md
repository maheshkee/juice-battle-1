# SESSION HANDOFF — 2026-06-04 FINAL
# Gas Cylinder Monitor — New Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.

---

## Current position
Group 1 — WEIGHT. E-000 PASSED. E-001 is next.

| Experiment | Status | Date |
|---|---|---|
| E-000 raw read | PASSED | 2026-06-04 |
| E-001 tare + cal_factor + grams | NEXT | — |

---

## What this product is
LPG gas cylinder weight monitor. ESP32-C3 sensor node reads load cell via HX711,
computes gross weight in grams, sends over WiFi to Arduino UNO Q hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

Pipeline:
```
Load cell → HX711 → ESP32-C3 (WiFi) → UNO Q hub (Python, SQLite, WebUI)
```

The seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp on receipt.
Gas% is computed on hub only (needs steel from history). Node never computes gas%.

---

## Hardware
| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | 192.168.1.161, user arduino — hub only in V1 |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, Q1 on VCC line |
| YZC-161A 20kg load cell | single cell dev unit |
| Test weights | six 10g blocks, 82g adapter, 112g container, 227g speaker |

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
- DO NOT use v3.3.9 — flasher.exe missing on Windows (confirmed bug 2026-06-04)
- Board: ESP32C3 Dev Module
- Port: COM11 (shows as "ESP32 Family Device, Ozobot DRVKit" in Windows — correct device)
- USB CDC On Boot: ENABLED — mandatory for Serial output on native USB boards
- First flash only: hold BOOT → click Upload → release after 2s
- All subsequent flashes: automatic, no BOOT button needed
- Board URL (add as new line in Preferences, do not replace existing):
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

---

## Real measured outputs — E-000 (2026-06-04)
| Condition | Raw range | Spread |
|---|---|---|
| Unloaded (no weight) | -15200 to -15423 | ~223 raw |
| 30g weight on load cell | -11620 to -11872 | ~252 raw |
| Delta for 30g | ~3400 raw | — |
| Rough cal_factor | ~113 raw/g | rough only — E-001 derives properly |

---

## Sketches built so far
| Sketch | Location | Purpose |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | raw bit-bang read, E-000 experiment |
| STOP.ino | node/STOP/ | flash to halt ESP32 when rewiring |
| HW_VERIFY.ino | node/HW_VERIFY/ | 3-check hardware verification, flash anytime |

---

## What E-001 must build
In node/E001_tare_cal_grams/ create E001_tare_cal_grams.ino that:

1. Takes N=50 samples unloaded → computes tare (mean) and noise floor (std)
2. Prompts via Serial: "place known weight, send any key when ready"
3. Takes N=50 samples loaded → computes loaded mean
4. Derives cal_factor = (loaded_mean - tare) / known_weight_grams
5. Prints tare and cal_factor clearly
6. Enters continuous loop: reads raw → subtracts tare → divides by cal_factor → prints grams
7. Gate: stable grams output matching known weight within 5%

Known weights available: six 10g blocks (use multiples for reference weight).
known_weight_grams entered via Serial at runtime — never hardcoded.

---

## Key rules — never violate
| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare — always derived, never hardcoded |
| No library | raw bit-bang only, port from E-000 |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory — open-drain line |
| Sign-extend bit 23 | mandatory — two's complement |
| node/hub seam | node outputs grams only, never gas% |
| Two contexts | node/ and hub/ never blur |

---

## Key learnings from E-000 (do not re-derive)

### HX711 CMOS output rule
Output high = VCC. No internal voltage regulator.
HX711 at 3V3 VDD → DOUT swings at 3.3V → safe for ESP32-C3 GPIO.
HX711 at 5V VDD → DOUT swings at 5V → destroys ESP32-C3 GPIO (max 3.6V absolute).

### STM32 vs ESP32 — why 5V was safe before but not now
STM32U585 pins D6/D7 are 5V-tolerant (input protection diodes).
ESP32-C3 GPIO has no 5V tolerance. Same HX711, same 5V, different MCU = different outcome.

### ESP32 5V pin is not a regulated output
It is USB VBUS passthrough. Unregulated, no current limit, gives nothing on battery.
Never power sensors from it.

### HX711 at 3.3V vs 5V — performance verdict
Full-scale range: ±12.9 mV at 3.3V vs ±19.5 mV at 5V.
A 20kg load cell outputs ~10-15 mV at full load — both ranges cover it.
Internal noise: ~50 nV RMS, independent of VCC.
For our use case: 3.3V is a free lunch. Same effective performance, no GPIO damage risk.

### Why unloaded raw is negative
Wheatstone bridge manufacturing offset. Resistors never perfectly equal.
Unloaded: A- slightly higher than A+ → small negative raw. Normal. Expected.
This is the tare — subtracted away, not an error.

### bit-bang non-negotiables
- INPUT_PULLUP on DOUT — open-drain line, floats when not ready
- Wait for DOUT LOW before clocking — cannot clock early
- Sign-extend bit 23: if (value & 0x800000) value |= 0xFF000000
- Three corrupt filters: LONG_MIN, -1, 0x7FFFFF — always all three
- noInterrupts() for entire 25-pulse sequence — ISR corrupts gain selection
- 25th pulse mandatory — locks Channel A / Gain 128

---

## Folder structure
```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                                    ← CLI reads this first every session
├── node/                                        ← ESP32-C3 firmware
│   ├── E000_raw_read/E000_raw_read.ino          ← DONE — E-000 experiment
│   ├── STOP/STOP.ino                            ← flash to halt board
│   └── HW_VERIFY/HW_VERIFY.ino                 ← hardware verification
├── hub/                                         ← UNO Q Python (not started)
└── docs/
    ├── PLAN.md
    ├── SCOPE.md
    ├── RESEARCH.md                              ← ESP32-C3 findings appended
    ├── SESSIONS.md                              ← real outputs per session
    ├── LEARNINGS_AND_INSIGHTS.md               ← deep WHY knowledge base (L-001 to L-005)
    ├── PROJECT_CONTEXT.md                       ← updated: E-000 PASSED
    ├── HANDOFF_2026_06_04.md                   ← morning session (architecture)
    ├── HANDOFF_2026_06_04_SESSION2_E000.md     ← afternoon session (E-000 hardware)
    ├── HANDOFF_2026_06_04_FINAL.md             ← next chat entry point (this file)
    └── reference/
        ├── ARCHITECTURE.md
        ├── INTERFACE_CONTRACTS.md
        └── specs/
```

---

## Session start checklist for new chat
Before answering anything, confirm:
1. This document is read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: E-001 next
4. Wiring is still as locked above before powering hardware
5. Design E-001 in chat first, then give Claude Code CLI prompt to implement

---

## SCP command to save this file to the board
From Windows laptop terminal:
```
scp HANDOFF_2026_06_04_FINAL.md arduino@192.168.1.161:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_04_FINAL.md
```

Then on the board commit it:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add docs/HANDOFF_2026_06_04_FINAL.md && git commit -m "docs: add final handoff for next session" && git push
```

---

*End of handoff. New chat is ready to design E-001.*
