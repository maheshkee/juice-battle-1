# LEARNINGS.md — Locked-In Truths

Entries here are permanent. New entries added only after a CONCLUSION.md is written and experiment is marked complete in PLAN.md.

---

## Pre-Experiment Knowledge

The following are supported by datasheet analysis and reference driver study but have NOT yet been verified on hardware. Hardware verification status noted per entry.

---

### HX711 Conversion Behavior — H1 CONFIRMED

**Claim**: HX711 freezes until MCU reads — DOUT stays LOW after conversion until all 24 bits + gain pulses are clocked out. Next conversion starts only after the read is complete.

**Source**: AVIA HX711 datasheet Fig.2 + hardware verified 2026-05-02, experiment 001-freeze-test.

**Hardware verification**: CONFIRMED — 2 runs, AQ3 board, DT=D7 SCK=D6
- DOUT stayed LOW for 30 unbroken seconds with no SCK pulses (both runs)
- S2 = frozen value in both runs — weight placed during pause was not captured
- DOUT went HIGH at +0 ms after MCU read — read is the only trigger for a new conversion
- S3 captured the weight placed during the pause (first conversion after the pause ended)

**Impact**: MCU read rate = conversion rate. No background sampling. If loop() never reads, the HX711 never converts again. Skipping a read delays the next conversion — it does not lose data. 500 ms read interval (digital-scale) is correct and sufficient.

**Observed anomaly**: After a 30-second freeze, first new conversion took ~552 ms instead of expected ~100 ms. Likely RATE pin state or post-idle settling. Does not affect normal operation (reads every 100–500 ms).

---

### Sigma-Delta Architecture

- HX711 is NOT a simple averaging ADC
- Internal 1-bit modulator + decimation filter
- 10 Hz output rate = ~100,000:1 oversampling ratio
- More oversampling time = less quantization noise
- 80 Hz mode = ~4× noisier per sample than 10 Hz (less decimation time per sample)

**Hardware verification**: Not required — fundamental ADC architecture, verifiable from datasheet.

---

### HX711 Electrical Specs (gain 128, 5V AVDD)

| Parameter | Value |
|-----------|-------|
| Full scale input | ±20 mV |
| Input noise (10 Hz) | 50 nV rms |
| CMRR | 100 dB |
| PSRR | 100 dB |
| Power-up settling time | 400 ms |
| Channel change settling time | 400 ms |

---

### Corrupt Reading Signatures

| Raw value | Cause |
|-----------|-------|
| 0x7FFFFF | Pin conflict or input out of range |
| 0x800000 | Pin conflict or input out of range |
| -1 | Can be a valid ADC reading (all 24 bits = 1, near minimum range). Also seen when HX711 not ready — confirm DOUT was LOW before reading to distinguish. |
| Fixed cycling value | Free end of load cell is touching surface |

---

## Experiment-Verified Entries

### 001-freeze-test (2026-05-02) — HX711 freeze behavior confirmed
See full evidence in `hx711/001-freeze-test/CONCLUSION.md`.

---

### 006-water-spoon-test Part A (2026-05-02) — Gram-level detection confirmed

**Calibration factor**: 103.02 raw/g
- Hardware: AQ3, 20kg load cell, gain 128, 10 Hz, D7=DT D6=SCK
- Derived from: tare=-13086 raw, 130g cup=306 raw → (306−(−13086))/130

**Tare offset**: ~-13086 raw (empty scale, this hardware)
- Raw offset is large (~100× a gram's worth of counts) — tare is mandatory before any gram conversion
- Do not attempt to interpret raw values without subtracting raw_zero first

**Detection floor so far**: 5.35g cleanly detected with 20-sample averaging
- Noise floor not yet measured (002-noise-baseline pending)
- Both ~5–6g removals showed consistent negative deltas with no sign scatter — noise is well below 5g

**Calibration method**: 2-point (empty + one known weight)
- Formula: `grams = (raw - raw_zero) / cal_factor`
- Single known weight is sufficient at this precision level

**20-sample averaging at 100 ms**: sufficient for stable gram-level output (2s per reading)

See full evidence in `hx711/006-water-spoon-test/CONCLUSION.md`.

---

## Hardware-verified learnings — 2026-05-02

### L1: HX711 freeze behavior confirmed (experiment 001)
H1 is true. HX711 freezes after each conversion. DOUT stays LOW
indefinitely until MCU reads 24 bits + 25th gain pulse.
Evidence: S1=S2=-1 after 30s stall. DOUT LOW all 30 seconds.
S3=10308 (first fresh read after resume reflects current weight).

### L2: Post-stall settling = 554ms
After long stall, first conversion takes 400-554ms (not 100ms).
Datasheet spec: 400ms settling after reset. Normal. Subsequent
conversions return to 100ms rate immediately.

### L3: 25th pulse triggers next conversion at +0ms
The 25th SCK rising edge in hx711_read_raw() causes DOUT to go
HIGH immediately (+0ms measured). HX711 resets and starts fresh
100ms window instantly. Baked into every read call automatically.

### L4: Calibration factor = 103.02 raw/g (this hardware, 2026-05-02)
Tare (empty scale) = -13086 raw units
Formula: grams = (raw_value - (-13086)) / 103.02
Verified twice. Consistent to ±0.2 raw/g.
WARNING: tare changes if load cell moved/remounted. Recalibrate then.

### L5: 20-sample average detects 5.35g changes cleanly
Smallest verified detection: 5.35g from 130g water cup.
Signal was clean, not noise-limited at this averaging level.
Noise floor characterization still pending (experiment 002).

### L6: Monitor.begin() blocks MCU forever (App Lab)
Monitor.begin() sends synchronous RPC to Python (mon/connected).
Without registered Python handler, MCU hangs before any output.
Fix: Bridge.notify("log", msg) + Python Bridge.provide("log", handler).

### L7: user_loop is correct Python polling pattern
Threading (daemon threads) fails silently in App Lab Docker.
Correct: App.run(user_loop=my_loop) where my_loop polls state.

### L8: delay(3000) before Bridge.begin() in setup()
Python container needs ~3s to start. Without pre-delay, Bridge
handshake may fail or produce unstable connection.

### L9: Bridge.provide_safe() required for blocking MCU handlers
Handlers blocking >100ms must use provide_safe() not provide().
20 reads × 100ms = 2s — always use provide_safe() for HX711 reads.
Never call Bridge.notify() from inside a provide_safe() handler.

### L10: Symlink required for nested experiment apps
arduino-app-cli only looks one level deep under ~/ArduinoApps/.
Every experiment app needs: ln -s .../app ~/ArduinoApps/APP_NAME
APP_NAME pattern: sensor-NNN-name (e.g. hx711-001-freeze-test)
