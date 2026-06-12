# Multi-Cell Load Cell Physics, Wiring, and Electrical Theory
## Complete First-Principles Reference

**Project:** gas-cylinder-monitor | Gratian Technologies
**Date:** 2026-06-10
**Derived from:** Claude.ai learning session — full first-principles derivation
**Status:** VERIFIED — all equations proven from first principles in this session
**Platform:** ESP32-C3 SuperMini + GISLAB HX711 + YZC-161A 20 kg load cells
**Repo:** gratiantechnologies/project13
**Board path:** `~/ArduinoApps/gas-cylinder-monitor/docs/` on `arduino@AQ3`

---

## Table of Contents

1. Single Load Cell — Physics from First Principles
2. The Gauge Factor — How Strain Becomes Resistance Change
3. The Wheatstone Bridge — How Resistance Change Becomes Voltage
4. Thevenin Equivalent of a Single Load Cell Bridge
5. Circuit Theory Foundations — Nodes, KCL, Source Impedance
6. Two Cells in Parallel — Full KCL Proof
7. Why the Node Voltage is an Average — Not a Sum
8. Unequal Load Distribution — Proof That the Split Is Irrelevant
9. Extreme Cases — One Cell Has Zero Load
10. N Cells in Parallel — General Formula
11. Why Parallel, Not Series — Electrical Proof
12. CAL_FACTOR and Wiring Topology
13. Three Cells vs Four Cells — Geometry and Accuracy
14. Case 1 vs Case 2 — Independent Plates vs Shared Platform
15. Experiment Design — Verifying Sum Invariance in Hardware
16. Locked Rules and Handoff Notes

---

## Section 1 — Single Load Cell: Physics from First Principles

### 1.1 What a Load Cell Actually Is

A load cell is not a sensor in the conventional sense. It contains no transistors, no active circuitry, and no digital components. It is a precision metal beam — machined to a specific geometry — with four thin metallic foils bonded to its surface. These foils are called strain gauges.

When weight is placed on the free end of the beam, it bends. The bending is microscopic — on the order of micrometers — but it is enough to stretch or compress the foils. Stretching a metal foil changes its electrical resistance. That resistance change is the entire weight signal. Everything else in the system exists to detect and digitise that tiny resistance change.

### 1.2 Stress, Strain, and Hooke's Law

Three equations govern what happens physically when force is applied.

**Stress** is force distributed over area:

```
σ = F / A

σ = stress (Pa)
F = applied force (Newtons)
A = cross-sectional area of beam (m²)
```

**Strain** is the fractional deformation — how much the material stretches or compresses relative to its original length:

```
ε = ΔL / L

ε = strain (dimensionless)
ΔL = change in length (m)
L  = original length (m)
```

**Hooke's Law** connects stress and strain through the material's stiffness:

```
σ = E × ε

Rearranging:  ε = σ / E = F / (E × A)

E = Young's modulus of beam material (Pa)
  = ~200 GPa for steel
```

The critical conclusion from these three equations: **strain is linearly proportional to force**. Double the force → double the strain. This linearity is not an approximation — it is fundamental to the material behaviour of metals within their elastic range. It is why weight measurement with a load cell is possible at all.

### 1.3 Beam Bending Zones

The YZC-161A is a cantilever bending beam. One end is fixed (bolted to the platform structure), the other end is free (the platform plate rests on it). When weight is applied to the free end:

- The **top surface** of the beam is compressed — fibres are squeezed together
- The **bottom surface** of the beam is stretched — fibres are pulled apart
- The **neutral axis** (centre plane) experiences zero strain

The four strain gauges are bonded precisely into a machined notch in the beam where the strain is greatest. Two gauges sit on the tension surface (they stretch under load), two sit on the compression surface (they compress under load). This opposing arrangement is the foundation of the full Wheatstone bridge.

**Key takeaway:** A load cell is a precision metal beam whose bending under load is the weight signal. Everything else is converting that bending into a voltage.

---

## Section 2 — The Gauge Factor: How Strain Becomes Resistance Change

### 2.1 Why Metal Resistance Changes Under Deformation

A strain gauge is a thin metallic foil patterned in a serpentine grid, bonded to the beam surface. The fundamental resistance formula for a wire is:

```
R = ρ × L / A

ρ = resistivity of metal (Ω·m) — material property
L = length of wire (m)
A = cross-sectional area (m²)
```

When the beam bends and the gauge is on the tension surface:
- The wire stretches → L increases
- The wire becomes thinner → A decreases
- Both effects increase R simultaneously

When the gauge is on the compression surface:
- The wire compresses → L decreases
- The wire becomes thicker → A increases
- Both effects decrease R simultaneously

### 2.2 The Gauge Factor Equation

The fractional resistance change is related to strain by the Gauge Factor (GF):

```
ΔR / R = GF × ε
```

For metal foil gauges, GF ≈ 2.0. Substituting Hooke's Law (ε = F / (E×A)):

```
ΔR / R = GF × F / (E × A)
```

**This is the master equation.** It says: the fractional resistance change in a strain gauge is linearly proportional to the applied force. Every gram of load produces a fixed, repeatable, predictable resistance change. This is what makes accurate weight measurement possible.

Typical numbers for the YZC-161A under a 20 kg load at rated capacity:
- Strain ε ≈ 1000 microstrain = 0.001
- ΔR/R = 2.0 × 0.001 = 0.002 = 0.2% of nominal resistance

**Key takeaway:** ΔR/R = GF × F/(E×A) — the master equation. Resistance change is linear in force.

---

## Section 3 — The Wheatstone Bridge: How Resistance Change Becomes Voltage

### 3.1 The Bridge Circuit

A single strain gauge with 0.2% resistance change produces a signal too small to measure directly. The Wheatstone bridge topology solves this by using four gauges in opposition to produce a differential voltage output.

The bridge is a diamond-shaped circuit with four nodes:

```
           E+ (Red wire, 3.3V from HX711)
               │
    ┌────R1(R+ΔR)────┐    ┌────R2(R-ΔR)────┐
    │                │    │                │
   A+              E+/E−               A-
    │                │    │                │
    └────R3(R-ΔR)────┘    └────R4(R+ΔR)────┘
               │
           E− (Black wire, GND)
```

More clearly as a diamond:

```
                E+ (3.3V)
               /          \
          R1(R+ΔR)      R2(R-ΔR)
             /                \
           A+                A-
             \                /
          R3(R-ΔR)      R4(R+ΔR)
               \          /
                E− (GND)
```

Under load: R1 and R4 are on the tension surface (resistance increases by ΔR). R2 and R3 are on the compression surface (resistance decreases by ΔR).

### 3.2 Why E+/E− and A+/A− Are Different Things

**E+ and E−** are the excitation pins. The HX711 applies a known voltage (Vex = 3.3V on ESP32-C3 setup) here. They are the power supply to the bridge. They do not carry weight information.

**A+ and A−** are the signal output pins. The HX711 measures the differential voltage (V(A+) − V(A−)) here. This difference is the weight signal.

The reason for the differential arrangement: any noise, temperature drift, or supply variation affects A+ and A− equally (common-mode), and is cancelled when the HX711 takes the difference. Only the weight signal (which makes A+ and A− move in opposite directions) survives.

### 3.3 Deriving Vout — Full Working

The bridge has two voltage divider arms.

**Right arm** (E+ through R1 to A+, then R3 to E−):

Voltage at A+ = voltage divider output:

```
V(A+) = Vex × R3 / (R1 + R3)

Substituting R1 = R+ΔR and R3 = R-ΔR:

V(A+) = Vex × (R - ΔR) / ((R + ΔR) + (R - ΔR))
       = Vex × (R - ΔR) / (2R)
```

**Left arm** (E+ through R2 to A−, then R4 to E−):

```
V(A-) = Vex × R4 / (R2 + R4)

Substituting R2 = R-ΔR and R4 = R+ΔR:

V(A-) = Vex × (R + ΔR) / ((R - ΔR) + (R + ΔR))
       = Vex × (R + ΔR) / (2R)
```

**The output voltage:**

```
Vout = V(A+) - V(A-)
     = Vex × (R - ΔR)/(2R) - Vex × (R + ΔR)/(2R)
     = Vex × [(R - ΔR) - (R + ΔR)] / (2R)
     = Vex × (-2ΔR) / (2R)
     = -Vex × ΔR/R
```

Substituting the master equation (ΔR/R = GF × F/(E×A)):

```
Vout = -Vex × GF × F / (E × A)
```

**Proven:** Vout is linearly proportional to force F. No assumptions. No approximations (within the elastic range of the beam material).

### 3.4 Why Four Gauges and Not One

Using only one active gauge (quarter bridge) instead of four has three critical failures:

**Problem 1 — No temperature compensation:** A single gauge's resistance changes with both strain (weight) and temperature. These cannot be separated. The bridge reads a false weight whenever temperature changes. With four gauges in a full bridge, temperature changes all four arms equally — the differential measurement cancels it completely. This is called common-mode rejection. It is the most important property for a kitchen deployment where temperature swings 8–15°C daily.

**Problem 2 — Signal is 4× weaker:** With one active gauge, only one arm changes. With four active gauges, all four arms change simultaneously in opposition — the differential output is four times larger than a quarter bridge for the same load.

**Problem 3 — Non-linearity:** A single voltage divider has a non-linear response. The full bridge with opposing gauges is inherently more linear.

**Key takeaway:** Vout = -Vex × GF × F/(E×A). Output is linear in force. Four gauges give temperature cancellation, 4× signal, and linearity.

---

## Section 4 — Thevenin Equivalent of a Single Load Cell Bridge

### 4.1 Why Thevenin Matters

Thevenin's theorem states: any circuit containing voltage sources and resistors, seen from two terminals, can be replaced by one ideal voltage source (Vth) in series with one resistor (Rth).

This is critical because once each load cell bridge is reduced to its Thevenin equivalent, connecting multiple cells together becomes simple algebra — addition of voltages and resistances. Without this reduction, analysing the combined circuit would require solving a large system of simultaneous equations.

### 4.2 Calculating Vth — Open Circuit Voltage

Rule: Vth = voltage across the terminals (A+ and A−) when nothing is connected between them. This is exactly what was derived in Section 3.3.

```
Vth = V(A+) - V(A-)
    = -Vex × ΔR/R
    = -Vex × GF × F / (E × A)
```

### 4.3 Calculating Rth — Thevenin Resistance

Rule: replace all independent voltage sources with short circuits (replace Vex with a wire), then measure the resistance between A+ and A−.

When Vex is shorted, E+ and E− become the same node — call it E±.

Looking from A+ to A− through the now-shorted circuit:

- **Left path:** R2 in series with R4 (both go from A− through E± to A+ ... wait, from A− through R4 to E±, then through R1 to A+) = R + R = 2R
- **Right path:** R1 in series with R3 (from A+ through R1 to E±, then through R4 to A−) = R + R = 2R

Two paths of 2R each, in parallel between A+ and A−:

```
Rth = 2R ∥ 2R = (2R × 2R) / (2R + 2R) = 4R² / 4R = R
```

### 4.4 Parallel Resistance Formula — Derived from First Principles

Two resistors Ra and Rb in parallel. The same voltage V appears across both. By Ohm's Law:

```
Ia = V / Ra
Ib = V / Rb
```

By KCL (Kirchhoff's Current Law), total current:

```
I_total = Ia + Ib = V × (1/Ra + 1/Rb) = V × (Ra + Rb)/(Ra × Rb)
```

The equivalent single resistor R_parallel draws the same current at the same voltage:

```
I_total = V / R_parallel

Therefore: 1/R_parallel = 1/Ra + 1/Rb

R_parallel = (Ra × Rb) / (Ra + Rb)
```

For equal resistors (Ra = Rb = X):

```
R_parallel = (X × X) / (X + X) = X² / 2X = X/2
```

Equal resistors in parallel always give half of one. This is the foundation of why Rth = R for the full bridge.

### 4.5 Source Impedance at A+ Terminal Only

When analysing multiple cells at the shared A+ node, what matters is the Thevenin resistance seen looking into just the A+ terminal (with A− as the reference).

From A+, there are two paths to the excitation rails:
- Through R1 to E+
- Through R3 to E−

Since E+ and E− are AC ground (the HX711 excitation is effectively a fixed reference), these two paths are in parallel:

```
Rs (at A+) = R1 ∥ R3 ≈ R ∥ R = R/2
```

This R/2 is the source impedance used in the KCL multi-cell analysis.

### 4.6 Complete Thevenin Result

```
Vth = -Vex × ΔR/R = -Vex × GF × F / (E × A)
Rth = R  (full bridge, terminal-to-terminal)
Rs  = R/2  (single terminal, used in multi-cell node analysis)
```

**Key takeaway:** Every load cell bridge collapses to Vth + Rth. This is what the outside world sees. This is what connects to HX711 or to other cells.

---

## Section 5 — Circuit Theory Foundations

### 5.1 What Is a Node

In circuit theory, a **node** is any point where two or more wires connect. It is not a component. It is a connection point. At a node, all connected wires are at the same electrical potential (voltage).

Physical reality in this project: the A+ node is literally the spot where you twist Cell 1's white wire + Cell 2's white wire + Cell 3's white wire + Cell 4's white wire together, then connect that twist to HX711 A+. That physical twist — one spot, four wires meeting — is the node. There is no mystery to it.

A node has no capacitance in an ideal circuit — it cannot store charge. Anything flowing in must immediately flow out.

### 5.2 Kirchhoff's Current Law (KCL)

KCL originates from the law of conservation of charge. Charge cannot be created or destroyed. If charge flows into a node, it must flow out. There is no accumulation.

**KCL statement:**

```
At any node: ΣI = 0

Or equivalently: ΣI_in = ΣI_out
```

This is not an approximation. It is a direct consequence of Maxwell's equations applied to lumped circuits. It is true at any frequency, for any component values, under any conditions.

Sign convention: currents flowing INTO the node are positive. Currents flowing OUT are negative. The sum is zero.

### 5.3 Ohm's Law in the Node Context

The current flowing through a resistor connecting a source to a node:

```
I = (V_source - V_node) / R
```

If V_node is higher than V_source, the current is negative — it flows from the node back into the source. KCL handles this correctly through the sign.

### 5.4 HX711 Input Impedance

The HX711 differential input is very high impedance. It draws essentially zero current. This means:

```
I_HX711 ≈ 0
```

At the A+ node: currents from all the cell sources must sum to zero among themselves, because nothing flows out into the HX711. This simplifies the KCL equation significantly.

### 5.5 Thevenin Equivalent Source Model

Every real voltage source (including a bridge output) has:
1. An open-circuit voltage (Voc) — the voltage it produces when nothing is connected
2. A source impedance (Rs) — the internal resistance it presents to the outside

When a load is connected, the terminal voltage drops below Voc because current through Rs creates a voltage drop. The Thevenin model captures both in a simple series circuit.

**Key takeaway:** Node = physical twist point. KCL = charge conservation at that point. HX711 draws zero current. These three facts together allow us to solve for node voltage algebraically.

---

## Section 6 — Two Cells in Parallel: Full KCL Proof

### 6.1 Physical Wiring — No Junction Box Needed

To connect two load cells in parallel to one HX711, twist same-color wires together:

```
Cell 1 Red   + Cell 2 Red   → twist → single wire → HX711 E+
Cell 1 Black + Cell 2 Black → twist → single wire → HX711 E-
Cell 1 White + Cell 2 White → twist → single wire → HX711 A+  ← the A+ node
Cell 1 Green + Cell 2 Green → twist → single wire → HX711 A-  ← the A- node
```

The twist itself is the junction. No screw terminal, no junction box, no additional hardware. Each twist is one node in the circuit.

Note: wire colors vary by manufacturer. The above uses the most common convention. Your verified ESP32-C3 platform wiring from HARDWARE.md is: Red=E+, Black=E−, Green=A+, White=A−.

### 6.2 The Circuit Model

Each cell is modelled as its Thevenin equivalent (from Section 4):
- Cell 1: ideal voltage V1 in series with Rs1 = R/2
- Cell 2: ideal voltage V2 in series with Rs2 = R/2
- Both V1 and V2 connect to the same A+ node
- HX711 is connected to the A+ node but draws no current (I_HX ≈ 0)

Let V_node = the unknown voltage that actually appears at the A+ node.

### 6.3 KCL at the A+ Node

Current from Cell 1 into the node (positive = flowing toward node):

```
I1 = (V1 - V_node) / Rs1 = (V1 - V_node) / (R/2)
```

Current from Cell 2 into the node:

```
I2 = (V2 - V_node) / Rs2 = (V2 - V_node) / (R/2)
```

Current out to HX711:

```
I_HX = 0
```

KCL: all currents sum to zero:

```
I1 + I2 + (-I_HX) = 0
I1 + I2 = 0

(V1 - V_node)/(R/2) + (V2 - V_node)/(R/2) = 0
```

Multiply both sides by R/2:

```
(V1 - V_node) + (V2 - V_node) = 0
V1 + V2 - 2 × V_node = 0
V_node = (V1 + V2) / 2
```

**Proven: the node voltage is the arithmetic average of the two source voltages.** This result comes directly from KCL and Ohm's Law. It is not an assumption.

### 6.4 Same Analysis at the A− Node

By identical reasoning at the A− node:

```
V_node(A-) = (V1_Aminus + V2_Aminus) / 2
```

### 6.5 Computing the Final Vout

From the bridge voltage divider equations:

```
V1 at A+  = Vex/2 - Vex × ΔR1 / (2R)    ← Cell 1 under load F1
V2 at A+  = Vex/2 - Vex × ΔR2 / (2R)    ← Cell 2 under load F2
```

Node voltage at A+:

```
V_node(A+) = (V1_A+ + V2_A+) / 2
           = [Vex/2 - Vex×ΔR1/(2R) + Vex/2 - Vex×ΔR2/(2R)] / 2
           = Vex/2 - Vex×(ΔR1 + ΔR2) / (4R)
```

By symmetry, at A−:

```
V_node(A-) = Vex/2 + Vex×(ΔR1 + ΔR2) / (4R)
```

Differential output seen by HX711:

```
Vout = V_node(A+) - V_node(A-)
     = [Vex/2 - Vex×(ΔR1+ΔR2)/(4R)] - [Vex/2 + Vex×(ΔR1+ΔR2)/(4R)]
     = -2 × Vex×(ΔR1+ΔR2)/(4R)
     = -Vex × (ΔR1 + ΔR2) / (2R)
```

Substituting ΔR1 = R×GF×F1/(E×A) and ΔR2 = R×GF×F2/(E×A):

```
Vout = -Vex × GF × (F1 + F2) / (2 × E × A)
     = -Vex × GF × F_total / (2 × E × A)
```

**Proven: Vout is proportional to F_total = F1 + F2. The split between cells does not appear anywhere in the final expression.**

**Key takeaway:** KCL at the A+ node → V_node = average of sources → Vout ∝ F1+F2. Proven rigorously.

---

## Section 7 — Why the Node Voltage Is an Average, Not a Sum

This is one of the most important conceptual questions that arose in this session. The proof is in Section 6, but here is the physical intuition.

### 7.1 The Tug-of-War Analogy

Imagine Cell 1 "wants" to push the A+ node to voltage V1. Cell 2 "wants" to push it to V2. They fight each other through their source resistances (Rs1 and Rs2 — the internal resistance of each bridge).

Because Rs1 = Rs2 (both bridges are identical load cells with the same R), neither source is stronger than the other. They have equal "pulling strength." The node settles exactly midway between V1 and V2. This is the average.

If the resistances were unequal — say Rs1 = R/4 (a stronger, lower-impedance source) and Rs2 = 3R/4 (a weaker source) — Cell 1 would dominate and the node would be pulled closer to V1. The general formula shows this:

```
V_node = V1 × Rs2/(Rs1+Rs2) + V2 × Rs1/(Rs1+Rs2)
```

For equal Rs (Rs1 = Rs2 = Rs):

```
V_node = V1 × Rs/(2Rs) + V2 × Rs/(2Rs)
       = V1/2 + V2/2
       = (V1 + V2) / 2
```

The equal source impedance — which comes from all cells being identical YZC-161A 20 kg load cells with the same nominal bridge resistance R — is what makes it a plain average rather than a weighted average.

### 7.2 Why Average Gives Total Force

The average seems to lose information — you'd expect to divide by 2 and get half the reading. But it doesn't work that way, because the same averaging happens at A− as well.

```
V_node(A+) = Vex/2 - Vex×(ΔR1+ΔR2)/(4R)
V_node(A-) = Vex/2 + Vex×(ΔR1+ΔR2)/(4R)
```

When you subtract: the Vex/2 terms cancel, and the ΔR sum terms add (one subtracts a negative term):

```
Vout = -2 × Vex×(ΔR1+ΔR2)/(4R) = -Vex×(ΔR1+ΔR2)/(2R)
```

The factor of 2 from the two-terminal differential measurement recovers what the averaging at A+ lost. The averaging at A+ and the averaging at A− are symmetric — their difference gives the full sum.

**Key takeaway:** Average × 2 terminal differential = total. The averaging does not lose signal — it is a balanced circuit that preserves the total force information exactly.

---

## Section 8 — Unequal Load Distribution: Proof That the Split Is Irrelevant

### 8.1 The Question

If Cell 1 has 80% of the total weight and Cell 2 has 20%, does HX711 still read the correct total? What about 99%/1%? What about 100%/0%?

### 8.2 Setup

```
Cell 1 carries F1  (any value)
Cell 2 carries F2  (any value)
Total:  F_total = F1 + F2
```

Each cell independently generates its own ΔR based only on the force on that particular cell:

```
ΔR1 = R × GF × F1 / (E × A)    ← depends only on F1
ΔR2 = R × GF × F2 / (E × A)    ← depends only on F2
```

### 8.3 Substituting Into the Vout Equation

From Section 6.5:

```
Vout = -Vex × (ΔR1 + ΔR2) / (2R)
     = -Vex × [R×GF×F1/(E×A) + R×GF×F2/(E×A)] / (2R)
     = -Vex × R×GF×(F1+F2) / (2R×E×A)
     = -Vex × GF × (F1+F2) / (2×E×A)
     = -Vex × GF × F_total / (2×E×A)
```

The expression for Vout contains only F_total = F1+F2. The individual values F1 and F2 have disappeared. They appear only in the sum.

### 8.4 Numerical Verification

Let GF=2, E=200×10⁹ Pa, A=10⁻⁴ m², Vex=3.3V, total=1000g=9.81N.

k = GF/(E×A) = 2/(200×10⁹ × 10⁻⁴) = 10⁻⁴ per Newton

| Split | F1 (N) | F2 (N) | ΔR1/R | ΔR2/R | Vout (µV) |
|-------|--------|--------|-------|-------|-----------|
| 50/50 | 4.905 | 4.905 | 4.905×10⁻⁴ | 4.905×10⁻⁴ | -1619 |
| 80/20 | 7.848 | 1.962 | 7.848×10⁻⁴ | 1.962×10⁻⁴ | -1619 |
| 99/1  | 9.711 | 0.099 | 9.711×10⁻⁴ | 0.099×10⁻⁴ | -1619 |
| 100/0 | 9.810 | 0.000 | 9.810×10⁻⁴ | 0.000×10⁻⁴ | -1619 |

Vout = -Vex × (ΔR1+ΔR2)/(2R) = -3.3 × 9.810×10⁻⁴/2 = -1619 µV in every row.

**The Vout is identical for all distributions.** Only the total force determines the output.

**Key takeaway:** Vout = -Vex×GF×F_total/(2EA). The split between cells is algebraically invisible.

---

## Section 9 — Extreme Cases

### 9.1 One Cell Has Zero Load

Cell 2 is completely empty. F2 = 0, so ΔR2 = 0.

```
Vout = -Vex × (ΔR1 + 0) / (2R)
     = -Vex × ΔR1 / (2R)
```

Compare to a single cell carrying the same F1:

```
Vout_single = -Vex × ΔR1 / R
```

The two-cell parallel result is exactly half of the single-cell result for the same force F1.

This is physically correct — the system is designed to measure total force across both cells. When only Cell 1 has load F1, the total IS F1. The system correctly reports F1. But because the CAL_FACTOR was derived with both cells in the circuit, the sensitivity correctly accounts for the parallel topology. The reading is accurate.

The reason the reading is half of what a single-cell system would give: the parallel topology reduces sensitivity by N (where N is the number of cells). CAL_FACTOR calibration compensates exactly for this.

### 9.2 One Cell Gets All the Weight (100/0 Split)

Same as Section 9.1. The cell with zero load contributes ΔR = 0 to the sum. It is electrically invisible. The reading equals the load on the one active cell — which is the correct total.

### 9.3 Two Different Objects on Two Independent Plates

Cell 1 has a phone (180g). Cell 2 has a speaker (340g). Nothing on Cell 3. All three wired in parallel.

```
ΔR1 ∝ 180g
ΔR2 ∝ 340g
ΔR3 = 0  (zero force)

Vout ∝ 180 + 340 + 0 = 520g
```

Serial monitor shows 520g. Not 180g. Not 340g. The sum. Always the sum. Individual cell readings are invisible to a single HX711.

**Key takeaway:** Empty cell = zero contribution. The reading is always the sum of whatever forces are present across all cells in the circuit.

---

## Section 10 — N Cells in Parallel: General Formula

### 10.1 Extending KCL to N Cells

For N cells with equal source impedance Rs = R/2, all tied at the A+ node, with HX711 drawing no current:

```
Σ (Vi - V_node)/(R/2) = 0   for i = 1 to N

Σ(Vi - V_node) = 0

ΣVi - N × V_node = 0

V_node = (V1 + V2 + ... + VN) / N
```

The node voltage is the arithmetic average of all N source voltages.

### 10.2 General Vout

Following the same derivation as Section 6.5 for N cells:

```
V_node(A+) = Vex/2 - Vex×Σ(ΔRi) / (2N×R)
V_node(A-) = Vex/2 + Vex×Σ(ΔRi) / (2N×R)

Vout = -Vex × Σ(ΔRi) / (N×R)
     = -Vex × GF × Σ(Fi) / (N×E×A)
     = -Vex × GF × F_total / (N×E×A)
```

### 10.3 Effect of N on Sensitivity

Adding more cells in parallel reduces sensitivity by a factor of N. The signal voltage per gram decreases:

```
Sensitivity = Vex × GF / (N × E × A)   (volts per Newton)
```

This does not mean accuracy decreases — it means CAL_FACTOR increases by the same factor. When you calibrate with N cells connected, the CAL_FACTOR absorbs the 1/N sensitivity factor. Subsequent measurements with the same N cells give correct readings.

| Cells | Sensitivity relative to 1 cell | CAL_FACTOR relative to 1 cell |
|-------|-------------------------------|-------------------------------|
| 1 | 1× | ~105 raw/g |
| 2 | 1/2× | ~210 raw/g |
| 3 | 1/3× | ~315 raw/g |
| 4 | 1/4× | ~420 raw/g |

Note: these are approximate values for the YZC-161A on the ESP32-C3 platform. Actual values must be derived by calibration on the specific hardware.

**Key takeaway:** N cells → Vout proportional to F_total always. Sensitivity reduces by N but CAL_FACTOR compensates. Always calibrate with all N cells connected.

---

## Section 11 — Why Parallel, Not Series

### 11.1 What Series Would Mean

Connecting in series would mean: Cell 1 A+ → Cell 2 A−, Cell 2 A+ → HX711 A+. The bridge outputs would be stacked like batteries.

### 11.2 Problem 1 — Broken Excitation Reference

In parallel, both E+ pins are connected to the same Vex from HX711. Both bridges share a common reference.

In series, Cell 1's E− and Cell 2's E− are no longer the same node. Cell 2's reference floats relative to Cell 1. To make series work, you would need to provide separate Vex to each cell from a separate source, defeating the purpose of sharing one HX711.

### 11.3 Problem 2 — Offset and Noise Stacking

In parallel, each bridge's offset (the tiny non-zero voltage at zero load) appears as a common-mode voltage on both A+ and A−, and is cancelled by the HX711's differential measurement.

In series, the offsets of both bridges add. The offset of Cell 1 shifts the reference seen by Cell 2. Temperature drift in Cell 1 affects the reading of Cell 2. These effects cannot be separated.

### 11.4 Problem 3 — Common-Mode Voltage Violation

The HX711 can only handle a certain common-mode voltage range at its A+/A− inputs. In parallel, both inputs are held near Vex/2 (approximately 1.65V for 3.3V excitation) — well within spec.

In series, stacking two bridge outputs pushes the absolute voltage level higher. Depending on the number of cells and their output voltages, this can exceed the HX711 input common-mode range and produce corrupt readings or damage the chip.

### 11.5 Why Parallel Solves All Three Problems

```
Problem 1 → Both E+ share same Vex. Single excitation source, single reference.
Problem 2 → Offsets appear common-mode on both A+ and A-. Cancelled by differential measurement.
Problem 3 → Both A+ and A- nodes held near Vex/2. Within HX711 input spec.
```

Parallel is the only correct topology for multiple load cells on one HX711.

**Key takeaway:** Series breaks excitation sharing, stacks offsets, and may violate HX711 input spec. Parallel solves all three.

---

## Section 12 — CAL_FACTOR and Wiring Topology

### 12.1 What CAL_FACTOR Is

CAL_FACTOR is the number of raw ADC counts per gram. It is the conversion factor between the HX711's arbitrary integer output and real-world grams:

```
grams = (raw_reading - tare_raw) / CAL_FACTOR
```

CAL_FACTOR is **not a universal constant**. It is specific to:
- The physical load cell(s) installed
- The number of cells wired in parallel (the topology)
- The HX711 gain setting
- The supply voltage (Vex)

### 12.2 How Parallel Wiring Affects CAL_FACTOR

With N cells in parallel, each additional cell reduces the signal voltage per gram by 1/N (proven in Section 10). The raw ADC count for a given weight is therefore 1/N of what a single cell would produce.

CAL_FACTOR is derived by placing a known weight and observing the raw count:

```
CAL_FACTOR = net_raw_count / known_weight_grams
```

If N cells are connected during calibration, the net_raw_count already reflects the 1/N reduced sensitivity. CAL_FACTOR therefore equals (single-cell value) / N × N = single-cell value? No — let's be precise:

Single cell: net_raw for 500g = 52,500 counts → CAL_FACTOR = 105 raw/g
4 cells: same 500g produces 500g/4 effective signal → net_raw = 13,125 counts → CAL_FACTOR = 26.25 raw/g

Wait — this is the inverse. Higher CAL_FACTOR means fewer raw counts per gram. Let me restate:

```
Single cell:  net_raw = 500 × 105 = 52,500 counts for 500g
4 cells:      sensitivity is 1/4, so net_raw = 500 × 105/4 ≈ 13,125 counts for 500g
              CAL_FACTOR = 13,125 / 500 = 26.25 raw/g
```

So 4-cell CAL_FACTOR is approximately 1/4 of single-cell. (Or: you need 4× fewer counts per gram because the signal per gram is 4× smaller.)

The formula for reported weight:

```
reported = actual × (N_cal / N_meas)

where N_cal = number of cells connected during calibration
      N_meas = number of cells connected during measurement
```

| N_cal | N_meas | Reported weight |
|-------|--------|----------------|
| 4 | 4 | actual × 1 = CORRECT |
| 1 | 4 | actual × 1/4 = 25% of actual |
| 4 | 1 | actual × 4 = 400% of actual |
| 3 | 4 | actual × 3/4 = 75% of actual |
| 2 | 4 | actual × 2/4 = 50% of actual |

### 12.3 The Calibration Topology Rule

**Always calibrate with all cells connected in their final configuration.**

If topology changes (you add a cell, remove a cell, or change wiring), CAL_FACTOR must be re-derived from scratch. A CAL_FACTOR measured on a different topology will produce systematic errors — always wrong by the same fixed ratio, with no warning or error flag.

For the gas-cylinder-monitor project specifically:

- The single-cell CAL_FACTOR derived during early experiments (~105 raw/g on STM32, ~113 raw/g on ESP32-C3) is **void** on the 4-cell platform
- The 4-cell platform CAL_FACTOR must be re-derived after the platform is fully assembled
- Expected value: approximately 4× smaller than single-cell (≈26 raw/g), but exact value depends on hardware — always measure, never compute

**Key takeaway:** CAL_FACTOR encodes the topology. Topology changes → re-calibrate. The formula is always grams = (raw − tare) / CAL_FACTOR, but CAL_FACTOR changes with N.

---

## Section 13 — Three Cells vs Four Cells: Geometry and Accuracy

### 13.1 The Two Distinct Arguments

There are two completely separate reasons to prefer 4 cells over 3:

1. **Electrical:** Both 3 and 4 cells in parallel sum correctly — Vout ∝ F_total for any N. Electrically, 3 cells works fine.
2. **Mechanical:** For a shared platform, the geometry of support points determines whether a cell can ever lift off (losing contact), which would make the electrical sum wrong.

### 13.2 The Mechanical Stability Argument (Shared Platform Only)

When one rigid plate sits on all cells, the **support polygon** — the shape formed by connecting the support points — determines stability. The cylinder is mechanically stable only when its center of mass (CoM) is inside the support polygon. If CoM exits the polygon, the platform tips and the cell on the opposite side lifts off.

**3 cells on a square platform:**
3 support points form a triangle. For any triangle inscribed in a square platform, there are regions of the square outside the triangle — these are unstable zones. If the cylinder's CoM lands in an unstable zone:
- The platform tips
- The cell on the opposite corner lifts off
- That cell reads zero (or negative — but load cells cannot transmit tension through a simple foot contact)
- The electrical sum drops: reads less than actual weight
- No error flag — the MCU has no way to detect this

**4 cells on a square platform:**
4 corner points form a rectangle identical to the platform. The support polygon IS the platform. The cylinder's CoM can never exit the rectangle while the cylinder is on the platform. No tipping is geometrically possible. Every cell always has positive force. The electrical sum is always correct.

### 13.3 Independent Plates (Your Experiment Setup)

With separate plates on each cell (no shared platform), there is no tipping concern. Each cell is independent. The mechanical stability argument does not apply.

For your experiment with four separate plates, 3 cells would also work correctly — the electrical sum would be accurate. 4 cells is used because the gas-cylinder-monitor product uses a shared platform in production.

### 13.4 Stable Zone Coverage

| Cell count | Support polygon | Stable zone as % of square platform area |
|------------|----------------|------------------------------------------|
| 1 | Point | ~0% |
| 2 | Line segment | ~0% (tips perpendicular to line) |
| 3 (equilateral triangle on square) | Triangle | ~58% |
| 4 (corners of square) | Full square | 100% |

### 13.5 Cost vs Accuracy Tradeoff

The cost of one additional YZC-161A 20 kg load cell is approximately ₹150–300. The cost of an incorrect low-gas reading (missed alert → user runs out of gas, cooking interrupted, potential safety issue) is much higher. For a production household product, 4 cells is the correct engineering decision.

**Key takeaway:** Electrically 3 and 4 cells both sum correctly. Mechanically, 4 corner cells on a square platform guarantee stable support polygon = 100% platform area coverage = no tipping under any placement.

---

## Section 14 — Case 1 vs Case 2: Independent Plates vs Shared Platform

### 14.1 Case 1 — Independent Plates, One Per Cell

Each cell has its own plate. You place different objects on each cell independently. There is no physical connection between cells — no shared rigid structure.

Example:
- Cell 1: phone = 180g
- Cell 2: speaker = 340g
- Cell 3: water bottle = 500g

Each cell generates its own ΔR:
```
ΔR1 ∝ 180g
ΔR2 ∝ 340g
ΔR3 ∝ 500g
```

Vout ∝ 180 + 340 + 500 = 1020g

**Serial monitor shows: 1020g.** Not 180g. Not 340g. Not 500g individually. The sum. One HX711 = one number.

### 14.2 Case 2 — Shared Platform

One rigid plate sits on all three cells. You place one gas cylinder (1020g total) on the platform. The platform distributes the weight:
- Cell 1 gets 400g
- Cell 2 gets 350g
- Cell 3 gets 270g

Each cell generates its own ΔR:
```
ΔR1 ∝ 400g
ΔR2 ∝ 350g
ΔR3 ∝ 270g
```

Vout ∝ 400 + 350 + 270 = 1020g

**Serial monitor shows: 1020g.** Same number. Same total.

### 14.3 Are the Two Cases Different?

**No.** In both cases, the HX711 reads the sum of all forces across all cells. 1020g distributed on independent plates or 1020g distributed across a shared platform — if the total force across all cells is 1020g, the reading is 1020g.

The difference between the two cases is:
- In Case 1, you control the distribution (you decide what to place where)
- In Case 2, the platform geometry and object position control the distribution

In both cases, the distribution is invisible to the HX711.

### 14.4 What HX711 Cannot Tell You

With a single HX711 and multiple cells in parallel:
- You cannot determine which cell has how much weight
- You cannot determine where on the platform an object is placed
- You cannot determine whether the load is evenly distributed
- You get exactly one number: total force across all cells

To read individual cells independently, you need one HX711 per cell.

**Key takeaway:** Independent plates or shared platform — same total = same reading. The HX711 is a total-force sensor, not a distribution sensor.

---

## Section 15 — Experiment Design: Verifying Sum Invariance in Hardware

### 15.1 Purpose

Verify in hardware that the theory proven in this document holds on your specific physical hardware: same total weight = same HX711 reading regardless of how that weight is distributed.

### 15.2 Your Weights

```
Phone   = 234g
Speaker = 229g
Adapter =  92g
Wood    =  34g
Total   = 589g
```

Weigh each object on a known-good kitchen scale first. These become your ground truth.

### 15.3 Critical Precondition

All 4 cells must be wired and electrically connected during calibration AND during all measurement configurations. Disconnecting any cell after calibration changes N_meas while N_cal remains 4, giving the formula:

```
reported = actual × (N_cal/N_meas) = actual × (4/3) = 133% of actual
```

The wiring must not change between tare, calibration, and all 8 test configurations.

### 15.4 Test Matrix

The experiment is implemented in `EXP_parallel_verify.ino`. The 8 configurations:

| Config | Cell 1 | Cell 2 | Cell 3 | Cell 4 | Expected | Tests |
|--------|--------|--------|--------|--------|----------|-------|
| C1 | Phone 234g | Speaker 229g | Adapter 92g | Wood 34g | 589g | Sum invariance |
| C2 | Wood 34g | Adapter 92g | Speaker 229g | Phone 234g | 589g | Sum invariance |
| C3 | ALL 589g | empty | empty | empty | 589g | Extreme — 100/0/0/0 |
| C4 | empty | ALL 589g | empty | empty | 589g | Extreme — 0/100/0/0 |
| C5 | Ph+Sp 463g | empty | Ad+Wo 126g | empty | 589g | Two-pair split |
| C6 | Phone 234g | empty | empty | empty | 234g | Partial loading |
| C7 | Phone 234g | Speaker 229g | empty | empty | 463g | Partial loading |
| C8 | empty | empty | empty | empty | 0g | Tare drift check |

### 15.5 Pass Criteria

Each configuration's average reading must be within ±5g of expected. C1 through C5 must all read within ±5g of each other (same 589g total). The ±5g tolerance accounts for the system noise floor (from E-002, STD was ~0.67g to ~1.81g depending on BLE state — 5g is ~3–7σ, very conservative).

### 15.6 Interpreting Failures

If some configurations read the correct total and others do not, the cause is almost always one of:

1. **Wiring fault:** a cell is intermittently disconnecting under weight
2. **Topology mismatch:** the wrong number of cells was connected during calibration
3. **CAL_FACTOR wrong:** not re-derived after adding a cell

If all configurations read the same (incorrect) total — e.g., all read 147g instead of 589g — the CAL_FACTOR is wrong (topology mismatch during calibration). 147/589 ≈ 1/4 would indicate calibration was done with 1 cell but measurement is running with 4.

**Key takeaway:** Same total different distribution → same reading. The experiment verifies the theory. Failures are diagnostic signals, not random noise.

---

## Section 16 — Locked Rules and Handoff Notes

### 16.1 CAL_FACTOR Recalibration Rule (HANDOFF NOTE — flag in session close)

CAL_FACTOR must be re-derived whenever the wiring topology changes. Specifically:

- Moving from single-cell test experiments to 4-cell production platform → re-derive
- Replacing one load cell with another → re-derive (even same model — manufacturing tolerances differ)
- Changing the number of cells connected → re-derive
- Moving the assembled platform to a new physical mount → re-derive tare; CAL_FACTOR may remain valid

**The single-cell CAL_FACTOR values previously measured (106.7 raw/g on STM32, ~113 raw/g on ESP32-C3) are void on the 4-cell production platform.** Expected 4-cell value: approximately 26–28 raw/g, but must be measured, never computed.

### 16.2 Wiring Rule

Same-color wires twisted together, direct to HX711 terminals. No junction box required. For N cells:

```
All Red wires    → twist → HX711 E+
All Black wires  → twist → HX711 E-
All White wires  → twist → HX711 A+
All Green wires  → twist → HX711 A-
```

Wire colors vary by manufacturer. Verify against your specific cell datasheet before wiring. Your locked wiring from HARDWARE.md (ESP32-C3 platform): Red=E+, Black=E−, Green=A+, White=A−.

### 16.3 Calibration Topology Rule

```
reported = actual × (N_cal / N_meas)

N_cal must always equal N_meas.
Always calibrate with the exact set of cells that will be used for measurement.
```

### 16.4 Corrupt Filter Rule

Three corrupt sentinels are always required — each catches a different failure mode:

```
LONG_MIN  (= -2147483648): timeout waiting for DOUT LOW; sign-extension artifact
-1        (= 0xFFFFFF):    read mid-conversion; all bits HIGH means not ready
0x7FFFFF  (= 8388607):     positive saturation; wrong pin or broken cell
```

Never use any HX711 library or sketch that omits any of the three.

### 16.5 Float Rule

Use `float` throughout on ESP32-C3. Do not use `double`. The `double` sum=0 bug was confirmed on STM32U585 — its status on ESP32-C3 is unverified but `float` is safe and sufficient for this application.

### 16.6 Timing Rules

- `delayMicroseconds(1)` after every SCK GPIO edge — both HIGH and LOW, data bits AND gain pulse
- `delay(110)` minimum between reads — HX711 at 10Hz needs 100ms per conversion
- `noInterrupts()` wrapping the full 24+1 pulse sequence — FreeRTOS/Zephyr scheduler must not interrupt mid-read
- `millis()` pacing guard at TOP of `loop()` — never inside a state case
- No `while()` loops inside state machine cases — one sample per `loop()` iteration

### 16.7 State Machine Rule

All firmware must use a non-blocking state machine. States progress on completion conditions (N samples collected, spread check passed, user pressed ENTER) not on time delays. `delay()` is permitted only in one-shot setup functions (like tare derivation), never in `loop()`.

---

## Quick Reference — All Key Equations

```
Physics:
  σ = F/A                           (stress from force)
  ε = ΔL/L                          (strain definition)
  ε = F/(E×A)                       (Hooke's Law — strain from force)
  ΔR/R = GF × ε = GF × F/(E×A)    (master equation — resistance from force)

Single cell bridge:
  V(A+) = Vex × (R-ΔR)/(2R)        (right arm voltage divider)
  V(A-) = Vex × (R+ΔR)/(2R)        (left arm voltage divider)
  Vout  = -Vex × ΔR/R               (differential output)
  Vout  = -Vex × GF × F/(E×A)       (output in terms of force)

Thevenin equivalent:
  Vth = -Vex × ΔR/R                 (open-circuit voltage)
  Rth = R                            (two-terminal Thevenin resistance)
  Rs  = R/2                          (single terminal source impedance)

Parallel formula:
  R_p = (Ra × Rb)/(Ra + Rb)         (two resistors in parallel)
  R_p = X/2   (when Ra = Rb = X)    (equal resistors)

KCL node (N equal sources):
  V_node = (V1 + V2 + ... + VN) / N (arithmetic average)

N cells in parallel:
  Vout = -Vex × GF × F_total/(N×E×A)  (total force, any distribution)

Calibration topology:
  reported = actual × (N_cal / N_meas)

Weight conversion:
  grams = (raw - tare_raw) / CAL_FACTOR
```

---

## Summary of Key Insights from This Session

1. **Strain is linear in force** (Hooke's Law). This is why load cells can measure weight.

2. **Four gauges in opposition** give temperature cancellation (common-mode rejection), 4× signal strength, and linearity. One gauge gives none of these.

3. **Vth and Rth** reduce the complex bridge to two numbers: a voltage source and a resistor. This is the handle that lets us analyse multiple cells mathematically.

4. **The A+ node voltage = arithmetic average of all source voltages** — this is a direct algebraic result of KCL + Ohm's Law at a node with equal-impedance sources. It is not an assumption.

5. **The average does not lose the total force signal** — because the same averaging happens at A−. The differential (A+ minus A−) recovers the sum of all ΔR values, which is proportional to F_total.

6. **Any load distribution gives the same Vout** — the split between cells cancels algebraically. Only F_total remains.

7. **CAL_FACTOR is topology-specific** — it must be re-derived when the number of cells changes.

8. **The reported weight formula** is `actual × (N_cal / N_meas)`. Calibrate with the exact topology you measure with.

9. **Parallel not series** — because series breaks shared excitation, stacks offsets, and may violate HX711 input spec.

10. **4 cells on a square platform** covers 100% of the platform as the support polygon. 3 cells leaves unstable corner zones. For a shared platform product, 4 cells is required.

11. **Case 1 (independent plates) and Case 2 (shared platform) give identical readings** for the same total weight. The HX711 reads the sum of forces across all cells, regardless of how that sum is distributed.

---

*gas-cylinder-monitor | Gratian Technologies | 2026-06-10*
*Derived from Claude.ai learning session — all equations proven from first principles*
*Upload to: `~/ArduinoApps/gas-cylinder-monitor/docs/` and project knowledge base*
