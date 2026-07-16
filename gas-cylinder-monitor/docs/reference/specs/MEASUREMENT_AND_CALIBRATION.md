# MEASUREMENT & CALIBRATION STACK — Gas Cylinder Weight Monitor (V1)

**Created:** 2026-06-02
**Purpose:** The complete set of readings, calibration quantities, and characterizations the system takes — and where each plugs into the raw→% chain. Seed for tomorrow's `SENSOR_CHARACTERISATION.md`.
**Companion docs:** `RESEARCH_AND_LEARNINGS.md`, `SESSION_HANDOFF_2026_06_02.md`, `PLAN_FORWARD.md`.

---

## The chain (where each quantity plugs in)

```
raw HX711 count
   │  filter corrupt (LONG_MIN, -1, 0x7FFFFF) + wait_ready
   ▼
clean sample
   │  average N samples            ← needs N
   ▼
stable reading (avg raw)
   │  − SCALE ZERO  (tare #1)      ← scale's own baseline
   ▼
zeroed counts
   │  ÷ CAL_FACTOR                 ← raw counts per gram
   ▼
grams (gross weight)
   │  − CYLINDER STEEL (tare #2)   ← anchor-derived
   ▼
gas remaining (g)
   │  ÷ CAPACITY                   ← classified
   ▼
percentage

Supporting characterizations feeding the chain:
  noise floor (σ, pp) → sets N · stability detection · linearity + hysteresis
```

---

## The two tares (do not conflate)

There are **two completely different "tares"** at two different layers. Conflating them causes bugs. Always say *scale zero* or *cylinder steel* — never bare "tare".

- **Tare #1 — scale zero / offset.** The raw count with the **empty platform at rest** (nothing / only fixtures on it). The **electrical/mechanical zero of the scale itself**, subtracted from *every* reading. Drifts with temperature → re-validated each boot. (This is the "empty weight of the scale".)
- **Tare #2 — cylinder steel.** The empty **cylinder's** weight in grams, derived by the anchor method. A property of the *cylinder*, not the scale.

They live at different steps of the chain and are found by entirely different methods.

---

## The full measurement set

### 1 · Per-reading hygiene
Before any number is trusted: the three corrupt-value filters (`LONG_MIN`, `-1`, `0x7FFFFF`) and the `wait_ready` DOUT-low poll with timeout. Not a "measurement" but the gate that makes the rest valid.

### 2 · N — samples per reading (efficiency)
One HX711 sample is too noisy; averaging N cuts noise by **√N**. N is **derived** from the noise floor and the margin needed, not arbitrary.
- Prior STM32 values: **N=200** lab characterization, **N=50** production boot, **N=20 rejected** (margin too thin).
- **Re-time on ESP32-C3** — different MCU speed and the HX711's selectable 10/80 Hz rate change how long N samples take.
- Tradeoff: more N = less noise but slower pull/response.

### 3 · Scale zero / offset (tare #1)
Captured at setup, re-validated per boot.
- **Self-validation:** stability check (consecutive-reading delta < band) + plausibility (near expected empty-platform value).
- Opportunistically re-zeroed whenever the scale is known-empty (cylinder removed).

### 4 · cal_factor (raw counts per gram)
The slope of raw-vs-grams. Use **multi-point** (line fit across several known weights), not single-point.
- **Self-validation:** the fit's **residuals / R²**; the fit simultaneously tests linearity.
- Per-MCU, per-cell → **re-derive on ESP32**.
- Long-term cross-check against anchors: `install_gross − steel ≈ capacity`.

### 5 · Noise floor (not from one sample)
Per boot, measure **σ (std)** and **peak-to-peak** over N at-rest samples.
- **Must** be measured each boot — σ drifted 1.33 → 2.36 g on the *same* hardware *same* day.
- Feeds everything: sets N, sets the event threshold (N≈30–50 g must clear it), and a σ above a sanity ceiling flags a **DEGRADED** wiring fault.

### 6 · Stability / settling detection
A *temporal* test, not a static value. When a weight lands, the reading ramps then settles → detect **SETTLING** vs **STABLE-READY** (consecutive-delta < `settle_band`) before capturing a cal point or trusting an install reading. (The live-status work mid-flight in 005 Phase B.)

### 7 · Linearity + hysteresis across the range
Does cal_factor hold from a few-hundred-gram test weight up to a ~30 kg full cylinder? Does loading-up read the same as unloading-down (mechanical creep = hysteresis)? This is **experiment 005** — and why multi-point cal spans the *full* range, not just light weights.

### 8 · Drift re-validation (long-term)
The ~6.5% / ~923 g enemy. Both **scale zero** and **cal_factor** wander with temperature, creep, and mounting stress → periodic re-checking: re-zero when known-empty, cross-check cal via anchors.

### 9 · State / event detection (above calibration, still "readings we take")
Ride on the same averaged readings:
- **Install** — big jump up.
- **Removal** — drop to ~0.
- **Empty floor** — flat plateau near the steel band.
- **Session start/stop** — sustained drop > N with hysteresis.

### 10 · Health
- **Node liveness** — is the heartbeat arriving?
- **Link health** — transport up?
- The uniform 15-min grid doubles as the liveness signal.

---

## The unifying principle

**Nothing is trusted from a single measurement.** Every quantity is made trustworthy by one of three things:
1. **Averaging** (N samples),
2. **A stability / consistency criterion** (settling, line-fit residuals),
3. **An independent cross-check / physical bound** (two routes to steel must agree; capacity must match the catalog; σ must be under a ceiling).

That is the entire quality discipline in one sentence.

---

## Cadence summary

| Quantity | When |
|----------|------|
| Per-reading hygiene, averaging (N) | Continuous |
| Scale zero (tare #1) | Setup + per-boot re-validate + opportunistic re-zero |
| Noise floor (σ, pp) | Per boot |
| Stability / settling | Continuous (on demand, before captures) |
| cal_factor | Setup (multi-point); cross-checked continuously via anchors |
| Cylinder steel (tare #2) | Derived at anchors; converges over cycles |
| Capacity | Classified at install; confirmed against catalog |
| Linearity + hysteresis | Characterization (exp 005); periodic re-check |
| Drift re-validation | Long-term / periodic |
| State/event + health | Continuous |
