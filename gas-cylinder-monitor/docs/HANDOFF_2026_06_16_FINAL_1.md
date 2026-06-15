# SESSION HANDOFF — 2026-06-16 FINAL
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No sketch.yaml in CLI prompts. No code written directly in chat.

---

## Current position (one line)
3E-004 COMPLETE AND PASSED. Self-calibrating boot working. ±7g accuracy verified.
Next: self-deriving cal_factor automatically on every boot — no user input required.

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
| ESP32-C3 SuperMini | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, 3.3V VCC ONLY |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | Fibre plate, triangle arrangement, 3 cells at 3 corners |
| Wiring | Direct twisted/soldered — NOT breadboard |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V |
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

- Package: esp32 by Espressif Systems v3.0.7 (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- SCP to: C:\Users\mahes\Documents\Arduino\[sketch_folder]\

---

## Locked values — hardware-verified 2026-06-16

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | ✅ LOCKED architecture |
| cal_factor typical value | ~35.98 raw/g (this session) | ✅ VERIFIED |
| tare source | s2_mean (Phase 2, 200-sample mean) | ✅ LOCKED |
| Zero accuracy | ±4g | ✅ VERIFIED |
| Weight accuracy | ±7g across 200g–1700g | ✅ VERIFIED |
| noise_std_g | 4.84g (this session) | ✅ VERIFIED |
| threshold_g | 19.34g (4 × STD) | ✅ VERIFIED |
| Minimum ref weight for cal | 500g minimum, 1000g ideal | ✅ LOCKED |
| Linear range | 200g–1700g confirmed linear | ✅ VERIFIED E-005 |
| Cold boot settle | 60–161s | ✅ PROVEN |
| tare_raw | NEVER hardcode — re-derived every boot | ✅ LOCKED |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Char UUID:       b9b25bb1-f2a9-4545-b48f-295ab2789f41
Device name:     GasCylMonitor
Char properties: NOTIFY | READ
Payload format:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
```

---

## Experiment status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read (single cell) | ✅ PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare + cal + grams (single cell) | ✅ PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 3-cell) |
| E-002 noise floor (single cell) | ✅ PASSED 2026-06-08 | STD 0.67g BLE-off (VOID on 3-cell) |
| E-003 BLE transport (single cell) | ✅ PASSED 2026-06-08 | STD 1.81g BLE-on (VOID on 3-cell) |
| 3E-001 cal_factor (3-cell) | ✅ PASSED 2026-06-12 | cal_factor = 36.1 raw/g (reference only) |
| 3E-002 noise floor (3-cell) | ✅ PASSED 2026-06-15 | BLE-on STD 4.64g, threshold 18.54g |
| 3E-003 BLE transport (3-cell) | ✅ PASSED 2026-06-15 | ESP32 → hub → WebUI end-to-end working |
| E-005 linearity (3-cell) | ✅ PASSED 2026-06-16 | System linear 700g–1700g, one CF valid |
| 3E-004 cal+run (3-cell) | ✅ PASSED 2026-06-16 | ±7g accuracy, self-calibrating boot |
| 3E-005 auto-cal (no user input) | ⏳ NEXT | Self-derive cal_factor on every boot |

---

## Sketches — complete list

| Sketch | Location on AQ3 | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE single cell |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE single cell |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE single cell |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE single cell BLE |
| 3E001_cal_factor_v5_2.ino | node/3E001_cal_factor_v5_2/ | DONE 3-cell cal |
| 3E002_noise_floor_v1_ble.ino | node/3E002_noise_floor_v1_ble/ | DONE 3-cell noise |
| 3E003_ble_transport_v1.ino | node/3E003_ble_transport_v1/ | DONE 3-cell BLE transport |
| E005_linearity.ino | node/E005_linearity/ | DONE linearity test |
| 3E004_cal_and_run.ino | node/3E004_cal_and_run/ | ← CURRENT PRODUCTION NODE |
| HW_VERIFY_3CELL.ino | node/HW_VERIFY_3CELL/ | Diagnostic tool |
| STOP.ino | node/STOP/ | Available |

---

## Hub — deployed and running

Location: ~/ArduinoApps/gas-cylinder-monitor/hub/
App Lab ID: user:gas-cylinder-monitor/hub
WebUI URL: http://AQ3:7000

Deploy command:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub
bash deploy.sh
```

Logs:
```bash
arduino-app-cli app logs user:gas-cylinder-monitor/hub --follow
```

---

## Critical architecture decisions — locked

### Why cal_factor must be derived in same boot
cal_factor = raw_delta / known_weight. It should be supply-voltage independent
because V_excitation cancels in the delta. But platform physical state (cell preload,
plate geometry, contact points) can differ between power cycles, shifting raw baseline
by thousands of counts. cal_factor derived in boot A used in boot B = invalid.
Fix: 5-phase boot — Phase 3 derives cal_factor fresh every boot.

### Why tare uses s2_mean not Phase 1 tare_raw
Error of mean = std / sqrt(N).
Phase 1 (N=20):  167/sqrt(20)  = 37.4 counts = ±1.18g uncertainty
Phase 2 (N=200): 167/sqrt(200) = 11.8 counts = ±0.37g uncertainty
Phase 2 already collects 200 samples. Its mean is 3× more accurate. Use it.

### Why minimum 500g reference weight for cal derivation
At noise_std_raw ~170 counts:
SNR at 200g = 6000/170 = 35 — marginal, cal_factor scatters ±15%
SNR at 1000g = 32000/170 = 188 — excellent, cal_factor repeatable ±1%
Always use 1000g reference weight for cal derivation.

---

## The next problem to solve — 3E-005

**Goal:** Derive cal_factor automatically on every boot without any user input or known external weight.

**Why this matters:** During demo and production use, requiring a user to place a known weight at boot is unacceptable.

**The insight:** The system can self-derive cal_factor using the cylinder itself across a refill cycle:
```
cal_factor = (raw_full − raw_empty) / 14200g
```
14200g is fixed by BIS regulation. raw_full and raw_empty are anchor events the hub already detects.

**The problem for first boot:** We don't have a refill event yet on day 1.

**Approaches to investigate:**
1. HX711 gain-switching self-test: read same load at gain 128 AND gain 64. Ratio = exactly 2.0. Use this to validate signal chain but cannot derive absolute cal_factor.
2. Stamped tare weight: user reads tare stamped on cylinder collar once, types into app. Hub derives cal_factor from raw_delta / stamped_tare. One-time user action, never repeated.
3. Bootstrap from 30-day refill cycle: accept approximate cal_factor for first 30 days, then lock exact value after first refill.

**Design question for next session:** Which approach or combination gives best accuracy with least user friction?

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived, never hardcoded |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory |
| HX711 VCC = 3V3 only | NEVER 5V |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | safe default on ESP32-C3 |
| tare = s2_mean | always use 200-sample Phase 2 mean, never Phase 1 window mean |
| cal + tare same boot | never use cal_factor from a different boot session |
| Min ref weight = 500g | never derive cal_factor from weight below 500g |
| BLE transport | BlueZ: "le" transport only, NO RemoveDevice before Connect |
| SCP hostname | always arduino@AQ3 — never IP address |
| Design in chat | all code written exclusively via Claude Code CLI on AQ3 |
| deploy.sh only | never start/stop hub app manually |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── 3E004_cal_and_run/    ← CURRENT PRODUCTION NODE SKETCH
│   ├── E005_linearity/
│   ├── 3E003_ble_transport_v1/
│   ├── HW_VERIFY_3CELL/
│   ├── STOP/
│   └── [other completed experiments]
├── hub/                      ← DEPLOYED, RUNNING
│   ├── app.yaml
│   ├── setup.sh
│   ├── deploy.sh
│   ├── python/
│   │   ├── main.py
│   │   ├── ble_subscriber.py
│   │   └── requirements.txt
│   ├── assets/
│   │   ├── index.html
│   │   └── socket.io.min.js
│   ├── wheels/
│   ├── typelibs/
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_16_FINAL.md  ← this file
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: 3E-004 PASSED. ±7g accuracy verified. Hub deployed and running.
4. Platform: 3-cell YZC-161A parallel, fibre plate.
5. cal_factor: derived every boot in Phase 3 — NOT hardcoded. Typical ~35.98 raw/g.
6. tare: always s2_mean (200-sample Phase 2 mean) — never Phase 1 window mean.
7. BLE UUIDs locked: Service aa206b91... Char b9b25bb1... Device GasCylMonitor
8. Hub running at user:gas-cylinder-monitor/hub, WebUI at AQ3:7000
9. Next problem: auto-derive cal_factor without user input — design in chat first
10. Session close docs updated via CLI before this handoff was generated

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_16_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_16_FINAL.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_16_FINAL — 3E-004 accuracy complete" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_16_FINAL.md fully before responding.
Context: 3E-004 COMPLETE. Self-calibrating boot working. ±7g accuracy verified.
Today we design 3E-005: auto-derive cal_factor on every boot without user input.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
