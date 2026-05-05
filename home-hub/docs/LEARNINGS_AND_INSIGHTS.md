# LEARNINGS_AND_INSIGHTS.md
# Permanent living knowledge base — Arduino UNO Q AQ3 projects
# Updated: 2026-05-05
# Rule: append new findings daily. Never delete old entries. Date every entry.

---

## How to use this file

This is not a handoff document. It is a permanent record of:
- Platform bugs discovered and their root causes
- Debugging journeys — what failed, why, what the real fix was
- Hardware-verified facts that override theory
- Design decisions and the reasoning behind them

Every future Claude instance and CLI session reads this before touching HX711 code.

---

## PLATFORM FINDINGS

### [2026-05-05] double arithmetic broken on STM32U585 Zephyr/Arduino Core

**Symptom:** Two-pass variance loop producing sum=0.000000 with confirmed
non-zero values in array. Both double loops (sum and sum_sq_dev) return zero.

**Diagnostic proof:**
```
DBG s0=-0.7046 s100=-0.4761 s199=-0.1290  ← array has real data
sum=0.000000 mean=0.000000 sq=0.000000    ← loops produce zero
```

**Root cause:** Unknown exactly — either sizeof(double)=4 (double==float on
this toolchain) causing float cancellation of small near-zero values, OR
compiler dead-code elimination of double loops. sizeof diagnostic was lost
(fired before Python ready). Will verify in future session.

**Fix:** Use float everywhere. Never use double in MCU sketch code on AQ2/AQ3.

**Rule:** All accumulator variables must be float. All math must be float.
double is banned in MCU sketches on this platform until proven working.

---

### [2026-05-05] double array on stack inside loop() causes hang

**Symptom:** After adding `double dtest[3] = {...}` inside STATE_IDLE in
loop(), the sketch hung completely after TARE/CAL — never reached
NOISE_MEASURE. 9 minutes with zero progress lines.

**Root cause:** double array initialisation on stack inside loop() corrupted
the stack frame. Zephyr/Arduino Core on STM32U585 does not handle double
stack allocation correctly. Corrupted g_state_ms or g_state, causing state
machine to loop silently in a broken state.

**Fix:** Remove all double declarations from MCU sketch. Use float only.

**Rule:** Never use double in any MCU sketch on AQ2/AQ3. Not in setup(),
not in loop(), not in state cases. float is sufficient for all sensor math.

---

### [2026-05-05] wait_ready timeout tuning for AQ3 under Bridge load

**Symptom:** hx711_wait_ready() timing out frequently, causing slow sample
collection. 200 samples taking 3-4 minutes instead of 24 seconds.

**Root cause:** noInterrupts()/interrupts() cycle in hx711_read_raw()
accumulates Bridge interrupt work. When interrupts() fires, Zephyr scheduler
runs deferred work, delaying next DOUT LOW by hundreds of milliseconds.

**Timeout values tested:**
- 150ms: 87% timeout rate (too tight)
- 300ms: still slow
- 400ms: acceptable

**Current working value: 400ms**

**Note:** This is not a hardware fault. HX711 is healthy. It's scheduler
interference from Bridge RPC infrastructure.

---

### [2026-05-05] Blocking while loops in state cases = Bridge interrupt accumulation

**Symptom:** Corrupt reads, massive spread values (1,357,614 raw = 12,722g),
wait_ready timeouts even with 500ms timeout.

**Root cause:** A while loop inside a switch case holds the MCU in that state
for many seconds. During this time, every noInterrupts/interrupts cycle
accumulates deferred Bridge work. The scheduler backlog grows, causing
subsequent wait_ready polls to find DOUT still HIGH (scheduler holding >Xms).

**Pattern that causes this:**
```cpp
case STATE_SOMETHING: {
    while (count < N) {          // ← WRONG: blocking inside state
        long r = hx711_read_raw();
        count++;
    }
}
```

**Fix — one sample per loop() iteration:**
```cpp
case STATE_SOMETHING: {
    long r = hx711_read_raw();
    if (corrupt) break;
    samples[count++] = r;
    if (count < N) break;       // accumulate across calls
    // compute stats here — only runs when count==N
}
```

**Rule:** Never use a while loop to collect multiple HX711 samples inside a
state case. Always accumulate one sample per loop() iteration.

---

### [2026-05-05] Bridge.notify diagnostic fires before Python ready

**Symptom:** PLATFORM sizeof line added to setup() after Bridge.begin()
never appeared in logs.

**Root cause:** Python container takes time to start and register
Bridge.provide() handlers. A notify fired immediately after Bridge.begin()
is lost because no handler is registered yet.

**Fix:** Add delay(500) after Bridge.begin() before any diagnostic notify
in setup(). Or move diagnostics to STATE_IDLE which fires 3 seconds later.

---

### [2026-05-05] @Bridge.on() does not exist in App Lab Python API

**Symptom:** Decorator @Bridge.on('event_name') causes AttributeError.

**Fix:** Use Bridge.provide('event_name', handler_function) instead.

**Confirmed in:** INTERFACE_CONTRACTS.md, PROJECT_CONTEXT.md

---

## HX711 FINDINGS

### [2026-05-05] Cal sequence must be: TARE first, then WEIGHT

**Symptom:** cal_factor ≈ 0, CAL_FAIL: out of range triggered every run.

**Root cause:** Tare was being taken AFTER user placed the known weight.
raw_with_weight ≈ tare_raw → cal_factor ≈ 0.

**Correct sequence:**
1. TARE_WAIT: ensure scale empty
2. TARE_MEASURE: 5 samples → tare_raw
3. CAL_WAIT: place known weight
4. CAL_MEASURE: 20 samples → raw_with_weight
5. cal_factor = (raw_with_weight - tare_raw) / known_weight_g

**Rule:** Tare must always be taken before calibration weight is placed.
Never measure tare with weight on scale.

---

### [2026-05-05] Accumulator globals must be reset before state entry

**Symptom:** Second run risk — stale values from first run corrupting stats.

**Pattern:** Reset all accumulator globals in the WAIT state transition,
not at declaration:

```cpp
// In STATE_CAL_WAIT transition:
g_cal_sum   = 0;
g_cal_count = 0;
g_state = STATE_CAL_MEASURE;

// In STATE_NOISE_WAIT transition:
g_noise_count  = 0;
g_noise_min    = 1e9f;
g_noise_max    = -1e9f;
g_state = STATE_NOISE_MEASURE;
```

**Rule:** Always reset accumulators at transition, not at declaration.
Static globals persist across state re-entries.

---

### [2026-05-05] Four corrupt value filters required (not three)

Previous knowledge: LONG_MIN, -1, 0x7FFFFF

Today: added grams-level filter after conversion:
```cpp
float g = (float)(r - g_tare_raw) / g_cal_factor;
if (g < -50.0f || g > 50.0f) break;  // outside physical range for empty scale
```

**Why:** Raw range filter `< -5000000L || > 5000000L` passes some partial
reads that convert to large gram values (e.g. -78508g). The grams filter
is a second layer of protection after conversion.

**Note:** Grams filter value depends on context:
- Empty scale noise measurement: ±50g
- Weight measurement: adjust to ±(expected_weight + 100g)

---

### [2026-05-05] PP is unreliable — use STD for threshold derivation

**Observed:** PP=40.99g with STD=2.36g. With Gaussian noise, PP should be
≈ 4-6× STD = 9-14g. Actual PP was 3× larger due to outlier reads.

**Conclusion:** Outliers inflate PP disproportionately even with filters.
PP is not a reliable noise metric for threshold derivation.

**Rule:** Always derive threshold from STD, not PP:
```
threshold_g = √2 × (std_g / √N_window) × safety_factor
```
where N_window=10, safety_factor=4.

---

## NOISE CHARACTERISATION RESULTS

### [2026-05-05] Run 1 — bench environment, AQ3

```
CAL_FACTOR  = 103.2721 raw/g
TARE        = -13456 raw
STD         = 2.3636g
PP          = 40.99g (outliers — not reliable)
THRESHOLD_G = 4.2281g
MEAN        = -1.714g (tare drift between phases)
```

### [2026-05-05] Run 2 — bench environment, AQ3

```
CAL_FACTOR  = 101.9114 raw/g
TARE        = -13039 raw
STD         = 1.3315g
PP          = 5.4557g  (clean — no outliers)
THRESHOLD_G = 2.3819g
MEAN        = -1.685g  (consistent tare drift)
MIN         = -4.6805g
MAX         = 0.7752g
```

### [2026-05-05] Two-run summary and locked range

| Metric | Run 1 | Run 2 | Meaning |
|--------|-------|-------|---------|
| STD | 2.3636g | 1.3315g | Environment varies — self-characterise essential |
| PP | 40.99g | 5.46g | Run 1 had outliers — PP unreliable |
| THRESHOLD | 4.2281g | 2.3819g | Correctly adapts to STD |
| MEAN | -1.714g | -1.685g | Consistent tare drift ~1.7g |

STD range on AQ3 bench: 1.33g – 2.36g
THRESHOLD range: 2.38g – 4.23g
Worst-case margin vs 16g min event: 16 / 4.23 = 3.8x ✅
Best-case margin: 16 / 2.38 = 6.7x ✅
Tare drift between phases: ~1.7g (consistent)

---

## DESIGN DECISIONS

### [2026-05-05] Why sliding window delta, not single-sample threshold

Single sample noise pp=7.5g (from 002 Phase 1) is too close to 16g minimum
event. Margin = 2x only.

Sliding window (N=10 each):
- window_std = single_std / √10 = 0.75g
- delta_std = √2 × 0.75 = 1.06g
- threshold = 1.06 × 4 = 4.23g
- margin vs 16g = 3.8x

Additionally: heavy averaging (N=20 single window) hides slow 3.15g/min
signal. Two-window comparison detects the drift between past and present.

### [2026-05-05] Why N=10 per window

- Covers 1.2 seconds of data (at 120ms pacing)
- Gas consumption in 1.2s = 3.15 × (1.2/60) = 0.063g — negligible
- Detection latency: event detectable within 2 minutes of cooking start
- Going larger: diminishing noise reduction, increasing detection latency

### [2026-05-05] Why safety factor = 4σ

At 4σ: false trigger probability = 1 in ~15,000 readings
At 120ms pacing: 1 false trigger per ~25 hours
Acceptable for a gas monitor. Not acceptable for a precision scale.

---

## DEBUGGING METHODOLOGY (rules for next session)

See CLAUDE.md on board for full rules. Summary:

1. Read all relevant files before suggesting any fix
2. Reproduce the symptom exactly before diagnosing
3. Diagnose from atomic level: what instruction is executing, what value
   is in what register/variable at that moment
4. Add minimal diagnostics to verify the hypothesis — print intermediate
   values, not just final results
5. One fix at a time — verify each fix before applying the next
6. Never patch without understanding the root cause
7. Hardware is almost never the problem — check code first

---

## OPEN QUESTIONS

- sizeof(double) on STM32U585 Zephyr/Arduino Core — verify in future session
- Why wait_ready timeouts at 400ms still occur occasionally
- Whether noise STD varies significantly across days/temperatures (exp 008)
- Minimum physically detectable weight change (exp 006B)
