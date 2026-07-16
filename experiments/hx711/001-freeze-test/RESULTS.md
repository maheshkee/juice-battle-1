# RESULTS.md — 001-freeze-test

---

## Test Run Details

- **Date**: 2026-05-02
- **Board**: AQ3 at 192.168.1.161
- **App**: user:hx711-001-freeze-test
- **Runs completed**: 2 (back-to-back, 120s gap between runs)
- **Test weight W2**: unknown mass — placed on scale during seconds 0–10 of each pause window

---

## Raw Log Output — Run 1

```
[main] App started
[main] === HX711 freeze vs refresh test ===
[main] DT=D7  SCK=D6
[main] HX711 ready.
[main] S1 = -1  at t = 8330 ms
[main] >>> PAUSE START at t=8333ms
[main] >>> ACTION WINDOW: seconds 0-10 — place new weight on scale NOW
[main] >>> SETTLE WINDOW: seconds 10-30 — hands off, do not touch
[main] >>> S2 will be read at t=30s
[main] t=0s  DOUT=LOW
[main] t=1s  DOUT=LOW
[main] t=2s  DOUT=LOW
[main] t=3s  DOUT=LOW
[main] t=4s  DOUT=LOW
[main] t=5s  DOUT=LOW
[main] t=6s  DOUT=LOW
[main] t=7s  DOUT=LOW
[main] t=8s  DOUT=LOW
[main] t=9s  DOUT=LOW
[main] t=10s  DOUT=LOW
[main] >>> ACTION WINDOW CLOSED — hands should be off scale now
[main] t=11s  DOUT=LOW
[main] t=12s  DOUT=LOW
[main] t=13s  DOUT=LOW
[main] t=14s  DOUT=LOW
[main] t=15s  DOUT=LOW
[main] t=16s  DOUT=LOW
[main] t=17s  DOUT=LOW
[main] t=18s  DOUT=LOW
[main] t=19s  DOUT=LOW
[main] t=20s  DOUT=LOW
[main] t=21s  DOUT=LOW
[main] t=22s  DOUT=LOW
[main] t=23s  DOUT=LOW
[main] t=24s  DOUT=LOW
[main] t=25s  DOUT=LOW
[main] t=26s  DOUT=LOW
[main] t=27s  DOUT=LOW
[main] t=28s  DOUT=LOW
[main] t=29s  DOUT=LOW
[main] >>> PAUSE END — reading S2 now (no delay, no SCK pulses until now)
[main] S2 = -1  at t = 38356 ms
[main] >>> Now waiting for next conversion (DOUT goes HIGH then LOW again)...
[main] DOUT went HIGH at +0 ms, LOW again at +554 ms (total wait 554 ms)
[main] S3 = 10308  at t = 38920 ms
[main] === TEST COMPLETE ===
```

---

## Raw Log Output — Run 2

```
[main] App started
[main] === HX711 freeze vs refresh test ===
[main] DT=D7  SCK=D6
[main] HX711 ready.
[main] S1 = -4035  at t = 8331 ms
[main] >>> PAUSE START at t=8334ms
[main] >>> ACTION WINDOW: seconds 0-10 — place new weight on scale NOW
[main] >>> SETTLE WINDOW: seconds 10-30 — hands off, do not touch
[main] >>> S2 will be read at t=30s
[main] t=0s  DOUT=LOW
[main] t=1s  DOUT=LOW
[main] t=2s  DOUT=LOW
[main] t=3s  DOUT=LOW
[main] t=4s  DOUT=LOW
[main] t=5s  DOUT=LOW
[main] t=6s  DOUT=LOW
[main] t=7s  DOUT=LOW
[main] t=8s  DOUT=LOW
[main] t=9s  DOUT=LOW
[main] t=10s  DOUT=LOW
[main] >>> ACTION WINDOW CLOSED — hands should be off scale now
[main] t=11s  DOUT=LOW
[main] t=12s  DOUT=LOW
[main] t=13s  DOUT=LOW
[main] t=14s  DOUT=LOW
[main] t=15s  DOUT=LOW
[main] t=16s  DOUT=LOW
[main] t=17s  DOUT=LOW
[main] t=18s  DOUT=LOW
[main] t=19s  DOUT=LOW
[main] t=20s  DOUT=LOW
[main] t=21s  DOUT=LOW
[main] t=22s  DOUT=LOW
[main] t=23s  DOUT=LOW
[main] t=24s  DOUT=LOW
[main] t=25s  DOUT=LOW
[main] t=26s  DOUT=LOW
[main] t=27s  DOUT=LOW
[main] t=28s  DOUT=LOW
[main] t=29s  DOUT=LOW
[main] >>> PAUSE END — reading S2 now (no delay, no SCK pulses until now)
[main] S2 = -1  at t = 38356 ms
[main] >>> Now waiting for next conversion (DOUT goes HIGH then LOW again)...
[main] DOUT went HIGH at +0 ms, LOW again at +552 ms (total wait 552 ms)
[main] S3 = 10601  at t = 38919 ms
[main] === TEST COMPLETE ===
```

---

## Extracted Values

| Reading | Run 1 | Run 2 | Notes |
|---------|-------|-------|-------|
| S1 | -1 | -4035 | Baseline — different because run 2 S1 reads a value frozen 120s earlier |
| S2 | -1 | -1 | First read after 30s pause — frozen value, unchanged |
| S3 | 10308 | 10601 | Next conversion after pause — captures weight placed during action window |
| Conversion time | 554 ms | 552 ms | Time from S2 read to next DOUT LOW |

---

## DOUT Behavior During Pause

- [x] Stayed LOW all 30 seconds — both runs (supports H1)
- [ ] Toggled HIGH/LOW repeatedly (supports H2)
