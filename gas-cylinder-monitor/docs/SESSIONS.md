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
