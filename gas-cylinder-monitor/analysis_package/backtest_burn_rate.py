"""
Backtest: endpoint-difference vs OLS burn rate on historical monitor.db data.
Reads TRACKING rows, samples every 15 minutes, computes both methods on the
BURN_RATE_WINDOW_DAYS rolling window at each sample point.
"""
import sqlite3
import sys
from datetime import datetime, timedelta

DB_PATH              = '/home/arduino/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db'
TS_FMT               = '%d %b %Y  %H:%M:%S'
BURN_RATE_WINDOW_DAYS = 0.14583   # 3.5 hours — matches domain.py TEST value
MIN_DATA_HOURS        = 0.25
SAMPLE_STEP_MIN       = 15        # evaluate every 15 minutes


def load_tracking_rows(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    cur.execute(
        "SELECT ts, gas_g FROM readings "
        "WHERE cylinder_state='TRACKING' AND gas_g IS NOT NULL "
        "ORDER BY rowid ASC"
    )
    rows = cur.fetchall()
    conn.close()
    parsed = []
    for row in rows:
        try:
            parsed.append((datetime.strptime(row['ts'], TS_FMT), float(row['gas_g'])))
        except Exception:
            continue
    return parsed


def endpoint_burn_rate(window):
    """(first_gas - last_gas) / window_days. Returns float or None."""
    if len(window) < 2:
        return None
    first_ts, first_gas = window[0]
    last_ts,  last_gas  = window[-1]
    wdays = (last_ts - first_ts).total_seconds() / 86400.0
    wh    = wdays * 24.0
    delta = first_gas - last_gas
    if delta > 0 and wh >= MIN_DATA_HOURS:
        return delta / wdays
    return None


def ols_burn_rate(window):
    """OLS regression burn rate. Returns (rate, r2) or (None, None)."""
    n = len(window)
    if n < 2:
        return None, None
    t0 = window[0][0]
    xs = [(ts - t0).total_seconds() / 86400.0 for ts, _ in window]
    ys = [g for _, g in window]
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    ss_xy  = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    ss_xx  = sum((x - mean_x) ** 2 for x in xs)
    if ss_xx == 0.0:
        return None, None
    slope     = ss_xy / ss_xx
    intercept = mean_y - slope * mean_x
    ss_res    = sum((y - (intercept + slope * x)) ** 2 for x, y in zip(xs, ys))
    ss_tot    = sum((y - mean_y) ** 2 for y in ys)
    r2        = 1.0 - ss_res / ss_tot if ss_tot > 0.0 else 0.0
    rate      = -slope
    if rate > 0:
        return rate, r2
    return None, None


def main():
    print('Loading TRACKING rows...', flush=True)
    rows = load_tracking_rows(DB_PATH)
    if not rows:
        print('No data found.', flush=True)
        sys.exit(1)

    t_start = rows[0][0]
    t_end   = rows[-1][0]
    print(f'Data range: {t_start.strftime(TS_FMT)} → {t_end.strftime(TS_FMT)}')
    print(f'Total rows: {len(rows)}')
    print(f'Rolling window: {BURN_RATE_WINDOW_DAYS*24:.1f}h  Sample step: {SAMPLE_STEP_MIN}min\n')

    # Build sorted list for binary-search style windowing
    # Step through time at SAMPLE_STEP_MIN intervals
    t = t_start + timedelta(hours=BURN_RATE_WINDOW_DAYS * 24)  # need full window first
    results = []
    window_td = timedelta(days=BURN_RATE_WINDOW_DAYS)

    while t <= t_end:
        cutoff = t - window_td
        window = [(ts, g) for ts, g in rows if cutoff <= ts <= t]
        if len(window) >= 2:
            ep  = endpoint_burn_rate(window)
            ol, r2 = ols_burn_rate(window)
            results.append({
                'ts':  t,
                'ep':  ep,
                'ols': ol,
                'r2':  r2,
                'n':   len(window),
            })
        t += timedelta(minutes=SAMPLE_STEP_MIN)

    total     = len(results)
    both_valid = [r for r in results if r['ep'] is not None and r['ols'] is not None]
    ep_only    = [r for r in results if r['ep'] is not None and r['ols'] is None]
    ols_only   = [r for r in results if r['ep'] is None and r['ols'] is not None]
    neither    = [r for r in results if r['ep'] is None and r['ols'] is None]

    print(f'Sample points evaluated: {total}')
    print(f'  Both valid:  {len(both_valid)}')
    print(f'  EP only:     {len(ep_only)}')
    print(f'  OLS only:    {len(ols_only)}')
    print(f'  Neither:     {len(neither)}')

    if both_valid:
        diffs = [r['ols'] - r['ep'] for r in both_valid]
        abs_diffs = [abs(d) for d in diffs]
        print(f'\n--- When both valid (n={len(both_valid)}) ---')
        print(f'OLS - EP:  mean={sum(diffs)/len(diffs):.1f}  '
              f'max_abs={max(abs_diffs):.1f}  '
              f'median_abs={sorted(abs_diffs)[len(abs_diffs)//2]:.1f}  g/day')
        r2s = [r['r2'] for r in both_valid if r['r2'] is not None]
        if r2s:
            print(f'R²:        mean={sum(r2s)/len(r2s):.4f}  '
                  f'min={min(r2s):.4f}  max={max(r2s):.4f}')

    # Per-day breakdown
    print('\n--- Per-day summary ---')
    print(f'{"Day":<12} {"N_pts":>6} {"EP_valid":>9} {"OLS_valid":>10} '
          f'{"mean(OLS-EP)":>13} {"maxabs":>7} {"mean_R2":>8}')
    from collections import defaultdict
    by_day = defaultdict(list)
    for r in results:
        by_day[r['ts'].date()].append(r)

    for day in sorted(by_day):
        day_rows = by_day[day]
        bv = [r for r in day_rows if r['ep'] is not None and r['ols'] is not None]
        ep_v = sum(1 for r in day_rows if r['ep'] is not None)
        ol_v = sum(1 for r in day_rows if r['ols'] is not None)
        if bv:
            diffs = [r['ols'] - r['ep'] for r in bv]
            abs_d = [abs(d) for d in diffs]
            r2s   = [r['r2'] for r in bv if r['r2'] is not None]
            mean_r2 = sum(r2s)/len(r2s) if r2s else float('nan')
            print(f'{str(day):<12} {len(day_rows):>6} {ep_v:>9} {ol_v:>10} '
                  f'{sum(diffs)/len(diffs):>+13.1f} {max(abs_d):>7.1f} {mean_r2:>8.4f}')
        else:
            print(f'{str(day):<12} {len(day_rows):>6} {ep_v:>9} {ol_v:>10} '
                  f'{"(no both valid)":>13}')

    # A few representative rows
    if both_valid:
        print('\n--- Sample rows (every 30th valid point) ---')
        print(f'{"Timestamp":<26} {"N_win":>5} {"EP g/day":>9} {"OLS g/day":>10} '
              f'{"diff":>7} {"R²":>7}')
        step = max(1, len(both_valid) // 30)
        for r in both_valid[::step]:
            diff = r['ols'] - r['ep']
            print(f'{r["ts"].strftime(TS_FMT):<26} {r["n"]:>5} '
                  f'{r["ep"]:>9.1f} {r["ols"]:>10.1f} {diff:>+7.1f} {r["r2"]:>7.4f}')


if __name__ == '__main__':
    main()
