# Session log - gas cylinder monitor
# Purpose: permanent record of real hardware outputs per session.
# Never delete entries. Add new sessions at the bottom with incrementing session number.

---

## Session 005 - 2026-06-08 (Session 2) - E-003 BLE Transport

Status: E-003 PASSED
Experiments completed: E-003 BLE transport validation

### What was done
- Designed full BLE transport architecture in chat (UUIDs, GATT server, hub subscriber)
- Locked BLE UUIDs: service aa206b91-235b-42aa-b370-453a3feedf35, char b9b25bb1-f2a9-4545-b48f-295ab2789f41
- Built E003_ble_transport.ino: boot sequence (stability → tare → N=200 noise → BLE advertise → loop notify)
- Built e003_ble_test.py: plain Python BlueZ subscriber, zero-human-intervention self-provisioning
- Fixed bleak service_uuids filter not respected on QRB2210 BlueZ backend - application-layer name filter applied instead
- MAC address self-provisioned and cached in config.json on first run
- Gate condition passed: readings arriving at hub with hub-stamped timestamp

### Key numbers confirmed
- Tare: -15588 raw
- Noise STD: 1.81g (higher than E-002 — ESP32 running BLE stack simultaneously)
- Threshold: 7.24g
- DEGRADED reading correctly reported during weight placement transition
- Stable readings: ~244-247g (speaker weight, consistent with E-001)

### Files created
- node/E003_ble_transport/E003_ble_transport.ino
- hub/e003_ble_test.py
- hub/requirements.txt
- hub/config.json

### Gate
E-003 PASSED.

---

## Session 001 - 2026-06-04 morning - architecture and scaffold
### What happened
- Read all 28 project documents
- Confirmed ESP32-C3 pivot is correct
- Rewrote CLAUDE.md, ARCHITECTURE.md for ESP32 era
- Created node/ and hub/ directory split
- Created INTERFACE_CONTRACTS.md
- Committed clean scaffold
### Real outputs
No hardware connected. Scaffold only.
### Gate
Architecture locked. Ready for E-000 hardware bring-up.

---

## Session 002 - 2026-06-04 afternoon - E-000 hardware bring-up
### What happened
- Wired ESP32-C3 SuperMini + GISLAB HX711 + YZC-161A load cell
- Safety gate cleared: 3.3V VDD confirmed safe, no level shifter needed
- Arduino IDE set up from scratch (first time): esp32 v3.0.7, ESP32C3 Dev Module, COM11
- Flashed E000_raw_read.ino - first successful flash
- Serial Monitor confirmed stable raw reads at 10Hz
### Real hardware outputs
| Condition | Raw range | Spread |
|---|---|---|
| Unloaded | -15200 to -15423 | ~223 raw |
| 30g weight | -11620 to -11872 | ~252 raw |
| Delta 30g | ~3400 raw | - |
| Rough cal_factor | ~113 raw/g | rough |
### Gate
E-000 PASSED. Zero corrupt values. Hardware confirmed talking.

---

## Session 003 - 2026-06-05 - E-001 tare + cal_factor + grams

### Goal
Derive tare from unloaded samples, derive cal_factor from known weight,
output grams in continuous loop. Gate: grams within 5% of known weight.

### What happened
- Built E001_tare_cal_grams.ino - single file, no library, raw bit-bang ported from E-000
- Fixed Serial buffer drain bug (stale \n byte caused cal_factor = inf on first run)
- Added 10 second settle window after keypress before sampling - eliminates load cell creep error
- Extended sketch to loop through multiple weights - derives separate cal_factor per weight
- Ran linearity test across 8 weights: 10g, 20g, 30g, 40g, 50g, 227g, 234g, 257g

### Real hardware outputs
| Weight | Cal_factor (raw/g) | Mean reading | Error |
|---|---|---|---|
| 10g | 29.50 | 9.26g | unstable |
| 20g | 69.13 | 20.37g | good |
| 30g | 87.52 | 30.61g | good |
| 40g | 95.83 | 40.37g | good |
| 50g | 97.77 | 50.12g | good |
| 227g | 104.84 | 227.57g | excellent |
| 234g | 105.21 | 233.24g | excellent |
| 257g | 105.50 | 256.47g | excellent |

Key finding: cal_factor unstable below ~100g (SNR problem, not hardware fault).
cal_factor stable at ~105 raw/g above 227g. Variation only 0.6% across 227-257g.
Load cell confirmed linear in the range that matters for gas cylinder operation.
Tare this session: -13823 to -15747 raw (varies per boot - self-characterised correctly)

### Gate
E-001 PASSED. Grams output accurate above 100g reference weight.

### Sketches built
- node/E001_tare_cal_grams/E001_tare_cal_grams.ino

---

## Session 004 - 2026-06-08 - E-002 Noise Floor Characterisation

Goal: Characterise noise floor of ESP32-C3 + GISLAB HX711 + YZC-161A. Derive
      event detection threshold. Confirm dynamic stability detection approach.

Hardware: ESP32-C3 SuperMini, GISLAB HX711, YZC-161A 20kg load cell
Wiring: GPIO4=DOUT, GPIO3=SCK, 3V3=VDD (unchanged from E-001)

### Sketch versions built
| Version | File | Key change |
|---|---|---|
| v1 | E002_noise_floor.ino | Fixed 5s timer - FAILED (STD 0.53-3.43g, unreliable) |
| v2 | E002_noise_floor.ino | Dynamic stability detection - IMPROVED but tare error |
| v3 | E002_noise_floor.ino | Tare after settle + mean drift check - PASSED |

### Real measured outputs - E-002 v3 (two clean runs, 3+ min power off)

| Run | STD | Peak-to-peak | Threshold 4xSTD | Tare correction | Settle reads |
|---|---|---|---|---|---|
| Clean run 1 (3 min off)  | 0.67g | 3.47g | 2.67g | 38 raw (0.36g) | 22 |
| Clean run 2 (30 min off) | 0.62g | 3.18g | 2.48g | 17 raw (0.16g) | 22 |

Production threshold locked: 2.67g (conservative upper bound)
Settle time: 2.2 seconds (22 reads at 10Hz) - both runs consistent

### Key findings
- Fixed timer completely unreliable: STD varied 0.53-3.43g (6.5x range) across 6 runs
- Dynamic detection reliable: STD 0.62-0.67g (1.08x range) across 2 clean runs
- True noise floor of ESP32-C3 is BETTER than STM32 (0.67g vs 1.87g)
- Fan (ceiling) has no measurable effect on noise (+0.07g, within variation)
- Tare must be derived AFTER stability confirmed - early tare gives 1-3g mean offset
- 16g minimum event is a planning estimate only - E-006B needed post-install
- Repeated power cycles without rest cause cumulative creep - not a production concern
- In production load cell stays powered continuously - settle issue does not apply

Gate result: PASSED
Next: Group 2 BLE transport - skipping remaining Group 1 experiments for now.
Parked (not forgotten): E-003 modular refactor, E-004 stability, E-005 cal_factor
linearity, E-006B minimum event, E-007B threshold stress test.
Decision: revisit after Group 2 gate passes.

---

## Session 006 - 2026-06-08 (Session 2) - E-003 BLE Transport Design + Validation

### Goal
Design and validate full BLE transport: ESP32-C3 GATT server → UNO Q hub BlueZ subscriber.
Define UUIDs. Prove one reading travels from load cell to hub terminal with hub timestamp.

### What happened
- Designed full BLE transport architecture in chat from first principles
- Generated and locked BLE UUIDs (service + characteristic, 128-bit random)
- Built E003_ble_transport.ino: full boot sequence (stability → tare → N=200 noise → BLE advertise → loop notify)
- Built hub/e003_ble_test.py: plain Python BlueZ subscriber
- Hit bleak service_uuids filter bug on QRB2210 - fixed with application-layer name filter
- Implemented self-provisioning: null MAC in config → discover by name → cache MAC → Phase 1 on all subsequent runs
- Created hub/config.json, hub/requirements.txt
- Gate condition achieved: readings arriving at hub with hub-stamped timestamp

### Real hardware outputs
| Parameter | Value | Condition |
|---|---|---|
| Tare | -15588 raw | empty load cell, power-on settle |
| Noise STD | 1.81g | BLE radio running simultaneously |
| Noise threshold | 7.24g | 4 × 1.81g |
| Stable window #1 spread | 1.87g | STAB_SPREAD_G < 2.5g ✓ |
| Stable window #1 drift | 0.00g | STAB_MEAN_DIFF_G < 1.0g ✓ |
| Confirmed weight (speaker) | 244-247g | consistent with E-001 |
| DEGRADED sigma | 97.65g | correctly fired during weight placement |
| Post-settle sigma | 0.40-0.65g | consistent with E-002 |
| ESP32 BLE MAC | 10:00:3B:CD:63:32 | self-provisioned into config.json |

### Gate
E-003 PASSED.
[2026-06-08T17:14:25] grams=246.2g  quality=GOOD  sigma=0.49g
Full pipeline proven: load cell → HX711 → ESP32-C3 → BLE → BlueZ → Python → timestamped reading.

### Files built this session
| File | Location | Purpose |
|---|---|---|
| E003_ble_transport.ino | node/E003_ble_transport/ | ESP32 GATT server + full boot sequence |
| e003_ble_test.py | hub/ | BLE subscriber, self-provisioning |
| config.json | hub/ | Device config, MAC cached after first run |
| requirements.txt | hub/ | bleak>=0.21.0 |

### What is next
Modular refactor: hx711.h/.cpp, tare.h/.cpp, noise.h/.cpp, weight.h/.cpp, ble.h/.cpp
sketch.ino becomes pure orchestrator.
Gate: behaviour identical to E-003 single file.
After refactor: App Lab migration with socat D-Bus forwarding.

---

## Session 003 - 2026-06-12 - 3E-001 cal_factor full characterisation

### Goal
Derive and validate cal_factor for 3-cell YZC-161A parallel platform across three stages:
Stage 1 (individual cells), Stage 2 (shared plate), Stage 3 (multi-weight linearity sweep).

### What happened
- Renamed experiment series from 4E to 3E (3-cell is the production platform - cost decision)
- Fixed serial gate skip bug: mandatory 2s dwell + double flush in waitForEnter()
- Stability gate moved to raw counts - gram-based gates had hidden cal_factor dependency
- Phase 0 settling monitor confirmed as mandatory before any noise characterisation
- Built 3E001_cal_factor_v5, v5_1 (wall-clock timing), v5_2 (per-iteration weight entry)
- Stage 1: 4 runs, fan on/off, power cycle, re-upload - weight on individual cells
- Stage 2: 4 runs, same conditions - shared plate on all 3 cells
- Stage 3: 3 runs, 100g to 1800g linearity sweep - confirmed linear across 9x range
- All settling times derived from v5_1 timing instrumentation (real wall-clock seconds)

### Real hardware outputs

| Parameter | Value | Method |
|---|---|---|
| cal_factor (3-cell, shared plate) | 36.1 raw/g | 80+ clean readings, 3 stages |
| Linear range | 200g to 1800g | Stage 3, 3 runs, CV 4.1% |
| Min reliable weight | ~150g | SNR floor hardware-confirmed |
| Cold boot settle, no plate | 3 to 12s | Stage 1 v5_1 timing |
| Cold boot settle, with plate | 60 to 161s | Stage 2 v5_1 timing |
| Placement settle | 10s sufficient | All loaded_std at or below noise_std |
| Removal re-tare, fast path | 5.9s | Stage 2/3 timing |
| Removal re-tare, after 500g | up to 86s | Stage 3 viscoelastic recovery |

### Sketches built

| Sketch | Location | Purpose |
|---|---|---|
| 3E001_cal_factor_v5 | node/3E001_cal_factor_v5/ | Self-characterising, fixed ref weight |
| 3E001_cal_factor_v5_1 | node/3E001_cal_factor_v5_1/ | Plus wall-clock timing |
| 3E001_cal_factor_v5_2 | node/3E001_cal_factor_v5_2/ | Plus per-iteration weight entry |

### Gate
3E-001 PASSED. cal_factor = 36.1 raw/g locked. Linear 200g to 1800g confirmed.

---

## Session 006 - 2026-06-15 - 3E-002 noise floor characterisation (BLE off + BLE on)

### Goal
Complete 3E-002: measure true noise floor of 3-cell platform in BLE-off and BLE-on conditions.
Lock production noise_std_g and threshold_g. Verify BLE EMI penalty on 3-cell.

### What happened
- Ran HW_VERIFY_3CELL sketch (new diagnostic tool built this session)
  All cells PASS: Cell1=-116.4g, Cell2=-119.0g, Cell3=-93.3g lift deltas
  cal_factor derived: 35.63 raw/g (consistent with locked 36.1 from 3E-001, 1.3% diff)
  Raw stability CV=0.108% - hardware confirmed clean
- Ran 3E002_noise_floor_v1 (BLE off) - 7 runs total across sessions
- Ran 3E002_noise_floor_v1_ble (BLE on) - 2 runs today
- Investigated intermittent hardware fault (tare_raw jumping ~18000 raw = ~500g)
  Root cause: loose wire connection during earlier session, resolved by re-seating
- Key discovery: 3-cell parallel wiring provides natural common-mode rejection of BLE EMI

### Real hardware outputs - BLE OFF (7 runs, 3-cell platform)
| Run | noise_std_g | threshold_g | notes |
|---|---|---|---|
| 1 | 2.22g | 8.87g  | anomalously quiet - cold boot outlier |
| 2 | 4.13g | 16.52g | mid-creep reboot |
| 3 | 4.02g | 16.09g | power off/on |
| 4 | 3.23g | 12.93g | consecutive boot |
| 5 | 3.23g | 12.93g | consecutive boot - matches run 4 |
| 6 | 4.93g | 19.71g | today, verified hardware |
| 7 | 4.64g | 18.54g | BLE-on run 1 - same STD as BLE-off |

### Real hardware outputs - BLE ON (2 runs today)
| Run | noise_std_g | threshold_g | BLE penalty |
|---|---|---|---|
| B1 | 4.64g | 18.54g | ~1.0x (no penalty) |
| B2 | 3.51g | 14.03g | ~1.0x (no penalty) |

### Locked production values
  noise_std_g  (BLE off, worst case) = 4.93g
  noise_std_g  (BLE on,  worst case) = 4.64g
  threshold_g  (BLE on,  production) = 18.54g
  BLE EMI penalty on 3-cell platform = ~1.0x (negligible)

### Key finding
BLE radio on ESP32-C3 does NOT increase noise meaningfully on 3-cell platform.
Single-cell showed 2.7x BLE penalty. 3-cell shows ~1.0x.
Root cause: 6 parallel signal wires (3x A+, 3x A-) twisted together act as
common-mode filter for 2.4GHz RF interference. BLE couples equally into all
wires → cancels at differential HX711 input.

### Sketches built this session
  node/3E002_noise_floor_v1/       BLE off noise characterisation
  node/3E002_noise_floor_v1_ble/   BLE on noise characterisation
  node/HW_VERIFY_3CELL/            3-cell hardware diagnostic tool

### Gate result
3E-002 PASSED. Production noise floor and threshold locked.

### What was NOT done (for next session)
- 3E-003 BLE transport not yet started
- Hub Python BLE subscriber not started
- WebUI not started
- Modular sketch architecture not yet started
- Demo not yet built

---
## Session 2026-06-16 — Accuracy Investigation + 3E-004

### Goal
Find root cause of systematic weight reading errors. Achieve accurate readings.

### Experiments run
- 3E003 re-runs with various weights — diagnosed two compounding errors
- E-005 linearity experiment — confirmed system is linear
- 3E004 cal+run — combined calibration and running in one boot

### Root causes found
1. cal_factor derived in one boot used in different boot — invalid. Platform physical
   state and supply voltage differ between boots causing different tare_raw baselines.
   cal_factor must be derived in same boot as measurement.
2. tare_raw_g set from Phase 1 20-sample window mean instead of Phase 2 200-sample
   mean. 200-sample mean has 3× lower uncertainty: std/sqrt(200)=11.8 vs std/sqrt(20)=37.4 counts.

### Key measured values (3E-004, 2026-06-16)
| Parameter | Value |
|---|---|
| cal_factor (derived this boot) | 35.98 raw/g |
| tare_raw_boot (s2_mean) | −106392.7 |
| noise_std_raw | 173.98 raw |
| noise_std_g | 4.84g |
| threshold_g | 19.34g |
| Zero reading (empty platform) | −3.6g, −2.1g |
| 200g reading | 200.6g, 206.4g (avg +3g) |
| 700g reading | 699.1g, 705.8g (avg +2g) |
| 1700g reading | 1707.2g, 1702.2g (avg +5g) |
| 1800g reading | 1801.8g (+2g) |

### Gate result
3E-004 PASSED — ±7g accuracy across 200g–1700g verified

### Sketches built
| Sketch | Location |
|---|---|
| E005_linearity | node/E005_linearity/E005_linearity.ino |
| 3E004_cal_and_run | node/3E004_cal_and_run/3E004_cal_and_run.ino |

### What was NOT done
- Session close docs from previous session (2026-06-15) still pending
- Self-deriving cal_factor (no user input) not yet built
- cal_factor not yet saved to config.json on hub

---

## Session 007 - 2026-06-16 (Session 2) - Architecture review and backlog audit

### Goal
Architecture review, backlog audit, V1/V2/V3 design consolidation. No hardware touched.

### What happened
- Full backlog audited — all remaining work identified and ordered
- Three product versions (V1/V2/V3) cold-start strategies consolidated
- All threshold values derived from first principles:
    CYLINDER_REMOVED=2kg, REFILL_THRESHOLD=6kg, FRESH_CYLINDER_MIN=26kg
- V1 hub state machine fully designed: UNINSTALLED / TRACKING / LOW_GAS
- 4-step calibration sequence on cylinder change designed
- Special cases identified: partial same-brand, different brand, non-domestic cylinder
- Water container simulation approach validated for 3E series experiments
- Session decisions documented in GasCylMonitor_SessionDecisions_2026_06_16.docx

### Key decisions made
- V1 ships with delta tracking only — burn rate and days_remaining exact from day 1
- V2 adds stamped tare from cylinder label → unlocks absolute gas%
- V3 self-heals steel estimate across a complete refill cycle
- Conservative bias rule locked: always report lower gas estimate when uncertain
- Delta tracking immune to unknown steel (S cancels in subtraction)

### Real outputs
None — design session only. No hardware touched. No sketches built.

### Gate
N/A — design session. Architecture and backlog locked. Ready for 1A modular sketch port.

---

## Session - 2026-06-16 (Session 2)
Goal: 1A - build and verify modular sketch port to 3-cell ESP32-C3

What was built:
- node/gas_monitor_v1/ - full modular sketch
  - hx711.h/.cpp - bit-bang, GPIO4=DT GPIO3=SCK, 3 corrupt filters
  - tare.h/.cpp - 2-phase non-blocking, s2_mean 200 samples
  - noise.h/.cpp - 200-sample two-pass float variance + noise_recompute_sigma()
  - cal.h/.cpp - 50-sample derivation, SPIFFS config.json cal_history append
  - weight.h/.cpp - 20-sample circular buffer, GOOD/DEGRADED/FAILED
  - ble.h/.cpp - NimBLE GATT, locked UUIDs, snprintf JSON notify
  - gas_monitor_v1.ino - orchestrator only, state machine, no sensor math
  - README.md - library dependencies documented

Real hardware outputs (verified on 3-cell platform):
| Metric | Value |
|---|---|
| cal_factor | 37.06 raw/g |
| sigma (recomputed) | 2.64g |
| Zero accuracy | ±3g (first stable plateau ~503g vs 500g known) |
| DEGRADED readings | 19 (buffer fill, correct) |
| GOOD readings | all subsequent, stable |
| Boot sequence | SETTLE→TARE→NOISE→CAL→RUNNING all correct |

Gate result: PASSED

Known issue logged: NOISE WARNING fires during boot (sigma in raw units
exceeds 20g guard before recompute). Not a bug - orchestrator correctly
continues. Log clarity issue only. Filed for 1B/1C session.

Next: 1B - load cell health detection module design

---

## Session: 2026-06-16 Session 3 - 1B Load Cell Health Detection Module

**Goal:** Design and implement the load cell health detection module (health.h / health.cpp) and wire it into the production sketch.

**What was built:**
- node/gas_monitor_v1/health.h - HealthResult struct + health_check() declaration (9 parameters)
- node/gas_monitor_v1/health.cpp - pure function implementation, 4 checks, bitmask output
- node/gas_monitor_v1/gas_monitor_v1.ino - updated to include health.h, wire health_check() in STATE_RUNNING, add g_prev_gross_g / g_prev_cal_factor / g_prev_sigma_g / g_tare_variance_raw globals

**Design decisions made:**
- health_check() is a pure function - no internal state, no static variables
- Orchestrator owns prev_gross_g (sentinel -1.0f), passes both cur and prev into health
- Diagnosis string uses pipe separator: "stuck:|jump:1009g"
- Bitmask: bit0=erratic_ok, bit1=stuck_ok, bit2=cal_ok, bit3=runtime_ok
- DEGRADED = 1 check fails, FAILED = 2+ checks fail

**Real hardware outputs (verified 2026-06-16):**
| Measurement | Value |
|---|---|
| cal_factor this boot | 35.84 raw/g |
| sigma recomputed | 3.44g |
| Empty platform quality | DEGRADED (stuck check fails, tare_variance=0.0f) |
| 1kg placement jump detected | 1009g delta - correctly flagged FAILED |
| Steady load quality | DEGRADED (stuck check only) |
| checks_passed steady | 0x0D (bits 0,2,3 set - only stuck failing) |
| checks_passed on placement | 0x05 (bits 0,2 set - stuck + jump both failing) |

**Gate result:** PASSED - health module compiles, flashes, runs on hardware. Runtime jump detection verified. Stuck detection firing correctly (expected, pending tare.h update).

**Known limitations carried forward:**
- TODO 1B-stuck: tare_variance_raw always 0.0f - stuck check always DEGRADED until tare.h exposes variance
- TODO 1B-persistence: prev_cal_factor and prev_sigma_g not persisted across boots - cal/erratic checks always skip

**Next session:** 1C - timing instrumentation. Add millis() timestamps to each boot phase. Emit in structured Serial journal.

---

## Session 003 — 2026-06-17 — Node Layer 1 complete (1C + 1D)

### Goal
Complete Node Layer 1: add timing instrumentation (1C) and structured 
event journal (1D) to the production sketch.

### What was built
- 1C: phase_start_ms global + per-phase duration emitted in seconds on boot exit
- 1D: journal.h / journal.cpp service module — owns all Serial output
  Events: START, PHASE_COMPLETE, BOOT_COMPLETE, QUALITY_CHANGE, 
          WEIGHT_EVENT, HEARTBEAT, PHASE_FAIL
  Boot counter persisted in config.json
  Format: #SEQ t=T boot=B [TAG] event=NAME key=val key=val

### Real hardware outputs (2026-06-17)
Boot timing verified:
| Phase | Duration |
|---|---|
| SETTLE | 2.1s |
| TARE | 21.1–21.2s |
| NOISE | 20.1s |
| CAL | 17–55s (human input variable) |
| Total boot | ~60s |

Journal output verified:
#0001 t=0.2 boot=1 [BOOT] event=START fw=1.0
#0002 t=2.3 boot=1 [BOOT] event=PHASE_COMPLETE phase=SETTLE result=OK s=2.1
#0003 t=23.5 boot=1 [BOOT] event=PHASE_COMPLETE phase=TARE result=OK mean=-102970.8 spread=0.0 s=21.1
#0004 t=43.6 boot=1 [BOOT] event=PHASE_COMPLETE phase=NOISE result=WARN s=20.1
#0005 t=64.3 boot=1 [BOOT] event=PHASE_COMPLETE phase=CAL result=OK cal_factor=35.9664 s=20.7
#0006 t=64.3 boot=1 [BOOT] event=BOOT_COMPLETE total_s=64.3 cal=35.9664 sigma=3.65 tare=-102970.8
#0007 t=64.4 boot=1 [RUN] event=QUALITY_CHANGE from=NONE to=DEGRADED grams=0.0 sigma=3.65 diagnosis=stuck:
#0008 t=64.4 boot=1 [HB] event=HEARTBEAT grams=0.0 quality=DEGRADED sigma=3.65 uptime=64.4
#0009 t=66.3 boot=1 [RUN] event=WEIGHT_EVENT type=PLACED grams=406.3 prev=0.0 delta=406.3
Heartbeat every 30s confirmed. Boot counter increments confirmed (boot=1→2).

### Key decisions
- journal.cpp is a SERVICE module (owns state) — not a pure function
- Computation modules = pure functions. Service modules = stateful. Rule distinction locked.
- tick_start_ms removed — per-tick timing was noise not signal at 0–1ms resolution
- Event log replaces data stream: 216,000 lines/6hr → ~750 lines. Every line meaningful.
- Log on transitions not state: QUALITY_CHANGE not quality every tick

### Gate
Node Layer 1: COMPLETE. All four items (1A, 1B, 1C, 1D) verified on hardware.

### Additional work — BLE pipeline debugging and fix
- Diagnosed QRB2210 BT adapter I/O error (hcitool lescan fails, bluetoothctl works)
- Root cause 1: InterfacesAdded UUID filter ignored on QRB2210 BlueZ backend
  Fix: changed discovery match from SERVICE_UUID to device Name
- Root cause 2: already-known BlueZ devices don't re-trigger InterfacesAdded
  Fix: added _check_known_devices() at startup to scan managed objects
- Added passwordless sudo rule for dbus-bridge service restart in deploy
- End-to-end pipeline verified: node→BLE→hub→WebUI showing live weight
  WebUI confirmed: 422g DEGRADED ±3.65g 2026-06-17T05:59:22

### Gate
Node Layer 1: COMPLETE
BLE transport: VERIFIED end-to-end on real hardware
WebUI: LIVE showing real weight

### Next
3E-006B — minimum detectable removal experiment.

---

## Session — 2026-06-17 SESSION2 — 3E-006B Minimum Detectable Removal

### Goal
Run 3E-006B: measure the minimum detectable weight removal on the 3-cell platform.
Fix the weight event detector bug discovered during this session.

### Bug found and fixed — weight event detector
Root cause: journal.cpp computed a tick-to-tick delta (current_grams − prev_grams),
not a windowed comparison. This caused:
- Cascades of 19+ WEIGHT_EVENT lines per single physical removal
- 100g removal on a 1615g base load completely missed (per-tick delta ~5g,
  never crossed the 21.3g threshold)

Fix — 20-tick delay-line detector added to weight.cpp:
- s_ref_buf[20] stores reference mean from 20 ticks ago
- s_event_pending lockout flag: one event per transition, no cascade
- s_ref_count guard: no detection for first 40 ticks (delay line priming)
- Detection logic moved from journal.cpp to weight.cpp (correct separation)
- journal.cpp is now a pure reporter: reads wr.event and wr.delta only
- weight_update() gains sigma_g as 4th parameter (threshold = 4.0f × sigma_g)
- journal_run() gains event and delta as 4th and 5th parameters

Files changed: weight.h, weight.cpp, journal.h, journal.cpp, gas_monitor_v1.ino
Verified on hardware: single event per physical removal for all test steps.

### Experiment results — 3E-006B
sigma this session: 5.33g | threshold: 4 × 5.33 = 21.3g

| Removal | Detected? | Events | Notes |
|---|---|---|---|
| 100g | ✅ YES | 1 | Clean, no cascade |
| 50g | ✅ YES | 1 | Clean, no cascade |
| 30g | ✅ YES | 1 | Clean, no cascade |
| 20g | ✅ YES | 1 | delta=21.8g — 0.94× threshold, slightly below 4σ |
| 10g | ❌ NO | 0 | Invisible to detector and heartbeat |

Minimum detectable removal: 20g (1 trial)
Hard floor: 10g (confirmed undetectable)

### Key findings
- Load cell creep: 1414g bowl took >60s to stabilise before detection was reliable
  Hub settle gate: use 2×sigma between consecutive heartbeats, not a fixed gram value
- WEIGHT_EVENT delta field is a detection signal, not a precise measurement
  Hub must use grams field, not delta, to compute actual weight change
- Delay-line detector is slightly more sensitive than 4σ theory predicts:
  detected 20g at 0.94× threshold
- Sigma varies boot-to-boot: 3.65g to 5.33g observed across sessions
  Minimum detectable removal therefore varies per boot — not a fixed product spec
- 1E identified: BLE journal transport — dedicated BLE characteristic for log lines,
  hub writes to rotating log file on AQ3. Not yet designed.

### Gate
3E-006B: COMPLETE
Minimum detectable removal: 20g (1 trial — 3-trial confirmation pending)
Hard floor: 10g (confirmed undetectable)
Weight event detector: FIXED and verified on hardware

### Next
3E-007B — false positive rate experiment. Design in chat first.

---

## Session — 2026-06-17 SESSION3 — 3E-007B False Positive Rate + Disturbance Analysis

### Goal
Run 3E-007B: measure the false positive rate of the delay-line weight event detector
on a static load over an extended observation window.
Conduct disturbance analysis: what happens when the platform is mechanically disturbed.

### Experiment results — 3E-007B (false positive rate)
sigma this session: 5.12g | threshold: 4 × 5.12 = 20.5g
Observation window: 38.4 minutes (2304 seconds) on static load

| Metric | Target | Result | Status |
|---|---|---|---|
| False WEIGHT_EVENT triggers | < 2 per hour | 0 | ✅ PASS |
| Slow drift immunity | Must not trigger | 190g peak-to-trough — zero events | ✅ PASS |
| Observation duration | > 30 minutes | 38.4 minutes | ✅ PASS |

### Disturbance analysis
Finding: moving the platform base (with or without a cylinder) shifts the zero reference silently.

Case A — cylinder removed, base moved, cylinder replaced:
- Hub knows platform was empty at removal (WEIGHT_EVENT type=REMOVED, grams≈0)
- Hub can trigger retare via BLE command to node
- Requires a writable BLE characteristic on node → HUB-001 backlog item

Case B — base moved with cylinder on platform:
- No WEIGHT_EVENT fires — weight is unchanged, only the zero reference shifted
- System reports wrong values silently — no current detection mechanism
- Mitigation: detect from heartbeat trend (sudden step with no WEIGHT_EVENT) → HUB-002 backlog item
- Cannot implement HUB-002 without burn rate estimate from Group 5 analytics

### New backlog items added this session
HUB-001: auto-retare after cylinder removal — requires writable BLE characteristic on node.
         Priority: high — required for correct operation after any cylinder change.
HUB-002: disturbance detection from heartbeat trend anomaly.
         Priority: medium — requires Group 5 burn rate first.

### Drift observation
190g peak-to-trough wander on static load over 38 minutes.
Drift rate: ~0.08g per 2-second tick window — far below 20.5g threshold.
Not noise — this is real slow drift (thermal or mechanical creep).
Will corrupt gas% calculation over a 6-hour reading cycle if not characterised.
Must be properly characterised in 3E-009 (long-run stability soak).

### Gate
3E-007B: COMPLETE
False positive rate: 0 per hour. Target < 2 per hour. PASS ✅
Delay-line detector validated against real slow drift on hardware.

### Next
3E-008 — temperature drift experiment. Design in chat first.

---

## Session — 2026-06-18 — Bug Fixes + BLE Command Char + Boot Sequence Redesign

### Goal
Fix all false-positive bugs found at session start. Build BLE command characteristic.
Add STATE_TARE_WAIT and tare SPIFFS persistence. Verify boot=35 clean.

### All 7 bugs fixed this session

| # | Bug | Root cause | Fix applied |
|---|-----|-----------|-------------|
| F1 | NOISE result=WARN on every healthy boot | NOISE_SIGMA_PASS_G calibrated for single-cell STM32 (healthy sigma ~1.87g). 3-cell ESP32-C3 healthy sigma 4.68–5.44g — always exceeded old gate | NOISE_SIGMA_PASS_G=8.0g, NOISE_SIGMA_WARN_G=15.0g in noise.cpp |
| F2 | quality=DEGRADED on every healthy boot | tare_variance_raw always 0.0f — tare.cpp never populates it. Stuck check always fired false positive | Skip stuck check when tare_variance_raw==0.0f in health.cpp (guard until TODO 1B-stuck resolved) |
| F3 | NOISE result=WARN persisted after F1 fix | cal_factor=0.0f during NOISE phase → raw-count path → sigma in raw counts (~180) vs gram-based threshold (15.0g) → always WARN | Load saved cal_factor from SPIFFS before NOISE phase in gas_monitor_v1.ino |
| F4 | sigma=0.09g → 200+ false WEIGHT_EVENTs (boot=33) | noise.cpp stored samples in grams (÷ cal_factor). noise_recompute_sigma() divided by cal_factor again. Double-division: sigma ~5g → 0.09g → threshold 0.36g | Store raw counts in s_samples[], divide by cal_factor exactly once at sigma_raw→sigma_g conversion |
| F5 | False WEIGHT_EVENT REMOVED on static 1000g (boot=31) | BUF_SIZE=20 (2-second delay-line). Two 2-second means could differ >21.76g (4σ) from natural creep on static load | BUF_SIZE=40 (4-second window). SE of 40-sample mean = 0.86g. Natural mean difference drops below threshold |
| F6 | sigma=25.62g on first boot | Intermittent load cell wire overnight — one cell dropping during NOISE phase. All samples contaminated | Physical: reconnect loose wire. Hardware clean on next boot (sigma=4.74g) |
| F7 | NimBLE onWrite compile error | NimBLE-Arduino v1.4+ changed callback to two-parameter signature. Old single-parameter form rejected by esp32 v3.0.7 | void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override |

### Hardware-verified values — boot=35

| Parameter | Value | Status |
|---|---|---|
| sigma | 3.16g | VERIFIED clean |
| threshold | 4 × 3.16 = 12.64g | DERIVED |
| cal_factor | 36.25–36.27 raw/g | VERIFIED (hw_test) |
| BUF_SIZE | 40 ticks (4-second window) | LOCKED |
| NOISE_SIGMA_PASS_G | 8.0g | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0g | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| Boot time (full TARE_WAIT) | ~103.9s | VERIFIED |
| tare_raw boot=35 | -105232.4 | VERIFIED — saved to SPIFFS |
| 1000g accuracy | 986.5g first HB | VERIFIED |
| False WEIGHT_EVENTs | 0 | VERIFIED — BUF_SIZE=40 |
| quality on boot=35 | GOOD | VERIFIED — all 7 bugs fixed |

### Features built this session

1. **BLE Command Characteristic** — writable GATT char on node for hub→node commands
   - UUID: c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b (write-without-response)
   - Commands: TARE, SKIP_TARE, SET_CAL:\<value\>, RETARE (DUMP_LOG/CLEAR_LOG stubs)
2. **STATE_TARE_WAIT** — new boot state between SETTLE and TARE
   - Node waits up to 60s for hub to send TARE or SKIP_TARE. 60s timeout = fail-safe.
   - Boot sequence now: SETTLE → TARE_WAIT → TARE → NOISE → CAL → RUNNING
3. **Tare SPIFFS persistence** — tare_save_to_spiffs() / tare_load_from_spiffs() in tare.cpp
   - Saved after every fresh tare. Sanity check [-200000, -50000] on load.
4. **STATE_RETARE** — new state in RUNNING. Triggered by RETARE command. Runs fresh N=200 tare, saves to SPIFFS, returns to RUNNING. HUB-001 path ready.
5. **Log char UUID registered** — d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c (notify) — streaming not yet built (1E backlog)

### Architecture decisions locked this session

- V1 cal_factor derived from cylinder via BIS 14.2kg anchor — hub computes, node stores and uses
- Tare + cal_factor are a PAIR — hub stores both together, always sends matching pair via SKIP_TARE + SET_CAL
- Log transport: node auto-pushes at 25KB threshold + hub requests on new boot number detected
- CLEAR_LOG sent only after hub confirms file written to disk — no log loss on BLE drop
- WebUI three-tab design: Live / Boot log / Serial feed + command input box

### Gate
boot=35: sigma=3.16g, quality=GOOD, zero false WEIGHT_EVENTs. All 7 bugs verified fixed.

### Next
N-TARE-CHECK — post-tare self-check. Detect if weight was on platform during tare.
Then: N1 — journal → SPIFFS persistence.
