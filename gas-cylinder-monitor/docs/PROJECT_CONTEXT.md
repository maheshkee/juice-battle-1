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
Status:           E-001 COMPLETE AND PASSED (2026-06-05)
Wiring:           LOCKED — GPIO4=DOUT, GPIO3=SCK, 3V3=VDD, GND=GND
                  Load cell Red=E+, Black=E-, Green=A+, White=A-
Arduino IDE:      esp32 v3.0.7, ESP32C3 Dev Module, COM11, USB CDC On Boot=ENABLED
node/ built:      E000_raw_read/E000_raw_read.ino — DONE
                  E001_tare_cal_grams/E001_tare_cal_grams.ino — DONE
                  STOP/STOP.ino
                  HW_VERIFY/HW_VERIFY.ino
hub/:             empty — not started
cal_factor:       ~105 raw/g (derived from 227g-257g weights, stable to 0.6%)
                  Unreliable below ~100g reference weight (SNR too low)
Tare range:       -13823 to -15747 raw (varies per boot, self-characterised)
Current chunk:    Group 1 - WEIGHT. E-001 PASSED. E-002 is next.
Next action:      E-002 noise floor characterisation on ESP32-C3
```

---

## Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | 3.3V logic-level compatibility: HX711 DOUT/SCK vs ESP32-C3 GPIO | RESOLVED — 3V3 VDD safe, no level shifter needed |
| 2 | GPIO pin pair for ESP32-C3 + HX711 | RESOLVED — GPIO4=DOUT, GPIO3=SCK |
| 3 | cal_factor on ESP32-C3 (old 106.7 is VOID) | RESOLVED — ~105 raw/g (derived E-001, stable 227g-257g) |
| 4 | float vs double on ESP32-C3 (double-broken was STM32-specific) | PENDING — E-001 |
| 5 | Noise floor on ESP32-C3 + with hardened wiring | PENDING — E-002 |
| 6 | WiFi transport protocol details (MQTT vs HTTP) | PENDING — Group 2 |
| 7 | cal_factor linearity (227g-257g confirmed, below 100g unreliable) | PARTIALLY RESOLVED — stable 0.6% variation 227g-257g. Below 100g unreliable (SNR). Above 257g unknown — pending Experiment 005 with kg-range weights. |
| 8 | cal_factor linearity above 257g | PENDING — requires kg-range known weights, Experiment 005 |

---

## Read Order for Next Session

1. CLAUDE.md → WORKING_MODE.md → docs/PLAN.md → docs/SCOPE.md
2. docs/PROJECT_CONTEXT.md (this file) → docs/HANDOFF.md
3. Relevant docs/reference/specs/ for the current chunk-group
4. Design prompt from chat
