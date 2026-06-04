# ARCHITECTURE.md — Gas Cylinder Monitor
# Last updated: 2026-06-04 (ESP32 pivot — complete rewrite)
# Status: Active. STM32/Bridge architecture is SUPERSEDED.
# See: docs/reference/HANDOFF_ESP32_PIVOT.md for the pivot decision record.

---

## System Overview

LPG cylinder weight monitor for Indian households. Single load cell (YZC-161A 20 kg)
under the cylinder. ESP32-C3 reads weight, sends grams to UNO Q hub. Hub owns everything
above grams: steel derivation, gas %, storage, analytics, prediction, WebUI.

---

## Pipeline

```
Load cell (20 kg YZC-161A)
    │ analog mV signal (4-wire: Red→E+, Black→E-, Green→A+, White→A-)
    ▼
HX711 ADC (24-bit, gain 128, channel A, RATE pin LOW = 10 SPS)
    │ raw 24-bit counts (corrupt-filtered)
    ▼
ESP32-C3 sensor node  [node/ directory]
    │ bit-bang read, corrupt filters, N-sample average, cal_factor → GRAMS
    │ WiFi (MQTT-style or HTTP POST)
    ▼
THE SEAM: { "grams": float, "quality": "GOOD"|"DEGRADED"|"FAILED", "sigma": float }
    │ hub stamps timestamp on receipt (ESP32-C3 has no RTC)
    ▼
UNO Q hub — QRB2210 Linux / App Lab / Python  [hub/ directory]
    │
    ├─ steel derivation (anchor events from SQLite history)
    │     steel = gross_at_install − CAPACITY_KG  (14.2 kg, BIS law IS 3196)
    │
    ├─ gas remaining = grams − steel
    │   gas %       = gas_remaining / 14200 × 100
    │
    ├─ SQLite storage
    │     readings (ts, gross_kg, gas_kg, gas_pct) — heartbeat every 15 min
    │     refill_events — full calibration context per cylinder change
    │
    ├─ Analytics (consumption, burn rate, patterns)
    │
    ├─ Prediction (days remaining, confidence interval)
    │
    └─ WebUI (Flask / Socket.IO dashboard, gas gauge, trend chart)
```

---

## The Seam (Node ↔ Hub Contract)

The seam is the node→hub WiFi payload. See docs/reference/INTERFACE_CONTRACTS.md
for the full contract.

```json
{ "grams": 29420.5, "quality": "GOOD", "sigma": 2.3 }
```

- `grams` = gross weight (steel + gas). Node never computes gas %.
- `quality` = GOOD | DEGRADED | FAILED (node's assessment of read quality)
- `sigma` = noise std from the node's last noise characterisation (grams)
- `timestamp` = stamped by HUB on receipt. ESP32-C3 has no RTC.

**What crosses the seam:** grams only.
**What never crosses:** raw ADC counts, tare_raw, cal_factor, steel, gas%.

---

## Component Responsibilities

### ESP32-C3 Sensor Node (node/)

| Owns | Does NOT own |
|------|-------------|
| HX711 raw bit-bang | Any computation of gas % |
| Corrupt-value filters (LONG_MIN, -1, 0x7FFFFF) | Steel/capacity knowledge |
| N-sample averaging (N=50 production, N=200 lab) | Timestamps (no RTC) |
| Scale-zero tare (self-computed, never hardcoded) | History or trend data |
| cal_factor derivation (never hardcoded) | SQLite |
| Noise characterisation (boot-time) | App Lab / Bridge / Docker |
| WiFi send (grams, quality, sigma) | — |

**SAFETY GATE:** HX711 VCC = 5V. ESP32-C3 GPIO = 3.3V.
**Verify DOUT/SCK logic-level compatibility before first power-on.** Level-shift if needed.
This is E-000 chunk 1.

**cal_factor:** re-derived on ESP32-C3 from scratch. The STM32 value (106.7 raw/g) is VOID.

**Pins:** TBD at E-000. Old DT=D7/SCK=D6 was a STM32 timer-conflict constraint, VOID here.

### UNO Q Hub (hub/)

| Owns | Does NOT own |
|------|-------------|
| WiFi receive from node | HX711 access |
| Timestamp stamping on receipt | Pin operations |
| Steel derivation (anchor events) | cal_factor |
| gas% = (grams − steel) / 14200 × 100 | Noise characterisation |
| SQLite storage | Any sensor bit-bang |
| Analytics + burn rate | Bridge.notify (not used) |
| Prediction (days remaining) | — |
| WebUI (Flask/Socket.IO) | — |

The UNO Q's STM32U585 MCU is **idle in V1** — the ESP32-C3 owns sensing.
All Python runs in App Lab Docker on the QRB2210 Linux side.

---

## Hub State Machine

```
UNINSTALLED ──── G jump > 6.0 kg ──────▶ TRACKING
    ▲                                        │
    │                                  gas < LOW_GAS_KG
    └── G < 2.0 kg (cylinder removed)   or days < LOW_GAS_DAYS
         ◀─────────────────────────────       │
                                              ▼
                                          LOW GAS ──── G jump > 6.0 kg ──▶ TRACKING
```

States: UNINSTALLED | TRACKING | LOW GAS
Transitions driven by hub analysis of the incoming grams stream, not by the node.

---

## Calibration Architecture (Two Layers — Never Conflate)

**Layer 1 — Scale calibration (node):** raw counts → grams
```
cal_factor = (raw_with_known_weight - tare_raw) / known_weight_g
grams      = (raw_reading - tare_raw) / cal_factor
```
Per-MCU, per-cell. Re-derived on ESP32-C3. Never hardcoded.

**Layer 2 — Domain calibration (hub):** grams → gas remaining + %
```
steel  = gross_at_install - CAPACITY_KG   (CAPACITY = 14.2 kg, BIS law)
gas    = gross_current - steel
gas%   = gas / 14200 × 100
```
Derived from anchor events (full cylinder install). Never assumed. Never hardcoded.

---

## Data Flow — Heartbeat Spine

```
ESP32-C3 fast reads (every few seconds, internal, not stored)
    │  WiFi → hub
    ▼
Hub receives grams, stamps timestamp
    │
    ├─ Store to SQLite every 15 min (heartbeat spine) ← authoritative time-grid
    │
    ├─ On install G-jump: steel derivation → enable gas% output
    │
    ├─ On removal: auto-tare of scale-zero → correct zero-drift
    │
    └─ Analytics + prediction read from readings table on demand
```

15-minute heartbeat: sub-hour resolution for cooking-pattern analytics; ~96 rows/day is
trivial storage; idle readings are evidence (liveness + leak detection), not waste.

---

## Folder Structure

```
gas-cylinder-monitor/
├── CLAUDE.md                    ← read first every session
├── SKILL.md                     ← node (ESP32/HX711) vs hub (App Lab/Python) patterns
├── README.md
├── node/                        ← ESP32-C3 firmware (Arduino/PlatformIO)
│   └── README.md
├── hub/                         ← UNO Q Python hub (App Lab Docker)
│   └── README.md
├── docs/
│   ├── PLAN.md                  ← chunk-groups 1–7
│   ├── SCOPE.md                 ← V1 locked scope, state machine, config values
│   ├── RESEARCH.md              ← first-principles findings (ESP32 era + STM32 archived)
│   ├── HANDOFF.md               ← session handoffs
│   ├── PROJECT_CONTEXT.md       ← one-screen current state
│   └── reference/
│       ├── ARCHITECTURE.md      ← this file
│       ├── INTERFACE_CONTRACTS.md  ← node↔hub seam + module contracts
│       ├── HANDOFF_ESP32_PIVOT.md  ← pivot decision record
│       ├── HARDWARE.md          ← load cell wiring, board pinouts
│       └── specs/               ← V1 subsystem specs (read per chunk-group)
│           ├── ARCHITECTURE_SPECIFICATION.md
│           ├── TRANSPORT_SPECIFICATION.md
│           ├── DATA_STORAGE_SPECIFICATION.md
│           ├── ANALYTICS_SPECIFICATION.md
│           ├── PREDICTION_SPECIFICATION.md
│           ├── LPG_DOMAIN_SPECIFICATION.md
│           ├── MEASUREMENT_AND_CALIBRATION.md
│           ├── EXPERIMENT_PROGRAM.md
│           └── _source/
│               └── MDD_v2_full.md
├── reference-code/
│   └── stm32-hx711-modular/     ← STM32 reference (port logic not code; see PORTING_NOTE.md)
└── docs/datasheets/             ← hx711_english.pdf, esp32-c3_datasheet_en.pdf, UNO Q docs
```

---

## SUPERSEDED ARCHITECTURE — STM32/Bridge Era

> Everything below this line is VOID and kept for history only.
> See docs/reference/HANDOFF_ESP32_PIVOT.md for the full pivot rationale.

```
[SUPERSEDED — STM32 era, all of this is VOID]

Load cell → HX711 → UNO Q STM32U585 MCU (DT=D7, SCK=D6, bit-bang, Bridge.notify)
                     │ Bridge RPC (LPUART1 9600 baud MSGPACK)
                     ▼
                   QRB2210 Linux / App Lab Docker / Python (Bridge.provide, App.run)

In the old design:
  - STM32 MCU on UNO Q owned HX711 bit-bang (DT=D7, SCK=D6 — timer-conflict rule, VOID on ESP32)
  - Weight pushed to Python via Bridge.notify("weight_event", payload)
  - Python received via Bridge.provide("weight_event", handler)
  - cal_factor was 106.7 raw/g (STM32-specific, VOID on ESP32-C3)
  - wait_ready timeout was 400ms (tuned for Bridge load, VOID on ESP32)
  - float-only was mandatory (STM32U585 double-broken bug, re-verify on ESP32)

None of these apply to node/ code. They are App Lab patterns only.
```
