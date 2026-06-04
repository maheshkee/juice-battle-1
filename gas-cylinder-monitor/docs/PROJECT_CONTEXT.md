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
| ADC | HX711 GISLAB (green PCB, AVIAIC chip) | VDD = 3.3V — DOUT/SCK safe for ESP32-C3 GPIO |

**JCTL on UNO Q = 1.8V ONLY. 3.3V damages hardware.**
**ESP32-C3 wiring locked: GPIO4=DOUT, GPIO3=SCK, 3V3=VDD. 3.3V gate cleared 2026-06-04.**

---

## Current State

```
Status:           E-000 COMPLETE AND PASSED (2026-06-04)
Wiring:           LOCKED — GPIO4=DOUT, GPIO3=SCK, 3V3=VDD, GND=GND
                  Load cell Red=E+, Black=E-, Green=A+, White=A-
Arduino IDE:      esp32 v3.0.7, ESP32C3 Dev Module, COM11, USB CDC On Boot=ENABLED
node/ built:      E000_raw_read/E000_raw_read.ino (flashed, verified)
                  STOP/STOP.ino
                  HW_VERIFY/HW_VERIFY.ino
hub/:             empty — not started
Rough cal_factor: ~113 raw/g (ESP32-specific — re-derive in E-001, never use STM32's 106.7)
Current chunk:    Group 1, E-001
Next action:      Design E-001 in Claude.ai chat, implement via Claude Code CLI
```

---

## Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | 3.3V logic-level compatibility: HX711 DOUT/SCK vs ESP32-C3 GPIO | RESOLVED — 3V3 VDD safe, no level shifter needed |
| 2 | GPIO pin pair for ESP32-C3 + HX711 | RESOLVED — GPIO4=DOUT, GPIO3=SCK |
| 3 | cal_factor on ESP32-C3 (old 106.7 is VOID) | PENDING — E-001 (rough estimate ~113 raw/g) |
| 4 | float vs double on ESP32-C3 (double-broken was STM32-specific) | PENDING — E-001 |
| 5 | Noise floor on ESP32-C3 + with hardened wiring | PENDING — E-002 |
| 6 | WiFi transport protocol details (MQTT vs HTTP) | PENDING — Group 2 |

---

## Read Order for Next Session

1. CLAUDE.md → WORKING_MODE.md → docs/PLAN.md → docs/SCOPE.md
2. docs/PROJECT_CONTEXT.md (this file) → docs/HANDOFF.md
3. Relevant docs/reference/specs/ for the current chunk-group
4. Design prompt from chat
