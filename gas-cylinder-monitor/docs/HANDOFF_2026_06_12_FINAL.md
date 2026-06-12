# SESSION HANDOFF — 2026-06-12 FINAL
# Gas Cylinder Monitor — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode unchanged: design in chat, all code via Claude Code CLI only.
No sketch.yaml files needed in CLI prompts from this session onwards.

---

## Current position

Group 1 (single cell) COMPLETE. Group 2 (transport) COMPLETE.
4-cell pivot in progress. 4E-000 PASSED. 4E-001 IN PROGRESS — v4 sketch written, awaiting clean data.

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read (single cell) | PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare + cal + grams (single cell) | PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 4-cell) |
| E-002 noise floor (single cell) | PASSED 2026-06-08 | STD 0.67g BLE-off |
| E-003 BLE transport (single cell) | PASSED 2026-06-08 | STD 1.81g BLE-on, threshold 7.24g |
| 4E-000 4-cell bring-up | PASSED 2026-06-11 | All 4 cells confirmed working |
| 4E-001 cal_factor 4-cell | IN PROGRESS | v4 sketch written — awaiting clean data |

---

## What this product is

LPG gas cylinder weight monitor. ESP32-C3 sensor node reads load cells via HX711,
computes gross weight in grams, sends over BLE to Arduino UNO Q hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

Pipeline:
```
N× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify) → UNO Q hub (Python, BlueZ, SQLite, WebUI)
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
| Reference weight | water bottle = 597g (locked for 4E-001) |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V |
| GND | GND | |
| GPIO4 | SDO (DOUT) | |
| GPIO3 | SCK | |

### 4-cell parallel wiring
All 4 red wires twisted together → HX711 E+
All 4 black wires twisted together → HX711 E−
All 4 green wires twisted together → HX711 A+
All 4 white wires twisted together → HX711 A−
Direct to HX711 module pins — NOT through breadboard.

### Pins never to use for HX711
GPIO2, GPIO8, GPIO9 — strapping pins
GPIO12-17 — internal flash

---

## Arduino IDE — locked setup

- Package: esp32 by Espressif Systems v3.0.7 (NOT v3.3.9 — flasher.exe missing)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- First flash: hold BOOT → Upload → release after 2s
- Subsequent flashes: automatic

SCP to laptop (run from Windows terminal):
```
scp arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/node/[sketch]/[sketch].ino "C:\Users\mahes\Documents\Arduino\[sketch]\[sketch].ino"
```

No sketch.yaml files needed — do not include in CLI prompts.

---

## The core problem being solved this session

Single-cell E-001, E-002, E-003 all worked perfectly. When ported to 4-cell, the
stability gate failed to converge. This session was spent diagnosing why and building
a correct self-characterising approach.

### Root cause 1 — Hidden cal_factor dependency in stability gate
E-002 and E-003 used grams for stability thresholds: STAB_SPREAD=2.5g, STAB_DRIFT=1.0g.
This secretly depended on cal_factor ~105 raw/g.
On 4-cell, cal_factor is ~22 raw/g (4× lower sensitivity).
Same gram thresholds = 4× tighter raw gates = physically impossible to pass on 4-cell noise.
Fix: work entirely in raw counts. Derive thresholds from measured STD_raw.

### Root cause 2 — Phase 1 characterisation ran during active platform drift
At cold boot the wooden platform + 4 plates creep under their own weight.
STD of 200 samples during this drift was ~4920 raw (drift-dominated, not noise).
This set stability gate at 7380 raw — so loose it passed during creep, not stability.
Fix: Phase 0 must wait for platform mechanical settling BEFORE characterising noise.

### Root cause 3 — max-min spread metric is outlier-sensitive
One spike in a 20-sample window dominates max-min, resetting the gate even when
19/20 samples are clean. The platform appeared to never settle.
Fix: use window STD instead of max-min. STD averages squared deviations — one spike
contributes only 1/20th of the variance.

### Root cause 4 — Serial buffer not flushed before readStringUntil
Stale newline bytes in Serial buffer caused the sketch to proceed through the human
gate without waiting for Enter. Readings taken without weight placed → negative cal_factor.
Fix: mandatory while(Serial.available()) Serial.read() before every readStringUntil().

---

## 4E-001 sketch evolution — what was tried and why each failed

| Version | What it did | Why it failed |
|---|---|---|
| v1 (4E001_cal_factor) | Auto-detect placement via PLACE_THRESHOLD, auto-retare in EMPTY state | Continuous re-taring chased moving drift curve. Placement detected mid-drift. |
| v2 (4E001_cal_factor_v2) | Human gate + 10s settle + re-tare after removal using stability gate. Fixed const thresholds SPREAD=300 DRIFT=200 | Thresholds too tight for 4-cell noise. Platform never stable enough to pass. Hidden cal_factor dependency exposed. |
| v3 (4E001_cal_factor_v3) | Self-characterising: 200 samples → STD_raw → derive thresholds. Window STD instead of max-min | Phase 1 ran during cold boot drift. STD=4920 (drift-dominated). Gate too loose. Passed during creep. |
| v4 (4E001_cal_factor_v4) | Phase 0 waits for platform settling first. Then Phase 1 characterises true noise. Then stability gate. Human gate with Serial flush. | CURRENT — awaiting clean data |

---

## v4 sketch architecture (current — on board now)

```
Phase 0 — Platform settling monitor (NEW — this is what was missing)
  Collect blocks of BLOCK_SIZE=200 samples repeatedly
  Per block: compute block_std and block_mean
  Pass condition: block_std < COLD_THRESHOLD=500 raw
                  AND |block_mean - prev_block_mean| < COLD_THRESHOLD
  Need COLD_CONFIRM=3 consecutive passing blocks
  Prints [SETTLING] progress so you can watch platform settle in real time
  On pass: noise_std_raw = block_std of final passing block

Phase 1 — Stability gate (derived from true settled noise)
  spread_gate = K_SPREAD(1.5) × noise_std_raw
  drift_gate  = K_DRIFT(1.0)  × noise_std_raw
  Uses window STD (not max-min) — robust to occasional spikes
  20-sample windows, 3 consecutive passes required
  On pass: tare_raw = window_mean

Phase 2 — Human gate
  Serial flush → prompt → readStringUntil('\n')
  10 second mechanical settle countdown (millis pacing)

Phase 3 — Measurement
  50 valid raw samples → mean → stable_delta = mean - tare_raw
  cal_factor = stable_delta / 597.0
  Prints loaded_std as consistency check (if loaded_std >> noise_std, weight was moving)

Phase 4 — Re-tare loop
  Serial flush → prompt → readStringUntil('\n')
  Full stability gate re-run after each removal
  noise_std_raw unchanged between runs
```

### Why COLD_THRESHOLD=500 is not magic number tuning
It sits between two physically distinct regimes:
- Platform actively drifting: block STD ~thousands of raw (measured: 4920 at cold boot)
- Platform settled: block STD ~tens to low hundreds raw (measured: 80–140 raw settled)
Any value between 300–2000 separates these regimes. Not precise tuning — coarse filter.

---

## Key physics locked for N-cell platform

### Parallel wiring signal averaging
V_bus = (V1 + V2 + ... + VN) / N
HX711 sees total weight regardless of distribution across cells.
Unequal load still gives correct total — proven via Wheatstone bridge + KCL.

### cal_factor scaling
Single cell: ~106.7 raw/g (verified)
4-cell: UNKNOWN — must be derived from hardware. Never assume.
3-cell: UNKNOWN — must be derived from hardware. Never assume.
The v4 sketch works on any cell count — flash same sketch, derive fresh cal_factor.

### Why cal_factor must be re-derived per topology
cal_factor absorbs: load cell sensitivity, HX711 gain, actual VCC, mechanical mounting,
AND number of cells in parallel. Any wiring topology change → re-derive.

---

## Existing sketches

| Sketch | Location | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE single cell |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE single cell |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE single cell |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE single cell BLE |
| 4E000_raw_read.ino | node/4E000_raw_read/ | DONE 4-cell bring-up |
| 4E001_cal_factor.ino | node/4E001_cal_factor/ | ABANDONED v1 |
| 4E001_cal_factor_v2.ino | node/4E001_cal_factor_v2/ | ABANDONED v2 |
| 4E001_cal_factor_v3.ino | node/4E001_cal_factor_v3/ | ABANDONED v3 |
| 4E001_cal_factor_v4.ino | node/4E001_cal_factor_v4/ | CURRENT — flash this |
| STOP.ino | node/STOP/ | available |
| HW_VERIFY.ino | node/HW_VERIFY/ | available |

Hub files (unchanged from single-cell):
- hub/e003_ble_test.py
- hub/config.json
- hub/requirements.txt

---

## What the next session must do

### Immediate — collect clean v4 data
Run 4E001_cal_factor_v4.ino. Wait for Phase 0 to complete (platform fully settled).
Run minimum 3 placement/removal cycles. Paste all serial output.
Accept run only if:
- loaded_std is close to noise_std_raw (weight was stable during sampling)
- cal_factor is positive
- cal_factor across 3 runs clusters tightly (within ~10% of each other)

### After clean cal_factor obtained
Lock cal_factor for 4-cell platform.
Proceed to 4E-002: noise floor characterisation on 4-cell platform.
4E-002 uses the same v4 Phase 0 settling logic — just replace cal measurement
with 200-sample STD characterisation after tare.

### Future — same v4 sketch on 3-cell setup
Flash 4E001_cal_factor_v4.ino unchanged on 3-cell wiring.
Derive cal_factor independently. Do not assume any value.
The sketch is cell-count agnostic by design.

### After 4E-001 and 4E-002 complete
4E-003: load distribution validation (same weight at different positions)
4E-004: BLE transport validation on 4-cell hardware

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor, tare — always derived |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three inside hx711_read() |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory |
| HX711 VCC = 3V3 only | NEVER 5V |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | double produces sum=0 bug |
| Tare after stability | never tare before stability confirmed |
| Serial flush | mandatory before every readStringUntil() |
| Window STD not max-min | max-min is outlier-sensitive |
| Phase 0 before Phase 1 | never characterise noise during drift |
| No sketch.yaml in CLI prompts | not needed |
| bleak name filter | service_uuids filter ignored on QRB2210 |
| BlueZ transport | "le" only — "auto" kills QRB2210 adapter |
| MAC in config.json | never hardcode MAC in source |
| SCP hostname | always arduino@AQ3 — never IP |

---

## Critical learnings from this session

### L-A — Stability gate had hidden cal_factor dependency
E-002/E-003 worked in grams. Gram thresholds secretly required cal_factor ~105.
4-cell cal_factor ~22 → same gram thresholds → 4× tighter raw gates → impossible.
Fix: always work in raw counts for stability. Derive STD_raw from hardware directly.

### L-B — max-min spread is wrong metric for noisy hardware
One outlier in 20 samples dominates max-min. Gate never passes.
Window STD averages all deviations — one outlier = 1/N contribution to variance.
Fix: always use window STD for stability gate.

### L-C — Phase 1 noise characterisation must happen after platform settling
200 samples during cold boot captures drift rate, not noise floor.
STD during drift >> STD when settled (4920 raw vs 80-140 raw on this hardware).
Fix: Phase 0 settling monitor before any characterisation.

### L-D — Serial buffer must be flushed before every readStringUntil
Stale newlines in buffer → sketch proceeds without human pressing Enter.
Readings taken without weight → negative cal_factor.
Fix: while(Serial.available()) Serial.read() before every readStringUntil().

### L-E — Experiment dependency order matters
4E-001 (cal_factor) depended on noise floor knowledge to set stability gate.
4E-002 (noise floor) should logically precede 4E-001.
Fix for production: embed self-characterisation in every experiment sketch
so dependency is resolved internally. Never carry assumptions from other experiments.

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
│   ├── 4E000_raw_read/
│   ├── 4E001_cal_factor/         ← v1 abandoned
│   ├── 4E001_cal_factor_v2/      ← v2 abandoned
│   ├── 4E001_cal_factor_v3/      ← v3 abandoned
│   ├── 4E001_cal_factor_v4/      ← CURRENT ACTIVE SKETCH
│   ├── STOP/
│   └── HW_VERIFY/
├── hub/
│   ├── e003_ble_test.py
│   ├── config.json
│   └── requirements.txt
└── docs/
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── EXPERIMENT_HISTORY.md
    ├── HANDOFF_2026_06_12_FINAL.md  ← this file
    └── [other docs]
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only. No sketch.yaml in prompts.
3. Current position: 4E-001 IN PROGRESS, v4 sketch on board, awaiting clean data
4. Active sketch: 4E001_cal_factor_v4.ino — self-characterising, 4-phase architecture
5. Hardware: 4× YZC-161A twisted parallel, direct to HX711, GPIO4=DT GPIO3=SCK, 3V3
6. cal_factor for 4-cell: UNKNOWN — must be derived from v4 data. Never assume.
7. Key insight: Phase 0 settling monitor is the critical fix. Without it Phase 1 runs during drift.
8. Same v4 sketch runs unchanged on 3-cell setup — cell count agnostic by design.
9. User will provide v4 serial output data. Analyse for: positive cal_factor, tight clustering across 3 runs, loaded_std close to noise_std_raw.

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_12_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_12_FINAL.md
```

Then commit on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: session close 2026-06-12 — 4E-001 v4 written, self-characterising architecture locked" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor.
Read HANDOFF_2026_06_12_FINAL.md fully before responding.
Context: 4E-001 v4 sketch on board. Self-characterising. Awaiting clean cal_factor data.
I have run the v4 sketch 3 times. Here is the serial output data: [paste data]
Analyse the data and tell me if we have a clean cal_factor result."

---

*End of handoff. Next chat is ready to analyse v4 data and proceed.*
