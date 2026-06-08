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
