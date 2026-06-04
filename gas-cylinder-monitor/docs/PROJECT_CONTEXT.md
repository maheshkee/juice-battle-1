# PROJECT_CONTEXT.md — Gas Cylinder Monitor
# Updated: 2026-06-04 (ESP32 pivot ingested)
# One-screen current state. Update at the start of every session.

---

## What This Product Is

LPG cylinder weight monitor for Indian households. Load cell under cylinder.
ESP32-C3 reads weight, sends grams to UNO Q hub. Hub derives steel, computes gas %,
stores to SQLite, runs analytics + prediction, serves WebUI.

Development uses water in a container — not gas. No code path hardcodes "gas" semantics.

---

## Architecture

```
Load cell → HX711 → ESP32-C3 (node/) ──WiFi──▶ UNO Q hub (hub/)
             [-------- node/ ---------]         [------- hub/ ----------]
             bit-bang, corrupt filters           timestamp, steel, gas%, SQLite,
             N-avg, cal_factor, grams            analytics, prediction, WebUI
             no gas%, no clock, no history       App Lab / Docker / Python
```

Payload across WiFi: `{grams: float, quality: GOOD|DEGRADED|FAILED, sigma: float}`
Hub stamps timestamp on receipt. ESP32-C3 has no RTC.

---

## Hardware

| Role | Board | IP / Connection |
|------|-------|----------------|
| Hub | Arduino UNO Q AQ3 | 192.168.1.161 (SSH: arduino@192.168.1.161) |
| Node | ESP32-C3 | in hand — USB flash via Arduino IDE / PlatformIO |
| Load cell | YZC-161A 20 kg | Red→E+, Black→E-, Green→A+, White→A- |
| ADC | HX711 (green PCB) | VCC = 5V (critical — HX711 needs 5V full excitation) |

**JCTL on UNO Q = 1.8V ONLY. 3.3V damages hardware.**
**ESP32-C3 GPIO = 3.3V. HX711 DOUT/SCK at 5V VCC — check logic-level compatibility (E-000 gate).**

---

## Current State

```
Status:         SCAFFOLD ONLY
node/:          empty — no ESP32-C3 firmware
hub/:           empty — no Python hub
Current chunk:  Pre-Group-1
Next action:    Design E-000 in Claude.ai chat
                (3.3V gate + GPIO pin selection + first raw read)
```

---

## Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | 3.3V logic-level compatibility: HX711 DOUT/SCK vs ESP32-C3 GPIO | PENDING — E-000 gate |
| 2 | GPIO pin pair for ESP32-C3 + HX711 | PENDING — E-000 |
| 3 | cal_factor on ESP32-C3 (old 106.7 is VOID) | PENDING — E-001 |
| 4 | float vs double on ESP32-C3 (double-broken was STM32-specific) | PENDING — E-001 |
| 5 | Noise floor on ESP32-C3 + with hardened wiring | PENDING — E-002 |
| 6 | WiFi transport protocol details (MQTT vs HTTP) | PENDING — Group 2 |

---

## Read Order for Next Session

1. CLAUDE.md → WORKING_MODE.md → docs/PLAN.md → docs/SCOPE.md
2. docs/PROJECT_CONTEXT.md (this file) → docs/HANDOFF.md
3. Relevant docs/reference/specs/ for the current chunk-group
4. Design prompt from chat
