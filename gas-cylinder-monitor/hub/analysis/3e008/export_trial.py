#!/usr/bin/env python3
"""Export a single 3E-008 trial from monitor.db starting at a boundary row ID."""
import argparse
import csv
import os
import sqlite3
from datetime import datetime

# [ADDITION] dependency check
try:
    import numpy, scipy
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install scipy numpy --break-system-packages")
    raise SystemExit(1)

TS_FMT      = '%d %b %Y  %H:%M:%S'
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_DB = os.path.join(_SCRIPT_DIR, '..', '..', 'data', 'monitor.db')


def main():
    ap = argparse.ArgumentParser(
        description='Export a 3E-008 trial: rows WHERE id >= start_id, ordered by id')
    ap.add_argument('--start-id', type=int, required=True,
                    help='DB row id of the first reading after stone placement (inclusive)')
    ap.add_argument('--out', required=True, help='Output CSV file path')
    ap.add_argument('--db', default=_DEFAULT_DB, help='Path to monitor.db')
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        'SELECT id, ts, grams, temp_c FROM readings WHERE id >= ? ORDER BY id ASC',
        (args.start_id,)
    ).fetchall()
    conn.close()

    if not rows:
        print(f'ERROR: no rows found for id >= {args.start_id}')
        return

    try:
        t0 = datetime.strptime(rows[0]['ts'].strip(), TS_FMT)
    except Exception as e:
        print(f'ERROR: cannot parse first-row ts "{rows[0]["ts"]}": {e}')
        return

    null_count = 0
    grams_vals = []

    with open(args.out, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'ts', 'grams', 'temp_c', 'elapsed_seconds'])
        for row in rows:
            try:
                ts      = datetime.strptime(row['ts'].strip(), TS_FMT)
                elapsed = (ts - t0).total_seconds()
            except Exception:
                elapsed = None
            temp_c = row['temp_c']
            if temp_c is None:
                null_count += 1
            grams_vals.append(float(row['grams']))
            writer.writerow([
                row['id'],
                row['ts'],
                f"{float(row['grams']):.2f}",
                '' if temp_c is None else f'{float(temp_c):.2f}',
                '' if elapsed is None else f'{elapsed:.0f}',
            ])

    t_last = datetime.strptime(rows[-1]['ts'].strip(), TS_FMT)
    span_h = (t_last - t0).total_seconds() / 3600.0

    print(f'Rows exported  : {len(rows)}')
    print(f'Elapsed span   : {span_h:.2f} h  ({span_h / 24:.2f} days)')
    print(f'temp_c null    : {null_count} / {len(rows)}')
    print(f'grams range    : {min(grams_vals):.1f} – {max(grams_vals):.1f} g')
    print(f'Output         : {args.out}')


if __name__ == '__main__':
    main()
