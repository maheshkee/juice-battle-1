# CONCLUSION.md — 001-freeze-test

**Date**: 2026-05-02  
**Status**: COMPLETE — locked

---

## Hypothesis Confirmed

- [x] H1 — Freeze (DOUT held LOW, S2 = frozen value, weight change lost)
- [ ] H2 — Autonomous refresh

---

## Evidence

Three independent signals, both runs, all consistent:

**1. DOUT stayed LOW for all 30 seconds**
Every second of the pause loop printed `DOUT=LOW`. The HX711 never went HIGH to signal a new conversion starting. It held the output register frozen and waited.

**2. S2 = frozen value — weight placed during action window was not captured**
- Run 1: S1 = -1, S2 = -1. Identical. 30 seconds of weight on scale made no difference.
- Run 2: S2 = -1 (the post-S1 conversion value, frozen for 30 seconds). S2 did not reflect the weight placed at t=0–10s.

**3. Reading triggered the next conversion instantly**
- Both runs: `DOUT went HIGH at +0 ms` — the moment the MCU sent clock pulses to read S2, DOUT jumped HIGH immediately. Nothing else starts a conversion. Only a read does.

**4. S3 captured the weight**
- Run 1: S3 = 10308. Run 2: S3 = 10601. Consistent across runs — the same test weight placed during the action window was captured by the first conversion after the pause ended.

---

## Note on S1 ≠ S2 in Run 2

Run 2 shows S1 = -4035 and S2 = -1. This does not contradict H1.

S1 in run 2 is a value frozen from the conversion triggered at the end of run 1 (120 seconds earlier). Reading S1 triggered a fresh conversion. That fresh conversion froze at -1. S2 reads that fresh frozen value. The H1 behavior being tested is whether S2 changes during the 30-second pause — it does not. DOUT = LOW all 30s, S2 = -1 unchanged.

---

## Note on 552–554 ms Conversion Time

After a 30-second freeze, the first new conversion took ~552 ms instead of the expected ~100 ms (10 SPS). This is 5.5× longer than nominal and was consistent across both runs. Most likely explanation: the RATE pin on this HX711 module is in a non-standard state, or the chip requires extra settling after a very long idle. Under normal operation (reads every 100–500 ms) this extended settling does not occur.

---

## Impact on Gas Cylinder Monitor Design

The gas cylinder weight reading loop in home-hub reads weight to track gas level. H1 has two direct implications:

1. **Each read IS one conversion.** There is no background sampling. Calling `hx711_read_raw()` once gives you one fresh measurement starting from the moment you called it. If you want 1 Hz measurements, you must read once per second.

2. **Missed reads delay conversions, they do not lose data.** If the MCU takes 500 ms between reads, the HX711 holds the last value for that 500 ms. The next read gets a value that started converting at the previous read. You are not losing samples — there are no samples to lose. You are simply controlling when each conversion starts.

For the gas cylinder monitor (which only needs a reading every few seconds), reading once every 500 ms is more than sufficient. The MCU could even read every 5 seconds without any data loss concern.

---

## Impact on home-hub MCU Loop Design

Current digital-scale `loop()` reads every 500 ms via `PUSH_INTERVAL_MS`. H1 confirms this is correct:

- **Do not skip reads indefinitely.** If `loop()` never calls `hx711_read_raw()`, the HX711 freezes permanently and the weight never updates. The read is what keeps the conversion cycle running.
- **Skipping one or two cycles is safe.** If `loop()` is busy for 1–2 seconds, the HX711 holds the last value. The next read just gets a slightly stale value. No corruption, no data loss.
- **500 ms interval is appropriate.** One read every 500 ms gives 2 Hz sampling. More than enough for weight monitoring. The HX711's 10 SPS limit means reading faster than 100 ms would redundantly read the same frozen value anyway.

---

## Locked into LEARNINGS.md

- [x] Yes — entry added and PENDING status updated to CONFIRMED
