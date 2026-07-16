# RESEARCH.md
# Gas Cylinder Monitor — Research, Derivations & First Principles Findings
# Arduino UNO Q AQ3
# Created: 2026-05-06
# Rule: never delete entries — only append. Mark superseded entries clearly.

---

## Purpose

This document captures research findings, first-principles derivations, and
design decisions that informed the product. Every entry is explicitly marked:

- ✅ PROVEN — hardware-verified on AQ3
- 📐 DERIVED — calculated from documented sources, not yet hardware-verified
- 🧠 REASONED — logical derivation from known facts, pending validation
- ❓ OPEN — question raised, not yet answered
- 🚫 SUPERSEDED — replaced by better understanding (kept for history)

---

## 1. Why Self-Characterisation — The Core Philosophy

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
| tare_raw        | Self-computing        | ✅ Verified |
| cal_factor      | Self-computing        | ✅ Verified |
| noise threshold | Self-computing        | ✅ Verified |
| spread_threshold| Must derive from STD  | 🧠 Reasoned, not yet implemented |

---

## 2. LPG Consumption Derivation — Indian Household

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

### Minimum detectable event sizes (📐 DERIVED)

| Event        | Duration | Gas consumed | Design status |
|--------------|----------|-------------|---------------|
| Tea/coffee   | 5 min    | ~16g        | Design target |
| Quick fry    | 10 min   | ~32g        | —             |
| Rice/dal     | 20 min   | ~64g        | —             |
| Full meal    | 45 min   | ~144g       | —             |

**16g is the design target — threshold must be reliably below this.**
**16g is NOT a measured fact. Experiment 006B will measure the actual minimum.**

### Caveat

Actual consumption depends on stove BTU rating, burner size, flame intensity,
actual cooking duration. 473g/day is a government average — real households vary.
This is why v0.3 derives personalised burn rate from actual data.

---

## 3. Sliding Window Delta Detector — Theory

### Problem with single-sample detection (🧠 REASONED)

```
Single sample noise PP  ≈ 7.5g (from experiment 003 clean run)
Min event               = 16g
Margin                  = 16 / 7.5 = 2.1×  ← too tight, false triggers likely
```

### Solution — two sliding windows of N=10

```
Window A = average of last 10 samples
Window B = average of 10 samples before that
delta    = |Window A - Window B|

delta_std = √2 × (single_std / √N) = √2 × (single_std / √10)

For single_std = 2.36g (worst case run 1):
    delta_std = √2 × (2.36 / 3.16) = 1.06g
    4σ threshold = 4.23g
    margin = 16 / 4.23 = 3.8×  ← acceptable

For single_std = 1.33g (run 2):
    delta_std = √2 × (1.33 / 3.16) = 0.60g
    4σ threshold = 2.38g
    margin = 16 / 2.38 = 6.7×  ← good
```

### Why 4σ (🧠 REASONED)

```
At 4σ, probability of false trigger from Gaussian noise = 0.0032%
Over 1 hour of readings at 500ms interval = 7200 readings
Expected false triggers = 7200 × 0.0000032 = 0.023 per hour
Well below target of < 2 per hour
```

**This is theoretical. Experiment 007B validates the actual false positive rate.**

---

## 4. Tare Spread Threshold — Why 600 is Wrong

### Finding (2026-05-06)

600 raw was the spread threshold inherited from digital-scale experiments.
It was empirical — not derived from first principles.

```
600 raw ÷ 106.7 raw/g = 5.62g
```

Experiment 003 peak-to-peak (clean run) = 5.46g. So 600 ≈ measured PP.
It worked on AQ3 by coincidence, not by design.

### Why it breaks in production

```
If deployed kitchen has STD = 4g:
    Expected PP = ~15g
    spread_threshold = 600 raw = 5.62g
    Tare will ALWAYS fail — spread will always exceed 5.62g
    Device loops forever in tare retry
```

### Correct approach (🧠 Reasoned, to implement in 004)

```
spread_threshold_raw = N × noise_std_raw × factor
Derived from noise characterisation output
Adapts to every environment automatically
```

---

## 5. Indian LPG Cylinder — Brand Weight Variation

### Finding (2026-05-06) (📐 DERIVED from documented standards)

```
HP Gas   empty weight : ~15,500g
Bharat   empty weight : ~15,000g
Indane   empty weight : ~14,800g
Variation between brands : up to ~700g
```

Within same brand, manufacturing tolerances introduce further variation.
The tare weight IS stamped on every cylinder collar by regulation — but
stamps may be worn or unreadable on older cylinders.

### Why this matters for cal_factor

```
If brand average is wrong by 400g on a 29,700g total weight:
    cal_factor error = 400 / 29700 = 1.35%
    On 14,200g gas: 192g weight error
    Acceptable for bootstrap phase, not for production accuracy
```

The 30-day self-derived cal_factor approach eliminates this error entirely
because it uses the 14,200g gas delta — which is fixed by regulation regardless
of cylinder brand or individual variation.

---

## 6. Cal Factor Variation — Why It Changes

### Finding (2026-05-06)

**Measured on AQ3:** cal_factor range 100–107 raw/g across multiple runs = 6.5%

### Root causes (🧠 Reasoned)

```
1. Temperature       — load cell uses strain gauge (resistive)
                       resistance changes with temperature
                       same physical load → different raw reading at different temps
                       kitchen temperature varies 15°C–35°C seasonally

2. Mechanical creep  — load cell metal (aluminium alloy) deforms slowly
                       under sustained load (14kg cylinder sitting 24/7)
                       raw offset drifts over weeks/months

3. Mounting stress   — how tightly the cell is fixed affects deflection geometry
                       if platform shifts → cal_factor shifts
```

### Production impact

```
6.5% variation × 14,200g = 923g error on a full cylinder
This is NOT negligible. Must recalibrate on every cylinder replacement.
```

---

## 7. Cal Factor Self-Derivation — 30-Day Method

### Core insight (2026-05-06) (🧠 Reasoned)

```
System records raw_full at cylinder install (day 0)
System records raw_empty at cylinder exhaustion (day ~30)
Gas consumed = 14,200g (fixed by regulation)

cal_factor = (raw_full - raw_empty) / 14,200g
```

No user input. No external reference weight. Immune to cylinder variation.

### Problem: user replaces at 95-98%, not 100%

```
If user replaces at 95% empty:
    actual gas consumed = 13,490g
    assumed gas consumed = 14,200g
    cal_factor error = 710 / 14,200 = 5% ← worse than brand average
```

### Solution: trend line extrapolation (🧠 Reasoned)

```
System has 120 readings over 30 days (6hr intervals)
Fit a linear trend through all readings
Extrapolate where weight = tare_raw (true zero gas)
raw_true_empty = extrapolated intersection

cal_factor = (raw_full - raw_true_empty) / 14,200g
```

User replaces at 95%, 97%, 98% — irrelevant. Trend knows where zero is.

### Bonus output from trend line

```
Slope of trend = grams consumed per day = ACTUAL household burn rate
days_remaining = current_gas_weight / actual_burn_rate
```

Personalised prediction. Not government average.

---

## 8. Bootstrap-Then-Refine Pattern

### Pattern (2026-05-06)

A cold-start problem exists: accurate cal_factor needs 30 days of data,
but the device must work on day 0.

Solution: use good-enough estimate immediately, replace with precise value
when data becomes available.

```
Day 0       : brand average bootstrap — ~1-2% error, device works immediately
Day ~30     : trend extrapolation — precise cal_factor, ~0.1% error
Day 30+     : every replacement refines further, error approaches measurement floor
```

This pattern applies broadly — any system that needs to self-calibrate but
must operate before calibration data is available.

---

## 9. Module Result Struct Pattern — Locked Contract

### Pattern (2026-05-06)

Every sensor module (tare, cal, noise) returns a struct containing:

```
value     → the computed number (tare_raw, cal_factor, threshold_g)
quality   → GOOD / DEGRADED / FAILED  (never just bool)
diagnosis → human readable: what went wrong and why
```

**Why not just bool success/fail:**

A bool forces the state machine to make binary decisions.
Quality levels allow graduated responses:
- GOOD    → proceed normally
- DEGRADED → proceed with warning on dashboard
- FAILED  → halt this flow, surface to user with specific message

The state machine never needs to know module internals.
It reads quality and routes. Clean separation of concerns.

---

## 10. Adaptive Retry vs Halt — Production Philosophy

### Finding (2026-05-06)

Halt on failure is never acceptable in a production device deployed
in a user's kitchen with no technical support available.

**Failure causes for tare are mostly temporary:**
```
Vibration      → stops in seconds
Person walking → stops in seconds
Door slam      → stops in 2 seconds
Fan vibration  → may persist but is predictable
Hardware fault → persistent, needs user action
```

**Adaptive backoff catches temporary causes:**
```
Wait 2s → 10s → 30s → 60s between attempts
Most disturbances resolve within this window
```

**Degraded operation catches persistent non-hardware causes:**
```
Use best available reading
Flag as degraded
Retry silently in background
Recover automatically
Never freeze the device
```

**Hardware fault detection:**
```
If spread never reduces below 3× threshold across all attempts
→ pattern is structural, not environmental
→ show specific alert: "Check load cell connection"
→ still operate in degraded mode if possible
```

---

## 11. Data Intelligence Vision — What 30-Day Data Enables

### Vision (2026-05-06)

Once continuous data collection runs (v0.2+), the system accumulates:
- 120 weight snapshots per cylinder cycle
- Cooking session events (delta spikes)
- Refill timestamps
- Cylinder brand/weight per cycle

**This data enables progressively more powerful intelligence:**

### Statistical layer (v0.3)
```
- Personalised burn rate from actual history
- Trend extrapolation for accurate days_remaining
- Precise self-derived cal_factor
```

### Pattern layer (v1.0)
```
- Cooking session count per day
- Peak usage hours (morning/evening pattern)
- Day-of-week variation
- Anomaly detection: consumption spike = stove left on?
- Confidence intervals on predictions
```

### AI/ML layer (v2.0)
```
- TensorFlow Lite on QRB2210 Cortex-A53 (4× ARM cores available)
- Personalised consumption model:
    weekday vs weekend patterns
    seasonal variation
    household size changes
- Kalman filter on successive cylinder cycles → auto-improving cal_factor
- Smarter anomaly detection: distinguish cooking from vibration/noise
- Predictive refill alert with delivery lead time
```

### Agent layer (v3.0)
```
- LLM agent (cloud API or on-device quantised model)
- Natural language: "how much gas did we use this week?"
- Proactive insights: "20% more usage — did you have guests?"
- Gas ordering agent: HP/Bharat/Indane booking API integration
- Multi-cylinder network: aggregate data across homes
- Fleet management for LPG distributors
```

### Data collection rule (locked)
```
Store everything raw. Never discard history.
Aggregated summaries lose information.
The model gets better with every cylinder cycle.
```

---

## 12. Noise Sample Count — Statistical Derivation (2026-05-06)

### Finding

200 samples used in experiments. 50 samples sufficient for production boot.
This is not a guess — derived from statistics.

### HX711 hardware rate is the bottleneck

```
HX711 RATE pin LOW = 10 SPS (fixed in hardware)
Per sample cost    = ~100ms HX711 ready + ~120ms loop pace = ~220ms
N=200 → 44 seconds boot characterisation
N=50  → ~11 seconds boot characterisation
```

Corrupt sample filtering adds negligible time (~0.5s extra).
The hardware rate dominates — not filtering.

### STD estimation error formula

```
Standard Error of STD = STD / sqrt(2 × N)

N=200 : ±5%  error on threshold
N=100 : ±7%  error on threshold
N=50  : ±10% error on threshold
N=20  : ±16% error on threshold — rejected, too high
N=10  : ±22% error on threshold — rejected, far too high
```

### Why 10% is acceptable but 16% is not

```
Worst case measured threshold : 7.03g (run 2, session 2026-05-06)
Minimum event to detect       : 16g (tea/coffee)

At N=50  (10% error): worst threshold = 7.03 × 1.10 = 7.73g
                       detection margin = 16 / 7.73 = 2.07× safe

At N=20  (16% error): worst threshold = 7.03 × 1.16 = 8.15g
                       detection margin = 16 / 8.15 = 1.96× too tight
```

2× margin is the minimum acceptable. N=50 passes. N=20 fails.

### Decision locked

```
N=200 : experiments only — lab reference, maximum accuracy
N=50  : production boot — sufficient accuracy, acceptable boot time
```

### Implementation note

noise_reset(int n_samples) — N passed as parameter, never hardcoded.
sketch.ino decides N based on context (experiment vs production).

---

## 13. Open Questions — Pending Research

| # | Question | Raised | Status |
|---|----------|--------|--------|
| 1 | Actual minimum detectable removal on AQ3 | 2026-05-05 | ❓ Experiment 006B |
| 2 | Actual false positive rate over 30 min | 2026-05-05 | ❓ Experiment 007B |
| 3 | Temperature drift magnitude on AQ3 | 2026-05-05 | ❓ Experiment 008 |
| 4 | Cal_factor linearity across weight range | 2026-05-05 | ❓ Experiment 005 |
| 5 | Trend line accuracy for cal_factor derivation | 2026-05-06 | ❓ Requires v0.2+ data |
| 6 | Actual household burn rate distribution | 2026-05-06 | ❓ Requires field data |
| 7 | Optimal N for sliding window on 6hr duty cycle | 2026-05-06 | ❓ Requires experiment 009 |

---

## Change Log

| Date | Entry |
|------|-------|
| 2026-05-06 | Created — captured all research from sessions 2026-05-05 and 2026-05-06 |
