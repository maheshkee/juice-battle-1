# SESSION HANDOFF — 2026-06-16 FINAL_4
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
1B complete and verified on hardware. Health module (health.h / health.cpp) running on 3-cell ESP32-C3.
Next: 1C — timing instrumentation (millis() per boot phase).

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
- #include <cstdio> required for snprintf — confirmed on ESP32 Arduino toolchain

---

## Locked values — hardware-verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | LOCKED |
| cal_factor typical | ~37 raw/g (3-cell parallel) | VERIFIED 2026-06-16 |
| tare source | s2_mean (200-sample Phase 2 mean) | LOCKED |
| sigma | 2.64g (session 2) / 3.44g (session 3) | VERIFIED — boot-to-boot variation normal |
| Zero accuracy | ~±3g | VERIFIED 2026-06-16 |
| Weight accuracy | ±7g across 200g–1700g | VERIFIED E-005 |
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
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino    ← orchestrator
│       ├── hx711.h / hx711.cpp
│       ├── tare.h  / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h   / cal.cpp
│       ├── weight.h / weight.cpp
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp  ← NEW — 1B complete
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
    ├── LEARNINGS_AND_INSIGHTS.md  ← last entry L-048
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_16_FINAL_4.md  ← this file
```

---

## Node Layer 1 backlog — status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE 2026-06-16 |
| 1B — Load cell health detection | ✅ COMPLETE 2026-06-16 |
| 1C — Timing instrumentation | NOT STARTED — next |
| 1D — Structured Serial journal | NOT STARTED |

---

## Health module — what was built (1B)

### Files
- `health.h` — HealthResult struct + health_check() 9-parameter declaration
- `health.cpp` — pure function, 4 checks, bitmask checks_passed, pipe-separated diagnosis

### Contract
```cpp
HealthResult health_check(
    float sigma_g,           // from noise.cpp
    float prev_sigma_g,      // from config.json (-1.0f = first boot)
    float tare_variance_raw, // from tare.cpp (0.0f until tare.h updated)
    float cur_cal_factor,    // from cal.cpp
    float prev_cal_factor,   // from config.json (-1.0f = first boot)
    float cur_gross_g,       // from weight.cpp
    float prev_gross_g,      // owned by orchestrator (-1.0f = first tick)
    float cal_tolerance,     // 0.20f placeholder (move to config.json later)
    float sigma_tolerance    // 3.0f placeholder (move to config.json later)
);
```

### Output struct
```cpp
struct HealthResult {
    char quality[12];      // "GOOD" / "DEGRADED" / "FAILED"
    char diagnosis[64];    // e.g. "stuck:|jump:1009g"
    uint8_t checks_passed; // bit0=erratic, bit1=stuck, bit2=cal, bit3=runtime
};
```

### Quality rules
- GOOD = all 4 checks pass
- DEGRADED = 1 check fails
- FAILED = 2+ checks fail

### Verified hardware outputs (2026-06-16 Session 3)
| Measurement | Value |
|---|---|
| Empty platform quality | DEGRADED (stuck check fails — expected) |
| Empty platform checks | 0x0D |
| 1kg placement jump | 1009g delta — FAILED |
| 1kg placement checks | 0x05 |
| Steady load quality | DEGRADED (stuck only) |

---

## Known limitations — health module

| ID | Description | Fix |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f — stuck check (bit 1) always fails | Update TareResult struct to expose variance. Wire in orchestrator. |
| TODO 1B-persistence | prev_cal_factor and prev_sigma_g from current boot only — cal/erratic checks always skip | Read prev from config.json at startup. Write after CAL_SUCCESS. |

---

## 1C — what it must do (next session brief)

Add millis() timing to each boot phase. Emit durations in structured Serial output.

Phases to instrument:
- Phase 0 (SETTLE): record start_ms, emit settle_ms on completion
- Phase 1 (NOISE): emit noise_ms
- Phase 2 (TARE): emit tare_ms
- Phase 3 (CAL): emit cal_ms
- STATE_RUNNING tick: emit tick_ms per reading cycle

Target output format:
```
[BOOT] phase=SETTLE ms=1823
[BOOT] phase=NOISE ms=412
[BOOT] phase=TARE ms=2104
[BOOT] phase=CAL ms=8341
[RUN] grams=1654.3 quality=DEGRADED sigma=2.64 tick_ms=103
```

Rules:
- No RTC — durations only, not wall clock
- millis() calls at phase entry and exit
- tick_ms = time from loop() entry to ble_notify() call
- No new module for 1C — timing logic goes in orchestrator directly
- This is a DESIGN session first — no CLI until structure confirmed in chat

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
| Pure function rule | health_check() owns no state. Orchestrator owns prev_* values. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". Must be physically impossible. |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — never IP address. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode confirmed: chat = design only, CLI = code only
3. Current position: 1B complete, health module verified on hardware
4. Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
5. Next action: 1C timing instrumentation — design session
6. Hub running at arduino@AQ3 gas-cylinder-monitor/hub — WebUI at AQ3:7000 — no gas logic yet

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_16_FINAL_4.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_16_FINAL_4.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_16_FINAL_4 — 1B complete, next=1C timing" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_16_FINAL_4.md fully before responding.
Context: 1B complete. Health module verified on 3-cell hardware.
Today we design 1C — timing instrumentation (millis() per boot phase).
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
