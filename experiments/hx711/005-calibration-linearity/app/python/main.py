import os
import csv
from datetime import datetime
from arduino.app_utils import App, Bridge

# Derive data dir from this file's location — no hardcoded paths
_APP_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DATA_DIR = os.path.join(_APP_DIR, 'data')
os.makedirs(_DATA_DIR, exist_ok=True)

_csv_file   = None
_csv_writer = None
_prev_mean  = None


def _open_csv():
    global _csv_file, _csv_writer
    ts   = datetime.now().strftime('%Y%m%dT%H%M%S')
    path = os.path.join(_DATA_DIR, f'staircase_{ts}.csv')
    _csv_file   = open(path, 'w', newline='', buffering=1)
    _csv_writer = csv.writer(_csv_file)
    _csv_writer.writerow(['seq', 'mean_raw', 'spread', 'n_samples', 'delta_from_prev'])
    print(f"[CSV] opened {path}", flush=True)


def on_log(data):
    print(f"[MCU] {data}", flush=True)


def on_plateau(data):
    global _csv_file, _csv_writer, _prev_mean
    if _csv_file is None:
        _open_csv()

    parts = data.split(',')
    if len(parts) != 4:
        print(f"[PLATEAU] unexpected format: {data}", flush=True)
        return

    try:
        seq       = int(parts[0])
        mean_raw  = float(parts[1])
        spread    = float(parts[2])
        n_samples = int(parts[3])
    except ValueError:
        print(f"[PLATEAU] parse error: {data}", flush=True)
        return

    delta = round(mean_raw - _prev_mean, 2) if _prev_mean is not None else 0.0
    _prev_mean = mean_raw

    row = [seq, round(mean_raw, 2), round(spread, 2), n_samples, delta]
    _csv_writer.writerow(row)
    _csv_file.flush()
    print(f"[PLATEAU] seq={seq} mean_raw={mean_raw:.2f} spread={spread:.2f} "
          f"n={n_samples} delta={delta:.2f}", flush=True)


Bridge.provide("log",     on_log)
Bridge.provide("plateau", on_plateau)

App.run()
