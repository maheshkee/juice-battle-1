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
  hub/ COMPLETE AND DEPLOYED — App Lab ID: user:gas-cylinder-monitor/hub, WebUI: http://AQ3:7000
  hub/python/main.py           - Flask + Socket.IO server
  hub/python/ble_subscriber.py - BlueZ BLE subscriber, self-provisioning
  hub/assets/index.html        - WebUI showing live grams
  hub/app.yaml, setup.sh, deploy.sh
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
| 11 | Accuracy offset — readings proportional but offset from known weights | 2026-06-15 | ❓ Pending |

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

### Experiment status (as of 2026-06-15)

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read single cell | PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare cal grams single cell | PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 3-cell) |
| E-002 noise floor single cell | PASSED 2026-06-08 | STD 0.67g BLE-off (VOID on 3-cell) |
| E-003 BLE transport single cell | PASSED 2026-06-08 | STD 1.81g BLE-on (VOID on 3-cell) |
| 3E-001 cal_factor 3-cell | PASSED 2026-06-12 | 36.1 raw/g locked, linear 200g to 1800g |
| 3E-002 noise floor 3-cell | PASSED 2026-06-15 | noise_std_g BLE-off=4.93g, BLE-on=4.64g LOCKED |
| 3E-003 BLE transport (3-cell) | PASSED 2026-06-15 | ESP32→BLE→Hub→WebUI end-to-end |
| 3E-004 accuracy investigation | PASSED 2026-06-16 | ±7g accuracy across 200g–1700g verified |

### Locked values
cal_factor: NOT hardcoded — derived every boot via Phase 3 self-cal (~36 raw/g nominal)
tare source: s2_mean from Phase 2 (200-sample mean) — not Phase 1 window mean
GPIO4 = DOUT, GPIO3 = SCK | HX711 VCC = 3.3V only
Transport: BLE confirmed (not WiFi — any WiFi references in older sections are void)
Production sketch: node/3E004_cal_and_run/3E004_cal_and_run.ino

---

## Current State — 2026-06-16 (design session — no hardware touched)

Updated: 2026-06-16 | This section supersedes all prior state sections.

### Architecture confirmed
Transport: BLE only — locked, validated end-to-end
Platform: 3-cell (3× YZC-161A 20kg, shared fibre plate)
cal_factor: ~36 raw/g nominal, derived every boot (self-calibrating boot)
Production sketch: 3E004_cal_and_run.ino

### Backlog audit complete — full ordered backlog

**1A-1D: Modular sketch series (immediate next)**
| Chunk | Task | Status |
|-------|------|--------|
| 1A | Modular sketch port to 3-cell ESP32-C3 (hx711.cpp, tare.cpp, cal.cpp, weight.cpp) | NEXT ACTION |
| 1B | Structured Serial journal (machine-parseable [BOOT][CAL][TARE][WEIGHT][ERR] prefixes) | Queued |
| 1C | Timing instrumentation — log read latency and state machine cycle times | Queued |
| 1D | Noise floor recheck on 3-cell platform (repeat 3E-002 procedure post-modular port) | Queued |

**Sensor experiment backlog (3E series)**
| ID | Experiment | Status |
|----|-----------|--------|
| 3E-006B | Minimum detectable event — cook real/simulated water event | Queued |
| 3E-007 | Temperature drift characterisation — 24hr indoor range | Queued |
| 3E-008 | Long-term drift soak — 24hr continuous unloaded | Queued |
| 3E-009 | Multi-cylinder weight envelope — 5kg, 14.2kg, 19kg gross ranges | Queued |
| 3E-010 | Refill detection false-positive tuning — weight jump threshold validation | Queued |

**Hub integration backlog (Groups 4-7)**
| Group | Feature | Status |
|-------|---------|--------|
| 4 | Gas snapshot 6hr cycle + SQLite writes | Queued |
| 5 | Daily aggregates + multi-window burn-rate prediction | Queued |
| 6 | Refill detection + learning window reset on anchor event | Queued |
| 7 | Gas dashboard WebUI + BLE low-gas alert | Queued |

**V2 / V3 cold-start strategies (hub phase)**
| Version | Strategy | Notes |
|---------|---------|-------|
| V1 | Delta tracking only — burn rate, sessions, days_remaining slope exact from day 1 | Ship this |
| V2 | Tare persistence — stamped tare from cylinder label, unlocks absolute gas% | Requires user input at install |
| V3 | Self-heal anchor — system learns steel across a complete refill cycle | Unlocks full gas% without user input |

### V1/V2/V3 threshold values (derived from first principles, 2026-06-16)
| Threshold | Value | Derivation |
|-----------|-------|-----------|
| CYLINDER_REMOVED | < 2 kg | Kitchen item upper bound ~5kg, margin |
| FRESH_CYLINDER_MIN | > 26 kg | Full 14.2kg gross minimum per BIS IS 3196 |
| REFILL_THRESHOLD | Δ > 6 kg | Sits above 5kg max kitchen object on platform |
| LOW_GAS | gas% < 20% | ~2.84kg gas remaining, ~9 days at avg consumption |
| CRITICAL_GAS | gas% < 5% | ~710g remaining, ~2 days — trigger immediate alert |

### Conservative bias rule (locked 2026-06-16)
Always report lower gas estimate when uncertain.
False pessimism → user orders early (minor inconvenience).
False optimism → gas outage (major product failure).
The product must NEVER tell the user they have more gas than they actually do.

### Open questions remaining
| # | Question | Status |
|---|----------|--------|
| 1 | 3E-006B: minimum real cooking event in grams | Pending post-install |
| 2 | Temperature drift magnitude over real 24hr indoor cycle | Pending 3E-007 |
| 3 | Whether partial same-brand cylinder swap needs special handling | Design pending |
| 4 | Non-domestic cylinder support (19kg commercial) | V3 scope |
