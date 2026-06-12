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
Load cell → HX711 → ESP32-C3 (node/) ──BLE──▶ UNO Q hub (hub/)
             [-------- node/ ---------]        [------- hub/ ----------]
             bit-bang, corrupt filters          timestamp, steel, gas%, SQLite,
             N-avg, cal_factor, grams           analytics, prediction, WebUI
             no gas%, no clock, no history      App Lab / Docker / Python
```

Payload via BLE GATT notify: `{grams: float, quality: GOOD|DEGRADED|FAILED, sigma: float}`
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
Transport  : BLE only (LOCKED 2026-06-05, validated 2026-06-08)
             E-003 PASSED. Full pipeline proven end-to-end.
             ESP32 GATT server → BlueZ QRB2210 → Python bleak → hub terminal with timestamp.
             bleak service_uuids filter not respected on QRB2210 - name filter applied in code (L-020)
             Noise STD with BLE running: 1.81g, threshold 7.24g (supersedes E-002 BLE-off values)

Experiments:
  E-000  PASSED  2026-06-04
  E-001  PASSED  2026-06-05
  E-002  PASSED  2026-06-08
  E-003  PASSED  2026-06-08
  Next: modular refactor → App Lab migration

Hub files:
  hub/e003_ble_test.py     - BLE subscriber, self-provisioning, MAC cache
  hub/config.json          - device config (MAC auto-populated on first run)
  hub/requirements.txt     - bleak>=0.21.0
```

---

## Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | 3.3V logic-level compatibility: HX711 DOUT/SCK vs ESP32-C3 GPIO | RESOLVED — 3V3 VDD safe, no level shifter needed |
| 2 | GPIO pin pair for ESP32-C3 + HX711 | RESOLVED — GPIO4=DOUT, GPIO3=SCK |
| 3 | cal_factor on ESP32-C3 (old 106.7 is VOID) | RESOLVED E-001: ~105 raw/g (single point, E-005 pending) |
| 4 | float vs double on ESP32-C3 (double-broken was STM32-specific) | RESOLVED E-001: float-only confirmed sufficient |
| 5 | Noise floor on ESP32-C3 + with hardened wiring | RESOLVED E-002: STD 0.62-0.67g, threshold 2.67g |
| 6 | WiFi transport protocol details (MQTT vs HTTP) | SUPERSEDED — transport locked as BLE-only |
| 7 | cal_factor linearity across full 0-20kg range | PENDING E-005 (parked) |
| 8 | Minimum detectable cooking event (real measurement) | PENDING E-006B post-install |
| 9 | BLE GATT UUIDs (service + characteristic) | RESOLVED E-003: service aa206b91-..., char b9b25bb1-... |
| 10 | Hub discovery without hardcoded MAC | RESOLVED E-003: self-provisioning via name filter + config.json cache |

---

## Read Order for Next Session

1. CLAUDE.md → WORKING_MODE.md → docs/PLAN.md → docs/SCOPE.md
2. docs/PROJECT_CONTEXT.md (this file) → docs/HANDOFF.md
3. Relevant docs/reference/specs/ for the current chunk-group
4. Design prompt from chat

---

## Current State - 2026-06-12 (ESP32 era - supersedes all sections above)

The platform described above (STM32/Bridge/App Lab) is VOID. Current architecture is in CLAUDE.md.

### Platform
ESP32-C3 SuperMini sensor node + Arduino UNO Q AQ3 hub.
3x YZC-161A 20kg load cells in parallel, shared plate. Transport: BLE-only.

### Experiment status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read single cell | PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare cal grams single cell | PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 3-cell) |
| E-002 noise floor single cell | PASSED 2026-06-08 | STD 0.67g BLE-off (VOID on 3-cell) |
| E-003 BLE transport single cell | PASSED 2026-06-08 | STD 1.81g BLE-on (VOID on 3-cell) |
| 3E-001 cal_factor 3-cell | PASSED 2026-06-12 | 36.1 raw/g locked, linear 200g to 1800g |
| 3E-002 noise floor 3-cell | NEXT | BLE off then BLE on |

### Locked values
cal_factor = 36.1 raw/g | GPIO4 = DOUT, GPIO3 = SCK | HX711 VCC = 3.3V only

### Next action
Design 3E-002 in chat. Implement via Claude Code CLI on AQ3.
