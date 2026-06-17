# SESSION HANDOFF — 2026-06-17 FINAL_3
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Node Layer 1 complete + 3E-006B complete (min detectable removal = 20g, hard floor 10g).
Next: 3E-007B — repeat removal experiment 3 trials to confirm 20g minimum.

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
| sigma | 3.48–5.33g (boot-to-boot variation — range observed across sessions) | VERIFIED |
| zero accuracy | ~±3g | VERIFIED |
| weight accuracy | ±7g across 200g–1700g | VERIFIED |
| threshold_g | 4 × sigma (~14–21g depending on boot) | LOCKED |
| linear range | 200g–1700g | VERIFIED |
| min detectable removal | 20g (1 trial, SESSION2) | VERIFIED 3E-006B |
| hard floor | 10g — not detected | VERIFIED 3E-006B |
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

## Node module API — current (post-SESSION2)

### weight_update() — UPDATED SESSION2
```cpp
// 4-arg signature — sigma_g is now required
WeightResult weight_update(long raw, float tare_raw, float cal_factor, float sigma_g);

// WeightResult gains event and delta
enum WeightEvent { WEIGHT_EVENT_NONE=0, WEIGHT_EVENT_PLACED, WEIGHT_EVENT_REMOVED };
struct WeightResult {
    float         grams;
    WeightQuality quality;
    char          diagnosis[64];
    WeightEvent   event;   // NEW SESSION2
    float         delta;   // NEW SESSION2
};
```

Detector: 20-tick delay-line comparator (compares current mean to mean 20 ticks ago).
s_event_pending lockout flag: one WEIGHT_EVENT per physical event, no cascade.
Guard: no detection for first 40 ticks (BUF_SIZE × 2 — priming delay line).

### journal_run() — UPDATED SESSION2
```cpp
// 5-arg signature — event and delta are now required
void journal_run(float grams, float sigma, const HealthResult& health,
                 WeightEvent event, float delta);
```

journal.cpp is a pure reporter — it no longer contains detection logic.
Detection is weight.cpp's responsibility (computation module).

---

## Journal module — format unchanged

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
| [RUN] | WEIGHT_EVENT | Delta > 4×sigma (one per physical event) |
| [HB] | HEARTBEAT | Every 30 seconds |
| [FAULT] | PHASE_FAIL | Phase failure |

---

## 3E-006B — Experiment results (SESSION2, 2026-06-17)

sigma this session: 3.65g → threshold = 14.6g

| Removed (g) | Detected? | Notes |
|---|---|---|
| 200g | YES | Strong detection |
| 100g | YES | Strong detection |
| 50g | YES | Clear detection |
| 20g | YES | Above 14.6g threshold — single WEIGHT_EVENT fired |
| 10g | NO | Below threshold — hard floor |

Key insight: load cell creep over the 20-tick window slightly amplifies the measured delta.
Detector is marginally more sensitive than pure 4σ theory predicts.

---

## Hub — BLE subscriber state (SESSION2)

File: hub/python/ble_subscriber.py

Bug fixed SESSION2: InterfacesAdded does not fire for already-known/cached BlueZ devices.
Fix: _check_known_devices() walks GetManagedObjects() to find cached devices.
Called at: startup (in _run()) AND on every _start_scan() call (for reconnect).

BlueZ rules on QRB2210 (locked):
- Transport='le' only in SetDiscoveryFilter — 'auto' kills the adapter
- Name-based matching only — UUID filter in SetDiscoveryFilter is ignored
- No RemoveDevice before Connect on fresh discovery
- GetManagedObjects() for scanning existing BlueZ device cache

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
│       ├── weight.h / weight.cpp ← UPDATED SESSION2: 4-arg, delay-line detector
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp
│       ├── journal.h / journal.cpp ← UPDATED SESSION2: 5-arg, pure reporter
│       ├── README.md
│       └── config.json
├── hub/                          ← DEPLOYED, RUNNING (skeleton — no gas logic yet)
│   ├── app.yaml
│   ├── deploy.sh
│   ├── python/
│   │   ├── main.py
│   │   └── ble_subscriber.py    ← UPDATED SESSION2: _check_known_devices() fix
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    ├── EXPERIMENT_PROGRAM.md
    ├── HANDOFF_2026_06_17_FINAL_1.md
    ├── HANDOFF_2026_06_17_FINAL_2.md
    └── HANDOFF_2026_06_17_FINAL_3.md  ← this file
```

---

## Node Layer 1 backlog — status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE |
| 1C — Timing instrumentation | ✅ COMPLETE 2026-06-17 |
| 1D — Structured Serial journal | ✅ COMPLETE 2026-06-17 |
| 1E — BLE journal transport | DESIGNED, NOT BUILT — medium priority, post-experiment |

### 1E — BLE journal transport (design only)
Dedicated BLE GATT characteristic for journal log lines.
Hub writes to rotating log file on AQ3 (max 7 days retention).
Requires second characteristic UUID — separate from weight notify characteristic.
Gate: after 3E experiment program complete + hub BLE subscriber stable.

---

## Experiment program — status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read | COMPLETE | bit-bang proven |
| E-001 tare cal grams | COMPLETE | cal_factor ~105 raw/g (single cell, VOID for 3-cell) |
| E-002 noise floor | COMPLETE | STD 0.67g (single cell, VOID for 3-cell) |
| E-003 BLE transport | COMPLETE | end-to-end pipeline proven |
| 3E-001 cal_factor 3-cell | COMPLETE | ~36 raw/g, linear 200g–1800g |
| 3E-002 noise floor 3-cell | COMPLETE | BLE-on sigma ~4.6–5.3g |
| 3E-003 BLE transport 3-cell | COMPLETE | ESP32→BLE→Hub→WebUI end-to-end |
| 3E-004 accuracy | COMPLETE | ±7g across 200g–1700g |
| 3E-006B min detectable removal | COMPLETE 2026-06-17 | min=20g, hard floor=10g (1 trial) |
| **3E-007B** | **NEXT** | **Repeat 3 trials — confirm 20g minimum** |
| 3E-007 temperature drift | Queued | |
| 3E-008 long-term drift soak | Queued | |

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
| Computation vs service modules | Computation = pure function (health, cal, noise, weight). Service = stateful (journal). |
| Detection in computation module | weight.cpp owns event detection. journal.cpp is a pure reporter. Never put detection in a service module. |
| Event log not data stream | Log transitions not state. ~750 lines/session vs 216k tick-by-tick. |
| Delay-line detector | Compare mean(now) vs mean(20 ticks ago). Immune to single-sample noise. Single event per removal via lockout flag. |
| Sequence numbers in RAM only | Never persist to flash. Boot counter persisted; seq resets per boot. |
| Heartbeat dual purpose | Proof of life + trend data spine for hub. 30s interval. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". Must be physically impossible. |

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
| Build order discipline | Verify each layer before building on top. |
| Module contract | Computation modules return {value, quality, diagnosis}. Never just bool. |
| Pure function rule | Computation modules own no state. Service modules (journal) own their state. |
| Detection belongs in computation | Never detect events in journal.cpp — it is a reporter only. |
| Sentinel = -1.0f | 0.0f is a valid gross weight. Use -1.0f for "no previous reading". |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — if hostname fails, use 192.168.88.20 (current IP). |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

---

## Next session — 3E-007B: confirm minimum detectable removal

### What this experiment answers
Does 20g detection hold across 3 independent trials?
SESSION2 was a single trial — not statistically reliable.
3 trials required to declare the minimum confirmed.

### Setup needed
- Same water container setup as 3E-006B
- Measuring cup, kitchen scale
- Run: place container → wait for RUNNING → remove 20g → observe journal → replace → repeat × 3

### What to measure
- Does WEIGHT_EVENT type=REMOVED fire for every 20g removal?
- How many ticks until WEIGHT_EVENT fires?
- Any false positives while container is sitting still?

### Gate
3 successful trials → declare min_detectable_removal = 20g confirmed.
If any trial fails → investigate (sigma variance? placement variance?) → adjust threshold or re-test.

---

## Session start checklist for new chat

Before answering anything, confirm:
1. HANDOFF_2026_06_17_FINAL_2.md read (BLE subscriber session)
2. This document (FINAL_3) read fully
3. Working mode confirmed: chat = design only, CLI = code only
4. Current position: 3E-006B complete, next = 3E-007B
5. Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino (weight.cpp updated)
6. Hub BLE subscriber: _check_known_devices() fix deployed, WebUI at AQ3:7000

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_17_FINAL_2.md and HANDOFF_2026_06_17_FINAL_3.md fully before responding.
Context: 3E-006B complete — min detectable removal = 20g (1 trial), hard floor 10g.
Weight detector fixed: delay-line in weight.cpp, journal is now a pure reporter.
Today we design and run 3E-007B — 3-trial confirmation of the 20g minimum.
Start by confirming you read both handoffs and state current position."

---

*End of handoff. Next chat is ready.*
