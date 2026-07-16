# SESSION HANDOFF — 2026-06-12 FINAL_2
# Gas Cylinder Monitor — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only. No sketch.yaml in prompts.

---

## Current position (one line)
3E-001 cal_factor COMPLETE AND PASSED. cal_factor = 36.1 raw/g locked. Next = 3E-002 noise floor characterisation on 3-cell platform.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify) → UNO Q hub (Python, BlueZ, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp, computes gas%.
Gas% = (gross − steel) / 14200 × 100. Never computed on node.

---

## Hardware

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — IP changes, never use IP) |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, 3.3V VCC only |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform — production configuration |
| Platform | Round wooden board ~400mm, 3 cells, shared plate on all cells |
| Wiring | Direct twisted/soldered — NOT breadboard |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V — would damage ESP32-C3 GPIO |
| GND | GND | |
| GPIO4 | SDO (DOUT) | INPUT_PULLUP mandatory |
| GPIO3 | SCK | OUTPUT |

### 3-cell parallel wiring
All 3 red wires → HX711 E+
All 3 black wires → HX711 E−
All 3 green wires → HX711 A+
All 3 white wires → HX711 A−
Direct to HX711 module pins. Twisted or soldered. NOT breadboard.

---

## Arduino IDE — locked setup

- Package: esp32 by Espressif Systems v3.0.7 (NOT v3.3.9 — flasher.exe missing on Windows)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- First flash after power: hold BOOT → Upload → release after 2s
- Subsequent flashes: automatic (CDC keeps port alive)

SCP to laptop (run from Windows terminal):
```
mkdir "C:\Users\mahes\Documents\Arduino\[sketch_name]"
scp arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/node/[sketch]/[sketch].ino "C:\Users\mahes\Documents\Arduino\[sketch]\[sketch].ino"
```

---

## Locked values — hardware-verified 2026-06-12

| Parameter | Value | Status |
|---|---|---|
| cal_factor (3-cell, shared plate) | 36.1 raw/g | ✅ PROVEN — 80+ readings, 3 stages, 200g–1800g |
| Linear range | 200g – 1800g | ✅ PROVEN — CV 4.1%, no curvature |
| Min reliable weight | ~150g | ✅ PROVEN — SNR floor |
| Cold boot settle (no plate) | 3–12s | ✅ PROVEN |
| Cold boot settle (with plate) | 60–161s | ✅ PROVEN |
| Placement → stable | 10s sufficient | ✅ PROVEN — all loaded_std ≤ noise_std |
| Removal → re-tare (light loads) | ~6s | ✅ PROVEN |
| Removal → re-tare (500g+) | up to 86s | ✅ PROVEN — viscoelastic recovery |
| 3-cell noise floor (BLE off) | ~2–5g equiv | ❓ ESTIMATE — must measure in 3E-002 |
| 3-cell noise floor (BLE on) | UNKNOWN | ❓ Must measure in 3E-002 |

---

## Experiment status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read (single cell) | ✅ PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare + cal + grams (single cell) | ✅ PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 3-cell) |
| E-002 noise floor (single cell) | ✅ PASSED 2026-06-08 | STD 0.67g BLE-off (VOID on 3-cell) |
| E-003 BLE transport (single cell) | ✅ PASSED 2026-06-08 | STD 1.81g BLE-on, threshold 7.24g (VOID on 3-cell) |
| 3E-001 cal_factor (3-cell) | ✅ PASSED 2026-06-12 | cal_factor = 36.1 raw/g, linear 200g–1800g |
| 3E-002 noise floor (3-cell) | ⏳ NEXT | BLE off then BLE on, derive STD and threshold |
| 3E-003 BLE transport (3-cell) | 📋 PLANNED | BLE GATT notify to AQ3 hub |
| 3E-004 measurement stability | 📋 PLANNED | Fixed load, extended duration |
| 3E-005 linearity/hysteresis formal | ✅ COVERED by 3E-001 Stage 3 | |
| 3E-006A anchor validation | 📋 PLANNED | Steel derivation with real cylinder |
| 3E-006B consumption validation | 📋 PLANNED | Min detectable cooking event (16g theoretical) |
| 3E-007A refill detection | 📋 PLANNED | |
| 3E-007B threshold stress test | 📋 PLANNED | |
| Thermal / long-term / diurnal studies | 📋 PLANNED | |

---

## Sketches built so far

| Sketch | Location on AQ3 | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE single cell |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE single cell |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE single cell |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE single cell BLE |
| 3E001_cal_factor_v5.ino | node/3E001_cal_factor_v5/ | DONE 3-cell cal Stage 1+2 |
| 3E001_cal_factor_v5_1.ino | node/3E001_cal_factor_v5_1/ | DONE + timing instrumentation |
| 3E001_cal_factor_v5_2.ino | node/3E001_cal_factor_v5_2/ | DONE + per-iteration weight entry (Stage 3) |
| STOP.ino | node/STOP/ | Available |
| HW_VERIFY.ino | node/HW_VERIFY/ | Available |

Hub: not yet started. hub/ directory exists but empty.

---

## Next experiment — 3E-002 noise floor

### Objective
Measure the true noise floor of the 3-cell platform in two conditions:
1. BLE off — baseline hardware noise
2. BLE on — noise with radio running (BLE EMI couples into HX711 analog front end)

Derive: STD in grams, detection threshold = 4 × STD.

### Why not use E-002/E-003 values
Those were measured on single-cell AQ3 platform. 3-cell has different sensitivity
(36.1 vs 106.7 raw/g). Same raw noise count = different gram noise. Must re-measure.

### What the sketch must do
1. Phase 0: settle platform (same as v5 logic — mandatory)
2. Phase 1: derive tare (same stability gate)
3. Phase 2: collect N=200 samples undisturbed — no weight changes
4. Compute STD in raw counts AND in grams (using locked cal_factor = 36.1)
5. Compute threshold = 4 × STD_grams
6. Print: noise_std_raw, noise_std_grams, threshold_grams
7. Print grams reading live using: grams = (raw_mean - tare_raw) / 36.1
8. For BLE-on run: BLE advertising must be active during measurement
   (same BLE code as E-003 — copy GATT server setup)
9. Run should be at least 5 minutes of continuous sampling to get a stable estimate

### Sketch name
3E002_noise_floor_v1

### Key rules (never violate)
- GPIO4 = DOUT, GPIO3 = SCK. Never change.
- No HX711 library. Raw bit-bang only.
- Three corrupt filters: LONG_MIN, -1, 0x7FFFFF
- noInterrupts()/interrupts() around 25-pulse sequence
- INPUT_PULLUP on DOUT
- Sign-extend bit 23
- float only, no double
- millis() pacing, no blocking in loop()
- No String class — snprintf into char buf[]
- cal_factor = 36.1 hardcoded ONLY for grams display — this is the one place
  a derived-and-locked constant may appear. Comment clearly: "LOCKED 2026-06-12"

---

## v5 sketch architecture — reference for 3E-002

Phase 0 — PHASE_SETTLING:
  200 samples per block → block_std, block_mean
  Pass: block_std < 500 raw AND |block_mean - prev| < 500 raw
  Need 3 consecutive passing blocks
  Output: noise_std_raw = block_std of last passing block

Phase 1 — PHASE_STABILISING:
  spread_gate = 1.5 × noise_std_raw
  drift_gate = 1.0 × noise_std_raw
  20-sample windows, 3 consecutive passes required
  Output: tare_raw = window_mean

Phase 2+ (3E-001 specific) — human gate, measurement, re-tare loop
  NOT needed in 3E-002. After tare, just collect samples continuously.

waitForEnter() helper (use in 3E-002 wherever human sync needed):
  delay(2000);                           // mandatory — prevents stale Enter skip
  while(Serial.available()) Serial.read(); // flush
  Serial.println(prompt);
  Serial.println(">>> Press Enter when ready <<<");
  while(!Serial.available()) { delay(10); }
  while(Serial.available()) Serial.read(); // consume Enter

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived — except cal_factor in gram display which is locked-and-labelled |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory for two's complement |
| HX711 VCC = 3V3 only | NEVER 5V |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | double broken on STM32U585 — use float as safe default |
| Tare after stability | never tare before Phase 0 + Phase 1 complete |
| Serial flush before gates | mandatory before every readStringUntil() |
| Window STD not max-min | max-min is outlier-sensitive |
| Phase 0 before Phase 1 | never characterise noise during drift |
| Stability gates in raw counts | never in grams — gram gates have hidden cal_factor dependency |
| waitForEnter() 2s dwell | never reduce — prevents stale Enter byte gate skip |
| BLE transport | BlueZ on QRB2210: "le" transport only, name filter not service_uuids |
| SCP hostname | always arduino@AQ3 — never IP address |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                          ← CLI briefing — read first
├── node/
│   ├── E000_raw_read/
│   ├── E001_tare_cal_grams/
│   ├── E002_noise_floor/
│   ├── E003_ble_transport/
│   ├── 3E001_cal_factor_v5/           ← Stage 1+2
│   ├── 3E001_cal_factor_v5_1/         ← + timing
│   ├── 3E001_cal_factor_v5_2/         ← + per-iteration weight (Stage 3)
│   ├── STOP/
│   └── HW_VERIFY/
├── hub/                               ← empty — not yet started
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── EXPERIMENT_PROGRAM.md
    ├── EXPERIMENT_HISTORY.md
    ├── HANDOFF_2026_06_12_FINAL.md    ← previous (start of today)
    └── HANDOFF_2026_06_12_FINAL_2.md  ← this file
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only. No sketch.yaml in prompts.
3. Current position: 3E-001 COMPLETE. 3E-002 is next.
4. Platform: 3-cell YZC-161A parallel, shared plate. cal_factor = 36.1 raw/g LOCKED.
5. Noise floor for 3-cell: NOT YET MEASURED. E-003 values are void here.
6. Next sketch: 3E002_noise_floor_v1 — BLE off run first, BLE on run second.
7. Gram display in 3E-002: use locked cal_factor = 36.1 with clear label comment.
8. All sketch development via Claude Code CLI on AQ3. SCP to Windows for flashing.

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor.
Read HANDOFF_2026_06_12_FINAL_2.md fully before responding.
Context: 3E-001 COMPLETE. cal_factor = 36.1 raw/g locked for 3-cell platform.
Today we design and run 3E-002 noise floor characterisation — BLE off, then BLE on.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready to build 3E-002.*
