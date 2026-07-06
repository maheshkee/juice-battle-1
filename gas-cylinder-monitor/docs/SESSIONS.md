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

---

## 2026-06-18 Session 2 (afternoon)

### Items completed

- **N-TARE-CHECK:** post-tare self-check built and verified
- **Hub dev/prod mode toggle:** WebUI toggle, auto re-anchor, g_weight_was_removed gate
- **IST timestamp fix:** subprocess date call replaces strftime
- **Two-level alerts:** amber (low_gas) + red (critical/empty) with days remaining
- **PROD mode placeholder:** "Calibrating..." when steel unknown
- **Burn rate constants locked:** L-064 + addendum in LEARNINGS
- **Drift budget documented** in RESEARCH.md
- **HUB-WATCHDOG designed** and added to backlog

### Bugs fixed

- on_set_dev_mode missing sid parameter
- Duplicate constant block (400/600 overwriting 350/1000)
- Re-anchor firing continuously on static load
- DEV/PROD toggle not responding (sid signature bug)

### BT incident documented

- WCN3990 firmware crash — hci0 wedged
- Only reboot recovered it
- HUB-WATCHDOG added as pre-production requirement

### Known open items carried forward

- on_set_dev_mode sid fix: committed, needs deploy
- BT power-on at startup (Layer 1): needs CLI + deploy
- deploy.sh BT restart (Layer 2): needs CLI + deploy
- HUB-WATCHDOG (Layer 3): backlog, before production
- N1 journal → SPIFFS: next node item
- tare_check threshold: still at 1000g test value, restore to 2000g before production

---

## Session 003 - 2026-06-18 morning - node bugs, BLE command char, TARE_WAIT

### Goal
Fix all node false positives. Build BLE command characteristic. Build STATE_TARE_WAIT.

### What happened
- Fixed sigma=25g bug (loose load cell wire at junction — physical reconnect)
- Fixed NOISE=WARN every boot: thresholds recalibrated for 3-cell platform (PASS=8g, WARN=15g)
- Fixed quality=DEGRADED every boot: skip_stuck guard for tare_variance_raw=0.0f
- Fixed NOISE=WARN after threshold fix: load SPIFFS cal_factor before NOISE phase
- Fixed sigma=0.09g / 200+ false WEIGHT_EVENTs: store raw counts in s_samples[], divide by cal_factor exactly once
- Fixed false WEIGHT_EVENT REMOVED on static load: BUF_SIZE 20→40 ticks
- Fixed NimBLE onWrite compile error: add NimBLEConnInfo& as second parameter
- Built BLE command characteristic: TARE / SKIP_TARE / SET_CAL / RETARE / DUMP_LOG(stub) / CLEAR_LOG(stub)
- Built STATE_TARE_WAIT: hub decides tare path, 60s timeout fallback
- Built tare SPIFFS save/load: tare_save_to_spiffs() / tare_load_from_spiffs()

### Real hardware outputs
| Parameter | Value | Status |
|---|---|---|
| sigma boot=35 | 3.16g | VERIFIED |
| sigma boot=31 | 5.44g | VERIFIED |
| cal_factor | 36.2689 raw/g | VERIFIED |
| weight accuracy | ±6g on 1000g | VERIFIED |
| SETTLE duration | ~2.1s | VERIFIED |
| TARE duration | ~21.1s (N=200 at 10 SPS) | VERIFIED |
| NOISE duration | ~20.1s (N=200 at 10 SPS) | VERIFIED |
| Boot total (timeout path) | ~103.9s | VERIFIED |
| tare_raw boot=35 | -105232.4 | VERIFIED |

### Gate
Node clean on boot=35. All seven false positives eliminated. BLE command char compiled and running.

---

## Session 004 - 2026-06-18 afternoon - hub dev mode, alerts, WebUI, first working demo

### Goal
Hub DEV mode with auto-anchor and percentage tracking. Two-level alerts. DEV/PROD toggle.
First end-to-end working demo verified on hardware.

### What happened
- Node: N-TARE-CHECK built — post-tare self-check, TARE_CHECK_THRESHOLD_G=1000g (DEV)
- Node: NimBLE advertising restart on disconnect — node always findable after hub reconnect
- Hub: db_get/set_dev_mode() in db.py — DEV/PROD mode stored in SQLite
- Hub: Auto re-anchor with 3-reading spread window (ANCHOR_SPREAD_THRESHOLD_G=30g)
- Hub: g_weight_was_removed gate — anchor only fires after removal + replacement
- Hub: Two-level alerts: amber pct<20% + days_remaining, red grams<50g
- Hub: PROD mode scaffold — Calibrating... placeholder, no pct until steel known
- Hub: dev_mode field in every weight_update payload
- Hub: node_status events — connected/disconnected, name, MAC shown in topbar
- Hub: IST timestamp fix — subprocess date call replaces Python strftime
- Hub: on_set_dev_mode(sid, data) signature fix
- Hub: BT power-on added to deploy.sh — prevents adapter power loss on redeploy
- Hub: setup_sudoers.sh created — passwordless sudo for all deploy commands
- Hub: DEVICE_SETUP.md created — one-time device commissioning guide
- Constants locked: DAILY_USE_DEFAULT_G=350, ALERT_AMBER_G=2000, ALERT_RED_G=1000, MIN_HISTORY_DAYS=7, ANCHOR_SPREAD_THRESHOLD_G=30
- L-064 through L-070 appended to LEARNINGS_AND_INSIGHTS.md
- WCN3990 BT firmware crash incident — documented in L-065, L-070, RESEARCH.md
- HUB-WATCHDOG designed and added to pre-production backlog

### Real hardware outputs — demo verified
| Check | Result |
|---|---|
| Anchor at correct weight | 1694.9g VERIFIED |
| pct 1786g=100%, 998g=56%, 352g=20% | VERIFIED |
| Amber alert at 20% with days text | VERIFIED |
| Red alert at <50g | VERIFIED |
| Progress bar green→amber→red | VERIFIED |
| DEV/PROD toggle | VERIFIED |
| NimBLE advertising restart | VERIFIED — [BLE] Restarting advertising after disconnect in journal |
| IST timestamp | VERIFIED — 18 Jun 2026 10:56:38 |
| Node MAC in topbar | VERIFIED — 10:00:3B:CD:63:32 |

### Gate
First end-to-end DEV mode demo working. Percentage tracks real consumption.
Alerts fire at correct thresholds. Hub stable. Node auto-reconnects after hub restart.

---

## Session 003 - 2026-06-18 morning - node bugs, BLE command char, TARE_WAIT

### Goal
Fix all node false positives. Build BLE command characteristic. Build STATE_TARE_WAIT.

### What happened
- Fixed sigma=25g bug (loose load cell wire at junction — physical reconnect)
- Fixed NOISE=WARN every boot: thresholds recalibrated for 3-cell platform (PASS=8g, WARN=15g)
- Fixed quality=DEGRADED every boot: skip_stuck guard for tare_variance_raw=0.0f
- Fixed NOISE=WARN after threshold fix: load SPIFFS cal_factor before NOISE phase
- Fixed sigma=0.09g / 200+ false WEIGHT_EVENTs: store raw counts in s_samples[], divide by cal_factor exactly once
- Fixed false WEIGHT_EVENT REMOVED on static load: BUF_SIZE 20→40 ticks
- Fixed NimBLE onWrite compile error: add NimBLEConnInfo& as second parameter
- Built BLE command characteristic: TARE / SKIP_TARE / SET_CAL / RETARE / DUMP_LOG(stub) / CLEAR_LOG(stub)
- Built STATE_TARE_WAIT: hub decides tare path, 60s timeout fallback
- Built tare SPIFFS save/load: tare_save_to_spiffs() / tare_load_from_spiffs()

### Real hardware outputs
| Parameter | Value | Status |
|---|---|---|
| sigma boot=35 | 3.16g | VERIFIED |
| sigma boot=31 | 5.44g | VERIFIED |
| cal_factor | 36.2689 raw/g | VERIFIED |
| weight accuracy | ±6g on 1000g | VERIFIED |
| SETTLE duration | ~2.1s | VERIFIED |
| TARE duration | ~21.1s (N=200 at 10 SPS) | VERIFIED |
| NOISE duration | ~20.1s (N=200 at 10 SPS) | VERIFIED |
| Boot total (timeout path) | ~103.9s | VERIFIED |
| tare_raw boot=35 | -105232.4 | VERIFIED |

### Gate
Node clean on boot=35. All seven false positives eliminated. BLE command char running.

---

## Session 004 - 2026-06-18 afternoon - hub dev mode, alerts, WebUI, first working demo

### Goal
Hub DEV mode with auto-anchor and percentage tracking. Two-level alerts. DEV/PROD toggle.
First end-to-end working demo verified on hardware.

### What happened
- Node: N-TARE-CHECK built — post-tare self-check, TARE_CHECK_THRESHOLD_G=1000g (DEV)
- Node: NimBLE advertising restart on disconnect (ble.cpp — NimBLEDevice::startAdvertising())
- Hub: db_get_dev_mode() / db_set_dev_mode() in db.py
- Hub: DEV/PROD branching in on_weight() — auto-anchor vs PROD scaffold
- Hub: 3-reading spread window anchor (ANCHOR_SPREAD_THRESHOLD_G=30g)
- Hub: g_weight_was_removed gate — anchor only fires after removal and replacement
- Hub: two-level alerts — amber pct<20% + days_remaining, red grams<50g
- Hub: PROD mode scaffold — Calibrating... placeholder, no pct until steel known
- Hub: dev_mode field in every weight_update payload
- Hub: node_status events — connected/disconnected, name, MAC shown in topbar
- Hub: IST timestamp fix — subprocess date call replaces Python strftime
- Hub: on_set_dev_mode(sid, data) — sid parameter fix
- Hub: BT power-on added to deploy.sh — prevents adapter power loss on redeploy
- Hub: setup_sudoers.sh — passwordless sudo for all deploy commands
- Hub: DEVICE_SETUP.md — one-time device commissioning guide
- Constants locked: DAILY_USE_DEFAULT_G=350, ALERT_AMBER_G=2000, ALERT_RED_G=1000, MIN_HISTORY_DAYS=7, ANCHOR_SPREAD_THRESHOLD_G=30
- L-064 through L-070 appended to LEARNINGS_AND_INSIGHTS.md
- WCN3990 BT firmware crash incident — documented L-065, L-070, RESEARCH.md
- HUB-WATCHDOG designed and added to pre-production backlog

### Real hardware outputs — demo verified
| Check | Result |
|---|---|
| Anchor at correct weight | 1694.9g VERIFIED |
| 1786g=100%, 998g=56%, 352g=20% | VERIFIED |
| Amber alert at 20% with days text | VERIFIED |
| Red alert at <50g | VERIFIED |
| Progress bar green→amber→red | VERIFIED |
| DEV/PROD toggle | VERIFIED |
| NimBLE advertising restart | VERIFIED |
| IST timestamp | VERIFIED — 18 Jun 2026 |
| Node MAC in topbar | VERIFIED — 10:00:3B:CD:63:32 |

### Gate
First end-to-end DEV mode demo working. Percentage tracks real consumption.
Alerts fire at correct thresholds. Hub stable. Node auto-reconnects after hub restart.

Do not commit yet.

---

## Session 006 - 2026-06-22 - N1 journal SPIFFS + anchor fix

### Goal
Build N1: persist journal lines to SPIFFS flash so logs survive power cuts.
Fix hub anchor logic bug causing spurious re-anchoring on hub restart.

### What happened

#### Node — N1 journal SPIFFS (journal.h, journal.cpp, gas_monitor_v1.ino)
- Added g_journal_file_bytes (uint32_t) and g_transfer_pending (bool) globals
- Added JOURNAL_TRANSFER_THRESHOLD_BYTES = 25600 (25KB)
- Added journal_append() private static helper: opens /node_journal.log in
  FILE_APPEND mode, writes line, closes immediately (flush guarantee), increments
  g_journal_file_bytes, sets g_transfer_pending when threshold crossed
- journal_init() now reads actual SPIFFS file size at boot to initialise
  g_journal_file_bytes honestly (handles reboot-without-clear correctly)
- All 7 journal functions rewritten: LOG_PREFIX() + Serial.printf replaced with
  ++s_seq / full snprintf into 256-byte buffer / Serial.print / journal_append
  Complete line (prefix + body) written to both Serial and SPIFFS identically
- Added journal_tare_check(result, delta_g) and journal_retare(new_tare, old_tare)
  as new journal functions — same full-line pattern with proper sequence numbers
- Replaced 4 raw Serial.printf calls in gas_monitor_v1.ino with journal calls:
  3x tare_check lines in STATE_TARE → journal_tare_check()
  1x RETARE line in STATE_RETARE → journal_retare()
- Added [DBG] journal_init print at boot showing file_bytes and pending state
- Added g_transfer_pending stub check in STATE_RUNNING (logs once when flag true)

#### Hub — anchor logic fix (main.py)
- Added ANCHOR_SPREAD_THRESHOLD_G = 30.0 constant (was using 2.0*sigma ~7g)
- Fixed anchor spread check: abs(grams - g_sw_candidate_val) <= ANCHOR_SPREAD_THRESHOLD_G
  (previously used 2.0*sigma which caused mid-settling false anchors)
- Fixed g_starting_weight initialisation: now loaded from DB immediately after
  db_init() at startup in DEV mode (previously stayed None until first weight
  arrived, causing spurious re-anchor on every hub restart)

### Real hardware outputs
| Check | Result |
|---|---|
| journal_init boot=43 file_bytes=0 | VERIFIED — first boot after flash, no file |
| journal_init boot=46 file_bytes=3531 | VERIFIED — 3.5KB accumulated from boot 45 survived power cycle |
| Boot sequence complete boot=46 | VERIFIED — all phases normal |
| sigma boot=46 | 3.56g (healthy range) |
| tare_check=NO_REF routed correctly | VERIFIED — seq#4 boot=45, not seq#0 |
| Anchor fix: 5kg weight anchors at ~5021g | VERIFIED — previously anchoring at 578g |
| WebUI 5028g = 100% after anchor fix | VERIFIED |
| g_transfer_pending fires at 25KB | NOT YET TESTED — threshold requires ~2hr of heartbeats |

### Gate
N1 COMPLETE — journal lines persist to SPIFFS across power cycles. File accumulates
correctly across boots. All journal events including tare_check and retare now
route through journal functions with correct sequence numbers.
Anchor fix COMPLETE — hub no longer spuriously re-anchors on restart or during
mid-settling weight placement.
Next: 1E — activate BLE log characteristic, MTU gate, stream /node_journal.log
line-by-line to hub on DUMP_LOG command.

---

## Session 7 — 2026-06-22

**Goal:** Build 1E — BLE log characteristic streaming. Full DUMP_LOG/stream/LOG_END/CLEAR_LOG pipeline.

**What was built:**
- Node: log_transfer.h / log_transfer.cpp — full transfer FSM (IDLE/SENDING/DONE)
- Node: ble.cpp — g_mtu_ready flag, onMTUChange callback, log_transfer_abort in onDisconnect
- Node: gas_monitor_v1.ino — wired DUMP_LOG/g_transfer_pending/CLEAR_LOG stubs to real calls, log_transfer_tick in RUNNING
- Node: delay(10) added to STATE_TARE_WAIT — fixes FreeRTOS watchdog starvation crash
- Hub: ble_subscriber.py — log char + cmd char discovered, _subscribe_log_notify, _on_log_notify, write_command, _connecting guard
- Hub: main.py — on_log_line handler, LOG_START/LOG_END sentinels, temp file→logs/node/, DUMP_LOG trigger on connect, CLEAR_LOG after verify, duplicate LOG_START guard

**Hardware verified:**
- MTU negotiated: 255 bytes (QRB2210 BlueZ → ESP32-C3 NimBLE)
- Transfer: 233 lines streamed, 21102 bytes, at ~10Hz pace
- CLEAR_LOG received and SPIFFS cleared — g_journal_file_bytes reset to 0
- Second transfer after clear: 16 lines, 1468 bytes — clean no duplicates
- Abort-and-preserve: BLE drop mid-transfer → file preserved → retransfer on reconnect verified
- FreeRTOS watchdog: boot=1 crashed at t=11.978s (TARE_WAIT starvation) — fixed with delay(10), boot=6 ran 5000+ seconds clean

**Gate result:** PASSED — 1E complete end-to-end verified on hardware

**Key fixes discovered:**
- hub write_command must strip newline — node strcmp requires exact match without \n
- BLESubscriber needs _connecting guard to prevent duplicate connect on hub restart
- on_log_line needs LOG_START guard to prevent duplicate temp file open
- delay(10) mandatory in STATE_TARE_WAIT to yield FreeRTOS IDLE task
- Full chip erase (Erase All Flash) destroys 2nd stage bootloader — never use for flash failures

**Next session:** CAL timeout fix (HIGH PRIORITY) — 120s timeout on STATE_CAL → 36.0 fallback → DEGRADED quality

---

## Session — 2026-06-23 — CAL timeout fix + g_cal_degraded flag

**Goal:** CAL timeout fix — prevent indefinite hang in STATE_CAL when hub is offline and SPIFFS is empty.

**What was built:**
- 120s timeout in STATE_CAL → 36.0 fallback → g_cal_degraded = true
- SET_CAL accepted in STATE_RUNNING → updates g_cal_factor immediately, clears g_cal_degraded
- g_cal_degraded = false on real SET_CAL received (in either STATE_CAL or STATE_RUNNING)
- g_cal_degraded overrides BLE payload quality to DEGRADED when cal is a fallback
- Journal always records true hardware health — never masked by g_cal_degraded

**Gate result:** VERIFIED on boot=8 — SPIFFS fast-load path confirmed working

**Node boot count at session end:** boot=8

---

## Session — 2026-06-23 — G4 hub domain logic: modular reorg + state machine + gas%

**Goal:** G4 hub domain logic — modular reorganisation, production state machine, gas% calculation, setup endpoint.

**What was built:**
- log_transfer.py extracted from main.py (chunk 1) — owns LOG_DIR, LOG_TMP, LOG_START/LOG_END pipeline
- domain.py created: all constants, state machine, anchor window, steel derivation,
  gas% calc, bootstrap regimes (FRESH/PARTIAL_BRAND/PARTIAL_PRIOR), first-reading cross-check,
  setup endpoint handler (chunks 2–4)
- main.py: 267 → 113 lines, DEV mode fully deleted, wired to domain.py (chunk 3)
- db.py: new columns gas_pct, gas_g, alert_level, cylinder_state; dead DEV functions removed (chunks 5–6)
- index.html: DEV/PROD toggle removed, calibrating-label wired to cylinder_state === 'BOOTSTRAP_ANCHOR' (chunk 6)
- config.json: G4 schema fields added (brand, install_mode, cylinder_state, steel_g,
  steel_source, steel_anchored_at, cal_factor, tare_raw, cal_tare_session)

**What was verified:**
- UNINSTALLED state on empty platform — correct
- setup endpoint fires BOOTSTRAP_ANCHOR transition — confirmed
- Anchor window correctly ignores readings < 26000g — confirmed
- config.json persists state across deploy — confirmed
- DEV/PROD toggle gone from WebUI — confirmed visually
- Full pipeline: [DOMAIN] → [DB] → [MAIN] clean on every reading

**Hub module count:** 5 files, each single responsibility
**Node boot at session end:** boot=9
**Gate result:** G4 COMPLETE

---

## Session — 2026-06-24 — BLE stability + config.json path fix + SKIP_TARE verification

**Goal:** Confirm overnight BLE stability. Fix config.json path bug. Verify SKIP_TARE+SET_CAL on connect. Boot time reduction.

### What happened

- **17-hour stability confirmed** — session=16 ran from 11:33 IST Jun 23 to 04:19 IST Jun 24 without reboot.
  BLE supervision-timeout disconnects (every ~3-4 min) all recovered within 30s. Watchdog never fired.

- **config.json path bug found and fixed** — hub was reading hub/data/config.json but Docker mounts hub/ not
  hub/data/. The file at hub/data/config.json was never read — no error, silent failure. Fix: wrote
  cal_factor=36.2231 and tare_raw=-107041.4 to hub/config.json (the file the container actually reads).

- **Redeployed hub** — hub now correctly finds cal_factor in config.json and sends SKIP_TARE+SET_CAL:36.2231
  on every node connect instead of TARE.

- **boot=21 verified clean** — TARE_WAIT result=CMD_SKIP_TARE at t=7.2s.
  BOOT_COMPLETE total_s=27.5 (was 103.9s — 74% faster). CAL loaded via SET_CAL command
  (not SPIFFS fallback) — g_cal_degraded=false confirmed.

- **Tare corruption on reconnect permanently prevented** — SKIP_TARE path safe regardless of platform state.

- **Cal_factor and BLE reference documents created** — GasMonitor_CalFactor_BLE_Reference.docx
  covering all 6 tare scenarios documented.

### Real hardware outputs

| Parameter | Value | Status |
|---|---|---|
| System uptime (session=16) | 17+ hours (11:33 Jun23 → 04:19 Jun24) | VERIFIED |
| Boot count | 21 | VERIFIED |
| Boot time (SKIP_TARE path) | 27.5s | VERIFIED — was 103.9s |
| TARE_WAIT result | CMD_SKIP_TARE at t=7.2s | VERIFIED |
| cal_factor loaded | 36.2231 via SET_CAL command | VERIFIED |
| g_cal_degraded | false | VERIFIED — not SPIFFS fallback |
| BLE reconnects | Every ~3-4 min, recover in <30s | VERIFIED normal behaviour |
| Watchdog triggers | 0 | VERIFIED |

### Gate result

SKIP_TARE+SET_CAL VERIFIED. config.json path fixed. System stable 17h. Boot time 74% faster.
Ready for 3E-005 water bowl anchor validation.

---

## Session 003 - 2026-06-25 - 3E-005 water bowl anchor validation + WebUI additions

### Goal
Validate full domain state machine end-to-end: UNINSTALLED  BOOTSTRAP_ANCHOR  TRACKING.
Add Install cylinder button and gas% to WebUI. Validate grace window behaviour.

### What happened
- Diagnosed tare_raw discrepancy (config.json showed -89234.5 not -88281.3 from handoff).
  Root cause: platform swap test continued through boots 24 and 25 after handoff was written.
  -89234.5 is the correct and most recent tare. No bug.
- Changed 4 domain.py constants for water bowl test (NET_GAS_G, ANCHOR_GROSS_MIN_G,
  STEEL_PLAUSIBLE_MIN_G, STEEL_PLAUSIBLE_MAX_G).
- Fixed gas% field name mismatch in WebUI: data.pct  data.gas_pct.
- Added 'Install cylinder' button to WebUI (visible only when UNINSTALLED).
- Added gas% display and progress bar to WebUI (visible only when TRACKING/LOW_GAS).
- Discovered and fixed BUG: refill detection used ANCHOR_GROSS_MIN_G causing infinite
  re-anchor loop at 5000g. Fixed by adding separate REFILL_GROSS_MIN_G = 5500.0 (prod: 29000.0).
- Implemented Option A removal grace window: REMOVAL_GRACE_S = 120.0s before UNINSTALLED.
- Ran 3E-005 experiment: anchor fired correctly, steel_g derived, gas% showed 100%.
- Ran demo for boss: full flow from power cycle to 100% gas% confirmed live.
- Validated grace window: 30s removal  stayed TRACKING. 120s+ removal  UNINSTALLED.
- Noted minor race condition: first reading after anchor transition briefly shows
  stale BOOTSTRAP_ANCHOR state in weight_update. Self-corrects next read. Deferred.

### Real hardware outputs
| Measurement | Value |
|---|---|
| Boot | 28 (post demo) |
| tare_raw | -89234.5 (boot=25, new platform) |
| cal_factor | 36.2231 (locked) |
| sigma (boot=25 clean) | 3.60g |
| sigma (boot=28 demo) | 6.91g (platform disturbed during noise phase) |
| Anchor mean_gross | 5018.6g (boot=28 demo run) |
| steel_g derived | 483.6g (bowl 406 + plate 59 + variance = 483.6g) |
| gas% at anchor | 100% |
| ANCHOR_GROSS_MIN_G test | 4800.0g |
| REFILL_GROSS_MIN_G test | 5500.0g |
| REMOVAL_GRACE_S | 120.0s |
| 5-reading anchor spread | 9g (boot=25 first run - excellent) |

### Gate
3E-005 PASSED. All pass criteria met:
- Anchor fired correctly UNINSTALLED  BOOTSTRAP_ANCHOR  TRACKING V
- steel_g derived from first principles V
- gas% shows 100% on WebUI V
- Install button appears/disappears correctly V
- Grace window holds within 120s V
- Grace expires and triggers UNINSTALLED after 120s+ V
- Boss demo completed successfully V

### Files changed this session
- hub/python/domain.py - 4 test constants + REFILL_GROSS_MIN_G + REMOVAL_GRACE_S + grace logic
- hub/assets/index.html - Install button, gas% display, data.pctdata.gas_pct fix

### What is next
- Revert 5 domain constants to production values (see revert checklist in handoff)
- Restore node HEAVY_LOAD_THRESHOLD_G to 2000g (requires reflash)
- 3E-008: mini cylinder thermal drift characterisation
- Minor race condition investigation (stale state on first post-anchor read)

---

## Session 004 — 2026-06-25/26 — G5 analytics + G7 WebUI + HUB-WATCHDOG

### Goal
Complete HUB-WATCHDOG deployment, implement G5 burn rate analytics with adaptive
lookback strategy, implement dual-condition alert architecture, build G7 WebUI
with full state display, validate end-to-end with water bowl simulator.

### What happened
- HUB-WATCHDOG: hub_watchdog.py + watchdog_host.sh already written, systemd service
  missing. Installed gas-cylinder-watchdog.service, sudoers confirmed, host daemon
  running. Both Python side (inside Docker) and host side fully operational.
- G5 analytics: compute_analytics() redesigned with adaptive burn rate:
  cumulative from anchor_ts when elapsed < BURN_RATE_WINDOW_DAYS, rolling window
  thereafter, cumulative fallback if rolling window fails.
- G5 alert architecture: dual-condition. Condition A (gram failsafe, always active:
  ALERT_AMBER_G=2000g, ALERT_RED_G=1000g). Condition B (day-based, active after
  MIN_DAYS_FOR_DAY_ALERT: ALERT_AMBER_DAYS=5.0, ALERT_RED_DAYS=3.0).
- LOW_GAS state bypasses MAX_BURN_RATE_G_PER_DAY ceiling — user always sees
  burn rate and days_remaining during alert state.
- One-reading transition fix: when TRACKING→LOW_GAS occurs in same reading,
  compute_analytics re-called with cylinder_state='LOW_GAS' to bypass ceiling.
- G7 WebUI: state pill (PLATFORM EMPTY/CALIBRATING/TRACKING/LOW GAS/CRITICAL),
  alert banner (amber/red), SENSOR OK/DEGRADED/FAILED badge, progress bar colour
  follows alert level, formatDays() with < 0.1 for very small values,
  UNINSTALLED always shows 0g, grams clamped to 0 minimum.
- Cooking intelligence vision documented: session detection (G8), dish tagging (G9),
  cooking calendar (G10). FUNCTIONAL_ZERO_G design decision documented.
- IST timezone set on host. Docker container TZ fix pending (main.py).
- 4 new docx reference documents created and committed to docs/.
- Water bowl end-to-end demo: UNINSTALLED → Install → BOOTSTRAP_ANCHOR →
  TRACKING → LOW GAS (amber) → CRITICAL (red) → UNINSTALLED. All states
  and transitions confirmed working.
- SQLite confirmed: 149+ TRACKING readings from 3E-005, new clean readings from
  Session 004 test cycles.
- sigma improved: ±3.19g with bowl on platform during noise phase (vs 1817.25g
  when bowl placed after noise phase — timing matters for quality reading).

### Real hardware outputs
| Parameter | Value | Notes |
|---|---|---|
| boot number at session end | 34 | session=34 in hub logs |
| steel_g (new anchor boot=32) | 494.7g | bowl 5000g, 3-cell platform |
| sigma (bowl on platform, correct timing) | 3.19g | excellent |
| sigma (bowl added after noise phase) | 1817.25g | wrong timing artefact |
| AMBER fires at gas_g | < 2000g | Condition A gram failsafe |
| RED fires at gas_g | < 1000g | Condition A gram failsafe |
| burn_rate during stable tracking | ~1300 g/day cumulative | no consumption = NO_CONSUMPTION src |
| tare_raw (boot=32) | -88791.0 | clean tare on empty platform |
| WCN3990 BLE watchdog | operational | host daemon polling 30s |

### Gate
G5 PASSED — adaptive burn rate computing, dual-condition alerts firing correctly.
G7 PASSED — all WebUI states rendering correctly with correct colours and labels.
HUB-WATCHDOG PASSED — both Python and host sides operational.
3E-009 IN PROGRESS — node running unattended on wall charger Fri→Mon.

### What is next
- Monday: power on hub, read 3E-009 stability data, analyse drift
- 3E-008: thermal drift characterisation (controlled heat cycle)
- 3E-010: load cell failure injection
- Docker container IST timezone fix (main.py os.environ TZ)
- Production revert of all 7+1 constants when G7 confirmed stable
- Real 14.2kg cylinder production test

---

## Session 60 — 2026-07-01 — Fixes 1-3 deployed + 3E-009 attempt 2 launch

### Goal
Deploy three hub hardening fixes from 3E-009 RCA: READING_STALE_S, WiFi power save, and CMD_TARE protection. Re-launch 3E-009.

### What was done

#### Fix 1 — READING_STALE_S 900 → 1800 (hub_watchdog.py)
Single-line change. WCN3990 modem recovery takes 13–17 min; 900s (15 min) was too
tight against variance. 1800s (30 min) gives reliable headroom above worst-case recovery.

#### Fix 2 — WiFi power save disabled permanently
Verified iw and iwconfig at /sbin/. Created systemd oneshot service
wifi-power-save-off.service at /etc/systemd/system/. Interface name derived
dynamically at runtime via `iw dev | awk '/Interface/{print $2; exit}'` — never
hardcoded. Service enabled and started. WiFi power saving confirmed off.

#### Fix 3 — CMD_TARE protection in ble_subscriber.py
`_send_tare_commands()` now reads steel_g and tare_raw from config.json before any
TARE decision. If both are non-null (valid measurement session exists), SKIP_TARE is
sent regardless of cylinder_state in memory. TARE is only sent when steel_g is null.
Log prefix PROTECTIVE_SKIP: emitted when the guard fires.
This prevents the RCA3 failure mode: hub crash → state lost → CMD_TARE → stone absorbed.

#### TZ fix confirmed already applied
main.py already had TZ fix at lines 1–4 (from a prior session). No change needed.

#### Fix 4 — ESP32 reset reason logging
Deferred. Requires Arduino IDE on Windows (COM11). Node firmware reflash needed.
To add: `esp_reset_reason()` in BOOT journal event. Document the change and defer
until next node reflash opportunity.

### Code changes this session
| File | Change |
|---|---|
| hub/python/hub_watchdog.py | READING_STALE_S: 900 → 1800 |
| hub/python/ble_subscriber.py | Protective TARE check: steel_g+tare_raw guard added |

### Current system state at session end
```
tare_raw:       -107041.4 (hub config, correct)
cal_factor:     36.2231
steel_g:        null (3E-009 attempt 1 data ended at T+24h, state lost on crash)
cylinder_state: UNINSTALLED
Node:           boot=38, WRONG tare (stone absorbed during CMD_TARE at t=43s boot 38)
                Node must be retared: remove stone → hub sends CMD_TARE → clean tare → stone back
READING_STALE_S: 1800 (deployed)
WiFi power save: OFF (systemd service active)
```

### 3E-009 attempt 2 next steps
1. Remove 20kg stone from platform
2. Verify node is powered — hub will connect and send CMD_TARE (steel_g=null → TARE path correct)
3. Confirm clean tare in node journal: `event=PHASE_COMPLETE phase=TARE result=OK mean=<small value>`
4. Place stone fresh on platform
5. Record: start time (IST), node boot number, hub session number
6. Hub Install cylinder → BOOTSTRAP_ANCHOR → TRACKING
7. Record: anchor mean_gross, steel_g derived
8. Let run unattended 65h minimum — 3 clean runs needed for 3E-009 formal pass

### Gate
Fixes 1-3 DEPLOYED. WiFi power save OFF. 3E-009 attempt 2 ready to launch.

---

## Session 61 — 2026-07-02

### Goal
Verify Session 60 fixes survived, protect 3E-009 attempt 1 data, implement and verify Fix 4, resolve G5/G7 tracking discrepancy, design UNINSTALLED redesign, rewrite session close protocol.

### Real outputs
- CSV export confirmed intact: 7867 rows, all states present.
- Fix 2 confirmed survived reboot — WiFi power save still OFF.
- Fix 4 (esp_reset_reason + heap_caps_get_largest_free_block) implemented in journal.cpp, compiled clean (46% flash, 7% RAM), flashed via Arduino IDE, verified live on boot 45.
  - reset=OTHER — expected for USB/esptool-triggered reset, not a fault.
  - heap_max_block=114676 bytes, flat across 14+ heartbeats — clean baseline, no fragmentation.
- N-TARE-CHECK and HEAVY_LOAD_THRESHOLD_G=2000.0f confirmed already implemented in firmware prior to session — no new code needed, verified by direct source read.
- G5/G7 tracking discrepancy resolved: neither is built; old git commit message was pre-ESP32-pivot and does not reflect current hub/python/ state.
- UNINSTALLED redesign (CYLINDER_ABSENT intermediate state + weight-matching + explicit button flow) fully designed but not implemented — blocked on one product-decision question.
- SESSION_CLOSE_PROTOCOL.md rewritten to v2.

### Gate
3E-009 attempt #2 deliberately deferred — a decision, not a failure. Stability confidence to be built via 2-3 more attempts first.

---

## Session 62 — 2026-07-02 evening through 2026-07-03

### Goal
Verify Session 60/61 fixes survived, protect and analyze 3E-009 attempt 1 data, launch and monitor attempt 2, diagnose a real 41-minute BLE staleness event, design and lock the CYLINDER_ABSENT redesign and full Cooking Intelligence (whistle-event tracking) feature, correct multiple earlier findings against real source/log evidence, launch attempt 3 for a 3-night unattended run.

### Real outputs
- Fix 2 proven durable across a genuine hard power-cycle (not just a soft reboot) via NM connection profile (`nmcli powersave 2`) + NM dispatcher script; setup.sh patched to auto-apply this on any future board/network with zero hardcoding.
- Attempt 2 ran ~14h38m with one watchdog-triggered reboot at 5h16m — escalation timing matched pure arithmetic prediction to 9 seconds; root cause of the underlying BLE silence in the predicted window never conclusively identified (kernel log empty in that window).
- health.cpp stuck-check confirmed structurally non-functional since inception: tare.cpp PHASE2 never computes variance, so `g_tare_variance_raw` stays `0.0f` forever, auto-passing every boot. Fix fully specified but deliberately not flashed — pending real variance data from attempt 3.
- G5 Analytics status corrected: burn rate and days-remaining confirmed live in production logs, contradicting the earlier "not built" finding from Session 61.
- CYLINDER_ABSENT redesign and Cooking Intelligence (whistle-event tracking) feature designed and locked.
- Multiple earlier findings corrected against real source and log evidence.

### Gate
Attempt 3 launched 2026-07-03 16:07:59 IST after a full physical power-cycle reset (node boot=47, reset=POWERON) — 3-night unattended run, result pending at session close, to be evaluated at start of Session 63.
