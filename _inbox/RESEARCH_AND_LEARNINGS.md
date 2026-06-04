# RESEARCH & LEARNINGS — Gas Cylinder Weight Monitor (V1, ESP32-C3 + UNO Q Hub)

**Last updated:** 2026-06-02
**Status of this doc:** Distilled, durable knowledge. Upload to the Claude project folder (chat) and to the project folder on the UNO Q (SBC) board.
**Companion docs:** `SESSION_HANDOFF_2026_06_02.md` (full narrative of the session that produced this), `PLAN_FORWARD.md` (course + experiments + docs-to-create).

**Tagging convention** (kept on every value):
- **[PROVEN]** — verified by official source or direct measurement.
- **[DERIVED]** — computed/reasoned from proven facts.
- **[REASONED]** — design judgement, defensible but not yet measured.
- **[PENDING]** — to be measured/decided.

---

## 0. The product in one line

A weighing scale (4× 20 kg load cells in final form; 1 cell + substitute weights in dev) under an LPG cylinder. An **ESP32-C3 reads the weight**, sends it to an **Arduino UNO Q acting as a hub ("SBC")**, which displays remaining gas (grams + %), tracks consumption, finds usage patterns, and **predicts when the cylinder will run out**, reported daily.

---

## 1. The V1 pipeline (mental spine)

```
Sense → Convert(raw→g) → Convert(g→gas/%) → Transport → Store → Understand → Predict → Present
[--------- ESP32-C3 node ---------]   [gap]   [---------------- UNO Q hub ----------------]
```

Sensing is solved physics (ports from prior work). The product *value* lives in the right-hand stages — intelligence and connectivity.

---

## 2. KEY DOMAIN FACTS — Indian LPG  **[PROVEN, official]**

- **Net gas is regulation-fixed.** Domestic = **14.2 kg ± 150 g**. Pack sizes are a small fixed set: **5 kg, 14.2 kg** (domestic) and **19 kg, 47.5 kg, 425 kg** (commercial/industrial).
  - IOCL (net 14.2, empty ~15.5, gross ~29.7): https://www.iocl.com/MediaDetails/9580
  - Indane pack sizes: https://iocl.com/indane-cooking-gas-overview
- **Cylinders are built to BIS standard IS 3196 (Part 1).**
- **Tare (steel/empty) weight is stamped on every cylinder** and is mandated by Legal Metrology; it **varies** by brand/batch (~14.5–15.8 kg for domestic). Total = stamped tare + net gas.
  - Legal Metrology consumer guidance: https://lmd.kerala.gov.in/2025/05/23/consumer-guidance/

**The asymmetry that drives the whole design:**
- **Capacity** = tightly standardized → *classify* (pick from the known set).
- **Steel (tare)** = loosely standardized, varies per cylinder → *measure*, never assume.

---

## 3. The core measurement problem  **[DERIVED]**

The scale reports one number: `gross = steel + gas`. That is **one equation, two unknowns** (steel, gas), plus a discrete third (capacity/type). A single reading is **mathematically underdetermined** — no sensing trick extracts both.

Everything below is about supplying the missing equation cheaply, or waiting for an event that supplies it.

---

## 4. The percentage truth (and the 52% trap)  **[DERIVED]**

Steel never leaves the scale. A full domestic reads ~29.5 kg (≈15.3 steel + 14.2 gas); an empty one still reads ~15.3 kg.

- **WRONG:** `gross / full × 100` → an *empty* cylinder reads ~52%. A fuel gauge that bottoms out at half = strands the user. Worst possible failure for this product.
- **RIGHT:** `gas_remaining = gross − steel; percentage = gas_remaining / 14200 × 100`. Empty = 0%, full = 100%.

→ **No honest % exists until the hub knows the steel weight.**

---

## 5. Two stacked calibration layers (keep separate)  **[DERIVED]**

1. **`cal_factor`** — converts raw HX711 counts → grams. Hardware/MCU-specific. **Must be re-derived on the ESP32-C3** (the prior 106.7 raw/g was an STM32 figure). Never hardcoded; computed on boot or from config.
2. **steel / capacity** — converts grams → gas remaining + %. The logic in this document.

A perfect layer 1 still needs layer 2, and vice versa. They are independent.

---

## 6. Anchor events — how steel & capacity are learned without user input  **[DERIVED]**

Two moments in a cylinder's life are self-revealing:

- **FULL INSTALL — the primary, guaranteed anchor.** A delivered cylinder is full, so `gas = capacity` and `gross_install = steel + capacity`. Classify capacity from the gross band → **`steel = gross_install − capacity`**. Fires on **every refill**, guaranteed within one cylinder lifetime (days–weeks). Accuracy ~±150 g (≈1%).
- **EMPTY FLOOR — opportunistic cross-check.** When gas ≈ 0, `gross ≈ steel`. Direct, exact, but only happens if the user runs to true empty (common for households without a spare; not guaranteed). **Demoted to cross-check** — do NOT depend on it.

Cross-check: `gross_install − steel` should match a catalog capacity. Two independent routes to steel → system **converges and self-heals** over cycles.

**Caveats:**
- Users often swap *before* empty → a removal plateau may be `steel + residual`, not steel. Only treat a floor as "empty" if it sits near the expected steel band.
- "Install = full" is a safe assumption + sanity check: if install gross matches no plausible `steel_band + capacity`, stay in calibrating.

---

## 7. Capacity is classifiable; brand is invisible — and irrelevant  **[DERIVED]**

- Full-weight **bands for the types sit far apart** (full domestic ~29.5 kg vs full 19 kg commercial ~35+ kg) → **type/capacity is robustly classifiable** from gross.
- **Brand** (Indane/HP/Bharat) within a type differs *only* in steel by a few hundred grams — i.e. exactly the unknown. **Cannot be read off gross, and is never needed**: `steel = gross − capacity` *measures* that cylinder's steel directly, brand-agnostic.

---

## 8. Error budget — what actually matters  **[PROVEN/DERIVED]**

- **Fill tolerance ±150 g (~1%)** is **negligible** for the gauge and prediction:
  - It is a **constant one-time offset** → **cancels in any slope/difference**, so **burn-rate and days-remaining are immune** to it.
  - It nudges the absolute gauge by ~1% only.
- **The real enemy is `cal_factor` drift** (temperature, mechanical creep, mounting): up to **~6.5% ≈ 923 g** on a full cylinder — **6× larger** than the fill tolerance. Engineering attention belongs here, not on the 150 g.
- **Principle:** a constant offset is negligible for anything built on *differences/slopes*; it only bites when an *absolute* value to tight bound is needed (e.g. a future short-delivery-verification feature, where ±150 g IS the legal tolerance band and you'd need <~50 g resolution).

---

## 9. The partial-cylinder cold start — solved honestly  **[DERIVED]**

A partial of unknown type at first sight is **not solvable to a point by sensing alone** (the underdetermined system of §3). "Full" and "empty" are easy *only because the state supplies the second equation* (`g=capacity` or `g=0`). "Partial" = unknown state = the hard core. **"Don't know full/partial/empty" and "solve the partial" are the same problem.**

Only two levers exist (no third):
1. **Supply the missing equation** — user taps stamped tare → `steel` known → `gas = gross − steel`.
2. **Wait for an observed known-state event** — refill (`g=capacity`) or run-to-empty (`g=0`) — which pins `g` and back-solves steel permanently.

**What we CAN do without input — bound it to an interval:**
`gas ∈ [gross − steel_max, gross − steel_min]`, clamped to `[0, capacity]`. Width = steel range ≈ **±0.65 kg ≈ ±5%**.
- The **position of the interval IS the classification** — near top = "nearly full", middle = "about half ±5%", near 0 = "nearly empty". No pre-branching needed; one formula yields all three.
- Report the **conservative (low-gas) end** for warnings → never strand the user.

**Structural relief:**
- The truly blind case is **only first power-on with a cylinder already present** (the one transition not witnessed). It is a **one-time** event — every later swap is fully observed (removal = weight drops to ~0, unmistakable).
- First boot is the natural **setup moment** → one optional question ("tap stamped tare, or skip") is appropriate there.
- Unanswered, the interval (±5%) holds and **collapses to an exact point at the first refill** (bounded, weeks).

---

## 10. Δ-tracking is immune to every unknown  **[DERIVED]**

`used = weight_earlier − weight_later`. A difference cancels steel, capacity, and brand. So **usage, burn rate, and patterns work from day one with zero calibration**. Only the **absolute % gauge** and **days-remaining** require steel/capacity. → Cold start degrades gracefully: analytics exact immediately; gauge/prediction sharpen at the first refill.

(Open thinking thread for next session: name the one extra thing days-remaining needs that Δ-tracking does not — it needs the *absolute remaining amount* (`gas = gross − steel`), i.e. a fixed reference, not just a change.)

---

## 11. Sampling strategy — LOCKED  **[REASONED]**

**Sampling ≠ recording.** Two rates:
- **Internal read (fast, every few seconds):** cheap, not stored; exists to (a) answer a *pull* instantly, (b) detect session start/stop crisply.
- **Heartbeat record (slow, every 15 min):** the **authoritative time-grid** stored to disk. Feeds prediction + hourly/daily analytics. 15 min chosen because the *coarsest* requirement ("which hours do you cook") needs sub-hour resolution; ~96 rows/day is trivial. Single tunable constant.

Layered on top:
- **Event/session record** on a sustained drop past **N ≈ 30–50 g** with hysteresis (start when windowed drop > N, end after flat for a few min). **UX annotation only** — accuracy-safe because the heartbeat spine already counts every gram, so N can sit comfortably above the noise floor (single-sample noise drifted to ~5.6 g; raw threshold needs ~10–15 g clearance).
- **Pull on demand** — answered from the latest internal read.

**Why a uniform grid (not adaptive/cooking-hours-only):** idle readings are evidence, not waste — they prove the node is alive (heartbeat/liveness), anchor the trend line's flat stretches, and are the **only** way to catch a leak (weight dropping while nobody cooks). Don't optimize a cost that isn't a constraint.

---

## 12. Power — USB, LOCKED  **[REASONED]**

- The electronics are part of the **scale**, not the cylinder → **stationary, fixed-location for life**; a kitchen has a socket. The "battery = no wires at swap" intuition doesn't apply (nothing to unplug at a swap either way).
- **Battery trilemma:** a battery node can have at most two of {instant pull, long life, simple firmware}. The *pull* requirement (answer anytime) fights deep sleep, which is the only way batteries last. Waking the radio (esp. WiFi association) is the expensive step.
- **USB dissolves the trilemma:** always powered → instant pull + sample as often as wanted + simple firmware. Energy stops being a design constraint, so sampling is chosen purely on data/UX merit.
- Battery is a **v1.x deployment-flexibility feature**, only if a deployment truly lacks a reachable outlet.

---

## 13. Engineering principles carried forward (MCU-agnostic)

- **HX711 raw bit-bang, NO library.** 24-bit read + 25th gain pulse (gain 128, ch A). Sign-extend: `if (v & 0x800000) v |= 0xFF000000`. `wait_ready` polls DOUT LOW, timeout → LONG_MIN. `noInterrupts()` around the clocking loop; `delayMicroseconds(1)` per edge. **Three corrupt-value filters mandatory: LONG_MIN, -1, 0x7FFFFF.**
- **Modular result-struct contract:** every module returns `{value, quality(GOOD/DEGRADED/FAILED), diagnosis}`.
- **Modules receive raw readings injected by the orchestrator** — never call HX711 directly. Enables multi-cell scaling AND clean MCU swap (this very pivot).
- **Non-blocking, one-sample-per-loop, `millis()` pacing at top of loop.** No blocking `delay()` in setup (corrupts HX711 reads).
- **`float` is the safe default** (the double-broken bug was STM32U585-specific; **re-verify on ESP32-C3** — double may be fine).
- **Adaptive retry** (2s/10s/30s/60s backoff) + degraded operation — never halt in production.
- **No hardcoding:** paths/names derived dynamically; `cal_factor`, thresholds, steel/capacity always derived or from config — never buried constants.
- **4-cell note:** `gross = Σ(4 cells)`, so off-center placement does not disturb steel/capacity math (total = total) as long as every foot is on a cell.

---

## 14. Carried hardware reality — analog wiring noise  **[PENDING]**

HX711 ↔ load cell is on **jumper wires**; empty-scale per-sample noise drifted 100 → 587 raw (~1 → 5.6 g), trending up. Tare DC is rock-solid → the cell is fine; this is **signal-path contact noise on the mV analog hop, amplified 128×**. **Harden the 4 analog connections (solder / screw terminal, short leads) before trusting fine measurements.** This problem **moves with the HX711 onto the ESP32-C3**.

---

## 15. New ESP32-C3 concerns (flag early)  **[PENDING]**

- **Voltage:** HX711 wants **5 V VCC** for full excitation; ESP32-C3 is a **3.3 V** part. The STM32's D7/D6 were 5 V-tolerant — **ESP32-C3 GPIO tolerance vs HX711 DOUT/SCK levels must be checked; level-shifting may be needed.**
- **Pins:** the "DT=D7/SCK=D6 only" rule was an STM32U585 *timer-conflict* constraint — it does **NOT** apply to the ESP32-C3. Pick two GPIO (one SCK, one DOUT), validate on ESP32.
