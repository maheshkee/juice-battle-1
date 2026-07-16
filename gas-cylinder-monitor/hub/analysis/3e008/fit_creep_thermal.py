#!/usr/bin/env python3
"""
Phase B analysis for experiment 3E-008.

Phase A: fit creep model  raw(t) = A - B*exp(-t/tau)  to first 6 hours
Phase B: subtract fitted creep curve from full trace -> residual
Phase C: regress residual vs temp_c -> thermal coefficient alpha (g/degC)

Requires: scipy, numpy
Output:   printed summary + {csv}_fit_report.txt
"""
# [ADDITION] dependency check
try:
    import numpy as np
    from scipy.optimize import curve_fit
    from scipy.stats import linregress
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install scipy numpy --break-system-packages")
    raise SystemExit(1)

import argparse
import csv
import os

CREEP_FIT_HOURS  = 6.0
CREEP_FIT_S      = CREEP_FIT_HOURS * 3600.0
SECONDS_PER_DAY  = 86400
MIN_POINTS_EARLY = 10
MIN_POINTS_TEMP  = 5


def creep_model(t, A, B, tau):
    """
    raw(t) = A - B * exp(-t / tau)
    A   : plateau (grams) the reading converges to as t -> inf
    B   : initial offset from plateau  (positive -> weight starts below A)
    tau : time constant (seconds)
    At t=0: A - B.  As t->inf: A.
    """
    return A - B * np.exp(-t / tau)


def load_csv(path):
    rows = []
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        for r in reader:
            try:
                grams   = float(r['grams'])
                elapsed = float(r['elapsed_seconds']) if r.get('elapsed_seconds') else None
                temp_c  = float(r['temp_c']) if r.get('temp_c') else None
                rows.append({'grams': grams, 'elapsed': elapsed, 'temp_c': temp_c})
            except (ValueError, KeyError):
                continue
    return rows


def main():
    ap = argparse.ArgumentParser(description='Fit creep + thermal model to a 3E-008 trial CSV')
    ap.add_argument('--csv', required=True, help='Trial CSV produced by export_trial.py')
    args = ap.parse_args()

    rows = load_csv(args.csv)
    if not rows:
        print('ERROR: no rows loaded')
        return
    print(f'Loaded {len(rows)} rows from {args.csv}\n')

    # [ADDITION] soft warning if boundary row looks wrong
    if rows and rows[0]['elapsed'] is not None and abs(rows[0]['elapsed']) > 120:
        print(f"WARNING: first row elapsed_seconds = {rows[0]['elapsed']:.0f} s "
              f"(expected approx 0). Check that --start-id is the correct boundary row.")

    report = [
        '3E-008 Creep + Thermal Fit Report',
        f'Input : {args.csv}',
        f'Rows  : {len(rows)}',
        '',
    ]

    # Phase A: creep fit on first 6 hours
    print(f'-- Phase A: Creep fit (first {CREEP_FIT_HOURS:.0f} h) --')
    report.append(f'Phase A -- Creep model  raw(t) = A - B*exp(-t/tau)')
    report.append(f'  Early-time window: first {CREEP_FIT_HOURS:.0f} h')

    early = [(r['elapsed'], r['grams']) for r in rows
             if r['elapsed'] is not None and r['elapsed'] <= CREEP_FIT_S]
    print(f'  Points in window: {len(early)}')
    report.append(f'  Points: {len(early)}')

    popt = None
    perr = None

    if len(early) < MIN_POINTS_EARLY:
        msg = f'FAIL: only {len(early)} points in first {CREEP_FIT_HOURS:.0f} h (need {MIN_POINTS_EARLY})'
        print(f'  {msg}')
        report.append(f'  {msg}')
    else:
        t_arr = np.array([e[0] for e in early])
        g_arr = np.array([e[1] for e in early])
        n_lq  = max(1, len(g_arr) // 4)
        A0    = float(np.mean(g_arr[-n_lq:]))
        B0    = A0 - float(g_arr[0])
        tau0  = 3600.0
        try:
            popt, pcov = curve_fit(
                creep_model, t_arr, g_arr,
                p0=[A0, B0, tau0],
                bounds=([-np.inf, -np.inf, 60.0], [np.inf, np.inf, 7.0 * SECONDS_PER_DAY]),
                maxfev=20000,
            )
            with np.errstate(invalid='ignore'):
                perr = np.sqrt(np.diag(pcov)) * 1.96
            A, B, tau     = popt
            A_ci, B_ci, tau_ci = perr
            print(f'  A   = {A:.2f} +/- {A_ci:.2f} g         (plateau)')
            print(f'  B   = {B:.2f} +/- {B_ci:.2f} g         (initial offset from plateau)')
            print(f'  tau = {tau:.0f} +/- {tau_ci:.0f} s = {tau/3600:.2f} +/- {tau_ci/3600:.2f} h')
            print(f'  t=0: {A-B:.2f} g  ->  plateau: {A:.2f} g  (delta = {B:.2f} g)')
            report += [
                f'  A   = {A:.4f} +/- {A_ci:.4f} g',
                f'  B   = {B:.4f} +/- {B_ci:.4f} g',
                f'  tau = {tau:.1f} +/- {tau_ci:.1f} s  ({tau/3600:.4f} h)',
                f'  t=0 value : {A-B:.4f} g',
                f'  plateau   : {A:.4f} g',
            ]
        except Exception as e:
            msg = f'FAIL: curve_fit error: {e}'
            print(f'  {msg}')
            report.append(f'  {msg}')

    # Phase B: subtract creep curve from full trace
    print(f'\n-- Phase B: Residual after creep subtraction --')
    report.append('\nPhase B -- Residual statistics')

    full   = [(r['elapsed'], r['grams'], r['temp_c']) for r in rows
              if r['elapsed'] is not None]
    t_full = np.array([p[0] for p in full])
    g_full = np.array([p[1] for p in full])

    if popt is None:
        print('  Skipped -- Phase A failed')
        report.append('  Not computed -- Phase A failed')
        residuals = None
    else:
        residuals = g_full - creep_model(t_full, *popt)
        print(f'  n={len(residuals)}  mean={residuals.mean():.2f} g  '
              f'std={residuals.std():.2f} g  '
              f'min={residuals.min():.2f} g  max={residuals.max():.2f} g')
        report.append(
            f'  n={len(residuals)}  mean={residuals.mean():.4f} g  '
            f'std={residuals.std():.4f} g  '
            f'min={residuals.min():.4f} g  max={residuals.max():.4f} g'
        )

    # Phase C: thermal regression
    print(f'\n-- Phase C: Thermal regression --')
    report.append('\nPhase C -- Thermal regression')

    if residuals is None:
        print('  Skipped -- Phase A failed')
        report.append('  Skipped -- Phase A failed')
    else:
        temps_raw = [p[2] for p in full]
        n_valid_t = sum(1 for t in temps_raw if t is not None)
        print(f'  Rows with temp_c: {n_valid_t} / {len(temps_raw)}')
        report.append(f'  Rows with temp_c: {n_valid_t} / {len(temps_raw)}')

        if n_valid_t == 0:
            print('  Skipped -- all temp_c null (DHT22 not present in this trial)')
            report.append('  Skipped -- all temp_c null')
        elif n_valid_t < MIN_POINTS_TEMP:
            print(f'  Skipped -- fewer than {MIN_POINTS_TEMP} valid temp_c rows')
            report.append(f'  Skipped -- fewer than {MIN_POINTS_TEMP} temp_c rows')
        else:
            mask    = [t is not None for t in temps_raw]
            t_valid = np.array([t for t, m in zip(temps_raw, mask) if m], dtype=float)
            r_valid = residuals[np.array(mask)]
            slope, intercept, r_val, p_val, std_err = linregress(t_valid, r_valid)
            sig = p_val < 0.05
            print(f'  alpha (g/degC) = {slope:.4f}  (intercept = {intercept:.2f})')
            print(f'  r = {r_val:.4f}   p = {p_val:.4e}   std_err = {std_err:.4f}')
            print(f'  Significant (p < 0.05): {"YES" if sig else "NO"}')
            report += [
                f'  alpha     = {slope:.6f} g/degC',
                f'  intercept = {intercept:.4f} g',
                f'  r         = {r_val:.6f}',
                f'  p         = {p_val:.4e}',
                f'  std_err   = {std_err:.6f}',
                f'  Significant (p < 0.05): {"yes" if sig else "no"}',
            ]

    report_path = args.csv + '_fit_report.txt'
    with open(report_path, 'w') as f:
        f.write('\n'.join(report) + '\n')
    print(f'\nReport saved: {report_path}')


if __name__ == '__main__':
    main()
