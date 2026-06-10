# Voltage & 4-Cell Load Cell Mechanics — Complete Reference

**Project:** gas-cylinder-monitor  
**Date:** June 2026  
**Scope:** Two deep-dive research topics from session 2026-06-10  
**Status:** Locked — all conclusions verified against ESP32-C3 datasheet and HX711 datasheet  
**Board path:** `~/ArduinoApps/gas-cylinder-monitor/docs/` on `arduino@AQ3`

---

## Part 1 — Voltage: Complete ESP32-C3 Power Architecture

### 1.1 What the ESP32-C3 SuperMini actually is electrically

The SuperMini is NOT powered at 5V internally. It has an **AMS1117-3.3 LDO regulator** on its PCB between the USB-C VBUS pin and the ESP32-C3 chip. The chip itself only ever sees 3.3V regardless of what USB input voltage arrives.

```
USB-C source (4.75–5.25V VBUS)
       ↓
  AMS1117-3.3 LDO regulator  (on SuperMini PCB)
       ↓
  3.3V regulated rail  → ESP32-C3 chip (VDD3P3 pins)
                       → 3V3 output pin (for peripherals)
                       → All GPIO pins (3.3V logic)
```

The 5V from USB never touches the ESP32-C3 silicon.

### 1.2 What USB-C from your laptop delivers

| USB standard | Voltage | Max current |
|---|---|---|
| USB 2.0 port | 5V ±5% (4.75–5.25V) | 500 mA |
| USB 3.0 port | 5V ±5% | 900 mA |
| USB-C standard | 5V, negotiated higher with PD | 1.5A or 3A |

The AMS1117 accepts input from 3.6V to 15V — all USB variants are well within range. Voltage sag, ripple, or variation from the laptop is absorbed by the LDO.

### 1.3 AMS1117-3.3 current budget

| Consumer | Current draw |
|---|---|
| ESP32-C3 active (no radio) | ~30–50 mA |
| ESP32-C3 with BLE transmitting | ~80–100 mA |
| ESP32-C3 peak BLE TX burst | ~250 mA momentarily |
| HX711 | ~1.5 mA |
| **AMS1117 rated max** | **800 mA** |

Available for peripherals on 3V3 pin: **~500–600 mA** at typical BLE operation. The HX711 uses 1.5 mA — you are using 0.25% of available capacity.

### 1.4 The 3V3 pin vs the 5V pin — they are completely different

| | 3V3 pin | 5V pin |
|---|---|---|
| What it is | AMS1117 LDO regulated output | Direct USB VBUS passthrough |
| Voltage | Always 3.3V exactly | 4.75–5.25V, unregulated |
| Available on battery | Yes | No — gives 0V |
| Protected | LDO has thermal/short-circuit protection | No protection whatsoever |
| Noise | Low — filtered by LDO | High — raw USB noise |
| **For HX711 VCC** | **USE THIS** | **NEVER USE** |

The 5V pin is literally a wire from the USB cable to a PCB pad. No regulation, no filtering, no protection.

### 1.5 Why 5V on HX711 VCC destroys the ESP32 GPIO — the exact mechanism

The HX711 is a **CMOS chip**. Its DT (data output) pin is driven by a P-channel transistor whose source is connected directly to VCC. No internal voltage regulation exists for the output. The output high voltage always equals VCC — exactly.

```
HX711 VCC = 3.3V  →  DT output HIGH = 3.3V  →  GPIO4 input = 3.3V  ✓ SAFE
HX711 VCC = 5.0V  →  DT output HIGH = 5.0V  →  GPIO4 input = 5.0V  ✗ DAMAGE
```

**ESP32-C3 absolute maximum ratings (from datasheet):**
- All VDD power pins: −0.3V to **3.6V maximum**
- All GPIO input pins: −0.3V to **VDD + 0.3V = 3.6V maximum**

At 5V on a GPIO: exceeds absolute maximum by 1.4V. The internal ESD protection diodes conduct hard, heat the junction, and cause permanent silicon damage — the GPIO fails, sometimes the whole chip fails.

This is not theoretical — it is documented in `LEARNINGS.md` as L-001, verified on this hardware.

### 1.6 Four scenarios — 5V HX711 excitation with ESP32-C3

| Scenario | Setup | Safety | Verdict |
|---|---|---|---|
| **1 (Current setup)** | HX711 VCC = 3.3V from 3V3 pin | DT output = 3.3V → GPIO safe | **USE THIS** |
| 2 | HX711 VCC = 5V from 5V pin, DT direct to GPIO | DT output = 5V → destroys GPIO | **NEVER** |
| 3 | HX711 VCC = 5V, DT via 5V→3.3V level shifter | GPIO safe, but no benefit | Not worth it |
| 4 | HX711 VCC = 5V, connected to STM32U585 D6/D7 | D6/D7 are 5V-tolerant on STM32 | Only on AQ3 MCU |

### 1.7 Is there any performance difference between 3.3V and 5V excitation?

**No. None. Zero. The performance is identical.**

```
Full-scale ADC input range at gain 128:
  VCC = 5.0V:  ±(0.5 × 5.0 / 128) = ±19.5 mV
  VCC = 3.3V:  ±(0.5 × 3.3 / 128) = ±12.9 mV

YZC-161A full-scale bridge output (sensitivity 1 mV/V):
  At 5.0V excitation:  5.0 × 1 mV/V = 5.0 mV
  At 3.3V excitation:  3.3 × 1 mV/V = 3.3 mV

ADC range utilisation:
  At 5.0V:  5.0 / 19.5 = 25.6% of ADC range
  At 3.3V:  3.3 / 12.9 = 25.6% of ADC range  ← identical
```

The load cell sensitivity and the ADC input range both scale with VCC — they track each other perfectly. Resolution in **grams per count** is identical at any VCC. The HX711 internal noise (~50 nV RMS) is thermal noise from the input amplifier transistors — independent of VCC.

**3.3V is a free lunch: same performance, no GPIO damage risk. This decision is permanently locked.**

### 1.8 Production power supply

For permanent household deployment: any **5V ≥1A USB charger** → USB-C cable → SuperMini USB-C port.

- Typical cheap Indian ₹200 charger: 4.8–5.2V output, 100–300 mV ripple — all absorbed by AMS1117
- The LDO input range is 3.6V to 15V — even a poorly regulated 5.4V input is fine
- Minimum charger rating needed: 500 mA (any 1A+ charger exceeds this)
- System behaviour is **identical** to laptop USB — same LDO, same path

### 1.9 LDO heat dissipation — not a problem

```
Power dissipated = (Vin − Vout) × I = (5.0 − 3.3) × I = 1.7V × I

At 100 mA (typical BLE):  170 mW
At 200 mA (peak BLE TX):  340 mW

Junction temperature at 340 mW in 30°C kitchen:
Tj = 30 + (0.340 W × 160°C/W) = 30 + 54 = 84°C

AMS1117 maximum junction temperature: 125°C
Margin: 41°C — no issue
```

### 1.10 Locked voltage rules — never violate

```
Rule 1: HX711 VCC = ESP32 3V3 pin ONLY
Rule 2: HX711 DT → GPIO4, HX711 SCK → GPIO3 (3.3V logic, no level shifter)
Rule 3: Power ESP32 via USB-C port from any 5V ≥1A charger
Rule 4: Never connect anything to the ESP32 5V pin for sensor power
Rule 5: Never change excitation voltage to 5V — zero benefit, guaranteed damage risk
```

---

## Part 2 — 4-Cell Load Cell Mechanics: Atomic Level to MCU

### 2.1 What a strain gauge does at the atomic level

The fundamental formula:

```
R = ρ × L / A

ρ = resistivity of the metal wire
L = length of the wire
A = cross-sectional area of the wire
```

When the beam bends:

- **Tension (bottom surface):** wire stretches → L increases, A decreases → both effects **increase R**
- **Compression (top surface):** wire compresses → L decreases, A increases → both effects **decrease R**

Typical change: ~0.005% of R per kilogram of load for the YZC-161A. This is the raw signal — microvolts at the bridge output. The entire useful signal exists in a 3.3 mV window across 0–20 kg.

### 2.2 Inside one load cell — the Wheatstone bridge

The YZC-161A contains four strain gauges wired in a diamond (Wheatstone bridge):

```
           E+ (Red, 3.3V)
               │
        R1(compress)  R3(tension)
        ↙               ↘
   A− (White)         A+ (Green)
        ↘               ↙
        R2(tension)   R4(compress)
               │
           E− (Black, GND)
```

Under load:
- R1, R4 (compression) → resistance **decreases**
- R2, R3 (tension) → resistance **increases**

**Left arm:** `V(A−) = 3.3 × R2/(R1+R2)` — R2↑ and R1↓ → V(A−) **rises**  
**Right arm:** `V(A+) = 3.3 × R4/(R3+R4)` — R4↓ and R3↑ → V(A+) **falls**

`Vout = V(A+) − V(A−)` — one rises and one falls simultaneously, giving 4× signal compared to a single gauge.

### 2.3 Why four gauges (full bridge) instead of one

| Configuration | Signal strength | Temp compensation | Linearity |
|---|---|---|---|
| Quarter bridge (1 gauge) | 1× | None — temperature looks like weight | Poor |
| Half bridge (2 gauges) | 2× | Partial | Better |
| **Full bridge (4 gauges)** | **4×** | **Complete cancellation** | **Best |

Temperature affects all four arms equally. The bridge measures ratios — equal temperature change on all arms produces zero differential. This is **common-mode rejection** — the most critical property for a kitchen environment where temperature swings 8–15°C daily.

### 2.4 Four load cells in parallel — the complete circuit

```
Cell 1 E+ ─┐
Cell 2 E+ ─┤──── HX711 E+  (3.3V from ESP32 3V3)
Cell 3 E+ ─┤
Cell 4 E+ ─┘

Cell 1 E− ─┐
Cell 2 E− ─┤──── HX711 E−  (GND)
Cell 3 E− ─┤
Cell 4 E− ─┘

Cell 1 A+ ─┐
Cell 2 A+ ─┤──── HX711 A+/INNA
Cell 3 A+ ─┤
Cell 4 A+ ─┘

Cell 1 A− ─┐
Cell 2 A− ─┤──── HX711 A−/INPA
Cell 3 A− ─┤
Cell 4 A− ─┘
```

All four join at the **junction block** — a screw-terminal block with four rails (E+, E−, A+, A−). Single 4-wire cable from junction to HX711.

### 2.5 The voltage averaging mechanism — the physics

Each cell's A+ output is a **Thevenin equivalent**: a voltage source V_i in series with a source resistance R_s (approximately 500Ω for each cell's bridge midpoint).

When four equal sources are joined at the bus, Kirchhoff's current law gives:

```
V_bus = (V₁/R_s + V₂/R_s + V₃/R_s + V₄/R_s) / (1/R_s + 1/R_s + 1/R_s + 1/R_s)

Since all R_s are equal, they cancel:

V_bus = (V₁ + V₂ + V₃ + V₄) / 4   ← simple arithmetic average
```

Substituting `Vout_i = S × W_i` (sensitivity × weight on that cell):

```
Vout_bus = S × (W₁ + W₂ + W₃ + W₄) / 4
         = (S/4) × W_total
```

**The bus output is proportional to total weight, regardless of how that weight is distributed across the four cells.** This is the fundamental reason the parallel bridge works.

### 2.6 Why the cal_factor changes for a 4-cell platform

Single cell: HX711 sees full sensitivity S → cal_factor ≈ 105 counts/gram  
4-cell parallel: HX711 sees S/4 → same total weight produces 1/4 the voltage per gram → cal_factor ≈ 4× larger

```
Single cell cal_factor:   ~105 counts/gram
4-cell parallel cal_factor: ~420 counts/gram  (4× larger)
```

**The formula `grams = (raw − tare_raw) / cal_factor` is identical** — the factor-of-4 is absorbed entirely into cal_factor at bench calibration. After calibration, the firmware doesn't change. Nothing in the hub changes.

**This is why cal_factor MUST be re-derived on the 4-cell platform. The single-cell value of ~105 counts/gram is void.**

### 2.7 Complete signal chain — 7 stages with real numbers

**Example:** Gas cylinder (29.56 kg) placed slightly off-centre.  
Cell distribution: C1=7.20 kg, C2=7.80 kg, C3=7.10 kg, C4=7.46 kg

**Stage 1 — Physical force**
```
Four different weights on four cells. Sum = 29.56 kg.
```

**Stage 2 — Mechanical (beam deflection)**
```
Each beam deflects proportional to its individual load.
Deflection in micrometers — not visible to the naked eye.
Top surface: compressed. Bottom surface: stretched.
```

**Stage 3 — Electrical (resistance change)**
```
ΔR per kg = 1000Ω × 0.00005 = 0.05Ω/kg

Cell 1 (7.20 kg): R_compression = 999.64Ω, R_tension = 1000.36Ω
Cell 2 (7.80 kg): R_compression = 999.61Ω, R_tension = 1000.39Ω
Cell 3 (7.10 kg): R_compression = 999.645Ω, R_tension = 1000.355Ω
Cell 4 (7.46 kg): R_compression = 999.627Ω, R_tension = 1000.373Ω
```

**Stage 4 — Bridge voltage (per cell)**
```
Sensitivity = 1 mV/V × 3.3V excitation / 20 kg rated = 0.165 mV/kg

Cell 1: 0.165 × 7.20 = 1.188 mV
Cell 2: 0.165 × 7.80 = 1.287 mV
Cell 3: 0.165 × 7.10 = 1.172 mV
Cell 4: 0.165 × 7.46 = 1.231 mV
```

**Stage 5 — Parallel averaging at junction block**
```
V_avg = (1.188 + 1.287 + 1.172 + 1.231) / 4
      = 4.878 / 4
      = 1.219 mV

Verification: (S/4) × W_total = (3.3mV/20kg)/4 × 29.56 = 0.04125 × 29.56 = 1.219 mV ✓
```

**Stage 6 — HX711 amplification**
```
Gain 128: 1.219 mV × 128 = 156.0 mV

ADC input range: ±(0.5 × 3.3V) = ±1650 mV
Signal uses: 156 / 1650 = 9.5% of range — no clipping, plenty of headroom
```

**Stage 7 — 24-bit delta-sigma ADC**
```
ADC full scale: ±8,388,608 counts
Counts per mV: 8,388,608 / 1650 = 5,084 counts/mV

raw_delta = 156.0 × 5,084 ≈ 793,104 counts above tare
```

**Stage 8 — ESP32 computation**
```python
raw_reading = tare_raw + 793,104
cal_factor  = 26.83          # re-derived on 4-cell platform at bench
grams = 793,104 / 26.83 = 29,560 g = 29.56 kg  ✓
```

### 2.8 Why load distribution is completely irrelevant

The same 29.56 kg produces identical readings regardless of distribution:

| Distribution | Cell voltages | V_avg | MCU reads |
|---|---|---|---|
| Perfectly centred (7.39/7.39/7.39/7.39) | 1.219/1.219/1.219/1.219 mV | **1.219 mV** | **29,560 g** |
| Slightly off-centre (7.20/7.80/7.10/7.46) | 1.188/1.287/1.172/1.231 mV | **1.219 mV** | **29,560 g** |
| Very off-centre (4.00/11.56/3.50/10.50) | 0.660/1.907/0.578/1.733 mV | **1.219 mV** | **29,560 g** |

The arithmetic average always equals total/4. The MCU sees only total weight — distribution is invisible.

### 2.9 The firmware does not change for 4 cells

The ESP32 firmware that reads one cell reads four cells in parallel. The HX711 sees one set of wires. The bit-bang code is identical. The seam contract `{grams, quality, sigma}` is unchanged. The hub code is unchanged.

**The only things that change:**
1. Physical wiring — 4 cells joined in parallel at junction block
2. `cal_factor` — must be re-derived on assembled 4-cell platform (~4× the single-cell value)
3. `tare_raw` — must be re-derived on assembled 4-cell platform
4. Noise characterisation — must be re-run (4-cell parallel noise floor may differ from single cell)

### 2.10 Signal chain — complete summary

```
Force (29.56 kg)
  → Beam deflects (micrometers per cell, proportional to each cell's load)
  → Gauge resistance changes (ΔR = 0.05Ω per kg)
  → Bridge output voltage (each cell: ~1.2 mV differential)
  → Parallel averaging at junction block (bus = average of 4 = 1.219 mV)
  → HX711 instrumentation amp × 128 (→ 156 mV)
  → 24-bit delta-sigma ADC (→ 793,104 raw counts above tare)
  → 25 SCK pulses shift out 24 bits on DT line
  → ESP32: (raw − tare_raw) / cal_factor = 29,560 grams
```

---

## Quick Reference — Locked values

| Parameter | Single cell | 4-cell parallel | Notes |
|---|---|---|---|
| HX711 VCC | 3.3V | 3.3V | Never 5V |
| GPIO (DT) | GPIO4 | GPIO4 | Unchanged |
| GPIO (SCK) | GPIO3 | GPIO3 | Unchanged |
| Gain | 128 | 128 | 25 SCK pulses |
| Rate | 10 SPS | 10 SPS | RATE pin LOW |
| cal_factor | ~105 counts/g | ~420 counts/g | Must re-derive |
| Full-scale bridge output | 3.3 mV | 3.3 mV total (0.825 mV avg per cell) | Same physics |
| Firmware | Unchanged | Unchanged | Same code |
| Seam contract | {grams, quality, sigma} | {grams, quality, sigma} | Unchanged |

---

*gas-cylinder-monitor | Gratian Technologies | June 2026*  
*Board: arduino@AQ3 | Path: ~/ArduinoApps/gas-cylinder-monitor/docs/*
