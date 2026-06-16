# SESSION HANDOFF — 2026-06-16 FINAL_3
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
1A complete and verified on hardware. Modular sketch running on 3-cell ESP32-C3.
Next: 1B — load cell health detection module (design in chat first).

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
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — IP changes, never use IP) |
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
- Required libraries (install via Library Manager):
  - NimBLE-Arduino by h2zero
  - ArduinoJson by Benoit Blanchon

---

## Locked values — hardware-verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | LOCKED |
| cal_factor typical | ~37 raw/g (3-cell parallel) | VERIFIED 2026-06-16 |
| tare source | s2_mean (200-sample Phase 2 mean) | LOCKED |
| sigma | 2.64g (recomputed post-CAL) | VERIFIED 2026-06-16 |
| Zero accuracy | ~±3g | VERIFIED 2026-06-16 |
| Weight accuracy | ±7g across 200g–1700g | VERIFIED E-005 |
| noise_std_g | 4.84g (3E-002) / 2.64g (this session) | VERIFIED |
| threshold_g | 4 × sigma | LOCKED |
| Linear range | 200g–1700g | VERIFIED E-005 |
| Production sketch | node/gas_monitor_v1/gas_monitor_v1.ino | CURRENT |

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
│   ├── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│   │   ├── gas_monitor_v1.ino    ← orchestrator
│   │   ├── hx711.h / hx711.cpp
│   │   ├── tare.h  / tare.cpp
│   │   ├── noise.h / noise.cpp
│   │   ├── cal.h   / cal.cpp
│   │   ├── weight.h / weight.cpp
│   │   ├── ble.h   / ble.cpp
│   │   ├── README.md
│   │   └── config.json
│   ├── 3E004_cal_and_run/        ← previous experiment (reference only)
│   └── [other completed experiments]
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
    ├── HANDOFF_2026_06_16_FINAL_3.md  ← this file
    └── HANDOFF_2026_06_16_SESSION2_1A_COMPLETE.md
```

---

## Node Layer 1 backlog — status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE 2026-06-16 |
| 1B — Load cell health detection | NOT STARTED — next |
| 1C — Timing instrumentation | NOT STARTED |
| 1D — Structured Serial journal | NOT STARTED |

---

## 1B — what it must do (design brief for next session)

Detect three load cell failure modes. Flag in quality field. Never halt.

| Failure mode | Symptom | Detection |
|---|---|---|
| Open wire | One cell disconnected — total output drops ~25% or goes near zero | gross reading implausibly low or negative |
| Stuck reading | HX711 frozen — N consecutive identical raw values | variance across N samples = 0 |
| Erratic variance | One cell oscillating — sigma >> noise floor | per-boot sigma vs threshold ratio check |

Module contract: returns {value, quality, diagnosis} like all other modules.
Quality: GOOD / DEGRADED (one cell suspect) / FAILED (platform unusable).
Must be non-blocking. Must not call hx711 directly. Receives raw from orchestrator.

This is a DESIGN session — no CLI until contract is fully specified in chat.

---

## Known issues (minor, not blocking)

| Issue | Impact | Fix |
|---|---|---|
| NOISE WARNING at boot | Raw-unit sigma (~95) exceeds 20g gram guard. Misleading log line only. Orchestrator correctly continues. | Deferred to 1C — add unit context to diagnosis string |
| noise_recompute_sigma() unit assumption | Only valid when cal_factor=0 path ran. Documented in CLAUDE.md and noise.cpp. | Accepted for V1 single-boot sequence |

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No government averages | 473 g/day banned. Real household data only. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| No premature prediction | burn_rate and days shown only after 24h real data. |
| Conservative bias | Always report lower gas estimate when uncertain. |
| Build order discipline | Verify each layer before building on top. |
| Module contract | Every module returns {value, quality, diagnosis}. Never just bool. |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — never IP address. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode confirmed: chat = design only, CLI = code only
3. Current position: 1A complete, gas_monitor_v1 verified on hardware
4. Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
5. Next action: 1B load cell health detection — design session
6. Hub running at arduino@AQ3 gas-cylinder-monitor/hub — WebUI at AQ3:7000 — no gas logic yet

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_16_FINAL_3.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_16_FINAL_3.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_16_FINAL_3 — 1A complete, next=1B health module" && git push
```

---

## Opening prompt for next session (Step 11)

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_16_FINAL_3.md fully before responding.
Context: 1A complete. Modular sketch verified on 3-cell hardware.
Today we design 1B — load cell health detection module.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
