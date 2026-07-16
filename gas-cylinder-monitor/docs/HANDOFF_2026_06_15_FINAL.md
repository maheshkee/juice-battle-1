# SESSION HANDOFF — 2026-06-15 FINAL
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No sketch.yaml in CLI prompts. No code written directly in chat.

---

## Current position (one line)
3E-002 COMPLETE AND PASSED. noise floor locked. Next = modular refactor + 3E-003 BLE transport + minimal WebUI demo.

---

## Demo target (2 days)
Boss places weight on platform → hub receives grams via BLE → WebUI shows grams on screen.
That is the entire demo. Nothing more. Nothing less.

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
| Platform | Fibre plate (food plate), triangle arrangement, 3 cells at 3 corners |
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

SCP pattern:
```
mkdir "C:\Users\mahes\Documents\Arduino\[sketch_name]"
scp arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/node/[sketch]/[sketch].ino "C:\Users\mahes\Documents\Arduino\[sketch]\[sketch].ino"
```

---

## Locked values — hardware-verified

| Parameter | Value | Status | Locked |
|---|---|---|---|
| cal_factor (3-cell, shared plate) | 36.1 raw/g | ✅ PROVEN | 2026-06-12 |
| HW_VERIFY cal_factor confirmation | 35.63 raw/g | ✅ CONSISTENT (1.3% diff) | 2026-06-15 |
| Linear range | 200g – 1800g | ✅ PROVEN | 2026-06-12 |
| Min reliable weight | ~150g | ✅ PROVEN | 2026-06-12 |
| noise_std_g (BLE off, worst case) | 4.93g | ✅ LOCKED | 2026-06-15 |
| noise_std_g (BLE on, worst case) | 4.64g | ✅ LOCKED | 2026-06-15 |
| threshold_g (BLE on, production) | 18.54g | ✅ LOCKED | 2026-06-15 |
| BLE EMI penalty on 3-cell | ~1.0x | ✅ LOCKED | 2026-06-15 |
| tare_raw | NEVER hardcode | — | re-derived every boot |
| Cold boot settle (with plate) | 60–161s | ✅ PROVEN | 2026-06-12 |

---

## BLE UUIDs — locked from E-003

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
| 3E-001 cal_factor (3-cell) | ✅ PASSED 2026-06-12 | cal_factor = 36.1 raw/g LOCKED |
| 3E-002 noise floor (3-cell) | ✅ PASSED 2026-06-15 | BLE-on STD 4.64g, threshold 18.54g LOCKED |
| 3E-003 BLE transport (3-cell) | ⏳ NEXT | ESP32 → hub, one reading arrives |
| Hub BLE subscriber | ⏳ NEXT | Python bleak on AQ3 |
| Minimal WebUI demo | ⏳ NEXT | grams on screen |
| 3E-004 measurement stability | 📋 PLANNED | |
| 3E-006A anchor validation | 📋 PLANNED | |
| 3E-006B consumption validation | 📋 PLANNED | |

---

## Sketches built so far

| Sketch | Location on AQ3 | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE single cell |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE single cell |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE single cell |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE single cell BLE ← reference for 3E-003 |
| 3E001_cal_factor_v5.ino | node/3E001_cal_factor_v5/ | DONE 3-cell |
| 3E001_cal_factor_v5_1.ino | node/3E001_cal_factor_v5_1/ | DONE + timing |
| 3E001_cal_factor_v5_2.ino | node/3E001_cal_factor_v5_2/ | DONE + per-iteration weight |
| 3E002_noise_floor_v1.ino | node/3E002_noise_floor_v1/ | DONE BLE off |
| 3E002_noise_floor_v1_ble.ino | node/3E002_noise_floor_v1_ble/ | DONE BLE on |
| HW_VERIFY_3CELL.ino | node/HW_VERIFY_3CELL/ | DONE permanent diagnostic tool |
| STOP.ino | node/STOP/ | Available |
| HW_VERIFY.ino | node/HW_VERIFY/ | Single-cell only |

Hub: not yet started. hub/ directory exists but empty.

---

## What next session must build — in order

### Task 1 — Modular sketch architecture (design in chat first)

Before writing 3E-003, design the module structure. The production node sketch
must be modular from the start. Module contracts:

```
sketch.ino      — orchestrator only. setup() + loop() + state machine. No sensor math.
hx711.h/.cpp    — raw bit-bang read. Corrupt filters. Nothing else.
tare.h/.cpp     — Phase 0 settling + Phase 1 tare derivation. Nothing else.
noise.h/.cpp    — Phase 2 noise characterisation. STD + threshold. Nothing else.
weight.h/.cpp   — grams computation. quality. sigma. Nothing else.
ble.h/.cpp      — GATT server setup. advertising. notify. Nothing else.
```

3E-003 can be a single-file experiment sketch (experiments are throwaway).
The production node sketch that follows is modular.

### Task 2 — 3E-003 BLE transport (node side)

Build ESP32 sketch that:
1. Phase 0: settle (same as v5 logic)
2. Phase 1: derive tare (same)
3. Phase 2: characterise noise (N=200, derive STD + threshold — same)
4. Start BLE advertising (same UUIDs as E-003)
5. Loop every 15 seconds:
   - Take N=20 samples
   - Compute grams = (mean_raw - tare_raw) / 36.1
   - Compute quality: sigma > threshold → DEGRADED, else GOOD
   - Build JSON: {"grams":X,"quality":"GOOD","sigma":Y}
   - If connected: notify hub
   - If not connected: discard, print to Serial

Use E-003_ble_transport.ino as reference — it has the full BLE GATT server pattern.
Replace cal_factor with 36.1. Replace single-cell noise logic with 3-cell Phase 0/1/2.

Sketch name: 3E003_ble_transport_v1
Location: node/3E003_ble_transport_v1/

### Task 3 — Hub Python BLE subscriber

Python script on AQ3 that:
1. Scans for GasCylMonitor by name (NOT service UUID filter — BlueZ bug on QRB2210)
2. Connects and subscribes to weight characteristic
3. On notification: parse JSON, print grams + timestamp
4. Auto-reconnect within 30 seconds if disconnected
5. BlueZ transport: "le" ONLY — never "auto" (kills BT adapter on QRB2210)

Use motion-sensor-webui socat pattern for D-Bus access if running inside App Lab Docker.
For initial test: run Python directly on AQ3 Linux (not inside Docker) — simpler.

Reference: E-003 hub Python script in hub/ (if it exists) or design fresh in chat.

### Task 4 — Minimal WebUI

Single HTML page served by Python (Flask or http.server).
Shows one number: current weight in grams.
Updates via WebSocket or polling every 15 seconds.
Nothing else. No gas%, no history, no analytics. Just grams.

### Task 5 — Demo

Boss places reference weight on platform.
Hub Python receives grams via BLE.
WebUI updates to show the weight.
That's the demo. Gate condition: weight appears correctly on screen within 30 seconds.

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived — except cal_factor in gram display which is locked-and-labelled |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory |
| HX711 VCC = 3V3 only | NEVER 5V |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | double broken on some platforms — use float as safe default |
| Tare after stability | never tare before Phase 0 + Phase 1 complete |
| waitForEnter() 2s dwell | never reduce — prevents stale Enter byte gate skip |
| BLE transport | BlueZ on QRB2210: "le" transport only, name filter not service_uuids |
| SCP hostname | always arduino@AQ3 — never IP address |
| Design in chat | all code written exclusively via Claude Code CLI on AQ3 |
| Modular from production | experiments can be single-file, production sketch is always modular |

---

## Key learnings from recent sessions (3E-001 to 3E-002)

**BLE EMI on 3-cell:** 3-cell parallel wiring provides natural common-mode rejection
of 2.4GHz BLE interference. 6 signal wires twisted together at HX711 terminals act
as a balanced antenna — BLE couples equally into all wires, cancels at differential
input. No RF shielding needed for V1. This is a free benefit of parallel topology.

**Noise floor is creep-dominated:** Phase 2 STD varies boot-to-boot because slow
viscoelastic creep continues below the stability gate threshold. The 20-second
Phase 2 window captures this creep as noise. Self-characterisation per boot is
essential — never hardcode STD or threshold.

**cal_factor variation is normal:** 34–37 raw/g range across boots on healthy
hardware. Acceptable because: (1) delta calculations cancel systematic error,
(2) absolute error bounded by ±150g BIS tolerance anyway.

**Intermittent connection signature:** tare_raw jumps >5000 raw between iterations,
Phase 1 takes >50 windows, re-tare after removal takes >60s. Fix: re-seat all 6
wires into HX711 terminals. Confirm with HW_VERIFY_3CELL CV < 0.2%.

**Load cell failure detection (design locked, implement in hub):**
- Tare ratio check on every cylinder removal (automatic)
- cal_factor drift check on every refill (automatic)
- HW_VERIFY_3CELL lift test at installation/maintenance (manual)

---

## Hub architecture (BLE side) — critical rules for QRB2210

```python
# CORRECT — BlueZ on QRB2210
scanner = BleakScanner(transport="le")          # "le" ONLY — "auto" kills adapter
device = await scanner.find_device_by_filter(   # name filter only
    lambda d, _: d.name == "GasCylMonitor"      # service_uuids filter is broken on QRB2210
)

# socat pattern for D-Bus inside App Lab Docker:
# socat UNIX-LISTEN:/app/dbus.sock,fork UNIX-CONNECT:/run/dbus/system_bus_socket &
# os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'
```

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                          ← CLI briefing — read first
├── node/
│   ├── E000_raw_read/
│   ├── E001_tare_cal_grams/
│   ├── E002_noise_floor/
│   ├── E003_ble_transport/            ← reference for 3E-003
│   ├── 3E001_cal_factor_v5/
│   ├── 3E001_cal_factor_v5_1/
│   ├── 3E001_cal_factor_v5_2/
│   ├── 3E002_noise_floor_v1/
│   ├── 3E002_noise_floor_v1_ble/
│   ├── HW_VERIFY_3CELL/               ← permanent diagnostic tool
│   ├── STOP/
│   └── HW_VERIFY/
├── hub/                               ← empty — starts this session
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── EXPERIMENT_PROGRAM.md
    ├── EXPERIMENT_HISTORY.md
    └── HANDOFF_2026_06_15_FINAL.md   ← this file
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: 3E-002 COMPLETE. 3E-003 is next.
4. Platform: 3-cell YZC-161A parallel, fibre plate. cal_factor = 36.1 raw/g LOCKED.
5. Noise floor LOCKED: STD 4.64g BLE-on, threshold 18.54g BLE-on.
6. BLE UUIDs locked: Service aa206b91... Char b9b25bb1... Device GasCylMonitor
7. Demo target: weight on WebUI within 2 days.
8. Modular sketch architecture must be designed in chat before any production code.
9. Hub Python starts this session — socat + bleak pattern from motion-sensor-webui.
10. All sketch development via Claude Code CLI on AQ3. SCP to Windows for flashing.

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_15_FINAL.md fully before responding.
Context: 3E-002 COMPLETE AND PASSED. noise floor locked. cal_factor locked.
Today we build 3E-003 BLE transport, hub Python subscriber, and minimal WebUI
to achieve the demo: boss places weight → grams appear on screen.
Start by confirming you read the handoff and state current position and demo target."

---

*End of handoff. Next chat is ready to build the demo.*
