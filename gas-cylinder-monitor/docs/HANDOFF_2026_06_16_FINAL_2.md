# SESSION HANDOFF — 2026-06-16 FINAL_2
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Design session complete. Full backlog audited. All V1/V2/V3 architecture locked.
Next: 1A — modular sketch port to 3-cell ESP32-C3 (hx711/tare/noise/cal/weight as .h/.cpp).

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

---

## Locked values — hardware-verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | LOCKED |
| cal_factor typical | ~36 raw/g (3-cell parallel) | VERIFIED |
| tare source | s2_mean (200-sample Phase 2 mean) | LOCKED |
| Zero accuracy | ±4g | VERIFIED |
| Weight accuracy | ±7g across 200g–1700g | VERIFIED |
| noise_std_g | 4.84g | VERIFIED |
| threshold_g | 19.34g (4 × STD) | VERIFIED |
| Linear range | 200g–1700g | VERIFIED E-005 |
| Production sketch | 3E004_cal_and_run.ino | CURRENT |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Char UUID:       b9b25bb1-f2a9-4545-b48f-295ab2789f41
Device name:     GasCylMonitor
Payload format:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
```

---

## Three product versions — cold-start strategy

| Version | Install condition | Steel source | User input | Accuracy |
|---|---|---|---|---|
| V1 | Fresh full cylinder | S = G − 14.2 (BIS law). Exact. | None ever | Exact from first reading |
| V2 | Partial, brand known | Brand lookup OR stamped tare (once) | Once at setup | ~±1-3% until anchor |
| V3 | Partial, fully blind | Interval [G−15.8, G−14.5]. Midpoint 15.15kg | None ever | ±5% until anchor |

All three versions converge to identical V1 steady-state after first anchor event (fresh cylinder refill). V2/V3 are one-time cold-start accommodations only.

---

## Hub state machine — V1

```
UNINSTALLED → (ΔG > 6kg AND G_new > 26kg AND stable 3 windows) → TRACKING
TRACKING    → (G < 2kg)                                          → UNINSTALLED
TRACKING    → (gas < 2kg OR days < 10)                          → LOW GAS
LOW GAS     → (ΔG > 6kg refill)                                 → TRACKING
LOW GAS     → (G < 2kg)                                         → UNINSTALLED
```

---

## Threshold values — first-principles derived

| Constant | Value | Why |
|---|---|---|
| CYLINDER_REMOVED_KG | 2.0 kg | Gap: empty platform <1kg vs lightest cylinder 14.5kg |
| REFILL_THRESHOLD_KG | 6.0 kg | Gap: max kitchen object 5kg vs min real jump ~29kg |
| FRESH_CYLINDER_MIN_KG | 26.0 kg | Gap: heaviest partial 27.7kg vs lightest full 29.0kg |
| LOW_GAS_KG | 2.0 kg | Alert threshold |
| LOW_GAS_DAYS | 10 days | Alert threshold |
| STEEL_MIN_KG | 14.5 kg | Indane minimum |
| STEEL_MAX_KG | 15.8 kg | HP maximum |
| CAPACITY_KG | 14.2 kg | BIS IS 3196 — legally fixed |

---

## Experiment status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read | PASSED 2026-06-04 | bit-bang proven |
| E-001 tare+cal+grams | PASSED 2026-06-05 | single-cell (VOID on 3-cell) |
| E-002 noise floor | PASSED 2026-06-08 | single-cell (VOID on 3-cell) |
| E-003 BLE transport | PASSED 2026-06-08 | single-cell (VOID on 3-cell) |
| 3E-001 cal_factor 3-cell | PASSED 2026-06-12 | ~36 raw/g |
| 3E-002 noise floor 3-cell | PASSED 2026-06-15 | STD 4.64g BLE-on |
| 3E-003 BLE transport 3-cell | PASSED 2026-06-15 | end-to-end working |
| E-005 linearity | PASSED 2026-06-16 | linear 200–1700g |
| 3E-004 cal+run | PASSED 2026-06-16 | ±7g accuracy, self-calibrating boot |
| 3E-006B min detectable removal | NOT RUN | water container needed |
| 3E-007B false positive rate | NOT RUN | threshold stress test |
| 3E-008 temperature drift | NOT RUN | kitchen temp variation |
| 3E-009 long-run 6hr | NOT RUN | baseline drift under load |
| 3E-010 load cell failure injection | NOT DESIGNED | health module needed first |
| 3E-005 V1 anchor validation | NOT RUN | hub domain logic needed first |

---

## Complete backlog — correct build order

### Layer 1 — Node foundation (build first)
1. **1A** — Modular sketch port to 3-cell ESP32-C3 (hx711/tare/noise/cal/weight as .h/.cpp)
2. **1B** — Load cell health detection module (open wire, stuck zero, erratic variance)
3. **1C** — Timing instrumentation: millis() per boot phase → settle_ms, tare_ms, noise_ms, cal_ms
4. **1D** — Structured Serial journal: [BOOT] phase=TARE result=SUCCESS spread=142 ms=2341

### Layer 2 — Experiments (run after Layer 1)
5. 3E-006B — Minimum detectable removal (water container + measuring cup)
6. 3E-007B — False positive rate (30min stable load, count false triggers)
7. 3E-008 — Temperature drift (cal_factor + zero shift vs kitchen temp)
8. 3E-009 — Long-run 6hr stability (baseline wander under real load)
9. 3E-010 — Load cell failure injection (disconnect one cell, verify health module)

### Layer 3 — Hub (build after Layer 2)
10. Hub timestamp discipline verification
11. Hub structured event journal
12. Hub quality=FAILED handling
13. Group 4 — Domain logic (steel derivation + state machine)
14. **3E-005** — V1 anchor validation experiment (water container simulation)
15. Group 5 — Analytics (burn rate from real data)
16. Group 6 — Prediction (days remaining)
17. Group 7 — WebUI outputs (gas gauge, state, trend)
18. V2 cold-start logic (brand lookup + stamped tare)
19. V3 cold-start logic (interval estimation)

---

## Key documents for this session
- GasCylMonitor_SessionDecisions_2026_06_16.docx — full session decisions reference
- EXPERIMENT_PROGRAM.md — experiment specifications
- SESSION_CLOSE_PROTOCOL.md — end-of-session sequence

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No government averages | 473 g/day banned. Real household data only. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32 has no RTC. |
| No premature prediction | burn_rate and days show — until 24h of real data. |
| Conservative bias | Always report lower gas estimate when uncertain. |
| Build order discipline | Verify each layer before building on top. |
| Module contract | Every module returns {value, quality, diagnosis}. Never just bool. |
| BLE transport | BlueZ: le transport only. No RemoveDevice before Connect. |
| SCP hostname | Always arduino@AQ3 — never IP address. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

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
├── hub/                      ← DEPLOYED, RUNNING (skeleton only — no gas logic yet)
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
    ├── HANDOFF_2026_06_16_FINAL_2.md  ← this file
    └── GasCylMonitor_SessionDecisions_2026_06_16.docx ← session decisions reference
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. GasCylMonitor_SessionDecisions_2026_06_16.docx reviewed
3. Working mode: chat = design only, CLI = code only
4. Current position: design session complete, backlog audited
5. Production sketch: 3E004_cal_and_run.ino — no changes needed to node yet
6. Next action: 1A modular sketch port design
7. Hub running at user:gas-cylinder-monitor/hub — WebUI at AQ3:7000 — no gas logic yet

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_16_FINAL_2.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_16_FINAL_2.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_16_FINAL_2 — backlog audited, V1/V2/V3 architecture locked" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_16_FINAL_2.md and GasCylMonitor_SessionDecisions_2026_06_16.docx fully before responding.
Context: Design session complete. Full backlog audited. V1/V2/V3 architecture locked.
Today we design 1A — the modular sketch port to 3-cell ESP32-C3.
Start by confirming you read both documents and state current position."

---

*End of handoff. Next chat is ready.*
