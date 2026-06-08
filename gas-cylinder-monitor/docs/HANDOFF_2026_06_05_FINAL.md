# SESSION HANDOFF — 2026-06-05 FINAL
# Gas Cylinder Monitor — New Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.

---

## Current position
Group 1 — WEIGHT. E-001 PASSED. E-002 is next.

| Experiment | Status | Date |
|---|---|---|
| E-000 raw read | PASSED | 2026-06-04 |
| E-001 tare + cal_factor + grams | PASSED | 2026-06-05 |
| E-002 noise floor characterisation | NEXT | — |

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

## Confirmed hardware values — ESP32-C3 era

### cal_factor (locked for this hardware combination)
| Reference weight | cal_factor | Verdict |
|---|---|---|
| 10g | 29.50 raw/g | VOID — SNR too low |
| 20–50g | 69–98 raw/g | unstable — SNR marginal |
| 227g | 104.84 raw/g | GOOD |
| 234g | 105.21 raw/g | GOOD |
| 257g | 105.50 raw/g | GOOD |

**Locked production value: ~105 raw/g** [DERIVED — pending E-005 for full range]
Rule: always derive cal_factor from reference weight above 150g minimum.

### Tare range (ESP32-C3, varies per boot)
-13823 to -15747 raw — self-characterised every boot, do not hardcode.

### Noise floor (UNKNOWN — E-002 will measure)
Not yet characterised on ESP32-C3. Do not carry STM32 values forward.

---

## Sketches built so far
| Sketch | Location | Purpose |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | raw bit-bang read, E-000 experiment |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | tare + cal_factor + grams loop |
| STOP.ino | node/STOP/ | flash to halt ESP32 when rewiring |
| HW_VERIFY.ino | node/HW_VERIFY/ | hardware verification |

---

## What E-002 must build
In node/E002_noise_floor/ create E002_noise_floor.ino that:

1. Boot with nothing on load cell
2. Takes N=200 samples → computes:
   - mean (tare)
   - STD (noise floor)
   - peak-to-peak range
   - event detection threshold = 4 × STD
3. Prints full characterisation report to Serial
4. Enters continuous loop printing grams at 500ms so noise is visible in real time
5. Gate: STD measured and threshold derived. Compare to STM32 values (STD ~1.87g, threshold ~6g)

No library. Raw bit-bang only. Port from E-001.
Same corrupt filters: LONG_MIN, -1, 0x7FFFFF — always all three.
Use float throughout, never double.
N=200 for statistical confidence (more samples = tighter estimate of true STD).

---

## Key rules — never violate
| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare, known_weight_g — always derived, never hardcoded |
| No library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory — open-drain line |
| Sign-extend bit 23 | mandatory — two's complement |
| 10s settle window | mandatory after any load change before sampling |
| Serial buffer flush | while (Serial.available()) Serial.read() before every user prompt |
| cal_factor reference weight | must be above 150g for reliable derivation |
| node/hub seam | node outputs grams only, never gas% |

---

## Key learnings (do not re-derive)

### cal_factor SNR regime
cal_factor = (loaded_mean - tare) / known_weight_g
Signal = known_weight × cal_factor raw counts.
Noise = ±200 raw peak on this hardware.
Below ~100g reference: noise is >10% of signal → cal_factor contaminated.
Above ~200g reference: noise is <1% of signal → cal_factor stable.
Rule: reference weight must produce signal at least 20× peak noise.

### Load cell mechanical creep
Metal strain gauge beams deform elastically but not instantaneously.
After load placement, raw values drift for 5–15 seconds as stress redistributes.
Sampling during creep = biased low readings = wrong cal_factor.
Fix: always wait 10 seconds after load change before sampling begins.

### Serial buffer drain
Opening Serial Monitor sends \n into ESP32 buffer.
readStringUntil('\n') finds this stale byte and returns immediately with empty string.
toFloat("") = 0.0. Division by 0.0 = inf cal_factor.
Fix: while (Serial.available()) Serial.read() before every readStringUntil call.

### HX711 at 3.3V vs 5V
3.3V VDD: DOUT swings at 3.3V — safe for ESP32-C3 GPIO (max 3.6V absolute).
5V VDD: DOUT swings at 5V — destroys ESP32-C3 GPIO.
Performance: 3.3V gives slightly smaller full-scale range but adequate for 20kg cell.

---

## Folder structure
```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── E000_raw_read/E000_raw_read.ino     ← DONE
│   ├── E001_tare_cal_grams/E001_tare_cal_grams.ino  ← DONE
│   ├── STOP/STOP.ino
│   └── HW_VERIFY/HW_VERIFY.ino
├── hub/                                     ← not started
└── docs/
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── HANDOFF_2026_06_05_SESSION1_E001.md
    └── HANDOFF_2026_06_05_FINAL.md          ← this file
```

---

## Session start checklist for new chat
Before answering anything, confirm:
1. This document is read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: E-002 next
4. Wiring is still as locked above before powering hardware
5. Design E-002 in chat first, then give Claude Code CLI prompt to implement

---

## SCP command to save this file to the board
From Windows laptop terminal:
```
scp HANDOFF_2026_06_05_FINAL.md arduino@192.168.1.161:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_05_FINAL.md
```

Then on the board commit it:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add docs/HANDOFF_2026_06_05_FINAL.md && git commit -m "docs: add final handoff for next session" && git push
```

---

*End of handoff. New chat is ready to design E-002.*
