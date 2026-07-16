# hub/analysis/3e008 — 3E-008 Creep & Thermal Drift Analysis

These scripts implement Phase B of experiment 3E-008. Run them in order
after each Phase A trial completes.

## export_trial.py

Exports one trial's raw data from `monitor.db` to a CSV, starting at the
boundary row ID recorded when the calibration stone was placed (disturbance
event, t = 0). Usage: `python3 export_trial.py --start-id <BOUNDARY_ID> --out
trial_N.csv`. Outputs columns `id, ts, grams, temp_c, elapsed_seconds`.
Rows where `temp_c` is NULL (recorded before DHT22 integration) are included
with an empty `temp_c` field — they are NOT skipped because the grams trace
is still needed for the creep fit. Prints a summary: row count, elapsed span,
null temp_c count, grams min/max.

## fit_creep_thermal.py

Fits the creep decay model and thermal coefficient to a single trial CSV.
Usage: `python3 fit_creep_thermal.py --csv trial_N.csv`. Phase A fits
`raw(t) = A - B*exp(-t/tau)` to the first 6 hours using scipy.optimize.curve_fit;
A is the plateau the reading converges to, B is the initial offset below the
plateau at placement time, and tau is the time constant in seconds (expected
7200-14400 s = 2-4 h per hardware reference). Phase B subtracts the fitted
creep curve from the full trace to produce a residual. Phase C regresses that
residual against `temp_c` via scipy.stats.linregress; the slope is alpha in
grams per degree C — a statistically significant alpha (p < 0.05) means the
platform zero shifts measurably with temperature. Phase C is skipped if all
temp_c values are null. All results are written to `{csv}_fit_report.txt`.

## Run order per trial

1. Note the boundary row ID at the moment the stone is placed.
2. Leave the platform undisturbed for >= 24 h.
3. `python3 export_trial.py --start-id <ID> --out trial_N.csv`
4. `python3 fit_creep_thermal.py --csv trial_N.csv`

Run all three trials, then compare A, B, tau across them for consistency,
and compare alpha values. Consistent parameters across trials validate the
additive correction model. Inconsistent ones indicate creep rate depends on
temperature, and Stage 2 (Kalman estimator, see
MEASUREMENT_AND_CALIBRATION_SPECIFICATION.md section 41) is needed instead.
