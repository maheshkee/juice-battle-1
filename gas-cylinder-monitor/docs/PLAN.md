# PLAN.md — Gas Cylinder Monitor (V1)
# Last updated: 2026-06-04 (ESP32 pivot — complete rewrite)
# Architecture: ESP32-C3 sensor node + UNO Q hub
# Rule: update this file at the end of every session.

---

## Active Hardware

```
UNO Q AQ3 : 192.168.1.161 (hub — Python / App Lab)
ESP32-C3   : in hand (node — Arduino IDE / PlatformIO)
```

---

## Current Position

```
Pre-Group-1.
node/ and hub/ are empty (scaffold only).
Next: Group 1, Chunk 1 — E-000 ESP32-C3 + HX711 bring-up.
Design in Claude.ai chat first. Then execute via CLI.
```

---

## Guiding Rules

- **First principles:** WHY before HOW; nothing floats in isolation; no "it just works".
- **Small → verify → compound.** One chunk at a time, gated by hardware verification.
- **Chat = design/plan/brainstorm. CLI = implementation only.**
- **No hardcoding:** cal_factor, thresholds, steel/capacity always derived or from config.
- **float is safe default on ESP32-C3** — re-verify double before using it.
- **Every chunk ends with a stated acceptance condition.**

---

## Chunk-Group Structure

V1 is delivered as 7 sequential chunk-groups. Each group is gated: the next group starts
only when the current group's gate condition is met and verified on hardware.

---

## Group 1 — WEIGHT (node/)

**Goal:** ESP32-C3 produces trustworthy grams from HX711.
**Spec:** docs/reference/specs/MEASUREMENT_AND_CALIBRATION.md (+ MEASUREMENT_AND_CALIBRATION_SPECIFICATION.md)

### Chunk 1-A: E-000 Bring-up (3.3V gate + first raw read)

Pre-condition: **3.3V safety assessment** — verify HX711 DOUT/SCK logic levels vs
ESP32-C3 GPIO before powering anything. Level-shift if needed.

1. Select GPIO pin pair (SCK, DOUT). Any two GPIO work on ESP32-C3.
2. Write minimal bit-bang: 24-bit read + 25th gain pulse + sign extension.
3. Apply three corrupt filters: LONG_MIN, -1, 0x7FFFFF.
4. Print raw counts over serial.

Gate: stable, non-corrupt raw stream on serial. No -1, no 0x7FFFFF, no LONG_MIN.

### Chunk 1-B: cal_factor derivation

1. Tare (scale-zero) — self-computing, never hardcoded.
2. Multi-point cal_factor with known weights (six 10g blocks available; 82g, 112g, 227g adapter).
3. Store to config.json. Load on subsequent boots.

Gate: cal_factor derived and verified at multiple weight points. Residuals acceptable.

### Chunk 1-C: Noise characterisation

1. N=200 lab characterisation.
2. Sigma, peak-to-peak, 4-sigma threshold derived.
3. Harden 4 analog connections (solder/screw terminal, short leads).

Gate: sigma stable across runs. Clean noise floor documented in docs/reference/SENSOR_CHARACTERISATION.md.

### Chunk 1-D: Grams output with quality

1. N-sample averaging (N=50 production, N=200 lab).
2. Module result-struct: {grams, quality, sigma}.
3. Noise characterisation runs every boot.

Gate: consistent grams output with quality tagging. float verified (or double confirmed safe).

---

## Group 2 — TRANSPORT (node/ → hub/)

**Goal:** One weight reading arrives at the hub from the ESP32-C3 over WiFi.
**Spec:** docs/reference/specs/TRANSPORT_SPECIFICATION.md

### Chunk 2-A: Transport bring-up

1. ESP32-C3 connects to WiFi.
2. Sends one `{grams, quality, sigma}` payload to UNO Q hub.
3. Hub receives + prints (bare Python receiver, no storage yet).

Gate: one live weight reading visible in hub Python logs.

### Chunk 2-B: Reliable heartbeat

1. Node sends every 15 min (heartbeat) + on-demand pull.
2. Hub stamps timestamp on receipt.
3. Reconnect/buffering on WiFi link loss.

Gate: hub receives reliable 15-min heartbeats. One missed heartbeat does not crash either side.

---

## Group 3 — STORAGE (hub/)

**Goal:** Hub stores heartbeat readings to SQLite.
**Spec:** docs/reference/specs/DATA_STORAGE_SPECIFICATION.md

### Chunk 3-A: SQLite schema + heartbeat spine

```sql
readings (id, ts, gross_kg, gas_kg, gas_pct)    -- heartbeat every 15 min
refill_events (id, ts, ...)                      -- per cylinder change
```

Gate: 15-min heartbeat rows appear in SQLite. No missing rows over 1 hour.

---

## Group 4 — DOMAIN (hub/)

**Goal:** Hub converts grams to gas remaining + state machine transitions.
**Spec:** docs/reference/specs/LPG_DOMAIN_SPECIFICATION.md + docs/SCOPE.md

### Chunk 4-A: Steel derivation + gas%

1. Hub detects install G-jump (> 6.0 kg).
2. Derives steel: `steel = gross_at_install − 14.2 kg`.
3. Computes: `gas% = (gross − steel) / 14200 × 100`.
4. Stores per-cylinder context to refill_events.

Gate: end-to-end "place cylinder → see honest grams + honest %" in hub output.

### Chunk 4-B: State machine

States: UNINSTALLED → TRACKING → LOW GAS
Transitions per docs/SCOPE.md.

Gate: correct state transitions verified with simulated G-jump events.

---

## Group 5 — ANALYTICS (hub/)

**Goal:** Hub computes consumption, burn rate, and patterns.
**Spec:** docs/reference/specs/ANALYTICS_SPECIFICATION.md

1. Daily consumption from heartbeat spine.
2. Burn rate (rolling 7-day window after 24h minimum data).
3. Basic hourly pattern.

Gate: burn_rate computed correctly from actual data. No government average ever used.

---

## Group 6 — PREDICTION (hub/)

**Goal:** Hub predicts days remaining with confidence.
**Spec:** docs/reference/specs/PREDICTION_SPECIFICATION.md

1. `days_remaining = gas_remaining / burn_rate`.
2. Confidence interval from burn-rate variance.
3. Shows `"—"` until MIN_HOURS_BURNRATE = 24h of data exists.

Gate: days_remaining computed from actual data only. Correct `"—"` behaviour before 24h.

---

## Group 7 — PRESENTATION (hub/)

**Goal:** WebUI dashboard shows live gas gauge, trend, state, prediction.

1. Flask/Socket.IO server in hub/.
2. Live gas gauge (% + kg).
3. Days remaining with confidence.
4. Cylinder state (UNINSTALLED / TRACKING / LOW GAS).
5. Replace cylinder button → triggers new steel derivation.

Gate: WebUI accessible at hub IP. All outputs update in real time from SQLite + live stream.

---

## Experiment Queue

### New, gating (Group 1)

| # | Name | Purpose | Gate |
|---|------|---------|------|
| E-000 | ESP32-C3 + HX711 bring-up | 3.3V check, pins, first raw read | Non-corrupt raw stream |
| E-001 | cal_factor re-derivation | Multi-point, verify float/double | cal_factor confirmed |
| E-002 | Noise re-characterisation | N=200 lab, sigma, threshold | Sigma stable across runs |

### Ported from STM32 (run on ESP32-C3, NOT on STM32)

| # | Name | Purpose |
|---|------|---------|
| E-005 | Calibration linearity | Multi-point cal across weight range |
| E-006B | Measured water removal | Validate Δ-consumption accuracy (needs measuring cup) |
| E-007B | Threshold stress test | Count false positives over 30 min |

### Post-MVP characterisation (after Group 2 end-to-end loop + wiring hardened)

| # | Name | Purpose |
|---|------|---------|
| E-T1 | Thermal drift (controlled) | cal_factor + scale-zero shift vs temperature |
| E-T2 | Long-run passive stability | Baseline wander + mechanical creep over days |
| E-T3 | Diurnal in-situ drift | Kitchen heat/cool cycle — is active temperature comp needed? |

Test weights on hand: six identical 10g blocks, 82g adapter, 112g container, 227g speaker.

---

## What We Know (Proven) vs What We Don't

### Proven on hardware (STM32 AQ3 — VOID on ESP32, re-verify)

```
HX711 bit-bang pattern works    : 24-bit + 25th gain + sign extension [port to ESP32]
Three corrupt filters needed    : LONG_MIN, -1, 0x7FFFFF [apply on ESP32]
Self-characterisation essential : noise STD varied 1.33–3.93g SAME hardware SAME day
Modular result-struct works     : tested on STM32, port to ESP32
double broken on STM32U585      : sum=0 bug — re-verify float/double on ESP32-C3
```

### VOID on ESP32 (must re-derive)

```
DT=D7/SCK=D6              : STM32 timer-conflict rule, VOID on ESP32-C3
cal_factor = 106.7 raw/g  : STM32U585-specific, VOID — re-derive on ESP32-C3
wait_ready = 400ms        : tuned for Bridge load, VOID — re-tune on ESP32
Noise STD range 1.33–3.93g: STM32 characterisation — redo on ESP32 (wiring noise likely moves)
```

### Pending (requires experiment on ESP32)

```
3.3V logic-level compatibility with HX711 at 5V VCC   → E-000 chunk 1 (safety gate)
Correct GPIO pin pair on ESP32-C3                      → E-000
cal_factor on ESP32-C3                                 → E-001
float sufficiency on ESP32-C3                          → E-001
Noise floor on ESP32-C3                                → E-002
Thermal drift magnitude                                → Post-MVP E-T1–T3
```

---

## Product Roadmap

| Version | Scope | Chunk-group |
|---------|-------|-------------|
| V1-MVP | Weight reading + transport + storage + domain (steel/gas%) + WebUI | Groups 1–4 + 7 skeleton |
| V1 | Full V1: analytics + prediction + complete WebUI | Groups 5–7 |
| v1.x | Battery node, short-delivery verification | Post V1 |
| v2.0 | 4-cell summing, ML on QRB2210 (TFLite) | Future |
| v3.0 | LLM agent, gas ordering API, multi-cylinder fleet | Future |

---

## Change Log

| Date | Change |
|------|--------|
| 2026-05-05 | Created — STM32 era, experiments 003/004 complete |
| 2026-05-06 | Major update — calibration architecture locked, data intelligence roadmap |
| 2026-06-04 | COMPLETE REWRITE — ESP32 pivot; phased chunk-groups; STM32 plan superseded |

---

## Deferred Work — Transport Observability (Option C)

### Item 1 — Node BLE journal entries (NEXT SESSION)
Add to ble.cpp: emit journal events for ADVERTISING, CLIENT_CONNECTED,
CLIENT_DISCONNECTED. Uses existing journal module. ~30 min work.

### Item 2 — Hub persistent log file (when hub domain logic built)
Rotating log file on AQ3 disk. Captures all transport + domain events
with timestamps. Survives restarts. Built alongside gas% and anchor logic.

### Item 3 — WebUI transport status panel (when WebUI built)
Live display: adapter status, scan/connected state, device name+MAC,
last received timestamp. One widget row added to existing WebUI.

### Item 4 — deploy.sh adapter health check (add now)
Before container starts, verify hci0 is up via bluetoothctl show.
Fail loudly if adapter is in bad state. Prevents silent scan failures.
