# Session Handoff — 2026-06-16 Session 2
# 3E-004 Accuracy Investigation Complete

## Session goal
Find and fix root cause of systematic weight reading errors.

## Gate result
3E-004 PASSED. ±7g accuracy across 200g–1700g. Self-calibrating boot working.

## Root causes found and fixed
1. Cross-boot cal_factor use — invalid. Fixed by deriving cal_factor in same boot.
2. tare_raw_g from Phase 1 (20 samples) — imprecise. Fixed: use s2_mean (200 samples).

## Sketches built this session
- node/E005_linearity/E005_linearity.ino — linearity test, PASSED
- node/3E004_cal_and_run/3E004_cal_and_run.ino — self-calibrating boot, PASSED

## Verified measurements
| Weight | Reading | Error |
|---|---|---|
| 0g (empty) | −3.6g, −2.1g | ±4g |
| 200g | 200.6g, 206.4g | +3g |
| 700g | 699.1g, 705.8g | +2g |
| 1700g | 1707.2g, 1702.2g | +5g |
| 1800g | 1801.8g | +2g |

## Next session goal
Self-deriving cal_factor without user input — automatic on every boot.
