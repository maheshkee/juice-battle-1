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

| Component | Part | Role |
|---|---|---|
| Sensor node | ESP32-C3 SuperMini | Raw sensor work: HX711 bit-bang, BLE GATT notify |
| Load cells | 3× YZC-161A 20kg parallel | Measures gross weight |
| ADC | GISLAB HX711, AVIAIC chip | 24-bit, 10SPS, 3V3 VCC only |
| Hub board | Arduino UNO Q AQ3 | QRB2210 Linux: Python, BlueZ, SQLite, WebUI |
| Transport | BLE only (NimBLE-Arduino) | Node notifies hub every tick |
| Storage | SQLite on AQ3 | Readings, anchor events, analytics |

**JCTL on UNO Q = 1.8V ONLY. 3.3V damages hardware.**
**ESP32-C3 wiring locked: GPIO4=DOUT, GPIO3=SCK, 3V3=VDD. 3.3V gate cleared 2026-06-04.**

---

## Version History

| Version | Scope | Status |
|---|---|---|
| V1 fresh cylinder | Node→hub BLE, steel from anchor, gas% | In progress |
| V2 partial + known brand | Brand lookup tare, heals at anchor | Not started |
| V3 partial + unknown brand | Interval estimation, conservative bias | Not started |
| v2.0 | ML/TFLite/Kalman | Not started |
| v3.0 | LLM agent, ordering API | Not started |

---

## Current State — 2026-06-18 (supersedes 2026-06-17)

### Node — COMPLETE (boot=35 verified clean)
- 1A Modular sketch port: DONE
- 1B Health module: DONE (health.h/health.cpp, 4 checks, bitmask quality)
- 1C Timing instrumentation: DONE (phase durations in seconds on boot)
- 1D Structured event journal: DONE (journal.h/journal.cpp, 7 event types)
- 3E-006B min detectable removal: DONE — min=20g (1 trial), hard floor=10g
- 3E-007B false positive rate: DONE — 0 false triggers in 38.4 min. PASS ✅
- BLE command char: DONE (UUID: c8a2f1e3-..., write-without-response)
  Commands: TARE | SKIP_TARE | SET_CAL:\<value\> | RETARE | DUMP_LOG | CLEAR_LOG (stubs)
- STATE_TARE_WAIT: DONE — hub sends TARE or SKIP_TARE within 60s timeout
- Tare SPIFFS persistence: DONE — tare_save_to_spiffs() / tare_load_from_spiffs()
- STATE_RETARE: DONE (stub) — triggered by RETARE command during RUNNING
- Boot sequence: SETTLE → TARE_WAIT → TARE → NOISE → CAL → RUNNING
- 7 bugs fixed this session (NOISE gates, stuck guard, cal-before-NOISE, double-division
  sigma, BUF_SIZE=40, loose wire, NimBLE onWrite signature)

### Weight module API (current)
- weight_update(): (long raw, float tare_raw, float cal_factor, float sigma_g) — 4 args
- Delay-line detector: 20-tick delay line + s_event_pending lockout flag
- journal_run(): (float grams, float sigma, HealthResult&, WeightEvent, float delta) — 5 args

### Verified hardware values (updated 2026-06-18, boot=35)
- cal_factor: ~36 raw/g (3-cell parallel, derived every boot; boot=35: 36.25–36.27)
- sigma: 3.16–5.44g boot-to-boot (boot=35: 3.16g clean; boot=33 bug: 0.09g — fixed)
- threshold: 4 × sigma (~12–21g depending on boot)
- BUF_SIZE: 40 ticks (4-second delay-line) — LOCKED
- NOISE_SIGMA_PASS_G: 8.0g | NOISE_SIGMA_WARN_G: 15.0g — LOCKED
- zero accuracy: ±3g, weight accuracy: ±7g (200g–1700g)
- 1000g accuracy boot=35: 986.5g first HB
- Min detectable removal: 20g (1 trial), hard floor 10g
- False positive rate: 0/hr on static load (BUF_SIZE=40 — verified 2026-06-18)
- Slow drift: 190g peak-to-trough over 38 min on static load — characterise in 3E-009
- Boot time: ~103.9s (full TARE_WAIT=60s) | ~63s (TARE_WAIT immediate)

### Known TODOs (deferred)
- TODO 1B-stuck: tare_variance_raw always 0.0f — stuck check always fails
- TODO 1B-persistence: prev values not read from config.json across boots

### Hub
- BLE subscriber: _check_known_devices() fix deployed, WebUI at AQ3:7000
- No gas logic yet — skeleton only
- BLE command char on node: BUILT (2026-06-18) — hub can now send TARE/SKIP_TARE/SET_CAL/RETARE
- HUB-001 node-side stub ready; hub-side detection logic still required

### Next action
N-TARE-CHECK — post-tare self-check (detect weight on platform at boot, use SPIFFS tare
as fallback). Design in chat. Implement via Claude Code CLI. Then: N1 journal→SPIFFS.

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
| 8 | Minimum detectable cooking event (real measurement) | RESOLVED 2026-06-17 — min=20g (1 trial), hard floor=10g. Confirm with 3E-007B (3 trials). |
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
Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
BUF_SIZE: 40 ticks (4-second delay-line) — LOCKED 2026-06-18
NOISE_SIGMA_PASS_G: 8.0g | NOISE_SIGMA_WARN_G: 15.0g — LOCKED 2026-06-18
NimBLE onWrite: (NimBLECharacteristic* c, NimBLEConnInfo& connInfo) — two params required
BLE command char UUID: c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b (write-NR) — LOCKED 2026-06-18
BLE log char UUID:     d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c (notify) — LOCKED 2026-06-18

---

## Current State — 2026-06-16 (design session — no hardware touched)

Updated: 2026-06-16 | This section supersedes all prior state sections.

### Architecture confirmed
Transport: BLE only — locked, validated end-to-end
Platform: 3-cell (3× YZC-161A 20kg, shared fibre plate)
cal_factor: 37.06 raw/g (2026-06-16, derived every boot — not hardcoded)
sigma: 2.64g (2026-06-16, recomputed in grams post-CAL)
Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
Last completed: 1B — load cell health detection module (health.h + health.cpp) COMPLETE 2026-06-16
Next action: 1C — timing instrumentation (millis() per boot phase)

### Backlog audit complete — full ordered backlog

**1A-1D: Modular sketch series (immediate next)**
| Chunk | Task | Status |
|-------|------|--------|
| 1A | Modular sketch port to 3-cell ESP32-C3 (hx711.cpp, tare.cpp, cal.cpp, weight.cpp) | COMPLETE 2026-06-16 |
| 1B | Load cell health detection — health.h + health.cpp. Pure function. 4 checks: erratic, stuck, cal_drift, runtime_jump. Bitmask checks_passed. DEGRADED=1 fail, FAILED=2+ fails. Known limitation: stuck check always fires (tare_variance=0.0f, TODO 1B-stuck). | COMPLETE 2026-06-16 |
| 1C | Timing instrumentation — millis() per boot phase | Queued |
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
| 5 | Can health module detect load cell failures at runtime? | RESOLVED 2026-06-16 — runtime jump check verified on hardware. Placed 1kg on empty platform, caught 1009g jump, flagged FAILED correctly. |
| 6 | tare.h variance exposure needed for stuck check to function | OPEN — TODO 1B-stuck: TareResult has no variance field. Stuck check (bit 1) always passes until tare.h updated. |
| 7 | config.json persistence for prev_cal_factor and prev_sigma_g | OPEN — TODO 1B-persistence: cal drift and erratic checks skip every boot (first-boot sentinel -1.0f). Needs read-at-startup + write-after-CAL_SUCCESS in config.json. |

---

## Backlog — Deferred Features

### HUB-001 — Auto-Retare on Cylinder Removal (DESIGNED, NOT BUILT)

Trigger: hub detects WEIGHT_EVENT type=REMOVED with grams≈0 (platform empty).
Action: hub monitors subsequent heartbeats. When two consecutive heartbeats satisfy
|grams[n] − grams[n−1]| < 2×sigma → platform stable → hub sends RETARE command
to node over BLE write characteristic → node executes STATE_TARE sequence →
confirms via next heartbeat reading ≈ 0g.

Node requirement: writable BLE GATT characteristic (command channel, hub→node).
Separate UUID from existing weight notify characteristic.
Command format: TBD — design in chat (options: single byte opcode, short JSON).
Priority: **high** — required for correct grams after any cylinder swap.
Gate: node BLE command characteristic must be designed and implemented first.

### HUB-002 — Disturbance Detection from Heartbeat Trend (DESIGNED, NOT BUILT)

Trigger: hub detects a sudden step change in consecutive heartbeat grams values
that exceeds 5× expected_consumption_in_interval AND no WEIGHT_EVENT occurred
in that window → platform was disturbed while loaded (silent tare shift).
Action: flag DISTURBANCE state → mark subsequent readings UNRELIABLE until
next confirmed retare → surface alert to user.

Prerequisite: requires burn rate estimate from Group 5 analytics.
Cannot compute expected_consumption without a known burn rate.
Priority: **medium** — improves reliability, not blocking V1.

### 1E — BLE Journal Transport (DESIGNED, NOT BUILT)

Design: dedicated BLE GATT characteristic on ESP32-C3 for journal log lines.
Hub Python subscriber reads characteristic notifications and writes to a rotating
log file on AQ3 (e.g. logs/node_journal_YYYY-MM-DD.log, max 7 days retention).
Enables post-mortem diagnosis of node-side events without USB Serial attached.
Required for production deployment.

Gate: implement after 3E experiment program complete and hub BLE subscriber is stable.
Priority: medium — not blocking V1 experiments, blocking production.
Note: requires a second BLE characteristic with its own UUID, separate from the
existing weight notify characteristic. Do not confuse the two.
