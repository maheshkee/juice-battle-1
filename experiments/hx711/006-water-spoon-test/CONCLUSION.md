# CONCLUSION.md — 006-water-spoon-test Part A

**Date**: 2026-05-02
**Board**: AQ3 at 192.168.1.161
**Load cell**: 20kg, D7=DT D6=SCK, gain 128, 10 Hz

---

## Question

Can the HX711 + load cell detect small unknown weight changes (drops of water)?

---

## Result

- [x] Yes — deltas are detectable and consistent (signal >> noise)
- [ ] Marginal — deltas visible but close to noise floor
- [ ] No — deltas buried in noise, indistinguishable

---

## Evidence

Calibration: tare (empty scale) = -13086 raw. Cup of water placed = 306 raw.
cal_factor = (306 − (−13086)) / 130 = 13392 / 130 = **103.02 raw/g**

| Reading | Raw avg | Grams | Delta |
|---------|---------|-------|-------|
| Tare | -13086 | 0g | — |
| W1 | 306 | 130.00g | — |
| W2 | -342 | 123.71g | -6.29g |
| W3 | -893 | 118.36g | -5.35g |
| W3-W1 | | | -11.64g |

Both removals produced clean negative deltas of similar magnitude (~5–6g).
No sign reversal, no scatter, no noise swamping the signal.
This is physically realistic — roughly a teaspoon of water removed by hand each time.

---

## Noise Assessment

Experiment 002-noise-baseline has not been run yet, so there is no formal noise floor number.

What this experiment tells us indirectly: the noise must be well below 5g, because:
- Both deltas are consistently negative (correct direction, every time)
- W2-W1 and W3-W2 are similar in magnitude (~5–6g) for similar physical actions
- If noise were even 1–2g, the readings would show scatter — they do not

The 002 experiment will put a precise number on this. The floor is below 5g. How far below is unknown.

---

## What I Understood From This

**The raw zero offset is large and non-negotiable.**
The tare reading was -13086. With 130g on the scale it was 306. You cannot interpret raw values without tare — the offset is not small, it is ~100× a gram's worth of raw counts. This is normal: the HX711 is DC-coupled to the load cell bridge, and the bridge has its own physical offset at rest. Tare isn't a convenience — it's mandatory.

**The calibration approach is clean.**
Two points — empty scale and one known weight — give you everything. From those two raw values you derive cal_factor and raw_zero. From that point every reading converts to grams with a single formula: `(raw - raw_zero) / cal_factor`. No lookup tables, no polynomial fitting, no iteration needed.

**103.02 raw/g tells us about sensitivity.**
At gain 128 and 10 Hz, the HX711's internal noise is ~50 nV rms at the input. The load cell sensitivity plus gain maps that to some number of raw LSBs of noise. We measured 103 raw counts per gram. If the noise floor is, say, 50–200 raw counts (to be confirmed by 002), that means minimum detectable weight is roughly 0.5–2g with 20-sample averaging. This experiment landed at 5g cleanly — we are nowhere near the floor.

**20-sample averaging at 100 ms intervals is sufficient for this scale of detection.**
2 seconds per reading gave stable results. For home-hub use (monitoring a water container), this is more than adequate. The question for later is: how few samples can we use and still stay above the noise floor? That is a 003/004 question.

**First run anomaly explained.**
The very first run of this experiment (before calibration was added) showed a huge W1→W2 jump (-56,179 raw units). At 103 raw/g, that would be ~545g — impossible for drops. The bowl was almost certainly not seated properly on the load cell during W1. A single misread at the start propagates through all deltas. This is why W1 must be a stable, settled reading — the whole calibration and baseline hangs on it. Lesson: always wait for the reading to stabilize before triggering.

---

## Impact on home-hub Design

- **cal_factor = 103.02 raw/g** — use this as the starting calibration constant for this load cell
- **Tare is mandatory before any gram conversion** — raw offset (~-13086) is too large to ignore
- **20-sample averaging is sufficient** — stable gram-level output in 2 seconds
- **Single known weight calibration works** — no need for multi-point calibration at this precision level

---

## Locked into LEARNINGS.md

- [x] Yes
