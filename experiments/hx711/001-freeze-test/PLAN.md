# PLAN.md — 001-freeze-test

**Question**: Does the HX711 freeze (hold last conversion) until the MCU reads, or does it refresh autonomously during a pause?

---

## Hypotheses

### H1 — Freeze (expected)
- DOUT stays LOW for the entire MCU pause
- HX711 holds the last conversion value
- S2 ≈ S1 (reflects weight at start of pause, not during pause)
- S3 reflects the new weight (first read after pause triggers fresh conversion)

### H2 — Autonomous refresh
- HX711 keeps converting internally during pause
- DOUT toggles HIGH → LOW every ~100 ms during pause
- S2 already reflects the weight added during pause

---

## Discriminating Observations

| Observation | H1 (freeze) | H2 (refresh) |
|-------------|------------|--------------|
| DOUT during 30s pause | Stays LOW | Toggles ~10×/s |
| S2 value | ≈ S1 (old) | Reflects W2 (new) |

Only S2 is required to determine the outcome. DOUT monitoring adds confirmation.

---

## Test Sequence

1. Boot sketch, confirm HX711 ready (DOUT goes LOW, first read succeeds)
2. Read **S1** — baseline (no weight, or known tare state)
3. MCU pauses for 30 seconds — no SCK pulses issued
4. During pause: add test weight **W2** within first 10 seconds, hands off by 10 seconds
5. Read **S2** immediately after pause ends
6. Wait for next natural conversion, read **S3**
7. Compare S1, S2, S3 — conclude H1 or H2

---

## App Location

`~/ArduinoApps/experiments/hx711/001-freeze-test/app/`

deploy.sh in that folder sets `APP_NAME="hx711-001-freeze-test"`.

---

## Results and Conclusion

- Raw output → `RESULTS.md`
- Interpretation → `CONCLUSION.md`
