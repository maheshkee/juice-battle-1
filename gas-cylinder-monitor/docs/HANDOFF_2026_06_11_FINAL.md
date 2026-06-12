# SESSION HANDOFF — 2026-06-11 FINAL
# Gas Cylinder Monitor — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.

---

## Current position

Group 1 (single cell) COMPLETE. Group 2 (transport) COMPLETE.
4-cell pivot in progress. 4E-000 bring-up PASSED with key learnings.
Next immediate task: redesign sketch for auto-retare scale mode, then 4E-001 cal_factor.

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read (single cell) | PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare + cal + grams (single cell) | PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 4-cell) |
| E-002 noise floor (single cell) | PASSED 2026-06-08 | STD 0.67g BLE-off |
| E-003 BLE transport (single cell) | PASSED 2026-06-08 | STD 1.81g BLE-on, threshold 7.24g |
| 4E-000 4-cell bring-up | PASSED 2026-06-11 | All 4 cells confirmed working |

---

## What this product is

LPG gas cylinder weight monitor. ESP32-C3 sensor node reads load cell via HX711,
computes gross weight in grams, sends over BLE to Arduino UNO Q hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

Pipeline:
```
4× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify) → UNO Q hub (Python, BlueZ, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp.
Gas% computed on hub only. Node never computes gas%.

---

## Hardware

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — IP changes) |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip |
| YZC-161A 20kg load cells ×4 | Setup B — 4 independent plates, one cell per plate |
| Platform | wooden board, 4 cells bolted down — wire-exit end bolted, smooth end faces up |
| Test weights | mobile ~234g, various small objects |

---

## Setup B — 4 independent plates (critical context)

This is NOT a shared single platform (Setup A).
Each load cell has its own small plate. Weights are placed on individual plates.
This means:
- Corner-lift test does NOT apply — lifting one plate removes only that cell's load
- Tare = sum of all 4 plate weights (each cell carries its own plate)
- Production target is Setup A (shared 380×380mm aluminium platform) — Setup B is bench test only

---

## Wiring — locked, do not change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V |
| GND | GND | |
| GPIO4 | SDO (DOUT) | |
| GPIO3 | SCK | |

### 4-cell parallel wiring
All 4 red wires twisted together → single wire → HX711 E+
All 4 black wires twisted together → single wire → HX711 E−
All 4 green wires twisted together → single wire → HX711 A+
All 4 white wires twisted together → single wire → HX711 A−
Direct to HX711 module pins — NOT through breadboard.

### Pins never to use for HX711
GPIO2, GPIO8, GPIO9 — strapping pins
GPIO12-17 — internal flash

---

## Arduino IDE — locked setup

- Package: esp32 by Espressif Systems v3.0.7 (NOT v3.3.9 — flasher.exe missing)
- Board: ESP32C3 Dev Module
- Port: COM11 (Windows laptop: user mahes)
- USB CDC On Boot: ENABLED — mandatory
- First flash: hold BOOT → Upload → release after 2s
- Subsequent flashes: automatic

SCP to laptop (run from Windows terminal):
```
scp arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/node/[sketch]/[sketch].ino "C:\Users\mahes\Documents\Arduino\[sketch]\[sketch].ino"
```

---

## 4-cell confirmed hardware values (2026-06-11)

### Stability gate (proven working)
- WIN_SIZE = 20 samples
- WIN_SPREAD_MAX = 300 raw
- WIN_DRIFT_MAX = 200 raw
- WIN_CONFIRM = 3 consecutive windows
- Time to stable: 65–73 seconds (cold boot, thermally unloaded)

### Tare values observed (Run 1 = 85420, Run 2 = 86567)
Note: tare varies between boots — always re-derived, never hardcoded.

### Noise floor (empty platform, thermally stable)
- Individual sample noise: ±200 raw peak-to-peak
- AVG(20) noise: ±170 counts stable
- Estimated ~6–7g at expected 4-cell cal_factor

### Expected 4-cell cal_factor
~26 raw/g (theoretical: single-cell 105 / 4 = ~26)
Must be re-derived in 4E-001. This is estimate only.

### Creep recovery time
After extended loading: 20–30 minutes for full beam recovery.
This is NOT a product problem (gas cylinder sits permanently loaded).
For scale/weighing mode: use auto-retare on empty detection — see below.

---

## Key finding from 4E-000 this session

### 4E-000 PASSED — all 4 cells confirmed
Evidence:
- Clean readings, no corrupt values, no spikes
- Negative deltas down to −7,266 counts (only possible if all 4 cells active)
- Symmetric up/down response to loading/unloading
- Stable ~6,800 count delta for 234g mobile (consistent with ~29 raw/g)
- Multiple place/remove cycles all registered correctly

### Post-creep recovery discovered
Running sketch after a loaded session showed empty-platform delta drifting from 0
down to −7,266 over ~38 AVG blocks (~7 minutes) with NOTHING on the plates.
This is beam spring-back from previous session's loading.
Not a fault — normal viscoelastic physics.
Fix for scale mode: auto-retare on empty detection (see below).

---

## Critical insight unlocked this session: scale mode vs gas cylinder mode

### Gas cylinder mode (current target)
- Platform loaded continuously for 30 days
- Creep settles once, stays settled
- Single tare at install, permanent
- 20-minute settle is fine — once a month event

### Scale/weighing mode (future capability)
- Platform loaded and unloaded repeatedly in quick succession
- 20-minute creep wait is unacceptable
- Solution: AUTO-RETARE ON EMPTY DETECTION
  - When platform drops to near-zero (delta < threshold for N windows): retare immediately
  - New tare captures whatever creep state the beam is in
  - Next placement delta is accurate relative to that new tare
  - Creep error cancels in the delta — absolute raw value doesn't matter
- This is firmware logic only — hardware is capable

---

## What next session must build

### Immediate priority: redesign 4E-000 sketch for auto-retare

The current 4E-000 sketch takes tare once at boot and never retares.
This makes it unusable for testing cal_factor across multiple load/unload cycles.

**New sketch: node/4E001_cal_factor/4E001_cal_factor.ino**

State machine with 3 states:

**STABILISING** (startup):
- Same stability gate as 4E-000 v2 (spread < 300, drift < 200, 3 confirms)
- On stable: tare_raw = window mean, transition to EMPTY

**EMPTY** (platform empty, ready):
- Monitor for placement: delta > PLACE_THRESHOLD (e.g. 500 counts = ~19g)
- While in EMPTY: if drift detected, auto-retare immediately
- Print: "EMPTY — tare=XXXXXX. Place known weight."

**LOADED** (weight placed, reading):
- Stability detection: same 2-condition window (spread < 300, drift < 200)
- On 3 consecutive stable windows: capture stable_delta
- Print: "STABLE DELTA: +XXXXXX  EST GRAMS (÷26): XXXg"
- Wait for removal: delta drops below REMOVE_THRESHOLD (e.g. 200 counts)
- On removal: transition back to EMPTY and AUTO-RETARE immediately

**cal_factor derivation** (manual, after stable reading):
- User notes the stable delta
- User notes the known weight
- cal_factor = stable_delta / known_weight_grams
- Run 3× with same weight, average

### Known weight for 4E-001
Mobile phone = 234g — confirmed known weight.
Place mobile → stable reading → note delta → compute cal_factor.
Do this 3 times, average.

---

## Existing sketches

| Sketch | Location | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE (single cell) |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE (single cell) |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE (single cell) |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE (single cell, BLE) |
| 4E000_raw_read.ino | node/4E000_raw_read/ | DONE (4-cell, stability-gated tare) |
| STOP.ino | node/STOP/ | available |
| HW_VERIFY.ino | node/HW_VERIFY/ | available |

Hub files (unchanged from single-cell):
- hub/e003_ble_test.py — BLE subscriber
- hub/config.json — device config, MAC cached
- hub/requirements.txt — bleak>=0.21.0

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare — always derived |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory |
| HX711 VCC = 3V3 only | NEVER 5V — destroys GPIO |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | double produces sum=0 bug on some platforms |
| Tare after stability | never tare before stability confirmed |
| bleak name filter | service_uuids filter ignored on QRB2210 |
| BlueZ transport | "le" only — "auto" kills QRB2210 adapter |
| MAC in config.json | never hardcode MAC in source |
| SCP hostname | always arduino@AQ3 — never IP |

---

## 4-cell physics — key numbers

| Parameter | Single cell | 4-cell parallel |
|---|---|---|
| cal_factor | ~105 raw/g | ~26 raw/g (must re-derive) |
| Signal for 234g | ~24,570 counts | ~6,084 counts |
| Sensitivity ratio | 1× | ¼ (4 cells average signal) |
| Firmware | same | same |
| Seam contract | unchanged | unchanged |

Signal averaging at junction: V_bus = (V1+V2+V3+V4)/4
All 4 cells contribute equally. Distribution of load across cells is irrelevant.

---

## Folder structure

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── E000_raw_read/
│   ├── E001_tare_cal_grams/
│   ├── E002_noise_floor/
│   ├── E003_ble_transport/
│   ├── 4E000_raw_read/        ← current sketch on ESP32
│   ├── STOP/
│   └── HW_VERIFY/
├── hub/
│   ├── e003_ble_test.py
│   ├── config.json
│   └── requirements.txt
└── docs/
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── TRANSPORT_DECISION_BLE_ONLY.md
    ├── SESSION_CLOSE_PROTOCOL.md
    ├── VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md
    ├── MULTI_CELL_LOADCELL_PHYSICS_AND_WIRING.md
    └── HANDOFF_2026_06_11_FINAL.md  ← this file
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: 4E-000 PASSED, platform is Setup B (4 independent plates)
4. Hardware: 4× YZC-161A twisted parallel, direct to HX711, GPIO4=DT GPIO3=SCK, 3V3 power
5. Expected 4-cell cal_factor: ~26 raw/g (to be derived in 4E-001)
6. Key insight: auto-retare on empty detection solves creep problem for scale mode
7. Next task: build 4E-001 sketch with auto-retare state machine

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_11_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_11_FINAL.md
```

Then commit on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: session close 2026-06-11 — 4E-000 PASSED, auto-retare insight, 4E-001 design ready" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor.
Read HANDOFF_2026_06_11_FINAL.md fully before responding.
Context: 4E-000 PASSED on 4-cell platform. Auto-retare insight unlocked.
Today we design and run 4E-001 to derive cal_factor on the 4-cell platform.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready to design 4E-001.*
