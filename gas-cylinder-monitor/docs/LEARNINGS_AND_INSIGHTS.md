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
