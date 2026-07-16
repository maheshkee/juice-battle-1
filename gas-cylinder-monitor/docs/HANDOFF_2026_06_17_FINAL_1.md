# SESSION HANDOFF — 2026-06-17 FINAL_1
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Node Layer 1 complete and verified on hardware (1A + 1B + 1C + 1D).
Next: 3E-006B — minimum detectable removal experiment on 3-cell hardware.

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

## Hardware — locked

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — IP may change, use hostname) |
| ESP32-C3 SuperMini | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, 3.3V VCC ONLY |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | Fibre plate, 3 cells at 3 corners |
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
All 3 red → E+ | All 3 black → E− | All 3 green → A+ | All 3 white → A−
Direct to HX711. Twisted or soldered. NOT breadboard.

---

## Arduino IDE — locked

- Package: esp32 by Espressif v3.0.7 (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- Required libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon
- #include <cstdio> required for snprintf

---

## Locked values — hardware-verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | LOCKED |
| cal_factor typical | ~36 raw/g (3-cell parallel) | VERIFIED |
| tare source | s2_mean (200-sample Phase 2 mean) | LOCKED |
| sigma | 3.48–3.68g (boot-to-boot variation normal) | VERIFIED |
| zero accuracy | ~±3g | VERIFIED |
| weight accuracy | ±7g across 200g–1700g | VERIFIED E-005 |
| threshold_g | 4 × sigma | LOCKED |
| linear range | 200g–1700g | VERIFIED E-005 |
| Production sketch | node/gas_monitor_v1/gas_monitor_v1.ino | CURRENT |

### Boot timing — verified 2026-06-17
| Phase | Duration |
|---|---|
| SETTLE | ~2.1s |
| TARE | ~21s (200 samples × 10 SPS) |
| NOISE | ~20s (200 samples × 10 SPS) |
| CAL | variable (human input) |
| Total boot | ~60s excluding CAL wait |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Char UUID:       b9b25bb1-f2a9-4545-b48f-295ab2789f41
Device name:     GasCylMonitor
Payload format:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
```

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino    ← orchestrator
│       ├── hx711.h / hx711.cpp
│       ├── tare.h  / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h   / cal.cpp
│       ├── weight.h / weight.cpp
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp
│       ├── journal.h / journal.cpp  ← NEW — 1D complete
│       ├── README.md
│       └── config.json
├── hub/                          ← DEPLOYED, RUNNING (skeleton — no gas logic yet)
│   ├── app.yaml
│   ├── deploy.sh
│   ├── python/main.py
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    ├── EXPERIMENT_PROGRAM.md
    └── HANDOFF_2026_06_17_FINAL_1.md  ← this file
```

---

## Node Layer 1 backlog — status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE |
| 1C — Timing instrumentation | ✅ COMPLETE 2026-06-17 |
| 1D — Structured Serial journal | ✅ COMPLETE 2026-06-17 |

---

## Journal module — what was built (1D)

### Files
- `journal.h` — 7 public function declarations
- `journal.cpp` — service module, owns all state, all Serial output

### Format
```
#SEQ t=T boot=B [TAG] event=NAME key=val key=val
```

### Event types
| Tag | Event | When emitted |
|---|---|---|
| [BOOT] | START | Once on boot |
| [BOOT] | PHASE_COMPLETE | Each phase exits |
| [BOOT] | BOOT_COMPLETE | Entering STATE_RUNNING |
| [RUN] | QUALITY_CHANGE | Quality transitions only |
| [RUN] | WEIGHT_EVENT | Delta > 4×sigma |
| [HB] | HEARTBEAT | Every 30 seconds |
| [FAULT] | PHASE_FAIL | Phase failure |

### Verified output (2026-06-17)
```
#0001 t=0.2 boot=1 [BOOT] event=START fw=1.0
#0002 t=2.3 boot=1 [BOOT] event=PHASE_COMPLETE phase=SETTLE result=OK s=2.1
#0003 t=23.5 boot=1 [BOOT] event=PHASE_COMPLETE phase=TARE result=OK mean=-102970.8 spread=0.0 s=21.1
#0004 t=43.6 boot=1 [BOOT] event=PHASE_COMPLETE phase=NOISE result=WARN s=20.1
#0005 t=64.3 boot=1 [BOOT] event=PHASE_COMPLETE phase=CAL result=OK cal_factor=35.9664 s=20.7
#0006 t=64.3 boot=1 [BOOT] event=BOOT_COMPLETE total_s=64.3 cal=35.9664 sigma=3.65 tare=-102970.8
#0007 t=64.4 boot=1 [RUN] event=QUALITY_CHANGE from=NONE to=DEGRADED grams=0.0 sigma=3.65 diagnosis=stuck:
#0008 t=64.4 boot=1 [HB] event=HEARTBEAT grams=0.0 quality=DEGRADED sigma=3.65 uptime=64.4
#0009 t=66.3 boot=1 [RUN] event=WEIGHT_EVENT type=PLACED grams=406.3 prev=0.0 delta=406.3
```

---

## Known TODOs — deferred, tracked

| ID | Description | Fix |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f — stuck check always fails | Update TareResult struct to expose variance |
| TODO 1B-persistence | prev_cal_factor/prev_sigma_g not read from config.json | Read/write at boot and after CAL_SUCCESS |

---

## Key architecture decisions (locked)

| Decision | Detail |
|---|---|
| Computation vs service modules | Computation = pure function (health, cal, noise...). Service = stateful (journal). Not all modules are pure. |
| Event log not data stream | Log transitions not state. 216k lines/6hr → ~750 lines. Every line meaningful. |
| Sequence numbers in RAM only | Never persist to flash — write cycles limited. Boot counter persisted, seq resets per boot. |
| Heartbeat dual purpose | Proof of life + trend data spine for hub analytics. 30s interval. |

---

## Next session — 3E-006B: minimum detectable removal

### What this experiment answers
What is the smallest weight removal the system reliably detects?
threshold_g = 4 × sigma ≈ 4 × 3.5g = 14g threshold.
But does the system actually detect a 15g removal reliably? 20g? 50g?
We do not know from theory alone. Hardware must tell us.

### Setup needed
- Water container on platform (simulates gas cylinder)
- Measuring cup — to remove precise water amounts
- Kitchen scale — to verify removed amounts independently
- Start with large removal (200g), step down until detection fails

### What to measure
- Smallest delta that triggers WEIGHT_EVENT type=REMOVED reliably
- False negative rate at threshold boundary
- How many ticks until WEIGHT_EVENT fires after removal

### Gate
Defines minimum resolution of the production system.
Required before committing to threshold_g formula.

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No government averages | 473 g/day banned. Real household data only. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| No premature prediction | burn_rate shown only after 24h real data. |
| Conservative bias | Always report lower gas estimate when uncertain. |
| Build order discipline | Verify each layer before building on top. |
| Module contract | Computation modules return {value, quality, diagnosis}. Never just bool. |
| Pure function rule | Computation modules own no state. Service modules (journal) own their state. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". Must be physically impossible. |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — if hostname fails, use 192.168.88.20 (current IP). |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode confirmed: chat = design only, CLI = code only
3. Current position: Node Layer 1 complete (1A + 1B + 1C + 1D)
4. Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
5. Next action: 3E-006B — design the experiment in chat first
6. Hub running at arduino@AQ3 gas-cylinder-monitor/hub — WebUI at AQ3:7000 — no gas logic yet

---

## SCP command to save this file to the board

From Windows laptop terminal (use IP if hostname fails):
```
scp HANDOFF_2026_06_17_FINAL_1.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_17_FINAL_1.md
```

Or with IP:
```
scp HANDOFF_2026_06_17_FINAL_1.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_17_FINAL_1.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: session close 2026-06-17 — Node Layer 1 complete, next=3E-006B" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_17_FINAL_1.md fully before responding.
Context: Node Layer 1 complete. 1A + 1B + 1C + 1D all verified on hardware.
Today we design and run 3E-006B — minimum detectable removal experiment.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
