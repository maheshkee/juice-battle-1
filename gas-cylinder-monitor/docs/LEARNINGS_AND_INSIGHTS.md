# Learnings and insights - gas cylinder monitor
# Purpose: deep first-principles understanding from real sessions.
# Not architecture. Not plans. The WHY behind every decision.
# Add new learnings each session. Never delete - mark superseded if outdated.

---

## L-001 - HX711 CMOS output level rule - 2026-06-04

### The rule
HX711 is a CMOS chip. Output logic high is driven from VCC through a P-channel transistor.
No internal voltage regulator for logic levels. Output high = VCC. Always.

### Consequences
- HX711 VCC = 5V → DOUT high = ~5V → damages ESP32-C3 GPIO (max 3.6V absolute)
- HX711 VCC = 3.3V → DOUT high = ~3.3V → safe for ESP32-C3 GPIO
- Fix: power HX711 VDD at 3.3V. DOUT automatically becomes 3.3V. No level shifter needed.

### Why STM32 UNO Q was safe at 5V but ESP32-C3 is not
UNO Q HX711 was wired to STM32U585 pins D6/D7 - labelled 5V-tolerant in STM32U585 datasheet.
Input protection diodes handle 5V without damage.
ESP32-C3 GPIO has no 5V tolerance. Absolute maximum input = 3.6V. No protection diodes.
Same HX711, same 5V, different MCU = different outcome.

### Why ESP32 5V pin cannot power HX711 anyway
ESP32-C3 5V pin = direct passthrough from USB VBUS. Not a regulated output.
- USB powered: ~4.8-5.1V (unregulated, whatever USB provides)
- Battery powered: gives nothing (becomes an input)
- No current limiting, no protection
Even if 5V were safe for GPIO, the ESP32 5V pin is the wrong source for a sensor.

### Verified
2026-06-04: GISLAB HX711 at 3.3V VDD → clean reads, zero corrupt values. Confirmed.

---

## L-002 - HX711 performance: 3.3V vs 5V - 2026-06-04

### The physics
HX711 internal ADC reference is derived from VCC. Full-scale input range = ±0.5 × AVDD / GAIN.

At VCC=5V, gain 128:   ±0.5 × 5.0 / 128 = ±19.5 mV full scale
At VCC=3.3V, gain 128: ±0.5 × 3.3 / 128 = ±12.9 mV full scale

A 20kg load cell at full load outputs ~10-15 mV. Both ranges cover it. No clipping either way.

### Noise
HX711 datasheet: ~50 nV RMS input-referred noise at gain 128. Independent of VCC.
Noise comes from thermal noise of input amplifier - not the supply rail.

### Verdict for our use case
| | 5V | 3.3V |
|---|---|---|
| Full-scale range | ±19.5 mV | ±12.9 mV |
| Internal noise | ~50 nV RMS | ~50 nV RMS |
| Risk to ESP32 GPIO | destroys it | safe |

For a 20kg load cell with 6g event threshold, resolution difference is invisible.
Dominant noise = mechanical vibration and load cell creep, not ADC quantisation.
3.3V is a free lunch: same effective performance, no GPIO damage risk.

---

## L-003 - Wheatstone bridge: why raw is negative unloaded - 2026-06-04

### What a load cell is
Four strain gauges in a diamond (Wheatstone bridge).
E+ and E- power the bridge with a known voltage.
Weight applied → two gauges stretch (R increases), two compress (R decreases).
Bridge unbalances → tiny differential voltage on A+ and A- (microvolts to millivolts).
HX711 amplifies this (gain 128) and digitises to 24 bits.

### Why raw is negative when unloaded
Ideal bridge: all four resistors perfectly equal → unloaded A+ = A- → output = 0V → raw = 0.
Real world: manufacturing variations → resistors never perfectly equal.
Unloaded: A- slightly higher than A+ → HX711 reads small negative number.
This is the tare offset. Normal, expected, consistent per unit.
It is NOT an error. Tare subtraction removes it.

### Verified
2026-06-04: Unloaded raw = -15200 to -15423.
With 30g: -11620 to -11872. Delta ~3400 raw for 30g → rough cal_factor ~113 raw/g.

---

## L-004 - HX711 bit-bang protocol: five non-negotiables - 2026-06-04

### Rule 1: Wait for DOUT LOW before clocking
DOUT HIGH = HX711 still converting. Cannot clock early.
DOUT is open-drain - HX711 pulls LOW to signal ready, floats otherwise.
INPUT_PULLUP mandatory: floating DOUT reads random noise = false ready signals = garbage bits.

### Rule 2: Sign-extend bit 23
HX711 outputs 24-bit two's complement. Bit 23 is the sign bit.
Without sign extension: negative reading appears as large positive number (>8 million).
Fix: if (value & 0x800000) value |= 0xFF000000;

### Rule 3: Three corrupt filters - always, all three, every read
- LONG_MIN (-2147483648): timeout sentinel - DOUT never went LOW in 200ms
- -1 (all 24 bits HIGH): HX711 not ready when we clocked it
- 0x7FFFFF (positive saturation): wiring or VCC problem on analog path

### Rule 4: noInterrupts() during the entire 25-pulse sequence
HX711 counts SCK pulses to set channel and gain for the NEXT conversion:
- 25 pulses = Channel A, Gain 128 (what we want)
- 26 pulses = Channel B, Gain 32
- 27 pulses = Channel A, Gain 64
ISR firing between pulses adds an unintended pulse → wrong gain → corrupted readings.
noInterrupts() for the full 25-pulse window is mandatory.

### Rule 5: 25th pulse is not optional
Locks Channel A / Gain 128 for next conversion. 24 pulses only = undefined gain state.

---

## L-005 - Arduino IDE setup for ESP32-C3 SuperMini - 2026-06-04

### Board package
- Use: esp32 by Espressif Systems v3.0.7
- DO NOT use v3.3.9 - flasher.exe missing on Windows (confirmed bug 2026-06-04)
- DO NOT use Arduino ESP32 Boards by Arduino - different unofficial port
- Board URL (add as new line in Preferences, do not replace existing URL):
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

### Board settings
- Board: ESP32C3 Dev Module
- USB CDC On Boot: ENABLED - mandatory for Serial output
  SuperMini has no CH340/CP2102. Uses native USB directly.
  Without this enabled: flashes successfully but Serial Monitor gets nothing.
- Port: COM11 (Windows shows "ESP32 Family Device, Ozobot DRVKit" - correct, ignore the name)

### First flash procedure
1. Hold BOOT button on ESP32-C3
2. Click Upload in Arduino IDE
3. Release BOOT after 2 seconds
Why: no bootloader sketch exists on first flash to auto-enter flash mode.
All subsequent flashes: automatic. No BOOT button ever again.

### LED indicators on SuperMini
- Red LED: power indicator. Wired to 3.3V rail. Always on when USB connected. Not code-controlled.
- Blue LED: connected to GPIO8. On at boot by default. Controllable by sketch.
- Rule: GPIO8 = blue LED pin only. Never connect external devices to GPIO8.

### Strapping pins - never connect external devices
- GPIO2, GPIO8, GPIO9: determine boot mode at startup
- External pull-down during boot can force flash mode or prevent normal boot
- GPIO12-17: internal flash, not broken out on SuperMini

---

## L-006 — Complete measurement mental model — 2026-06-04

### The measurement equation
grams = (raw - tare) / cal_factor
Everything in the system exists to get tare and cal_factor right.

### Raw counts
HX711 outputs a 24-bit integer. No units, no meaning in isolation.
Represents: voltage difference between A+ and A-, amplified 128x, digitised to 24 bits.
Meaning only comes from subtracting tare and dividing by cal_factor.

### Tare — the zero reference
Raw count when nothing is on the scale.
Exists because the Wheatstone bridge has manufacturing offset — never perfectly balanced.
Must be derived BEFORE cal_factor — cal_factor derivation depends on it.
If tare is wrong → cal_factor is wrong → every gram reading is wrong. Error compounds.
Derived: mean of N=50 unloaded samples per boot.

### Cal_factor — the conversion constant
How many raw counts equal one gram on this specific hardware combination.
Absorbs: load cell sensitivity, HX711 gain, actual VCC voltage, mechanical mounting.
Derived: (loaded_mean - tare) / known_weight_grams
Hardware-specific — never carry across MCU or hardware changes.

### Why mean, not mode or RMS
HX711 noise is Gaussian — random thermal and electrical noise, symmetrically distributed.
For Gaussian noise, mean is the maximum likelihood estimator of true value.
Mean uses all samples equally and converges to truth as N increases.
Mode ignores most data. RMS amplifies outliers. Mean is the right tool.

### Why N=50 production, N=200 experiments
Standard error of mean = std / sqrt(N)
At N=50:  SE = std / sqrt(50)  → ~10% error on event threshold → acceptable for production
At N=200: SE = std / sqrt(200) → ~5% error → tighter, needed for sensor characterisation
Beyond N=200: diminishing returns. Halving error again requires N=800. Not worth it.
Below N=50: mean too noisy to trust as tare or cal reference.

### Noise floor — why per boot, not hardcoded
Noise std is not constant. Same hardware, same room: std=1.4g one morning, 2.3g that evening.
Causes: temperature, vibration, USB power quality variations.
Hardcoded threshold → either misses real events or triggers on phantom ones.
Per-boot characterisation → threshold always set relative to actual noise of this run.
Threshold = 4σ (four times measured std) = 4x safety factor above noise.

### Temperature effect
Load cell strain gauge resistors have a temperature coefficient.
Resistance changes with temperature → tare drifts (zero shifts) + cal_factor drifts (sensitivity changes).
These are slow drifts — hours to seasons, not minute to minute.
Defence: re-derive tare every boot (catches slow zero drift).
Cal_factor drift: detected by 30-day trend line, triggers recalibration when needed.

### Sliding window delta detector
Single-sample threshold fails for slow consumption (cylinder loses ~50g over 30 minutes —
no single sample looks different enough from the previous one).
Sliding window: compare mean of last N samples (window_A) vs mean of N samples before that (window_B).
delta = window_A - window_B
If delta exceeds threshold → real weight change detected.
Smooths noise, detects trends invisible sample-by-sample.
The right question is not "is this reading different?" but "is the average changing over time?"

### Why 5% gate for E-001
5% of 30g calibration weight = 1.5g error tolerance.
1.5g is within the noise floor → if we pass this gate, calibration is in the right ballpark.
Not a precision engineering tolerance — a sanity gate before moving forward.

---

## L-007 — Re-evaluation rules: what must be re-derived and when — 2026-06-04

### Rule
Any time hardware, firmware, or physical setup changes — certain values become VOID and
must be re-derived before trusting any readings. Never carry numerical values across
hardware changes.

### List A — Must re-derive on EVERY boot (automatic, built into firmware)
These change run-to-run even on identical hardware. Firmware handles this automatically.
- Tare (mean of N=50 unloaded samples)
- Noise floor std (std of same N samples)
- Event detection threshold (4 × noise std)

### List B — Must re-derive when hardware or physical setup changes
These are stable within a setup but become void if anything physical changes.
Trigger: any of the items in the "what counts as a setup change" list below.
- cal_factor (raw counts per gram)
- Noise std baseline (the expected typical range)
- Event threshold baseline

### What counts as a setup change (triggers List B re-derivation)
- MCU change (STM32 → ESP32, or any other MCU swap)
- HX711 module swap (even same model — manufacturing variation)
- Load cell swap (even same model — sensitivity varies unit to unit)
- VCC voltage change (5V → 3.3V or vice versa — changes full-scale range)
- Number of load cells changes (1 cell → 4 cell summing)
- Mechanical mounting changes (load cell repositioned, platform changed)
- Long-term temperature drift detected (30-day trend line triggers recalibration)
- Cylinder brand change (for tare/steel values — not cal_factor, but worth noting)

### Values confirmed VOID from STM32 era — must re-derive on ESP32
| Value | STM32 value | Status | When re-derived |
|---|---|---|---|
| cal_factor | 106.7 raw/g | VOID | E-001 |
| Noise std | ~1.87g | VOID — re-measure | E-002 |
| Event threshold | 6g | VOID — re-derive from new std | E-002 |
| Tare range | -13744 to -14551 raw | VOID | E-001 boot |
| N=50 SE margin | ~0.26g (10% of 6g) | VOID — recalculate after E-002 | E-002 |

### The invariants — what never changes regardless of hardware
These are mathematical/physical laws. They do not need re-derivation.
- Mean is the correct estimator for Gaussian noise
- SE = std / sqrt(N) relationship
- The measurement equation: grams = (raw - tare) / cal_factor
- Three corrupt filters: LONG_MIN, -1, 0x7FFFFF
- Sign extension rule: bit 23 is the sign bit
- 25th SCK pulse locks Channel A Gain 128
- Wheatstone bridge physics (unloaded raw is negative due to manufacturing offset)
- Sliding window delta detection principle
- 4σ safety factor for threshold setting

---

## L-008 - cal_factor signal-to-noise regime boundary - 2026-06-05

### The finding
cal_factor derived from a reference weight below ~100g is unreliable on this hardware.
cal_factor derived from weights above ~200g is stable to within 0.6%.

### Why
cal_factor = (loaded_mean - tare) / known_weight_g
The numerator (loaded_mean - tare) is the signal.
The noise floor of this system is roughly ±2g peak.

For 10g reference weight:
  signal = 10g × 105 raw/g ~ 1050 raw
  noise = ±200 raw peak
  SNR = 1050 / 200 = 5.25 - noise is 19% of signal

For 227g reference weight:
  signal = 227g × 105 raw/g ~ 23835 raw
  noise = ±200 raw peak
  SNR = 23835 / 200 = 119 - noise is 0.8% of signal

When SNR is low, the 50-sample mean is still contaminated by noise.
The computed cal_factor absorbs that noise as error.
Above ~200g, SNR is high enough that the mean converges reliably.

### Rule
Always derive cal_factor from a reference weight that produces
a signal at least 20× the peak noise. For this system: reference weight > 150g minimum.
For production first-boot calibration: use the known steel weight (~15kg) as the reference.
The cylinder itself is the calibration weight - massive SNR advantage.

### Verified
Hardware confirmed 2026-06-05. 8-weight linearity run.

---

## L-009 - Load cell mechanical creep and the settle window - 2026-06-05

### The finding
When a weight is placed on a load cell, the raw reading does not immediately
settle to its final value. It creeps over several seconds.
If sampling begins too soon after placement, the 50-sample mean is pulled toward
the mid-creep value, not the settled value. This produces a wrong cal_factor.

### Why
Load cells are metal structures under mechanical stress (strain gauges bonded to a beam).
When a load is applied, the metal deforms elastically - but not instantaneously.
The metal creeps: it continues deforming slowly over 5-15 seconds as internal
stress redistributes. This is a physical property of the material, not electronics.
The HX711 faithfully reports this creep as a slow drift in raw values.
The first few seconds of readings after placement are systematically biased low
(the beam has not fully deformed yet), then the readings stabilise.

### The fix
Wait 10 seconds after the user signals weight is placed, before taking the 50 samples.
At 10 seconds, the beam has reached mechanical equilibrium.
The 50 samples then represent the true settled load, not the creep transient.

### Rule
Any calibration sampling (tare or cal_factor derivation) must happen only after
a minimum 5-10 second settle window following load change.
Tare settle is handled by waiting for stable readings before boot sampling.
Cal_factor settle is handled by explicit 10s delay after keypress.

### Verified
Hardware confirmed 2026-06-05. Previous bad cal_factor runs had no settle window.
Runs with 10s settle produced consistent, reproducible cal_factor values.

---

## L-010 - Why noise profiles differ across MCUs - 2026-06-08

Five noise sources change when the MCU changes, even with identical HX711 and load cell:

1. Power supply: HX711 uses VDD as its ADC reference. USB-powered ESP32-C3 SuperMini
   LDO ripple differs from AQ3 board-regulated 3.3V. Different ripple = different noise.

2. SCK timing: HX711 protocol is pulse-count based. ARM Cortex-M33 (STM32) and
   RISC-V RV32IMC (ESP32-C3) have different instruction pipelines. Even with identical
   delayMicroseconds(1), actual pulse width differs. Different pulse accuracy = different
   gain-bit reliability.

3. GPIO drive strength: Edge slew rate differs between STM32 and ESP32-C3 GPIO output
   drivers. Slower edges give HX711 ambiguous timing at the SCK transition point.

4. Interrupt latency: ESP32-C3 runs FreeRTOS with WiFi/BLE radio tasks. Even with
   noInterrupts(), radio subsystem has its own task context. STM32 AQ3 MCU side has
   no radio - cleaner interrupt environment.

5. Physical wiring: STM32 AQ3 used PCB traces (D7/D6). ESP32-C3 SuperMini uses jumper
   wires on breadboard - longer, acts as antenna, picks up more EMI.

Verified: ESP32-C3 measured STD 0.62-0.67g vs STM32 1.87g. ESP32-C3 is cleaner -
likely because USB LDO happens to be quieter for this specific HX711 module.
Rule: never carry STD or threshold values across MCU changes. Always re-measure.

---

## L-011 - Load cell physics: creep, noise, and why they are different - 2026-06-08

### What a load cell actually is
A metal beam (usually aluminium alloy) with strain gauges bonded to the surface.
When weight is applied the beam bends. Top surface stretches (tension), bottom
compresses. Strain gauges convert deformation to resistance change. HX711 measures
the differential resistance and outputs a 24-bit raw count.

### What is mechanical creep
Metal is not perfectly elastic. When stress changes (weight placed, weight removed,
power cycle causing temperature change in circuit), metal crystals slowly rearrange
toward a new equilibrium. This takes 30 seconds to several minutes depending on
previous stress state and temperature. Output during creep = slow directional drift -
always moving toward true zero, never random.

### What is electronic noise
Random fluctuation from thermal agitation in resistors, ADC quantisation, power
supply ripple, EMI coupling from wires. Has no direction - equally likely up or down.
Described by STD. Magnitude independent of previous state.

### Why they are completely different problems
Creep: slow, directional, deterministic, decreases over time, depends on history.
Noise: fast, random, stationary, constant magnitude, independent of history.

What you read = creep + noise superimposed. STD computed during creep is inflated
because the slow drift looks like variance. Must wait for creep to finish before
measuring true noise floor.

Verified: E-002 v1 fixed timer gave STD 0.53-3.43g depending on creep state at
sample time. E-002 v3 dynamic detection gave STD 0.62-0.67g consistently.

---

## L-012 - Why a fixed timer fails for stability detection - 2026-06-08

A fixed timer assumes settle time is constant. It is not. Settle time depends on:
- How long the load cell was powered off (longer off = more creep recovery needed)
- Previous mechanical stress state (heavy load, sudden removal)
- Ambient temperature (changes beam stiffness)
- Whether the platform was disturbed between runs

Same 5-second timer fired during: mid-heavy-creep (run 1: STD 3.43g),
mid-moderate-creep (runs 3-5: STD 0.86-1.56g), already-settled (run 2: STD 0.53g).
Same code, same hardware, wildly different results.

Dynamic stability detection solves this: watch the data, not the clock.
Physics tells you when it is done - not a guess.

---

## L-013 - Dynamic stability detection: two conditions required - 2026-06-08

One condition is not enough. Spread-only check can be fooled by slow creep where each
20-sample window looks internally flat but the mean drifts steadily between windows.

Two conditions both required:
  Condition 1: max - min within window < 2.5g (internal spread check)
  Condition 2: |mean(window_N) - mean(window_N-1)| < 1.0g (inter-window drift check)

Both must pass for stable_count to increment. Either failing resets stable_count to 0.
Three consecutive windows both-passing = settled.

Why 2.5g spread: above true noise pp (~3g) but below any creep contribution.
Why 1.0g mean drift: creep moves the mean; noise does not move it systematically.
Why 3 consecutive: three windows = 60 samples = 6 seconds of sustained quiet.

Verified: 2.42g spread windows with 0.00-0.08g drift = settled, STD 0.62-0.67g.

---

## L-014 - Tare must be derived after stability, not before - 2026-06-08

Tare is subtracted from every reading: grams = (raw - tare) / cal_factor.
If tare is wrong by X raw counts, every gram reading is shifted by X/cal_factor grams.

When tare is derived before stability detection:
- 20-sample mean is contaminated by creep at that moment
- Creep amount at that instant becomes a permanent offset in all subsequent readings
- Mean of characterisation block != 0g

When tare is derived after stability detection:
- Platform is genuinely settled
- 20-sample mean captures true mechanical zero
- Mean of characterisation block ~ 0g

Observed: tare-before gave means of 1.06g to 2.89g across consecutive re-upload runs.
Tare-after with clean rest gave tare correction of 17-38 raw (0.16-0.36g) - very small.
In production: tare offset does not affect gas% accuracy. Hub computes consumption
from delta between readings. Constant offset cancels in subtraction.

---

## L-015 - Why N=200 for noise characterisation - 2026-06-08

STD of a sample is an estimate of true population STD. Estimate has uncertainty:
  SE(STD) = STD / sqrt(2N)

At N=200: SE = STD / 20 = 5% of STD - threshold accurate to ±5%
At N=20:  SE = STD / 6.3 = 16% of STD - threshold could jump ±16% boot to boot
At N=500: SE = 3% - marginal gain, 50-second boot time not justified

HX711 at 10Hz = 100ms per sample. N=200 = 20 seconds boot time.
N=200 is the best accuracy-vs-boot-time tradeoff on this hardware.

---

## L-016 - Why 4xSTD for event detection threshold - 2026-06-08

Noise follows a Gaussian distribution. Threshold is the line beyond which a reading
is declared a real event rather than noise.

At 4s: probability of pure-noise crossing threshold = 0.0063% per sample.
At 15-min heartbeat (production): 0.0063% x 96 readings/day = 0.006 false/day.
At 3s: 0.27% - one false trigger every ~2 days at heartbeat rate - too many.

4s is the engineering standard across semiconductor, finance, and process control.
Tight enough to catch real events, loose enough to reject noise comfortably.
Our threshold 2.67g vs 16g planning estimate = 6x detection margin.

---

## L-017 - Why 500ms between readings in the live loop - 2026-06-08

Two constraints define the 500ms choice:

1. HX711 hardware floor: RATE pin LOW = 10Hz = one new conversion every 100ms.
   Reading faster than 100ms returns stale data - DOUT stays HIGH (not ready) and
   the read function blocks. Cannot go faster than 100ms on this hardware.

2. Human readability: live loop in experiments is a diagnostic tool - you watch it.
   100ms (10/sec): numbers blur, impossible to read patterns.
   500ms (2/sec): comfortable for human observation, trends visible.
   1000ms (1/sec): too slow, misses short transients.

500ms is 5x above hardware floor (safe) and comfortable for human observation.
Production uses 15-minute heartbeat - 500ms is for experiment diagnostic loops only.

---

## L-018 - 16g minimum event is a planning estimate, not a measurement - 2026-06-08

The 16g figure was derived from online LPG consumption averages:
  14.2kg / 30 days = 473g/day
  473g / 2.5hr cooking = 3.15g/min burn rate
  shortest cooking event (tea) = 5 min x 3.15g/min ~ 16g

This is theoretical. Never measured on real hardware in a real kitchen.
Different households, stove types, and cooking habits produce different values.
Status: planning estimate only. Use for system design sizing. Never treat as validated.

Required experiment: E-006B - minimum event measurement.
When: after cylinder installed on load cell in real kitchen.
Protocol: light stove, make tea, record weight before and after. Repeat for shortest
cooking events. Smallest real drop replaces 16g as the validated number.
Also required for future 4-cell summing configuration.

---

## L-019 - cal_factor must be re-verified across full cylinder weight range - 2026-06-08

cal_factor derived in E-001 used ~230g reference. Validates linearity at one point only.
Full operating range: empty steel (~900g) to full cylinder (~15kg). 230g is near the
bottom of this range - linearity across the full range is assumed, not measured.

If cal_factor shifts materially at higher loads (e.g. 105 raw/g at 230g but
103 raw/g at 15kg), gram values at full cylinder are wrong by ~300g. Not acceptable.

Dependency: if E-005 shows cal_factor shifts materially, re-run:
  - E-002 (noise STD is in grams - scales with cal_factor)
  - Any threshold derived from gram values

Required: E-005 - cal_factor linearity across 0-20kg.
Until then: use 105 raw/g tagged [DERIVED - single point, E-005 pending].

---

## BLE TRANSPORT FINDINGS - E-003 (2026-06-08)

### L-020: bleak service_uuids filter not respected on QRB2210 BlueZ backend
Date: 2026-06-08
BleakScanner(service_uuids=[UUID]) is supposed to pre-filter at scan level -
only return devices advertising that UUID. On QRB2210 BlueZ backend, this filter
is passed to BlueZ but not enforced. All nearby BLE devices are returned regardless
(14-15 devices in test environment, only one was the target).
Fix: always apply application-layer name filter after scan:
  matches = [d for d in devices if d.name == config["device_name"]]
Never rely on bleak service_uuids alone on this hardware.
Verified: confirmed on QRB2210 running Debian Linux, bleak 0.21+.

### L-021: MAC address self-provisioning pattern
Date: 2026-06-08
Hardcoding MAC address in code or config is a maintenance trap:
ESP32 hardware replacement, repair, production units, or multi-node expansion
all produce different MACs. Every change requires a code/config edit.
Correct pattern:
  1. config.json starts with device_address: null
  2. First run: scan for device by name, find exactly one match
  3. Cache MAC into config.json automatically
  4. All subsequent runs: use cached MAC (Phase 1 - faster, unambiguous)
  5. If ESP32 replaced: delete device_address from config.json - re-provisions automatically
Zero human intervention. No MAC ever in source code.
Verified: self-provisioned correctly on first run, MAC written to config.json.

### L-022: Noise STD higher with BLE radio running
Date: 2026-06-08
E-002 (BLE stack off): STD 0.62-0.67g
E-003 (BLE stack running): STD 1.81g
Nearly 3× increase. Root cause: BLE radio activity draws pulsed current from
the 3V3 power rail. Each BLE transmission causes a voltage ripple on the rail.
HX711 AVDD and DVDD are both on this rail. Ripple modulates the ADC reference
voltage and appears as measurement noise.
Production consequence: the E-003 values (1.81g STD, 7.24g threshold) are the
correct operating values. E-002 values (0.67g STD, 2.67g threshold) were
measured in a non-production condition (BLE off) and are superseded for
production use. Always characterise noise with BLE running.
Verified: two consecutive stable runs both showed STD 1.81g with BLE active.

### L-023: DEGRADED quality correctly fires during weight placement transition
Date: 2026-06-08
When a weight is placed on the load cell while a 20-sample measurement window
is in progress, the window captures both pre-placement and post-placement samples.
Sigma spikes massively (97.65g observed - vs normal 0.40-0.65g) because the
samples span two completely different weight states.
Quality correctly set to DEGRADED. Hub received it and must not store as a
valid measurement.
This is correct system behaviour - the quality field exists precisely to
protect the hub from trusting readings taken during a transition.
Rule: hub must check quality before storing or computing gas%.
FAILED and DEGRADED readings must not be stored as weight measurements.
Verified: DEGRADED reading observed and correctly propagated to hub.

### L-024: BLE transport best-effort confirmed correct
Date: 2026-06-08
ESP32 discards readings when hub is not connected. Hub receives and timestamps
readings when connected. Reconnect loop functions correctly.
No data loss panic needed for V1 - readings lost during disconnect are
acceptable. Hub reconnects and resumes within seconds.
Best-effort delivery is the right model for a 15-minute heartbeat system.
A reading missed due to a 30-second disconnect window is not a product failure.
Verified: "No hub connected - discarded" messages seen during startup before
hub script was launched. After connection: SENT messages confirmed delivery.

---

## BLE CONCEPTUAL FOUNDATIONS (2026-06-08)

### L-025: Why 128-bit UUIDs - not 16-bit
Date: 2026-06-08
16-bit UUIDs (e.g. 0x180D Heart Rate) are a reserved namespace managed by
the Bluetooth SIG standards body. Using them requires registration and means
your device claims to implement a standardised profile. Two devices using the
same unregistered 16-bit UUID would collide ambiguously.
128 bits = 2^128 possible values (~340 undecillion). A randomly generated
128-bit UUID is statistically guaranteed globally unique. No registration.
No collision possible in practice. Correct choice for all custom/private services.
Rule: always use 128-bit UUIDs for project-specific BLE services.

### L-026: What subscribing to BLE notifications actually means
Date: 2026-06-08
"Subscribing" is not a special BLE command. It is a write operation.
Every notifiable BLE characteristic has a Client Characteristic Configuration
Descriptor (CCCD) attached, at fixed UUID 0x2902.
CCCD is a 2-byte value: 0x0000 = notifications OFF, 0x0001 = notifications ON.
When the hub "subscribes", it writes 0x0001 to the CCCD on the ESP32.
The ESP32 sees this write via the onSubscribe callback, sets deviceConnected=true,
and starts calling notify().
If nobody writes 0x0001, notify() sends nothing regardless of how often it is called.
This is why the ESP32 does not guess whether anyone is listening - it knows,
because the hub physically wrote into its GATT database.

### L-027: Three communication patterns - all required simultaneously
Date: 2026-06-08
No single BLE communication pattern is sufficient for a real IoT product.
Three patterns must run simultaneously:
  Heartbeat (15 min): proves liveness, creates data spine for burn-rate analytics.
    Even "nothing changed" is a data point - it confirms consumption rate.
  Event-driven (immediate): time-sensitive state transitions - cylinder installed,
    cylinder removed, sensor fault. A 15-minute delay on these is unacceptable.
  Request-response (on demand): hub reconnects and needs current state immediately.
    Not waiting 15 minutes for the next heartbeat.
Anti-pattern: continuous streaming (every raw sample transmitted).
  Measurement rate (10Hz) must be separated from transmission rate (15 min).
  Transmitting 10 readings/second wastes BLE bandwidth, floods SQLite, adds no
  information beyond what averaging already provides. Noise is not signal.

### L-028: Event detection ownership - ESP32 vs hub
Date: 2026-06-08
Events are state transitions that need immediate push (bypass heartbeat rhythm).
Event detection ownership follows data ownership:
  ESP32 detects: CYLINDER_INSTALLED (weight jump >8kg), CYLINDER_REMOVED
    (weight near zero), SENSOR_FAULT (quality=FAILED × N reads).
    Reason: ESP32 directly observes these. It sees the raw weight change.
  Hub detects: LOW_GAS (gas% < 20%), CRITICAL_GAS (gas% < 5%).
    Reason: gas% is computed on hub only. ESP32 never knows gas%.
    Node only knows grams. Hub converts grams → gas% using steel from history.
Test for any candidate event: "Would a 15-minute delay on this cause a real problem?"
YES = push immediately as event. NO = heartbeat data spine is sufficient.
"Minimum gas used" (e.g. 16g) fails this test - no urgency. Hub derives
consumption from consecutive heartbeats by subtraction. Not an event.

### L-029: Weight=0 trap - quality=FAILED is not an empty cylinder
Date: 2026-06-08
A sensor fault must never be interpreted as an empty cylinder.
Weight=0 when quality=FAILED means: the sensor cannot produce a valid reading.
Weight~0 when quality=GOOD means: cylinder is empty or removed.
These are completely different situations with completely different responses.
Hub must check quality before computing gas%. A FAILED reading must trigger
a SENSOR_FAULT alert, not a "cylinder empty" alert.
This is why the quality field exists - to carry the node's self-assessment
so the hub can route correctly.

### L-030: Hub discovery strategy - three phases
Date: 2026-06-08
Three approaches to finding the ESP32 on the BLE network, compared:
  Manual: engineer copies MAC from scan output into config.json. Works but
    requires human action on every hardware replacement.
  Service UUID only: scan with UUID filter, connect to whatever matches.
    Fails on platforms where bleak ignores the filter (QRB2210 - L-020).
  Self-provisioning (chosen): null MAC in config → scan by name on first run
    → cache MAC automatically → use MAC on all subsequent runs.
    Survives hardware replacement (delete device_address, re-provisions).
    Zero human intervention. Name is reliable because it is project-controlled.
    Multiple-device safety: if >1 named device found, warn and wait rather
    than auto-selecting the wrong node.

---

## PRODUCTION ENGINEERING PRINCIPLES (2026-06-08)

### L-031: requirements.txt is mandatory for any Python dependency
Date: 2026-06-08
Any Python package installed via pip must be listed in requirements.txt.
Tribal knowledge ("oh you need bleak") is not documentation.
A new engineer or a fresh board must be able to run:
  pip3 install -r hub/requirements.txt --break-system-packages
and have a working environment. The --break-system-packages flag is AQ3-specific
and must be in the documented install command - without it pip3 refuses to
install on Debian system Python.

### L-032: config.json for all runtime parameters - nothing production-variable in code
Date: 2026-06-08
Any value that could differ between installations, change over time, or vary
between production units belongs in config.json - never hardcoded in source code.
This includes: device MAC address, device name, UUIDs, timeouts, thresholds.
Config change = one line edit. Code change = re-test, re-review, re-deploy.
The distinction: structural constants (pin numbers, protocol constants) can
live in code. Operational parameters (which device, how long to wait) belong in config.

### L-033: Plain script before App Lab container - one complexity layer at a time
Date: 2026-06-08
When building a new capability, always prove it works as a plain script
before introducing Docker/App Lab container complexity.
App Lab Docker adds: container isolation, D-Bus access restrictions,
socat socket forwarding requirement, app.yaml configuration.
If the BLE code has a bug AND the socat setup is wrong simultaneously,
you cannot tell which one caused the failure.
Correct order: plain Python script on host → proven working → then migrate
into App Lab container with socat. E-003 followed this correctly.

---

## Session 2026-06-12 - 3E-001 cal_factor characterisation

### L-ESP32-001: Phase 0 settling monitor is mandatory before noise characterisation
Date: 2026-06-12
At cold boot the wooden platform and load cell beams creep under their own weight. Block STD during this drift is 300 to 5000 raw (drift-dominated), not the true hardware noise floor of 70 to 190 raw when settled. Running Phase 1 during Phase 0 drift measures drift rate not noise - all gates derived from it are wrong.
Fix: Phase 0 collects 200-sample blocks and requires 3 consecutive blocks with block_std < 500 raw AND inter-block drift < 500 raw before Phase 1 runs.
Verified: cold boot with shared plate took 60 to 161s to settle on hardware.

### L-ESP32-002: Serial gate skip bug - stale Enter byte in buffer
Date: 2026-06-12
readStringUntil('\n') returns immediately if a newline already sits in the Serial buffer from a prior step. If the stability gate passes quickly after weight removal while you are still pressing Enter from the removal prompt, that byte skips the next placement gate - sketch samples with no weight and produces negative cal_factor.
Fix: mandatory 2000ms delay() before every flush-and-wait gate. Gate cannot open in the first 2s regardless of buffer state. Then double flush: clear buffer → print prompt → block until keypress → clear buffer again.
Verified: all Stage 1/2/3 runs completed with zero gate skips after fix.

### L-ESP32-003: Stability gate must work in raw counts not grams
Date: 2026-06-12
Gram thresholds secretly depend on cal_factor. On 3-cell, cal_factor is ~36 raw/g. On single-cell it is ~107 raw/g. A spread gate of 2.5g equals 267 raw on single-cell but only 90 raw on 3-cell - same gram threshold is 3x tighter raw gate, impossible to pass on equivalent hardware.
Fix: all stability gates in raw counts only. spread_gate = 1.5 x noise_std_raw, drift_gate = 1.0 x noise_std_raw.
Verified: 3-cell platform passes cleanly. Previous gram-based gates on 4-cell platform never converged.

### L-ESP32-004: Window STD not max-min for stability gate
Date: 2026-06-12
Max-min spread is dominated by the single largest outlier in a 20-sample window. One transient causes a reset even when 19 of 20 samples are clean. STD averages squared deviations - one outlier contributes only 1/N of total variance.
Fix: stability gates use window STD via sqrtf(variance) not max-min.
Verified: clean gate convergence in all runs. Previous max-min on 4-cell caused gate to never converge.

### L-ESP32-005: cal_factor scales with cell count - always re-derive
Date: 2026-06-12
Parallel wiring averages signals. N cells in parallel means HX711 bus signal equals average of individual cell outputs. Sensitivity = 1/N of single-cell. This follows from Kirchhoff's Current Law on the Wheatstone bridge outputs.
Measured: single cell ~106.7 raw/g. 3-cell 36.1 raw/g. Predicted 106.7/3 = 35.6. Matches within mounting variation.
Rule: never carry cal_factor across topology changes. Always re-derive after any wiring change.

### L-ESP32-006: SNR minimum 20x for reliable cal_factor derivation
Date: 2026-06-12
cal_factor = stable_delta / ref_weight_g. Error comes from tare noise. Effective noise on a 50-sample mean = noise_std_raw / sqrt(50). At SNR = 20x, percentage error in cal_factor is approximately 5%. Below 20x, individual readings become unreliable.
Hardware confirmation: 100g readings showed ±25% scatter. 200g+ showed ±5 to 8%. The 20x threshold correctly predicted the failure boundary.
Minimum reliable weight: ~150g on this platform.

### L-ESP32-007: Viscoelastic beam recovery time scales with load magnitude
Date: 2026-06-12
YZC-161A beams deform under sustained load and recover slowly after removal - more load means more deformation and longer recovery. This is a material property of the alloy.
Measured: 200g → ~6s recovery. 300g → 10 to 38s. 500g → 24 to 86s.
Production implication: after cylinder replacement, wait at least 90 to 120s before trusting the new tare. Phase 0 + Phase 1 enforce this automatically.

### L-ESP32-008: 3-cell platform is linear 200g to 1800g
Date: 2026-06-12
3 runs, ~80 clean readings from 200g to 1800g, CV = 4.1%. No systematic trend in cal_factor with weight. One cal_factor constant is valid for the entire cylinder weight range (15.5kg to 29.7kg).

### L-ESP32-009: Boot settling time is mass-dependent
Date: 2026-06-12
More mass on the platform means more creep force on the beams and longer time to reach equilibrium. Without plate: 3 to 12s cold settle. With plate: 60 to 161s. Phase 0 handles this automatically - never assume a fixed settle time.

---

## 3-CELL PLATFORM FINDINGS (2026-06-12 to 2026-06-15)

### [2026-06-15] BLE EMI does NOT increase noise on 3-cell parallel platform
**Finding:** Single-cell platform showed 2.7x noise increase when BLE radio active
(0.67g → 1.81g STD). 3-cell platform shows ~1.0x (no meaningful increase):
BLE-off worst case 4.93g, BLE-on worst case 4.64g.

**Root cause from first principles:**
BLE EMI is a common-mode interference - the 2.4GHz burst couples roughly
equally into all conductors near the antenna. On single-cell, one A+ and one A-
wire carry the signal. BLE couples into both, but asymmetrically depending on
wire routing, creating a differential noise component.

On 3-cell parallel, 3x A+ wires are twisted together at the HX711 terminal,
and 3x A- wires are twisted together. BLE couples identically into all 3x A+
wires (they are physically co-located) and identically into all 3x A- wires.
The interference appears as common-mode → HX711 differential input rejects it.

**Rule:** 3-cell parallel wiring is inherently more RF-immune than single-cell.
No RF shielding needed for V1. This is a free benefit of the parallel topology.

**Verified:** 2 BLE-on runs, 2026-06-15. Both matched BLE-off noise range.

---

### [2026-06-15] 3-cell noise floor is dominated by mechanical creep, not electronics

**Finding:** Phase 2 STD varies run-to-run (2.22g to 4.93g) not because of
electronics but because of viscoelastic creep still playing out during the
20-second Phase 2 collection window. The grams_offset is consistently
-1.7g to -3.5g (platform drifts ~3g in 20 seconds even after stability gate passes).

**Root cause:** The stability gate (Phase 0 + Phase 1) detects when drift between
consecutive windows is below a threshold. But slow creep continues below that
threshold. During Phase 2 (200 samples = 20 seconds), this slow drift adds a
trend component that inflates the measured STD.

**Implication for production:** Self-characterisation per boot is essential.
The noise floor varies boot-to-boot depending on thermal history. A hardcoded
threshold would be wrong on some boots.

**Rule:** Never hardcode noise_std_g or threshold_g. Always derive per boot
from Phase 0 → Phase 1 → Phase 2 sequence.

**Verified:** 7 BLE-off runs showing consistent creep pattern, 2026-06-15.

---

### [2026-06-15] cal_factor run-to-run variation on 3-cell is normal and acceptable

**Finding:** cal_factor varies ~34-37 raw/g across boots on healthy hardware.
This is not a measurement error - it is real physical variation from:
1. Weight placement position during calibration (plate flex changes load distribution)
2. Plate seating geometry (1mm shift changes lever arm)
3. Temperature (YZC-161A sensitivity ±0.02%/°C)

**Why acceptable:** cal_factor error cancels in delta calculations. If cal_factor
is 5% wrong, both readings are 5% wrong → delta is still correct. Gas consumption
is always computed as delta, never absolute. Absolute gas% error from cal_factor
is bounded by the ±150g BIS IS 3196 cylinder tolerance anyway.

**Rule:** cal_factor derived once at installation, stored in config.json.
Never recalculate unless hardware changes. HW_VERIFY_3CELL confirms it each boot
without re-running the full 3E-001 procedure.

**Verified:** Multiple sessions, 2026-06-12 to 2026-06-15.

---

### [2026-06-15] Load cell failure detection strategy for production (design locked)

**Three detection methods - implemented in hub code at hub stage:**

**Method 1 - Tare ratio check (automatic, on every cylinder removal):**
After cylinder removal detected, hub reads empty platform raw value.
Compare to tare_raw stored at installation.
  ratio = current_empty_raw / install_tare_raw
  0.85-1.15  → ALL_OK
  0.55-0.75  → ONE_CELL_FAILED (reading ~ 67% of expected, one cell open/shorted)
  0.25-0.45  → TWO_CELLS_FAILED
  otherwise  → UNKNOWN_FAULT

**Method 2 - cal_factor drift check (automatic, on every refill):**
At each refill event, hub estimates gross weight using stored cal_factor.
Full Indian LPG cylinder gross ~ 30-31kg.
If hub reads 20kg → cal_factor has drifted or a cell has failed.

**Method 3 - HW_VERIFY_3CELL lift test (manual, at installation or maintenance):**
Technician runs HW_VERIFY_3CELL sketch. Lift test isolates each cell individually.
Used when fault is confirmed and specific cell identity is needed.

**Physics of failure:** Open circuit or short on one cell → that cell outputs 0.
Parallel bus: V_bus = (V1 + V2 + 0) / 3 = 2/3 of correct. Reading → 67% of truth.
Two cells failed → 33% of truth.

**Rule:** All three methods must be implemented in hub code. Methods 1 and 2
run silently on every removal/refill event without user action.

---

### [2026-06-15] Intermittent connection causes catastrophic cal_factor scatter

**Finding:** During one session, cal_factor values ranged 15.73 to 39.84 raw/g
(2.5x spread). Root cause was one load cell wire making intermittent contact,
causing tare_raw to jump by ~18000 raw (~500g equivalent) between measurements.

**Diagnostic signature:**
- tare_raw jumps suddenly by thousands of raw between iterations (>5000 raw)
- Phase 1 stabilisation takes >50 windows with spikes to 8965 raw STD
- Re-tare after removal takes >60 seconds (108s observed)
- cal_factor varies wildly across iterations

**Fix:** Re-seat all 6 load cell wires into HX711 terminals. Run HW_VERIFY_3CELL.
If Raw Stability CV > 0.5%, the connection is still bad.

**Rule:** HW_VERIFY_3CELL is the first diagnostic step when cal_factor results
look inconsistent across iterations. Raw Stability CV < 0.2% = healthy connection.

**Verified:** 2026-06-15 - hardware fault reproduced then fixed by re-seating.

---
### L-034: cal_factor must be derived in the same boot as measurement
Date: 2026-06-16

cal_factor is a ratio: raw_delta / known_weight = (raw_loaded - raw_tare) / grams.
It should be supply-voltage-independent because V_excitation cancels in the delta.
However, the platform physical state (cell preload, plate position, contact geometry)
can differ between power cycles. This shifts the entire raw baseline by thousands of
counts. A cal_factor derived in boot A and used in boot B is invalid if the platform
state changed. The only safe approach: derive cal_factor and tare in the same boot,
from the same physical state, with the same supply voltage settling.
Verified: cross-boot cal_factor of 31.51 gave 13% error; same-boot cal_factor of
35.98 gave ±0.4% error on identical hardware.

---
### L-035: tare_raw must come from s2_mean not Phase 1 window mean
Date: 2026-06-16

The tare zero reference accuracy determines the floor for all grams readings.
Error of mean = noise_std / sqrt(N). With noise_std_raw = 167 counts:
  Phase 1 window (N=20):  uncertainty = 167/sqrt(20)  = 37.4 counts = ±1.18g
  Phase 2 mean   (N=200): uncertainty = 167/sqrt(200) = 11.8 counts = ±0.37g
Phase 2 already collects 200 valid samples for noise characterisation.
Its mean (s2_mean) is the best zero estimate available at boot — 3× more accurate
than the Phase 1 window mean. Using tare_raw (Phase 1) instead of s2_mean throws
away a free 3× accuracy improvement. Fix: tare_raw_g = s2_mean in handleNoiseCapture().

---
### L-036: E-005 linearity confirmed — 3-cell YZC-161A platform is linear
Date: 2026-06-16

Single-tare experiment with weights at 200g, 700g, 1700g:
  700g:  implied_cf = 31.48 raw/g
  1700g: implied_cf = 31.54 raw/g  (0.19% difference)
The system is linear across 700g–1700g. One cal_factor covers the full cylinder
operating range. Non-linearity was ruled out as a source of error.
200g point excluded — below reliable SNR floor (SNR=24.9 vs 91.8 at 700g).
Minimum reliable weight for cal_factor derivation: 500g or above.

---
### L-037: Minimum reference weight for cal_factor derivation is 500g
Date: 2026-06-16

At noise_std_raw = 167–240 counts:
  SNR at 200g  (raw_delta ~6000):  SNR = 25  — marginal, unreliable
  SNR at 500g  (raw_delta ~16000): SNR = 67  — acceptable
  SNR at 1000g (raw_delta ~32000): SNR = 133 — excellent
Below 500g, noise is a significant fraction of signal. cal_factor measurements
scatter widely (27–37 raw/g observed at 50–190g reference weights).
Above 500g, scatter collapses to <2% across repeated measurements.
Rule: always use ≥500g reference weight for cal_factor derivation.
Ideal: use 1000g for maximum SNR and repeatability.

---
### L-038: Self-calibrating boot architecture — tare + cal_factor in one session
Date: 2026-06-16

A weight measurement system has three unknowns per boot: tare, noise, cal_factor.
Tare and noise must be re-derived every boot (supply voltage variation changes zero).
Cal_factor is physically stable (it is a ratio, cancels supply variation) but only
valid when the platform physical state matches the state during derivation.
The safest architecture: derive all three in one continuous boot sequence.
Phase 0+1+2: tare and noise. Phase 3: cal_factor. Phase 4: running.
This guarantees all three values are consistent with each other and with the
current physical state of the platform. No cross-boot assumptions needed.

---

## Session 2026-06-16 — Design session learnings

### L-039: Threshold derivation principle — set above noise ceiling, not near signal
Date: 2026-06-16

A jump threshold for event detection must sit just above the noise ceiling (max possible false-event weight), not arbitrarily near the signal of interest. For fresh cylinder detection, 6kg sits above 5kg (max plausible kitchen object placed on platform). 10 or 12kg also work but buy nothing extra — they reduce sensitivity margin for no benefit. The rule: find the highest-possible false-event weight, add a safety margin, stop. No reason to go higher.

### L-040: Two-condition AND gate for anchor event detection
Date: 2026-06-16

Single threshold on jump size (ΔG > 6kg) fails on partial-cylinder swaps where a half-full replacement still crosses the jump threshold. Single threshold on absolute weight (G_new > 26kg) fails when a cylinder is already present at boot (no jump to observe). Both conditions together — ΔG > 6kg AND G_new > 26kg — are jointly sufficient and necessary to uniquely identify a fresh full domestic cylinder placement. Either condition alone is insufficient.

### L-041: Cold-start problem is mathematically unsolvable from sensor alone
Date: 2026-06-16

G = S + g is one equation with two unknowns (steel S, gas g). No software can solve it from a single weight reading alone — an external reference is required. The reference is supplied by: BIS law (14.2kg = gas on a fresh full cylinder), stamped tare from the label (V2), or anchor events accumulated across a complete refill cycle (V3 self-heal). Any system claiming to know gas% without a reference has hidden the reference somewhere. V1 deliberately avoids claiming absolute gas% for this reason — only delta tracking, which is reference-free.

### L-042: Delta tracking is immune to unknown steel — works from day 1 in all versions
Date: 2026-06-16

used = weight_earlier - weight_now. Steel S appears in both terms and cancels. Burn rate, consumption sessions, and days_remaining slope are all derived from delta — all exact immediately without knowing S. Only the absolute gas% gauge requires steel to be known. This means V1 can deliver all analytically useful outputs on day 1, even with no prior history.

### L-043: Conservative bias rule — always report lower gas estimate when uncertain
Date: 2026-06-16

Two failure modes: false pessimism (tell user less gas than actual) and false optimism (tell user more gas than actual). False pessimism causes the user to order gas slightly early — minor inconvenience. False optimism causes a gas outage mid-cooking — a major product failure and safety concern. The product must never tell the user they have more gas than they actually do. When uncertain (during V3 self-heal ramp-up, partial cylinder scenarios), round the gas estimate downward. Optimism is always the wrong direction for this product.

---
## L-044 - noise_recompute_sigma(): linear rescaling of stored raw samples
Date: 2026-06-16

When noise characterisation runs before cal_factor is known (boot order:
NOISE before CAL), samples are stored in net raw counts (tare subtracted,
cal_factor not applied). After CAL derives cal_factor, sigma can be
recomputed without re-running hardware measurement.

Why it works: dividing each sample by cal_factor is a linear rescaling.
Var(X/c) = Var(X)/c², so σ(X/c) = σ(X)/c. The sigma computed from
rescaled samples is algebraically identical to what hardware measurement
would produce with cal_factor known upfront.

Cost: two array passes, ~microseconds. Boot time unchanged.

Assumption: only valid when cal_factor=0 path ran during noise char.
If noise_init() ever called after cal_factor is set, stored samples will
already be in grams - calling recompute again would double-divide.
Documented in CLAUDE.md Known assumptions and noise.cpp comment block.
Verified: sigma recomputed = 2.64g consistent with hardware noise floor.

---
## L-045 - Arduino sketch library dependencies must be explicitly documented
Date: 2026-06-16

Arduino IDE does not have a package manager like pip or npm. Missing
libraries produce fatal compile errors with no install guidance. Every
sketch that uses non-core libraries must document them in two places:
1. README.md in the sketch folder - table of library name, author, purpose
2. Comment block at top of .ino - one line per library

This is the Arduino equivalent of requirements.txt.

Required for gas_monitor_v1:
- NimBLE-Arduino by h2zero (BLE GATT server)
- ArduinoJson by Benoit Blanchon (SPIFFS config.json)
- SPIFFS - built into ESP32 core, no install needed

---

## L-046 - Pure function design: why health_check() owns no state
Date: 2026-06-16

**The principle:**
A pure function given the same inputs always returns the same output and owns no persistent state. health_check() is pure - it receives all inputs as parameters and returns a verdict. It never calls hx711 directly and never stores anything between calls.

**Why it matters:**
If health_check() stored prev_gross_g internally as a static variable, the orchestrator could not reset it after a tare event, could not inspect it for debugging, and could not know whether it was comparing against a valid baseline or a zeroed initialisation. Hidden state is invisible to the caller and creates coupling where there should be none.

**The consequence of violating it:**
A static prev_gross_g initialised to 0.0f causes a false FAILED on the first tick - the delta from 0g to ~14000g exceeds any threshold. Adding a first-call skip flag adds a second hidden static, compounding the problem. The orchestrator is now responsible for a system it cannot see.

**The correct design:**
Orchestrator owns prev_gross_g, initialises to -1.0f sentinel (physically impossible for a real gross weight), passes both cur and prev into health_check() every tick. Health judges. Orchestrator updates prev after health returns. Each component has one job.

**Verified:** Health module tested on hardware 2026-06-16. First tick correctly skipped (prev=-1.0f). Subsequent ticks compared correctly.

---

## L-047 - Sentinel value selection: why -1.0f not 0.0f
Date: 2026-06-16

**The principle:**
A sentinel value must be physically impossible for the real system to produce. It signals "no valid data yet" unambiguously. The sentinel must not overlap with any valid measurement.

**Why 0.0f fails as a sentinel:**
- gross_g = 0.0f is a valid reading (empty platform after tare reads near zero)
- cal_factor = 0.0f could appear from a corrupt config.json read
- sigma_g = 0.0f is theoretically possible if variance is exactly zero

Using 0.0f as "no data" means the first valid zero reading gets mistaken for "no baseline" or vice versa.

**Why -1.0f works:**
- gross_g is always >= 0 on this hardware (load cells produce positive output above tare)
- cal_factor is always a large positive number (~37 raw/g on this platform)
- sigma_g is always >= 0 (it is a standard deviation)

-1.0f cannot occur naturally. It is unambiguous.

**Rule derived:** For any sentinel representing "no previous valid value", choose a value that is physically impossible for the measurement being tracked. Document the physical reasoning, not just the chosen value.

**Verified:** Applied consistently to prev_gross_g, prev_cal_factor, prev_sigma_g in gas_monitor_v1.ino. No false triggers observed on first boot.

---

## L-048 - Health module architecture: judge not sensor
Date: 2026-06-16

**The principle:**
The health module is a judge, not a sensor. It receives already-computed values from other modules and returns a verdict. It never touches hardware.

**Why this matters:**
Every piece of data health_check() needs already exists - sigma_g from noise.cpp, tare variance from tare.cpp, cal_factor from cal.cpp, gross_g from weight.cpp. The orchestrator has all of it. Health just inspects it.

If health called hx711 directly, it would have two jobs: reading hardware AND judging state. A change to HX711 pin assignments would then require changes to health.cpp even though health has nothing to do with pins. This is coupling where there should be none.

**The check-to-data mapping:**
- Erratic check → sigma_g from noise.cpp (already computed)
- Stuck check → tare_variance_raw from tare.cpp (already computed - pending tare.h update)
- Cal drift check → cur_cal_factor from cal.cpp + prev from config.json
- Runtime jump check → cur_gross_g and prev_gross_g from weight.cpp + orchestrator

**Rule derived:** A diagnostic module must never acquire its own data. It receives outputs from the modules it monitors and judges those outputs. The seam is the data, not the hardware.

**Verified:** health_check() has zero calls to hx711_read(). All inputs are passed by the orchestrator. Tested on hardware 2026-06-16.

---

## SESSION 003 LEARNINGS — 2026-06-17

### L-049 — Computation modules vs service modules: a critical distinction
Date: 2026-06-17

Pure function rule (from health.cpp): a module that takes inputs and produces 
outputs with no side effects. The same inputs always produce the same output.
Owns no state. Testable in complete isolation.

Service module rule (journal.cpp): a module whose entire job requires tracking 
what happened before. Cannot be stateless by definition. Owns its own internal 
state. The orchestrator calls it but does not manage its internals.

The rule is not "all modules are pure functions." The rule is:
- Computation modules (hx711, tare, noise, cal, weight, health) → pure functions
- Service modules (journal) → own state, encapsulate it completely

Violation: putting journal state (s_prev_quality, s_seq, s_last_hb_ms) in the 
orchestrator would make the orchestrator own implementation details that belong 
to the journal. The orchestrator would need to know about journal internals to 
call it correctly. That breaks encapsulation.

Correct design: journal.cpp owns all its state. Orchestrator calls 
journal_run(grams, sigma, health) — one line, no knowledge of internals.

### L-050 — Event log vs data stream: why transitions beat state
Date: 2026-06-17

A data stream emits state on every tick: 216,000 lines over 6 hours at 10 SPS.
An event log emits transitions: ~750 lines over 6 hours for a clean run.

The insight: a repeated state line carries zero information after the first 
occurrence. If quality=DEGRADED for 10,000 consecutive ticks, lines 2–10,000 
add nothing. The information is in the moment it changed — GOOD→DEGRADED — 
and the context at that moment (grams, sigma, diagnosis).

Rule: log the transition, not the state.

Corollary: heartbeat is the exception — it provides proof-of-life and a 
trend spine even when no events fire. 30s interval gives 2 heartbeats/min 
which is sufficient for both human review and hub analytics.

### L-051 — Serial sequence numbers: why they matter for deployed devices
Date: 2026-06-17

A log without sequence numbers cannot detect dropped lines, out-of-order 
delivery, or device resets mid-log. With #SEQ:
- Gap in sequence → line dropped or corrupt
- Sequence reset → device rebooted
- Combined with boot=B: #0047 boot=3 is globally unique across all boots

The sequence counter must NOT be persisted to flash because flash has 
limited write cycles (~10,000–100,000). Persisting a counter that increments 
hundreds of times per boot would exhaust flash in days. Solution: RAM-only 
counter that resets to 1 on every boot. boot=B provides the cross-boot 
identity.

### L-052 — Boot phase timing reveals actual hardware behaviour
Date: 2026-06-17

Before 1C: boot duration was unknown. After 1C, first real measurement:
SETTLE=2.1s, TARE=21s, NOISE=20s. 

The 21s and 20s for TARE and NOISE are not arbitrary — they are 
200 samples × 100ms per sample (HX711 at 10 SPS). This confirms the 
HX711 sample rate is exactly 10 SPS as per datasheet. No drift, no 
timing error. The math matches perfectly.

This is the value of timing instrumentation: it either confirms theory 
(as here) or reveals a discrepancy that demands investigation.

---

### L-053 — QRB2210 BlueZ: InterfacesAdded UUID filter is ignored
Date: 2026-06-17

On QRB2210 BlueZ backend, SetDiscoveryFilter with UUIDs array is silently
ignored. The InterfacesAdded signal fires for ALL devices regardless of
UUID filter. UUIDs field in the signal payload is also empty — it is only
populated after ServicesResolved, which happens post-connection.

Rule: Never match on UUID in InterfacesAdded on this platform.
Always match on device Name instead.

Fix applied: changed _interfaces_added() to check name == DEVICE_NAME
instead of SERVICE_UUID in uuids.

### L-054 — QRB2210 BlueZ: cached devices don't re-trigger InterfacesAdded
Date: 2026-06-17

BlueZ only fires InterfacesAdded for newly discovered devices. If a device
was seen in a previous session (bluetoothctl, previous app run), it exists
in BlueZ's managed objects cache but fires no signal on the next scan.

The hub would scan forever, seeing the node via RSSI updates but never
getting the InterfacesAdded callback.

Fix: added _check_known_devices() called via GLib.idle_add() immediately
after _start_scan(). It walks GetManagedObjects() at startup and connects
to any already-known device matching DEVICE_NAME.

This is now the primary discovery path for reconnects after hub restart.
InterfacesAdded remains as the fallback for fresh first-ever discovery.

### L-055 — hcitool lescan vs bluetoothctl vs Python D-Bus: three different paths
Date: 2026-06-17

hcitool lescan: uses HCI socket directly, bypasses BlueZ daemon entirely.
Fails with I/O error when adapter is in any non-clean state.

bluetoothctl: uses BlueZ D-Bus API. Works even when hcitool fails.
This is the correct diagnostic tool on this platform.

Python dbus-python: same D-Bus path as bluetoothctl. If bluetoothctl
can scan and connect, Python can too. hcitool failure does NOT mean
the adapter is broken — it means hcitool's direct HCI access is blocked.

Rule: on QRB2210, always use bluetoothctl to diagnose BLE issues.
Never trust hcitool lescan as the definitive adapter health check.
