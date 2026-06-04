# RESEARCH.md
# Gas Cylinder Monitor — Research, Derivations & First-Principles Findings
# Era: ESP32-C3 node + UNO Q hub (V1)
# Last updated: 2026-06-04 (ESP32 pivot ingested)
# Rule: never delete entries — only append. Mark superseded entries clearly.

---

## Purpose

This document captures research findings, first-principles derivations, and
design decisions. Every entry is explicitly marked:

- **[PROVEN]** — verified by official source or direct measurement
- **[DERIVED]** — computed/reasoned from proven facts, not yet measured
- **[REASONED]** — design judgement, defensible but not yet measured
- **[PENDING]** — to be measured/decided

---

## PART I — ESP32-C3 ERA (CURRENT, from 2026-06-02 session)

---

## 1. The Product in One Line

A weighing scale (4× 20 kg load cells in final form; 1 cell + substitute weights in dev)
under an LPG cylinder. An **ESP32-C3 reads the weight**, sends it to an **Arduino UNO Q
acting as a hub ("SBC")**, which displays remaining gas (grams + %), tracks consumption,
finds usage patterns, and **predicts when the cylinder will run out**, reported daily.

---

## 2. KEY DOMAIN FACTS — Indian LPG  **[PROVEN, official]**

- **Net gas is regulation-fixed.** Domestic = **14.2 kg ± 150 g**. Pack sizes: **5 kg,
  14.2 kg** (domestic) and **19 kg, 47.5 kg, 425 kg** (commercial/industrial).
  - IOCL (net 14.2, empty ~15.5, gross ~29.7): https://www.iocl.com/MediaDetails/9580
  - BIS standard IS 3196 (Part 1)
- **Tare (steel/empty) weight is stamped on every cylinder** — varies by brand/batch
  (~14.5–15.8 kg for domestic). Total = stamped tare + net gas.

**The asymmetry that drives the whole design:**
- **Capacity** = tightly standardized → *classify* (pick from known set).
- **Steel (tare)** = loosely standardized, varies per cylinder → *measure*, never assume.

---

## 3. The Core Measurement Problem  **[DERIVED]**

The scale reports one number: `gross = steel + gas`. That is **one equation, two unknowns**
(steel, gas). A single reading is mathematically underdetermined.

Everything else is about supplying the missing equation cheaply, or waiting for an event
that supplies it.

---

## 4. The Percentage Truth (and the 52% Trap)  **[DERIVED]**

Steel never leaves the scale. A full domestic reads ~29.5 kg (≈15.3 steel + 14.2 gas);
an empty one still reads ~15.3 kg.

- **WRONG:** `gross / full × 100` → an *empty* cylinder reads ~52%. Worst possible failure.
- **RIGHT:** `gas_remaining = gross − steel; percentage = gas_remaining / 14200 × 100`.
  Empty = 0%, full = 100%.

→ **No honest % exists until the hub knows the steel weight.**

---

## 5. Two Stacked Calibration Layers (keep separate)  **[DERIVED]**

1. **`cal_factor`** — converts raw HX711 counts → grams. Hardware/MCU-specific.
   **Must be re-derived on the ESP32-C3** (the prior 106.7 raw/g was an STM32 figure,
   VOID on ESP32-C3). Never hardcoded; computed on boot or from config.
2. **steel / capacity** — converts grams → gas remaining + %. The domain layer logic.

A perfect layer 1 still needs layer 2, and vice versa. They are independent.

---

## 6. Anchor Events — How Steel & Capacity Are Learned  **[DERIVED]**

Two moments in a cylinder's life are self-revealing:

- **FULL INSTALL — the primary, guaranteed anchor.** A delivered cylinder is full, so
  `gas = capacity` and `gross_install = steel + capacity`. Classify capacity from the
  gross band → **`steel = gross_install − capacity`**. Fires on **every refill**,
  guaranteed within one cylinder lifetime. Accuracy ~±150 g (≈1%).
- **EMPTY FLOOR — opportunistic cross-check.** When gas ≈ 0, `gross ≈ steel`. Direct,
  exact, but only happens if the user runs to true empty. **Demoted to cross-check.**

Cross-check: `gross_install − steel` should match a catalog capacity.
Two independent routes to steel → system **converges and self-heals** over cycles.

---

## 7. Capacity Is Classifiable; Brand Is Invisible — and Irrelevant  **[DERIVED]**

- Full-weight **bands sit far apart** (full domestic ~29.5 kg vs full 19 kg commercial
  ~35+ kg) → **type/capacity is robustly classifiable** from gross.
- **Brand** (Indane/HP/Bharat) within a type differs only in steel by a few hundred grams.
  Cannot be read off gross, and is never needed: `steel = gross − capacity` *measures*
  that cylinder's steel directly, brand-agnostic.

---

## 8. Error Budget  **[PROVEN/DERIVED]**

- **Fill tolerance ±150 g (~1%)** is negligible for gauge and prediction:
  - It is a constant one-time offset → **cancels in any slope/difference**, so
    burn-rate and days-remaining are immune to it.
- **The real enemy is `cal_factor` drift** (temperature, mechanical creep, mounting):
  up to **~6.5% ≈ 923 g** on a full cylinder — **6× larger** than the fill tolerance.

---

## 9. Partial-Cylinder Cold Start — Solved Honestly  **[DERIVED]**

A partial cylinder of unknown type at first sight is **not solvable to a point by sensing
alone** (the underdetermined system of §3). Only two levers exist:

1. **Supply the missing equation** — user taps stamped tare → `steel` known → `gas = gross − steel`.
2. **Wait for an observed known-state event** — refill or run-to-empty — which pins `g`
   and back-solves steel permanently.

**What we CAN do without input — bound it to an interval:**
`gas ∈ [gross − steel_max, gross − steel_min]`, clamped to `[0, capacity]`.
Width ≈ ±5%. Report conservative (low-gas) end → never strand the user.

The truly blind case is **only first power-on with cylinder already present** — it is a
**one-time** event. Every later swap is fully observed. Collapses to exact at first refill.

---

## 10. Δ-Tracking Is Immune to Every Unknown  **[DERIVED]**

`used = weight_earlier − weight_later`. A difference cancels steel, capacity, and brand.
**Usage, burn rate, and patterns work from day one with zero calibration.** Only the
absolute % gauge and days-remaining require steel/capacity.

→ Cold start degrades gracefully: analytics exact immediately; gauge/prediction sharpen
at first refill.

---

## 11. Sampling Strategy — LOCKED  **[REASONED]**

**Sampling ≠ recording.** Two rates:
- **Internal read (fast, every few seconds):** not stored; answers pull requests instantly.
- **Heartbeat record (slow, every 15 min):** the **authoritative time-grid** stored to disk.
  Feeds prediction + hourly/daily analytics. ~96 rows/day is trivial.

Layered on top:
- **Event/session record** on a sustained drop past N ≈ 30–50 g with hysteresis.
- **Pull on demand** — answered from the latest internal read.

**Why a uniform grid (not adaptive):** idle readings are evidence, not waste — they prove
node liveness (heartbeat), anchor the trend line's flat stretches, and are the **only** way
to catch a leak. Don't optimize a cost that isn't a constraint.

---

## 12. Power — USB, LOCKED  **[REASONED]**

The electronics are part of the **scale**, not the cylinder → stationary, fixed location.
Battery trilemma: a battery node can have at most two of {instant pull, long life, simple
firmware}. USB dissolves the trilemma. Battery deferred to v1.x.

---

## 13. Engineering Principles Carried Forward (MCU-Agnostic)

- **HX711 raw bit-bang, no library.** 24-bit read + 25th gain pulse (gain 128, ch A).
  Sign-extend: `if (v & 0x800000) v |= 0xFF000000`. `wait_ready` polls DOUT LOW,
  timeout → LONG_MIN. `noInterrupts()` around the clocking loop; `delayMicroseconds(1)`
  per edge. **Three corrupt-value filters mandatory: LONG_MIN, -1, 0x7FFFFF.**
- **Modular result-struct contract:** every module returns `{value, quality(GOOD/DEGRADED/FAILED), diagnosis}`.
- **Modules receive raw readings injected by the orchestrator** — never call HX711 directly.
  Enables multi-cell scaling AND clean MCU swap.
- **Non-blocking, one-sample-per-loop, millis() pacing at top of loop.**
- **`float` is the safe default** (the double-broken bug was STM32U585-specific;
  **re-verify on ESP32-C3** — double may be fine, but float is the safe default).
- **Adaptive retry** (2s/10s/30s/60s backoff) + degraded operation — never halt in production.
- **No hardcoding:** cal_factor, thresholds, steel/capacity always derived or from config.

---

## 14. Analog Wiring Noise — Carried Hardware Reality  **[PENDING]**

HX711 ↔ load cell is on jumper wires. Empty-scale per-sample noise drifted 100 → 587 raw
(~1 → 5.6 g), trending up. Tare DC is rock-solid → the cell is fine; this is **signal-path
contact noise on the mV analog hop, amplified 128×**.

**Recommendation:** harden the 4 analog connections (solder / screw terminal, short leads)
before trusting fine measurements. **This problem moves with the HX711 onto the ESP32-C3.**

---

## 15. New ESP32-C3 Concerns (Flag Early)  **[PENDING]**

- **Voltage:** HX711 wants **5 V VCC** for full excitation; ESP32-C3 is a **3.3 V** part.
  The STM32's D7/D6 were 5V-tolerant. **ESP32-C3 GPIO tolerance vs HX711 DOUT/SCK levels
  must be checked; level-shifting may be needed.**
- **Pins:** the "DT=D7/SCK=D6 only" rule was an STM32U585 *timer-conflict* constraint —
  it does **NOT** apply to the ESP32-C3. Pick two GPIO, validate on ESP32.
- **float vs double:** the double-broken bug was STM32U585-specific. Re-verify on ESP32-C3
  (double may be fine; use float as safe default until verified).
- **cal_factor:** the prior value of 106.7 raw/g was STM32U585-specific. VOID on ESP32-C3.
  Re-derive completely.

---

## 16. Open Questions — ESP32-C3 Era

| # | Question | Raised | Status |
|---|----------|--------|--------|
| 1 | 3.3V logic-level compatibility with HX711 at 5V VCC | 2026-06-02 | ❓ PENDING E-000 |
| 2 | Correct GPIO pin pair for ESP32-C3 + HX711 | 2026-06-02 | ❓ PENDING E-000 |
| 3 | cal_factor on ESP32-C3 (was 106.7 on STM32 — VOID) | 2026-06-02 | ❓ PENDING |
| 4 | float sufficiency on ESP32-C3 (double may be fine) | 2026-06-02 | ❓ PENDING |
| 5 | Noise floor on ESP32-C3 (drifted to ~5.6g on STM32 — wiring issue) | 2026-06-02 | ❓ PENDING |
| 6 | Thermal drift magnitude and whether software cross-checks swamp it | 2026-06-02 | ❓ Post-MVP |
| 7 | Actual minimum detectable removal on ESP32-C3 | 2026-06-02 | ❓ Experiment 006B |

---

---

## PART II — STM32 ERA (SUPERSEDED — archived for history)

> The following entries were written when the STM32U585 MCU on the UNO Q read the HX711
> directly. That architecture is superseded. The ESP32-C3 is now the sensor node.
> See docs/reference/HANDOFF_ESP32_PIVOT.md for the pivot decision record.
> STM32 hardware constants (DT=D7, SCK=D6, cal_factor=106.7) are VOID on ESP32-C3.

---

## STM-1. Why Self-Characterisation — The Core Philosophy

### Finding (2026-05-05)

Every installation is different. Hardcoded constants assume all environments
are identical. They are not.

**Hardware proof — same board, same bench, two runs same day:**

```
Run 1 STD = 2.3636g → THRESHOLD = 4.2281g
Run 2 STD = 1.3315g → THRESHOLD = 2.3819g
```

Nearly 2× difference in STD on same hardware same day.

**Conclusion:** Tare, cal_factor, and noise threshold must ALL be self-computed
at appropriate times. Nothing hardcoded except sanity bounds.

| Constant        | Approach              | Status |
|-----------------|-----------------------|--------|
| tare_raw        | Self-computing        | ✅ Verified (STM32, VOID on ESP32) |
| cal_factor      | Self-computing        | ✅ Verified (STM32, VOID on ESP32) |
| noise threshold | Self-computing        | ✅ Verified (STM32, VOID on ESP32) |

---

## STM-2. LPG Consumption Derivation — Indian Household

### Source data (Indian LPG standard, government documented)

```
Cylinder net gas weight : 14,200g (fixed by regulation, all brands)
Typical duration        : 30 days per cylinder
Average daily cooking   : 2.5 hours active flame
```

### Derivation (📐 DERIVED)

```
Daily consumption    = 14,200g ÷ 30 days         = 473g/day
Hourly consumption   = 473g   ÷ 2.5 hours        = 189g/hour
Per-minute burn rate = 189g   ÷ 60 minutes       = 3.15g/min
```

**NOTE:** This is a government average. V1 product derives personalised burn rate
from actual data — no government average is ever used in the product.

---

## STM-3. Sliding Window Delta Detector — Theory

### Problem with single-sample detection

```
Single sample noise PP  ≈ 7.5g (from experiment 003 clean run on STM32)
Min event               = 16g (estimated, not yet measured)
Margin                  = 16 / 7.5 = 2.1×  ← too tight
```

### Solution — two sliding windows of N=10

```
delta_std = √2 × (single_std / √N)

For single_std = 2.36g (worst case):
    delta_std = √2 × (2.36 / 3.16) = 1.06g
    4σ threshold = 4.23g
    margin = 16 / 4.23 = 3.8×  ← acceptable
```

This is theoretical. Experiment 007B (on ESP32) validates actual false positive rate.

---

## STM-4. Noise Sample Count — Statistical Derivation (2026-05-06)

```
N=200 : experiments only — lab reference, maximum accuracy (~44s boot)
N=50  : production boot — sufficient accuracy (~11s boot)
N=20  : rejected — 16% error cuts detection margin below 2×

Standard Error of STD = STD / sqrt(2 × N)
N=50 → ±10% threshold error → worst threshold 7.03 × 1.10 = 7.73g → margin 2.07× safe
```

Must re-verify timing on ESP32-C3 (different MCU speed + HX711 rate affects boot time).

---

## STM-5. STM32U585-Specific Bug Records

```
double accumulator in for loop → sum=0 on STM32U585
double array on stack in loop() → stack corruption → hang
DT=D7/SCK=D6 ONLY on STM32 → timer conflicts on D2-D5 (does NOT apply to ESP32-C3)
CAL_FACTOR = 106.7 raw/g on STM32 (VOID — re-derive on ESP32)
```

---

## STM-6. Proven Ranges (STM32 AQ3 — VOID on ESP32)

```
TARE range          : -12799 to -13737 raw (STM32 specific)
CAL_FACTOR range    : 100–107 raw/g (STM32 specific, VOID on ESP32)
NOISE STD range     : 1.33–3.93g (varies — must re-characterise on ESP32)
wait_ready timeout  : 400ms (tuned for AQ3 under Bridge load — re-tune on ESP32)
```

---

## Change Log

| Date | Entry |
|------|-------|
| 2026-05-05 | Created (STM32 era) |
| 2026-05-06 | Added entries 3–12 (STM32 era) |
| 2026-06-04 | MAJOR: ESP32 pivot — Part I is new canonical; Part II archived as SUPERSEDED |
