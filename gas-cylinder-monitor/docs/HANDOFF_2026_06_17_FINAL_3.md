# SESSION HANDOFF — 2026-06-17 FINAL_3
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes all prior FINAL handoffs for this date.
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Node Layer 1 complete. 3E-006B + 3E-007B complete. Drift observed, to be characterised.
Next: 3E-008 — temperature drift experiment. Design in chat first.

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
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — use hostname, not IP) |
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
| sigma | 3.48–5.33g (boot-to-boot variation normal) | VERIFIED |
| zero accuracy | ~±3g | VERIFIED |
| weight accuracy | ±7g across 200g–1700g | VERIFIED |
| threshold_g | 4 × sigma (~14–21g depending on boot) | LOCKED |
| linear range | 200g–1700g | VERIFIED |
| min detectable removal | 20g (1 trial, SESSION2) | VERIFIED 3E-006B |
| hard floor | 10g — not detected | VERIFIED 3E-006B |
| false positive rate | 0/hr on static load (SESSION3, 38.4 min) | VERIFIED 3E-007B |
| slow drift | 190g peak-to-trough over 38 min on static load | OBSERVED — to characterise |
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

## Node module API — current

### weight_update()
```cpp
WeightResult weight_update(long raw, float tare_raw, float cal_factor, float sigma_g);
// 4 args — sigma_g required for threshold computation

enum WeightEvent { WEIGHT_EVENT_NONE=0, WEIGHT_EVENT_PLACED, WEIGHT_EVENT_REMOVED };
struct WeightResult {
    float grams; WeightQuality quality; char diagnosis[64];
    WeightEvent event; float delta;
};
```
Detector: 20-tick delay line. One event per physical transition (lockout flag).
Guard: no detection for first 40 ticks.

### journal_run()
```cpp
void journal_run(float grams, float sigma, const HealthResult& health,
                 WeightEvent event, float delta);
// 5 args — pure reporter, no detection logic
```

---

## Experiment program — status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read | ✅ COMPLETE | bit-bang proven |
| E-001 tare cal grams | ✅ COMPLETE | cal_factor ~105 raw/g (single cell) |
| E-002 noise floor | ✅ COMPLETE | STD 0.67g (single cell) |
| E-003 BLE transport | ✅ COMPLETE | end-to-end pipeline proven |
| 3E-001 cal_factor 3-cell | ✅ COMPLETE | ~36 raw/g, linear 200g–1800g |
| 3E-002 noise floor 3-cell | ✅ COMPLETE | sigma ~4.6–5.3g BLE-on |
| 3E-003 BLE transport 3-cell | ✅ COMPLETE | node→BLE→hub→WebUI end-to-end |
| 3E-004 accuracy | ✅ COMPLETE | ±7g across 200g–1700g |
| 3E-006B min detectable removal | ✅ COMPLETE | min=20g, hard floor=10g (1 trial) |
| 3E-007B false positive rate | ✅ COMPLETE 2026-06-17 | 0/hr on static load. PASS ✅ |
| **3E-008** | **NEXT** | **Temperature drift characterisation** |
| 3E-009 | Queued | Long-run stability soak — 24hr. Must quantify 190g drift. |

---

## Hub backlog — new items from SESSION3

### HUB-001 — Auto-Retare on Cylinder Removal
Trigger: WEIGHT_EVENT type=REMOVED ∧ grams≈0.
Flow: hub waits for 2 consecutive heartbeats with |delta| < 2σ → platform stable →
      sends RETARE command to node via BLE write characteristic.
Node requirement: **writable BLE GATT characteristic (command channel).**
This is a new architectural requirement — hub→node direction.
Must be added to node before hub Layer 2 development.
Priority: high.

### HUB-002 — Disturbance Detection from Heartbeat Trend
Trigger: sudden heartbeat grams step > 5× expected_consumption, no WEIGHT_EVENT.
Action: flag DISTURBANCE, mark readings UNRELIABLE until retare confirmed.
Prerequisite: Group 5 burn rate estimate.
Priority: medium.

### 1E — BLE Journal Transport
Dedicated BLE characteristic for journal log lines.
Hub writes to rotating log file (7 days retention).
Second characteristic UUID — separate from weight notify.
Gate: after 3E experiment program complete.
Priority: medium.

---

## Critical drift warning

**190g peak-to-trough drift observed on static load over 38 minutes.**
This is real slow drift, not noise. Cause: thermal or mechanical creep.
Impact: gas% will drift by up to 1.3% per 38 minutes if uncorrected.

Rule: hub MUST NOT treat raw heartbeat grams trend as gas consumption.
Drift correction or anchor-event normalisation required before any burn-rate computation.
3E-009 (24hr soak) will quantify the full magnitude.

---

## Node Layer 1 backlog — all complete

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE |
| 1C — Timing instrumentation | ✅ COMPLETE |
| 1D — Structured Serial journal | ✅ COMPLETE |
| 1E — BLE journal transport | DESIGNED, NOT BUILT |

---

## Known TODOs — deferred

| ID | Description | Fix |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f — stuck check always fails | Update TareResult struct to expose variance |
| TODO 1B-persistence | prev_cal_factor/prev_sigma_g not read from config.json | Read/write at boot and after CAL_SUCCESS |

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No government averages | 473 g/day banned. Real household data only. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Conservative bias | Always report lower gas estimate when uncertain. |
| Detection in weight.cpp | weight.cpp owns event detection. journal.cpp is a pure reporter. |
| No raw heartbeat as burn rate | 190g drift means heartbeat wander ≠ gas consumption. |
| Sentinel = -1.0f | 0.0f is a valid gross weight. Use -1.0f for "no previous value". |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — fallback IP: 192.168.88.20. |
| Design in chat | All code written exclusively via Claude Code CLI. |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino
│       ├── hx711.h / hx711.cpp
│       ├── tare.h  / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h   / cal.cpp
│       ├── weight.h / weight.cpp  ← delay-line detector, 4-arg
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp
│       └── journal.h / journal.cpp ← pure reporter, 5-arg
├── hub/                           ← DEPLOYED SKELETON (no gas logic)
│   ├── app.yaml
│   ├── deploy.sh
│   ├── python/
│   │   ├── main.py
│   │   └── ble_subscriber.py     ← _check_known_devices() fix deployed
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── HANDOFF_2026_06_17_FINAL_1.md
    ├── HANDOFF_2026_06_17_FINAL_2.md
    ├── HANDOFF_2026_06_17_FINAL_3.md  ← this file (SESSION3 close)
    └── HANDOFF_2026_06_17_SESSION3.md
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document (FINAL_3) read fully
2. Working mode confirmed: chat = design only, CLI = code only
3. Current position: 3E-007B complete, next = 3E-008
4. Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino (unchanged from SESSION2)
5. 190g drift warning read and understood
6. HUB-001 requires new writable BLE characteristic on node before hub Layer 2

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_17_FINAL_3.md fully before responding.
Context: 3E-007B complete — 0 false triggers in 38.4 min, delay-line validated.
190g slow drift observed on static load — must characterise in 3E-009.
Today we design 3E-008 (temperature drift experiment) in chat.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
