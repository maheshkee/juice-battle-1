# Gas Cylinder Monitor — Production Hardware & System Design Reference

**Project:** gas-cylinder-monitor  
**Platform:** Arduino UNO Q (AQ3) + ESP32-C3 SuperMini  
**Sensor:** HX711 + YZC-161A 20kg Load Cell (×4 in production)  
**Organisation:** Gratian Technologies  
**Date:** June 2026  
**Repository:** gratiantechnologies/project13  
**Board path:** `~/ArduinoApps/gas-cylinder-monitor/` on `arduino@AQ3`

---

## Purpose

This document captures the complete research, theory, design decisions, and locked specifications developed during a deep brainstorming session covering the full production system. It is the authoritative reference for all hardware physics, calibration, signal integrity, installation scenarios, temperature effects, and long-term drift behaviour of the product.

---

## Table of Contents

1. Load Cell Physics — Strain, Gauges, Beam Bending
2. Wheatstone Bridge — Why Four Gauges, Differential Output
3. Quarter / Half / Full Bridge Comparison
4. RAW ADC to Grams Formula
5. Best Load Cell Type
6. Four Load Cell Production Wiring
7. Platform 3D Assembly Concept
8. Section A — The HX711 Chip In Depth
9. Section B — Calibration in Production
10. Section C — Platform Mechanical Design in Depth
11. Section D — Signal Integrity and Noise in Production
12. Section E — Installation Scenario Problem at Hardware Level
13. Section F — Temperature Effects in a Real Kitchen
14. Section G — Long Term Drift and Creep
15. Appendix 1 — All Locked Decisions and Constants
16. Appendix 2 — V1/V2/V3 Install Scenario Matrix
17. Appendix 3 — Complete Boot and Tare Sequence
18. Appendix 4 — Key Formulas Reference

---

## Section 1 — Load Cell Physics: Strain, Gauges, Beam Bending

### 1.1 What a Load Cell Actually Is

A load cell is a precision metal beam — not a sensor in the traditional sense. It contains no transistors or active circuitry. It is a carefully machined piece of metal that bends predictably under load, by a tiny, repeatable, measurable amount. That bending is called **strain**.

Strain is not visible deformation — we are talking about micrometers of deflection. But it is enough to change the electrical resistance of tiny wires bonded to the beam surface. Those wires are called **strain gauges**.

The complete signal chain:

```
Load applied → beam bends (strain)
→ strain gauges stretch or compress
→ stretched wire: higher resistance | compressed wire: lower resistance
→ resistance change causes voltage imbalance in Wheatstone bridge
→ HX711 amplifies and digitises the voltage imbalance
→ firmware converts digital number to grams using cal_factor
```

### 1.2 Strain Gauges — How They Work

A strain gauge is a thin metallic foil arranged in a serpentine pattern, bonded to the beam surface with adhesive. The relationship between mechanical strain and resistance change:

```
ΔR/R = GF × ε
```

Where:
- `ΔR/R` = fractional resistance change
- `GF` = gauge factor (typically 2.0 for metal foil)
- `ε` = strain (dimensionless, typically 500–2000 microstrain for load cells)

### 1.3 Beam Bending Zones

The YZC-161A is a bending beam load cell. When weight is applied to the free end:

- **Top surface (compression zone):** fibres squeezed together → gauges compressed → resistance **decreases**
- **Bottom surface (tension zone):** fibres pulled apart → gauges stretched → resistance **increases**
- **Neutral axis:** plane through beam centre, zero strain — gauges must never be placed here

The YZC-161A places four strain gauges inside the sensing notch: R1 and R3 on compression side, R2 and R4 on tension side. This creates the full Wheatstone bridge.

---

## Section 2 — Wheatstone Bridge: Why Four Gauges, Differential Output

### 2.1 The Bridge Circuit

The four strain gauges are wired as a Wheatstone bridge — a diamond-shaped circuit with four resistive arms. Four nodes:

| Pin | Wire Colour | Function |
|-----|-------------|----------|
| E+ | Red | Excitation positive — HX711 applies 3.3V here |
| E− | Black | Excitation negative — GND |
| A+ | Green | Signal positive output — read by HX711 |
| A− | White | Signal negative output — read by HX711 |

**E+ and E−** power the bridge — they do not carry the weight signal.  
**A+ and A−** are where the bridge is read. HX711 measures differential voltage (A+ minus A−).

### 2.2 Differential Output With Real Numbers

**At zero load** (all four R = 120Ω, 3.3V excitation):
```
A− = 3.3 × 120/240 = 1.650 V
A+ = 3.3 × 120/240 = 1.650 V
Vout = A+ − A− = 0 mV  (bridge balanced)
```

**Under load** (0.1% resistance change):
- R1, R4 (compression) → 119.88Ω
- R2, R3 (tension) → 120.12Ω

```
A− = 3.3 × 120.12/240 = 1.6517 V
A+ = 3.3 × 119.88/240 = 1.6484 V
Vout = A+ − A− = −3.3 mV
```

**Full-scale output at 3.3V excitation:** 3.3V × 1 mV/V sensitivity = **3.3 mV total across 0–20kg range.**

### 2.3 Why Four Gauges — Not One

**Problem 1: No temperature compensation with a single gauge.**  
A single gauge's resistance changes with both strain (signal) and temperature (noise) — indistinguishable. With four gauges in a full bridge, temperature affects all four arms equally. The bridge measures ratios. Equal temperature change on all arms cancels completely in the differential. This is **common-mode rejection**.

**Problem 2: Signal is 4× weaker.**  
With one active gauge, only one arm changes. With four active gauges, all four change simultaneously in opposing directions — compression arms decrease while tension arms increase. The differential signal is 4× stronger than a quarter bridge.

**Problem 3: Non-linearity.**  
A single voltage divider is inherently non-linear. The full bridge topology cancels second-order non-linearity terms, producing a linear response.

---

## Section 3 — Quarter / Half / Full Bridge Comparison

| Parameter | Quarter Bridge | Half Bridge | Full Bridge (YZC-161A) |
|-----------|---------------|-------------|----------------------|
| Active gauges | 1 | 2 | 4 |
| Signal strength | 1× | 2× | 4× |
| Temperature compensation | None | Partial | Full cancellation |
| Linearity | Poor | Better | Best |
| Noise rejection (CMRR) | None | Partial | Full |
| Full scale at 3.3V | ~0.83 mV | ~1.65 mV | ~3.3 mV |
| Used in YZC-161A | No | No | **Yes** |

The full bridge (4 active gauges) is the only viable choice for precision weight measurement. The YZC-161A contains a complete full bridge internally.

---

## Section 4 — RAW ADC to Grams Formula

### The Formula

```
grams = (raw_reading  −  tare_raw)  ÷  cal_factor
```

| Term | Definition |
|------|-----------|
| `raw_reading` | 24-bit integer from HX711 — no units on its own |
| `tare_raw` | raw reading at zero load (empty platform), stored in config.json |
| `cal_factor` | raw counts per gram — measured once at bench calibration |
| `grams` | net weight on platform in grams |

### Worked Example

```
Reference weight placed: 10,000 g
tare_raw (empty):        24,650,000
loaded_raw (10kg on):    26,724,000

cal_factor = (26,724,000 − 24,650,000) ÷ 10,000 = 207.4 counts/g

Live reading with cylinder: raw = 30,781,580
grams = (30,781,580 − 24,650,000) ÷ 207.4 = 29,561 g
```

**Important:** The cal_factor for a 4-cell parallel platform will differ slightly from a single-cell bench test. Always re-derive cal_factor on the fully assembled 4-cell platform. The parallel bridge topology preserves sensitivity — cal_factor does NOT need to be divided by 4.

---

## Section 5 — Best Load Cell Type for Gas Cylinder Platform

**Locked recommendation: Bending beam cells (YZC-161A, 20kg rated, matched set of 4). Never disc/button/compression cells.**

### Why Not Disc Cells

- Require perfectly vertical load transfer into the cell centre
- Cannot tolerate side forces — a cylinder being placed by a human always involves side force
- Sensitive to mounting surface flatness — kitchen floors are never flat enough
- No natural moment rejection

### Why Bending Beam Wins

- Naturally rejects lateral forces and torques
- Tolerates imperfect cylinder placement and platform levelling
- Available in matched sets for parallel bridge applications
- YZC-161A at 20kg per cell = 80kg total platform capacity (well above 29.7kg cylinder)

---

## Section 6 — Four Load Cell Production Wiring

### 6.1 Parallel Bridge Topology

All four cells are connected in parallel to a single HX711:

```
Cell 1 E+ ─┐
Cell 2 E+ ─┤──── HX711 E+
Cell 3 E+ ─┤
Cell 4 E+ ─┘

Cell 1 E− ─┐
Cell 2 E− ─┤──── HX711 E−
Cell 3 E− ─┤
Cell 4 E− ─┘

Cell 1 A+ ─┐
Cell 2 A+ ─┤──── HX711 A+ (INNA)
Cell 3 A+ ─┤
Cell 4 A+ ─┘

Cell 1 A− ─┐
Cell 2 A− ─┤──── HX711 A− (INPA)
Cell 3 A− ─┤
Cell 4 A− ─┘
```

### 6.2 Wire Colour Convention

| Colour | Signal | Connected To |
|--------|--------|-------------|
| Red | E+ | HX711 E+ — 3.3V excitation |
| Black | E− | HX711 E− — GND |
| Green | A+ | HX711 A+ / INNA |
| White | A− | HX711 A− / INPA |

### 6.3 HX711 to ESP32-C3 SuperMini

| HX711 Pin | ESP32-C3 Pin | Notes |
|-----------|-------------|-------|
| VCC | 3V3 | NEVER 5V — ESP32 is 3.3V logic |
| GND | GND | Star topology — single GND point |
| DT (DOUT) | GPIO4 | Data output |
| SCK (PD_SCK) | GPIO3 | Clock input |

### 6.4 Junction Block

All 16 cell wires meet at a central junction block mounted on the underside of the base plate, as close to geometric centre as possible. Four screw-terminal rails: E+, E−, A+, A−. Single 4-wire cable exits to HX711.

### 6.5 Why CAL_FACTOR Does Not Change for 4-Cell Setup

In parallel bridge topology, each cell carries ~1/4 of total load. Each cell's signal is 1/4 of full-load signal. But four signals are averaged at the junction — the average equals what a single cell produces under full load. Parallel averaging exactly compensates for reduced individual loading. **Cal_factor is preserved.**

---

## Section 7 — Platform 3D Assembly

### Layer Stack (Top to Bottom)

1. Gas cylinder (29.7 kg full)
2. 3mm natural rubber mat — bonded to top plate, prevents cylinder sliding
3. Top plate — 5mm aluminium 6061-T6, 380×380mm — **FLOATING**
4. Four YZC-161A load cells — fixed end to base, free end via ball to top plate
5. Base plate — 5mm aluminium 6061-T6, 380×380mm — fixed to floor
6. Four adjustable rubber levelling feet (M6, locknut)
7. Floor

### Critical Mounting Rules

> **Non-negotiable:**
> 1. Fixed end of each cell → bolted to base plate (M4 bolt)
> 2. Free end → contacts top plate via 10mm ball — **never bolted**
> 3. Top plate must float freely vertically with zero lateral constraint
> 4. All four free ends must face INWARD (rotationally symmetric)
> 5. Overload stop bolts (M6 × 4) through top plate, 0.8mm clearance above base plate

### Why Free End Must Rest, Not Bolt

A rigid bolt at the free end creates a moment constraint. The beam bends against the bolt resistance → non-linearity, hysteresis, lateral force sensitivity. The ball contact transfers only vertical force, allows natural free-end tipping, introduces zero moment constraint.

---

## Section A — The HX711 Chip In Depth

### A.1 Why a Dedicated Chip Is Required

Full-scale signal at 3.3V excitation: **3.3 mV**. ESP32 internal ADC: 12-bit across 3.3V = **0.8 mV per count**. The entire 20kg signal range is less than 4 ADC counts. Resolution ≈ 5 kg per count — completely useless. HX711 provides the solution: precision instrumentation amplifier + 24-bit delta-sigma ADC.

### A.2 Input Multiplexer

Two channels: Channel A (load cell, gain 128 or 64) and Channel B (second sensor, gain 32 only). Only Channel A used in this project.

### A.3 Instrumentation Amplifier

Amplifies only the differential voltage (A+ minus A−). Completely rejects any voltage appearing identically on both inputs (common-mode noise). This is why twisted A+/A− pairs work — noise couples identically to both wires, the inst. amp cancels it.

**Gain settings at 3.3V excitation:**

| Gain | Amplified Signal | Resolution | Selection |
|------|-----------------|-----------|-----------|
| **128 (use this)** | **422 mV** | **~105 counts/gram** | **25 SCK pulses** |
| 64 | 211 mV | ~52 counts/gram | 26 SCK pulses |
| 32 (Ch B) | 106 mV | ~26 counts/gram | 27 SCK pulses |

**Gain 128 is locked for this project.** The cal_factor of ~106.7 counts/gram was measured at gain 128.

### A.4 24-bit Delta-Sigma ADC

Instead of one careful measurement, takes millions of 1-bit measurements and averages them:
- Random noise: averages toward zero
- Real signal: consistently biases 1-bit decisions in one direction → survives as precise 24-bit number

This is why N=200 firmware averaging works — it performs the same principle at the software layer. Two layers of averaging, two layers of noise rejection.

### A.5 10 SPS Rate — The 50Hz Notch Filter

At 10 SPS (RATE pin LOW), the internal filter has a **notch at exactly 50 Hz** — completely rejecting mains interference. At 80 SPS, the notch shifts to 400 Hz and mains noise is no longer rejected. **10 SPS is mandatory for kitchen deployment.** The 120ms loop pacing matches 10 SPS.

### A.6 Gain Selection via SCK Pulse Count

No register or SPI command — gain is set by pulse count after reading:
- 25 total SCK pulses → Channel A, **Gain 128** ← our setting
- 26 total → Channel A, Gain 64
- 27 total → Channel B, Gain 32

This is why Zephyr scheduler interrupt mid-SCK was a critical bug — wrong pulse count → wrong gain → garbage reading for the entire next cycle. The 120ms top-of-loop pacing prevents this.

---

## Section B — Calibration in Production

### B.1 Two Separate Calibration Problems

| | cal_factor | steel_tare_kg (S) |
|--|-----------|-----------------|
| What it is | Hardware sensitivity: counts per gram | Cylinder-specific empty weight |
| When it changes | Only if hardware changes | Every time a different cylinder is installed |
| How derived | Once at bench calibration with known weight | At every fresh cylinder anchor event |
| Stored in | config.json calibration block | config.json cylinder block |
| Error if wrong | All weights systematically wrong | Gas% wrong; consumption still exact |

### B.2 Bench Calibration Procedure for 4-Cell Platform

1. Assemble platform fully — all 4 cells wired, junction block connected, ESP32 powered
2. Allow 10 minutes thermal equilibration
3. Level platform to 0.5° tolerance (spirit level on top plate)
4. Platform empty, stable → take N=200 readings → record as `tare_raw`
5. Place reference weight (10kg known weight or fresh full cylinder)
6. Wait for stability (spread < 2.5g, drift < 1.0g across 3 windows)
7. Take N=200 readings → record as `loaded_raw`
8. `cal_factor = (loaded_raw − tare_raw) ÷ reference_grams`
9. Write `cal_factor` to config.json

> **The cylinder as its own calibration reference:** BIS regulation mandates every filled domestic cylinder contains exactly 14.2 kg net gas (±150g tolerance). A fresh Indane/HP/Bharat delivery is a certified 14.2 kg reference by law. One setup step performs both calibrations: cal_factor from the cylinder weight AND steel_tare from `S = G_new − 14.2`.

### B.3 The Anchor Event

Fires when:
- G jump > `REFILL_THRESHOLD_KG` (6.0 kg)
- `G_new > FRESH_CYLINDER_MIN_KG` (26.0 kg) — confirms fresh cylinder, not partial swap
- G stable for 3 consecutive windows (spread < 2.5g, drift < 1.0g)

At anchor: `S = G_stable − CAPACITY_KG` (14.2). Stored in config.json with `anchor_exact: true`.

### B.4 Cal_Factor Sequencing — Critical Order

> **Non-negotiable sequence at every cylinder removal:**
> 1. G < CYLINDER_REMOVED_KG → REMOVED event
> 2. Wait for stability (vibration + creep spring-back: 5–20 minutes)
> 3. Auto-tare: N=200 on empty platform → new tare_raw saved
> 4. cal_factor validation: compare last pre-removal G against S + consumption
> 5. Hardware READY
> 6. New cylinder placed → stability → anchor event → G_new measured
> 7. S = G_new − 14.2 derived and stored
>
> **G_new MUST be measured AFTER steps 1–5. Error in G_new permanently corrupts stored S.**

---

## Section C — Platform Mechanical Design in Depth

### C.1 The Governing Rule

> The top plate must be mechanically isolated from the base plate in every direction **except vertical load**.  
> Any horizontal constraint → side force into cells → reading error.  
> Any vertical constraint → beam cannot bend → no signal.

### C.2 Platform Dimensions

- Cylinder base ring: 280–300mm diameter
- Load cell centre-to-centre: **300×300mm** — 10mm clearance inside cylinder base ring each side
- Plate edge inset: **40mm** each side of cell centres
- **Total platform: 380×380mm**

### C.3 Material Selection

| Material | Verdict | Reason |
|----------|---------|--------|
| **Aluminium 6061-T6, 5mm** | **Recommended — both plates** | Stiff, lightweight, corrosion resistant |
| Mild steel / GI | Base plate only | Must be painted/galvanised — rusts in kitchen |
| Acrylic / plywood | Prototype only | Acrylic cracks; plywood swells |

### C.4 Load Cell Orientation

- Wire exit side = **fixed end** → bolt to base plate
- Smooth rounded end = **free end** → contacts top plate via ball
- Sensing notch faces toward fixed end
- **Upside-down mounting = reversed or non-linear signal**

### C.5 Free End Contact Point

Options:
- 10mm hardened steel ball pressed into counterbore on free end
- Dome-head M6 screw (button head) against top plate underside
- Commercial load cell foot with hemispherical tip

**Never bolt the free end** — it must rest only, to allow natural deflection and avoid moment constraint.

### C.6 Overload Protection

- Four M6 bolts through top plate with washers
- 0.8mm clearance gap between washer and base plate at zero load
- Under impact: top plate travels max 0.8mm → bolt contacts base → stops at ~160% rated load
- **Setting:** back off 288° from snug (1mm pitch M6 × 0.8mm = 288°). Verify with feeler gauge. Lock with nut.

### C.7 Levelling

- 1° tilt ≈ 1–3% cross-axis error = up to 297g on 29.7kg cylinder
- Solution: four independently adjustable M6 rubber feet at corners
- Set to within 0.5° of horizontal with spirit level on top plate
- Lock feet with locknuts once levelled
- Re-check whenever platform is moved

### C.8 Complete Platform Specification

| Component | Specification |
|-----------|--------------|
| Top plate | 380×380mm, 5mm Al 6061-T6, floating |
| Base plate | 380×380mm, 5mm Al 6061-T6, fixed via feet |
| Load cells | YZC-161A 20kg × 4, matched set |
| Cell fixing | Fixed end: M4 to base. Free end: 10mm ball to top |
| Cell centres | 300×300mm, 40mm inset from edges |
| Platform height | ~55mm total assembled |
| Overload stops | M6 bolt × 4, 0.8mm clearance, locked |
| Levelling feet | M6 adjustable rubber × 4, locknut |
| Top surface | 3mm natural rubber mat bonded to top plate |
| Wire routing | All 4 cells equal length ±20mm, along base underside |
| Junction block | 4-rail screw terminal, centred under base plate |

### C.9 Production Gotchas

- **Gauge adhesive:** softens above ~80°C. Keep cells away from direct burner radiant heat.
- **Wire exit seal:** apply neutral-cure silicone (NOT acetic-cure — acetic acid corrodes copper) at every wire exit point before deployment.
- **Platform rocking:** four independently adjustable feet are mandatory. Equal-height fixed feet will rock on any real kitchen floor.
- **Top plate surface:** rubber mat prevents cylinder sliding and protects aluminium.

---

## Section D — Signal Integrity and Noise in Production

### D.1 The Problem

Full-scale signal: **3.3 mV**. Kitchen noise sources that can exceed this:

| Source | Amplitude | Risk Level |
|--------|-----------|-----------|
| Thermal noise | <10 nV | Negligible |
| BLE radio | ~300 µV (1.81g σ measured) | Managed by averaging |
| Mains 50 Hz | Up to 1 mV | Dangerous without mitigation |
| Motor switching | Up to 10 mV | Very dangerous — exceeds signal range |
| Ground loop | Variable | Unpredictable — must eliminate |
| Mechanical vibration | Up to 500 mV equivalent | Managed by stability detection |

### D.2 Noise Sources and Countermeasures

**Mains 50 Hz — Inductive Coupling**  
Mechanism: A+/A− wires act as antenna. 50Hz field induces voltage. Different voltage on each wire = false signal.  
Countermeasure: **Twist A+ and A− together.** Each half-twist, each wire alternately closer to source → equal pickup → common mode → cancelled by inst. amp.

**Motor Switching — Power Supply Noise**  
Mechanism: Motor switch-on/off injects spikes on mains → reaches HX711 VCC → corrupts excitation voltage.  
Countermeasure: **100µF electrolytic + 100nF ceramic capacitor at HX711 VCC/GND pins.** Both required, placed right at module pins. Electrolytic handles low-frequency bulk; ceramic handles high-frequency transients.

**BLE Radio — RF Coupling**  
Mechanism: 2.4GHz RF couples into signal wires; BLE TX current spikes cause VCC dips.  
Measured noise floor: **1.81g standard deviation, 7.24g threshold (4σ)**.  
Countermeasure: N=200 averaging already handles this. 10 SPS rate internally averages over 100ms.

**Ground Loops — Topology**  
Mechanism: Shared ground wire carries other devices' current → voltage drop on wire → looks like measurement error.  
Countermeasure: **Star grounding.** All grounds meet at ESP32 GND pin. HX711 GND direct to ESP32 GND. No daisy-chaining.

**Mechanical Vibration**  
Mechanism: Floor/cooking vibration → beam oscillates → looks like weight change.  
Countermeasure: Dynamic stability detection (spread < 2.5g AND drift < 1.0g across 3 windows). Rubber feet on base plate.

### D.3 Cable Length Matching

In parallel bridge, unequal cable lengths cause differential signal attenuation — one cell's signal attenuated relative to others. Systematic error depends on cylinder placement position.

> **Rule:** All four cell cables equal length ±20mm. Cut to longest required run; coil excess for shorter runs.

### D.4 10 SPS as a Noise Filter

At 10 SPS, HX711 internal filter has a **notch at 50 Hz** — complete rejection of mains interference. At 80 SPS, notch shifts to 400 Hz, mains no longer rejected. 10 SPS is mandatory.

### D.5 Complete Signal Integrity Checklist

- ☐ A+/A− twisted pair
- ☐ E+/E− twisted pair  
- ☐ All 4 cell cables equal length ±20mm
- ☐ Junction-to-HX711 cable kept away from mains
- ☐ 100µF + 100nF decoupling at HX711 VCC/GND pins
- ☐ Star grounding — all grounds to ESP32 GND only
- ☐ RATE pin LOW (10 SPS)
- ☐ N=200 averaging in firmware
- ☐ Stability detection in firmware
- ☐ All three corrupt value filters: LONG_MIN, -1, 0x7FFFFF

---

## Section E — Installation Scenario Problem at Hardware Level

### E.1 Core Principle

The hardware has no concept of installation. It produces only one output: a G (gross weight) reading. Every state transition is inferred purely from the pattern of G changes over time.

### E.2 Physical Events to Hardware Signals

| Physical Event | HX711 Sees | Software Infers |
|----------------|-----------|----------------|
| Boot, no cylinder | G ≈ 0 kg, stable ±7g | Auto-tare → UNINSTALLED |
| Boot, cylinder present | G ≈ 22–30 kg immediately | Cannot tare — use stored or V2/V3 path |
| Fresh cylinder placed | G jumps from ~0 to 28–30 kg | Anchor event → S = G − 14.2 → TRACKING |
| Cylinder removed | G drops below 2 kg, fast then stable | REMOVED → auto-tare → cal_factor validate |
| Cylinder bumped | G spikes ±500g briefly, returns to same value | Stability fails → reading discarded |
| Active cooking | G declining ~8g/minute | Heartbeat captures ΔG → consumption |
| Slow leak | G declines faster than burn history predicts | Anomaly flag |

### E.3 V1/V2/V3 Install Scenarios

**V1 — Fresh Cylinder (Production Baseline)**  
System installed when fresh delivery cylinder is placed. S derived exactly. Gas% exact from first reading. This is the normal steady-state for the entire product lifetime after initial setup.

V1 State Machine:
```
UNINSTALLED
  → Trigger: ΔG > 6.0kg AND G_new > 26.0kg AND stable 3 windows
  → Action: S = G_new − 14.2, write cylinder block, anchor_exact: true
  → State: TRACKING

TRACKING
  → Trigger: G < 2.0 kg
  → Action: stability wait → auto-tare → cal_factor validate → READY
  → State: UNINSTALLED

TRACKING → LOW GAS
  → Trigger: gas_kg < 2.0 OR days_remaining < 10
  → Action: BLE alert + screen warning
  → Same computation as TRACKING
```

**V2 — Partial Cylinder, Brand Known**  
User presses brand button once. S from lookup table:

| Brand | Steel Tare |
|-------|-----------|
| Indane (IOC) | 14.8 kg |
| HP (HPCL) | 15.7 kg |
| Bharat (BPCL) | 15.3 kg |

Gas% shown with `~` prefix (anchor_exact: false). Error ±1–3% until first anchor event.

**V3 — Partial Cylinder, Fully Blind**  
No user input. S = 15.15 kg (range midpoint). Gas% shown as range ("41–50%, calibrating…"), biased toward lower bound. Consumption exact from day 1.

All three versions converge to identical behaviour after first anchor event.

### E.4 Auto-Tare Sequence

1. G < CYLINDER_REMOVED_KG → REMOVED event, state = UNINSTALLED
2. Mechanical stability wait: vibration (3–8s) + creep spring-back (5–20 min)
3. Two-condition pass: spread < 2.5g AND inter-window drift < 1.0g for 3 windows
4. N=200 readings → mean → new tare_raw → saved to config.json
5. cal_factor validation vs consumption history
6. Hardware READY → await new cylinder

### E.5 Boot Sequence

1. Power on — ESP32 boots, BLE stack initialises
2. HX711 warmup: 400ms (bandgap reference stabilises)
3. Load config.json — cal_factor, tare_raw, cylinder block
4. Take N=20 quick readings to estimate G
5. G < CYLINDER_REMOVED_KG?
   - YES → auto-tare → UNINSTALLED
   - NO + cylinder block in config → resume TRACKING with stored S
   - NO + no cylinder block → V2/V3 partial path

### E.6 Atomic Config Write

```python
# Prevent corruption on power loss during anchor event
with open('config.json.tmp', 'w') as f:
    json.dump(new_config, f)
os.rename('config.json.tmp', 'config.json')  # atomic on most filesystems
```

On boot: if G_now > S + CAPACITY_KG + 0.5kg → stored S is from previous cylinder → re-trigger anchor event.

---

## Section F — Temperature Effects in a Real Kitchen

### F.1 Kitchen Temperature Profile

Indian kitchen floor temperature swings **8–15°C** between pre-dawn minimum and peak cooking-time maximum. Three independent physical mechanisms are affected.

### F.2 Three Temperature Effects

**Effect 1: Zero Drift**
- Mechanism: beam thermal expansion produces residual strain with no load
- Magnitude: ±0.02% FS per °C = ±4g per °C
- 10°C swing: ±40g on G reading
- Effect on gas_kg: partially cancels if G and S measured at same temperature
- Mitigation: **boot retare resets zero to current temperature**

**Effect 2: Span Drift**
- Mechanism: elastic modulus of steel changes with temperature — warmer beam is less stiff → higher reading per gram
- Magnitude: −0.01% per °C on the reading
- 10°C swing: 0.1% = **±29g on 29kg cylinder** — dominant error source in V1
- V2 mitigation: NTC thermistor + software correction → reduces to ±3g

**Effect 3: HX711 Reference Drift**
- Mechanism: internal bandgap reference has ~5 ppm/°C temperature coefficient
- 10°C swing: 0.005% = ±1.5g — negligible, no action needed

### F.3 Accuracy Budget (10°C Kitchen Swing)

| Error Source | Raw | After Mitigation | Residual |
|---|---|---|---|
| Zero drift | ±40g | Boot retare + S-cancellation | ~±5g |
| Span drift | ±29g | None (V1) | ±29g |
| HX711 reference | ±1.5g | Self-referencing | ±1.5g |
| BLE noise | 7.24g peak | N=200 + stability detection | ±2g |
| Vibration | ±500g peak | Stability detection discards | ±3g |
| cal_factor uncertainty | ±50g | Periodic validation | ±15g |
| **TOTAL (RSS)** | | **√(29²+5²+1.5²+2²+3²+15²)** | **≈ ±34g** |

**Total system accuracy ≈ ±34g on gas_kg — well within ±50g design target. (0.24% on 14.2kg full scale)**

### F.4 Temperature Gradient in 4-Cell Platforms

If one side of platform is closer to burner, cells are at different temperatures. In parallel bridge, all four outputs are averaged — the combined reading shows the **average drift**, not worst-case single-cell drift. The 4-cell topology naturally averages spatial temperature gradients.

**Practical rule:** Orient platform diagonal perpendicular to stove — diagonally opposite cells equidistant from burner.

### F.5 Cooking Event Interaction

During 30-minute cooking event at typical burn rate:
- Gas consumed: ~10g
- Temperature-induced zero drift (3°C rise): ~12g

These are comparable. This is why the **rolling 7-day burn rate window** is used — temperature errors are random in direction and cancel over the average. Single-event measurements are not reliable.

### F.6 V2 Temperature Compensation

Add 10kΩ NTC thermistor to base plate. Connect to ESP32 GPIO2. Apply span drift correction:

```python
T_cal = 28.0    # temperature when cal_factor was measured
alpha = 0.0001  # span drift coefficient per °C
G_corrected = G_raw * (1.0 + alpha * (T_cal - T_now))
```

Reduces span drift from ±29g to ±3g. Total system accuracy improves to ~±18g. Hardware cost: ₹20.

---

## Section G — Long Term Drift and Creep

### G.1 Two Distinct Phenomena

| | Zero Drift | Creep Under Load |
|--|-----------|-----------------|
| Timescale | Weeks to months | Hours (plateau in 2–4h) |
| Requires load? | No | Yes |
| Physical cause | Residual stress relaxation; adhesive curing | Metal viscoelasticity — atoms rearrange under sustained stress |
| Magnitude | ~10g/month (0.05% FS/month) | 30–80g total at plateau |
| Effect on consumption ΔG | **Cancels** — same drift in both readings | **Cancels** — plateau is stable, same offset in all readings |
| Effect on gas% absolute | Accumulates over months | Constant ~0.35% offset after plateau |
| Corrected by | Auto-tare at every delivery event | Stability window waits for recovery after removal |

### G.2 Creep Detail

- Beam begins deflecting when cylinder placed — initial reading is accurate
- Over 2–4 hours: beam slowly deforms ~30–80g more under sustained load (viscoelastic relaxation)
- Reading plateaus — remains stable for entire 30–45 day cycle
- Bias is **constant** → cancels in all consumption ΔG calculations
- Effect on gas%: 50g ÷ 14200g = **0.35%** — acceptable
- Anchor event reading taken shortly after placement = most accurate G_new (before creep begins)

### G.3 Creep Recovery After Removal

When cylinder removed after 30–45 days:
- Beam springs back elastically → overshoots slightly → recovers over 5–20 minutes
- Auto-tare stability window waits for genuine stabilisation (inter-window drift < 1.0g)
- Full wait after 30-day cylinder: typically 10–20 minutes

**Never take auto-tare immediately after removal.** The stability conditions protect against this.

### G.4 Long-Term Zero Drift

- Rate: ~10g per month (0.05% FS/month for YZC-161A class)
- Between delivery events (30–45 days): max accumulated drift ≈ 15g
- **Boot auto-tare completely resets all accumulated zero drift**
- If no delivery for >30 days: schedule drift estimation via consumption cross-check

### G.5 Cal_Factor Drift

- Rate: <0.1% per year (gauge adhesive aging)
- On 29.7kg: ~30g per year, ~90g after 3 years
- Monitored by cal_factor validation at every delivery event:

```python
gas_expected = CAPACITY_KG - total_consumed_since_install_kg
gas_actual   = G_last_reading_kg - steel_tare_kg
error_kg     = abs(gas_expected - gas_actual)

# error < 0.200 kg → CAL_OK
# error < 0.500 kg → CAL_DRIFT_MINOR — monitor
# error > 0.500 kg → CAL_DRIFT_MAJOR — recalibrate
```

Recalibration: place 10kg weight on empty platform, compute new cal_factor, update config.json. Takes 5 minutes. Expected at most once in product lifetime.

### G.6 Delivery Event as Natural Maintenance Cycle

Every 30–45 day delivery event automatically resets:

| What Resets | Mechanism |
|-------------|-----------|
| Zero drift | Auto-tare on empty platform |
| Creep | Stability window waits for spring-back recovery |
| cal_factor drift | Consumption cross-check validation |
| Steel tare S | Anchor event re-derives for new cylinder |
| Burn rate | Rolling window resets with new cylinder |

### G.7 Extended No-Removal Scenario

If no delivery for >30 days, schedule zero drift estimation:

```python
expected_G    = steel_tare_kg + (CAPACITY_KG - total_consumed_kg)
actual_G      = current_stable_G_kg
drift_est_kg  = actual_G - expected_G

if abs(drift_est_kg * 1000) > DRIFT_WARN_THRESHOLD_G:  # 100g
    log_warning("ZERO_DRIFT_ESTIMATED", drift_est_kg)
    gas_kg_display = gas_kg_raw - drift_est_kg  # optional soft correction
```

---

## Appendix 1 — All Locked Decisions and Constants

### config.py — Complete Constants

```python
# config.py — single source of truth for all system constants

REFILL_THRESHOLD_KG    = 6.0
# Derivation: min_jump at LOW_GAS_DAYS=10 high-burn household = 5.75kg → 6.0 has 0.25kg margin

FRESH_CYLINDER_MIN_KG  = 26.0
# Prevents partial-swap false anchor event. Min fresh full G = 14.5 + 14.05 = 28.55kg > 26kg

CAPACITY_KG            = 14.2   # BIS domestic regulation, fixed

CYLINDER_REMOVED_KG    = 2.0
# Dead zone: noise 0.0075kg to min empty cylinder 14.5kg. 2.0kg sits in middle.

STEEL_TARE_MIN_KG      = 14.5   # Indian domestic cylinder physical range
STEEL_TARE_MAX_KG      = 15.8   # Indian domestic cylinder physical range
STEEL_TARE_MIDPOINT_KG = 15.15  # V3 default — range midpoint

LOW_GAS_KG             = 2.0    # Alert: gas remaining below this
LOW_GAS_DAYS           = 10     # Alert: days remaining below this

BURN_RATE_WINDOW_DAYS  = 7      # Rolling window
MIN_HOURS_BURNRATE     = 24     # Minimum elapsed time before showing burn rate
                                 # NEVER use population averages — real data only

HEARTBEAT_MIN          = 15     # Weight reading every N minutes

VALIDATION_TOLERANCE_KG = 0.2   # cal_factor validation: OK threshold
VALIDATION_WARN_KG      = 0.5   # cal_factor validation: major warning threshold

DRIFT_WARN_THRESHOLD_G  = 100   # Zero drift estimate warning threshold

# V2 brand steel tare lookup
BRAND_STEEL_KG = {
    "Indane":  14.8,   # IOC
    "HP":      15.7,   # HPCL
    "Bharat":  15.3,   # BPCL
}
```

### config.json — Runtime State Schema

```json
{
  "calibration": {
    "cal_factor": 106.7,
    "tare_raw": -14000,
    "last_validated_ts": "2026-06-09T08:00:00"
  },
  "cylinder": {
    "steel_tare_kg": 15.5,
    "install_gross_kg": 29.7,
    "install_ts": "2026-06-09T08:15:00",
    "capacity_kg": 14.2,
    "anchor_exact": true,
    "brand": "HP"
  }
}
```

Absence of `cylinder` key = UNINSTALLED state.  
`anchor_exact: false` → show `~` prefix on all gas% displays.  
`anchor_exact: true` → show clean numbers.

### Master Locked Decision Table

| Decision | Locked Value | Reason |
|----------|-------------|--------|
| REFILL_THRESHOLD_KG | 6.0 kg | High-burn household worst-case |
| FRESH_CYLINDER_MIN_KG | 26.0 kg | Prevents false positive from partial swap |
| CAPACITY_KG | 14.2 kg | BIS domestic regulation |
| CYLINDER_REMOVED_KG | 2.0 kg | Dead zone analysis |
| Steel tare range | 14.5–15.8 kg | Physical measurement, Indian cylinders |
| V3 default S | 15.15 kg | Range midpoint, display biased low |
| V2 S source | Brand lookup table | User presses brand button — NOT gas estimate |
| Burn rate window | 24h minimum, 7-day rolling | Real data only, no population averages |
| cal_factor sequencing | Before G_new measurement | Corrupted G_new permanently corrupts S |
| anchor_exact flag | In config.json | Drives tilde prefix on approximate displays |
| Non-domestic detection | Derived S outside 14.5–15.8 kg | Catches 5kg/19kg/commercial cylinders |
| Excitation voltage | 3.3V (ESP32 3V3 rail) | ESP32 GPIO is 3.3V — never 5V |
| HX711 gain | 128 (Channel A) | Maximum sensitivity, matches cal_factor |
| HX711 rate | 10 SPS (RATE pin LOW) | Hardware 50Hz notch filter active |
| Corrupt filters | LONG_MIN, -1, 0x7FFFFF | All three always required |
| Platform size | 380×380mm | 300mm cell centres + 40mm inset |
| Plate material/thickness | Al 6061-T6, 5mm | Stiff, corrosion resistant |
| Cell free end mounting | Ball contact only — never bolted | Prevents moment constraint |
| Overload stop gap | 0.8mm | ~160% rated load limit |
| Cable length matching | ±20mm all four cells | Prevents differential attenuation |

---

## Appendix 2 — V1/V2/V3 Install Scenario Matrix

| | V1 — Fresh Cylinder | V2 — Partial + Brand | V3 — Partial Blind |
|-|--------------------|--------------------|------------------|
| First install trigger | Auto — G jump > 6kg AND G > 26kg | User presses brand button | Immediate — no input |
| S derivation | S = G_new − 14.2 (exact) | S = brand lookup ±300g | S = 15.15kg midpoint ±650g |
| Works immediately | Consumption + gas% exact + days after 24h | Consumption exact; gas% approx | Consumption exact; gas% as range |
| Gas% error until anchor | Zero — exact from install | ±1–3% | ±5–8% (shown as range) |
| anchor_exact | true | false until first anchor | false until first anchor |
| Converges to exact | Immediately | First fresh cylinder anchor | First fresh cylinder anchor |
| After first anchor | — | Identical to V1 | Identical to V1 |

---

## Appendix 3 — Complete Boot and Tare Sequence

### Boot Sequence

1. Power on — ESP32-C3 boots, GPIO initialised
2. BLE stack initialisation
3. HX711 power on — pins configured
4. HX711 warmup: **400ms** (bandgap reference stabilisation)
5. Discard first 5 HX711 readings (powerup transients)
6. Load config.json — parse cal_factor, tare_raw, cylinder block
7. Take N=20 quick readings to estimate current G
8. Branch on G vs CYLINDER_REMOVED_KG:
   - Empty platform → auto-tare sequence
   - Cylinder present + cylinder block in config → resume TRACKING
   - Cylinder present + no cylinder block → V2/V3 partial path

### Auto-Tare Sequence

1. Confirm G < CYLINDER_REMOVED_KG for 5 consecutive readings
2. Stability check loop:
   - Condition 1: window spread < 2.5g
   - Condition 2: inter-window mean drift < 1.0g across 3 consecutive windows
   - Wait until both conditions pass — no timeout
3. Take N=200 readings — compute mean
4. Store mean as new tare_raw in config.json
5. Log auto-tare event (timestamp + new tare_raw)

### Anchor Event Sequence

1. Detect G jump: (current_G − previous_stable_G) > REFILL_THRESHOLD_KG (6.0 kg)
2. Begin stability monitoring on new G
3. Wait for 3 consecutive windows: spread < 2.5g AND drift < 1.0g
4. Check: G_stable > FRESH_CYLINDER_MIN_KG (26.0 kg)?
5. Compute S = G_stable − CAPACITY_KG (14.2 kg)
6. Validate: STEEL_TARE_MIN_KG ≤ S ≤ STEEL_TARE_MAX_KG
   - Out of range → flag non-domestic, log warning, request confirmation
7. Write cylinder block to config.json atomically (write .tmp → rename)
8. Transition to TRACKING
9. Begin consumption recording

---

## Appendix 4 — Key Formulas Reference

### Core Measurement Chain

```python
raw_reading    = hx711_read()                           # 24-bit signed int
gross_kg       = (raw_reading - tare_raw) / cal_factor / 1000
gas_kg         = gross_kg - steel_tare_kg               # S cancels in ΔG
gas_pct        = gas_kg / CAPACITY_KG * 100
days_remaining = gas_kg / burn_rate_kg_per_day          # requires ≥24h history
```

### Consumption (S-Cancellation)

```python
gas_used_t1_t2  = gross_kg_t1 - gross_kg_t2            # S cancels — exact always
burn_rate_kgday = sum(gas_used) / elapsed_hours * 24   # rolling 7-day window
```

### Accuracy Budget (RSS)

```python
total_error_g = sqrt(zero_drift**2 + span_drift**2 + hx711_ref**2
                     + noise**2 + vibration**2 + cal_error**2)
             # = sqrt(5**2 + 29**2 + 1.5**2 + 2**2 + 3**2 + 15**2)
             # ≈ 34g
```

### Threshold Derivations

```
REFILL_THRESHOLD_KG:
  min_new_full_G  = STEEL_TARE_MIN + (CAPACITY - fill_tol) = 14.5 + 14.05 = 28.55 kg
  max_old_G_alert = STEEL_TARE_MAX + LOW_GAS_DAYS × max_daily_burn
                  = 15.8 + 10 × 0.700 = 22.8 kg  (high-burn household)
  min_jump        = 28.55 - 22.8 = 5.75 kg  →  6.0 kg gives 0.25 kg margin  ✓

CYLINDER_REMOVED_KG:
  noise floor (BLE running): 0.0075 kg
  lightest empty cylinder:   14.5 kg
  valid range for threshold: 0.0075 to 14.5 kg
  2.0 kg: comfortably in dead zone  ✓
```

### Span Drift Correction (V2)

```python
T_cal = 28.0    # calibration temperature (record at bench cal)
alpha = 0.0001  # elastic modulus drift coefficient per °C
G_corrected = G_raw * (1.0 + alpha * (T_cal - T_now))
# Reduces span drift from ±29g to ±3g
```

### cal_factor Self-Validation

```python
gas_expected = CAPACITY_KG - total_consumed_since_install_kg
gas_actual   = gross_kg - steel_tare_kg
error_kg     = abs(gas_expected - gas_actual)

# error < 0.200 → CAL_OK
# error < 0.500 → CAL_DRIFT_MINOR — monitor
# error > 0.500 → CAL_DRIFT_MAJOR — recalibrate
```

---

*End of document.*  
*gas-cylinder-monitor | Gratian Technologies | June 2026*  
*Project repository: gratiantechnologies/project13 | Board: arduino@AQ3*  
*Path: ~/ArduinoApps/gas-cylinder-monitor/*
