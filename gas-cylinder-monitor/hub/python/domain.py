import time
import os
import json
import subprocess
import hub_logger

# ── Physical constants ────────────────────────────────────────────────────────
NET_GAS_G = 4535.0  # BIS IS 3196 — fixed for 14.2 kg domestic cylinder, never change

# ── Anchor detection ─────────────────────────────────────────────────────────
ANCHOR_STABILITY_WINDOW_G  = 50.0  # TODO: tune after 3E-009
ANCHOR_MIN_STABLE_READINGS = 5     # TODO: validate after 3E-005
ANCHOR_GROSS_MIN_G         = 4800.0  # gross floor for a fresh full cylinder
REFILL_GROSS_MIN_G         = 22000.0  # TEST. PRODUCTION = 29000.0
REMOVAL_GRACE_S            = 120.0    # seconds before confirming cylinder removed

# ── Steel plausibility bounds ─────────────────────────────────────────────────
STEEL_PLAUSIBLE_MIN_G  = 13000.0
STEEL_PLAUSIBLE_MAX_G  = 18000.0
STEEL_UNKNOWN_PRIOR_G  = 16500.0  # conservative prior — lean toward less gas shown

# ── Alert thresholds — LOCKED 2026-06-12 ─────────────────────────────────────
ALERT_AMBER_G       = 2000.0
ALERT_RED_G         = 1000.0
DAILY_USE_DEFAULT_G = 350.0

# ── G5 analytics constants ────────────────────────────────────────────────────
# TEST values - see GasMonitor_Complete_Revert_Reference.docx for production values
MIN_DATA_HOURS           = 0.25          # PRODUCTION: 24.0
BURN_RATE_WINDOW_DAYS    = 7.0           # production rolling window; test was 0.14583 (3.5 h)
MIN_BURN_RATE_G_PER_DAY  = 10.0          # same in production
MAX_BURN_RATE_G_PER_DAY  = 100000.0      # PRODUCTION: 2000.0
# OLS fit quality gate — results below this R² are treated as unreliable.
# Starting value 0.3; revisit after production-constant backtest and 3E-008 thermal correction.
R2_MIN_THRESHOLD         = 0.3
SECONDS_PER_DAY          = 86400         # seconds in one day — used in all elapsed-day calculations

# ── Alert constants ────────────────────────────────────────────────────────────
# Gram failsafe - same in test and production
ALERT_AMBER_G            = 2000.0        # unchanged
ALERT_RED_G              = 1000.0        # unchanged
# FUNCTIONAL_ZERO_G — weight below which gas is inaccessible
# DEV value: bowl tap-height residual measured 2026-06-26
# PRODUCTION: replace after experiment 3E-ZERO
FUNCTIONAL_ZERO_G        = 1300.0
# Day-based - TEST values (scaled 1:48)
MIN_DAYS_FOR_DAY_ALERT   = 0.04167       # PRODUCTION: 2.0  (60 min test = 2 days prod)
ALERT_AMBER_DAYS         = 0.10417       # PRODUCTION: 5.0  (2.5 hrs test = 5 days prod)
ALERT_RED_DAYS           = 0.0625        # PRODUCTION: 3.0  (90 min test = 3 days prod)

# ── Brand steel lookup (grams) ────────────────────────────────────────────────
BRAND_STEEL_G = {
    'Indane': 15300.0,
    'HP':     14900.0,
    'Bharat': 15100.0,
}

# ── Config path — derived from this file, never hardcoded ────────────────────
_CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config.json')

# ── Module-level state ────────────────────────────────────────────────────────
_cylinder_state      = 'UNINSTALLED'
_removal_start_ts    = None           # set when gross drops below 500g in TRACKING/LOW_GAS
_brand               = None
_steel_source        = None   # 'ANCHOR' | 'LOOKUP' | 'PRIOR' | None
_steel_g             = None   # derived steel weight in grams
_install_mode        = None   # 'FRESH' | 'PARTIAL_BRAND' | 'PARTIAL_PRIOR'
_candidate_window    = []     # anchor candidate readings list
_first_reading_check = False  # True after first reading post-connect
_last_alert_level    = None


def get_config():
    try:
        with open(_CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {}


def parse_tare_from_journal(journal_path):
    """Return the tare mean (float) from the most recent TARE PHASE_COMPLETE line, or None."""
    try:
        tare_raw = None
        with open(journal_path) as f:
            for line in f:
                if ('[BOOT] event=PHASE_COMPLETE phase=TARE result=OK' in line
                        and 'mean=' in line):
                    for part in line.split():
                        if part.startswith('mean='):
                            tare_raw = float(part.split('=', 1)[1])
                            break
        return tare_raw
    except Exception as e:
        print(f'[DOMAIN] parse_tare_from_journal failed: {e}', flush=True)
        return None


def update_tare_in_config(tare_raw, config_path):
    """Read config_path, update tare_raw field, write back. Preserves all other keys."""
    try:
        try:
            with open(config_path) as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}
        cfg['tare_raw'] = tare_raw
        tmp = config_path + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(cfg, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, config_path)
        print(f'[DOMAIN] tare_raw updated: {tare_raw}', flush=True)
    except Exception as e:
        print(f'[DOMAIN] update_tare_in_config failed: {e}', flush=True)


def load_config():
    global _cylinder_state, _brand, _steel_source, _steel_g, _install_mode
    try:
        with open(_CONFIG_PATH) as f:
            cfg = json.load(f)
        _brand          = cfg.get('brand', None)
        _cylinder_state = cfg.get('cylinder_state', 'UNINSTALLED')
        _steel_source   = cfg.get('steel_source', None)
        _steel_g        = cfg.get('steel_g', None)
        _install_mode   = cfg.get('install_mode', None)
    except Exception as e:
        print(f'[DOMAIN] config load failed: {e} — using defaults', flush=True)
    print(
        f'[DOMAIN] config loaded: state={_cylinder_state} '
        f'brand={_brand} steel_source={_steel_source}',
        flush=True,
    )


def _save_config():
    try:
        try:
            with open(_CONFIG_PATH) as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}

        if _steel_g is not None:
            try:
                ts = subprocess.run(
                    ['date', '+%d %b %Y  %H:%M:%S'],
                    capture_output=True, text=True
                ).stdout.strip()
            except Exception:
                ts = None
        else:
            ts = None

        # Update domain keys only — never touch BLE transport keys
        cfg['brand']             = _brand
        cfg['install_mode']      = _install_mode
        cfg['cylinder_state']    = _cylinder_state
        cfg['steel_g']           = _steel_g
        cfg['steel_source']      = _steel_source
        cfg['steel_anchored_at'] = ts
        cfg['cal_factor']        = cfg.get('cal_factor', None)
        cfg['tare_raw']          = cfg.get('tare_raw', None)
        cfg['cal_tare_session']  = cfg.get('cal_tare_session', None)

        tmp = _CONFIG_PATH + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(cfg, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, _CONFIG_PATH)
        print(f'[DOMAIN] config saved: state={_cylinder_state} steel_g={_steel_g}', flush=True)
    except Exception as e:
        print(f'[DOMAIN] config save failed: {e}', flush=True)


def _compute_gas(gross_g):
    gas_g   = gross_g - _steel_g
    gas_pct = round(gas_g / NET_GAS_G * 100.0, 1)
    gas_g   = round(gas_g, 1)
    return (gas_g, gas_pct)


def _evaluate_alerts(gas_g, days_remaining=None, elapsed_days=None, burn_rate=None):
    # Condition A: gram failsafe — always active
    if gas_g < ALERT_RED_G:
        return 'RED'
    if gas_g < ALERT_AMBER_G:
        return 'AMBER'

    # Condition B: day-based — requires reliable burn rate
    if (days_remaining is not None and
            burn_rate is not None and
            elapsed_days is not None and
            elapsed_days >= MIN_DAYS_FOR_DAY_ALERT):
        if days_remaining < ALERT_RED_DAYS:
            return 'RED'
        if days_remaining < ALERT_AMBER_DAYS:
            return 'AMBER'
    return 'NONE'


def _run_anchor_window(grams):
    global _cylinder_state, _steel_g, _steel_source, _candidate_window

    if grams < ANCHOR_GROSS_MIN_G:
        if _candidate_window:
            print(f'[DOMAIN] Anchor window reset - gross dropped: {grams:.1f}g', flush=True)
        _candidate_window = []
        return

    _candidate_window.append(grams)

    if len(_candidate_window) < ANCHOR_MIN_STABLE_READINGS:
        print(f'[DOMAIN] Anchor candidate {len(_candidate_window)}/'
              f'{ANCHOR_MIN_STABLE_READINGS}: {grams:.1f}g', flush=True)
        return

    spread = max(_candidate_window) - min(_candidate_window)
    if spread > ANCHOR_STABILITY_WINDOW_G:
        _candidate_window.pop(0)
        print(f'[DOMAIN] Anchor window unstable: spread={spread:.1f}g '
              f'> {ANCHOR_STABILITY_WINDOW_G}g - rolling', flush=True)
        return

    # Window stable — derive steel
    mean_gross    = sum(_candidate_window) / len(_candidate_window)
    derived_steel = mean_gross - NET_GAS_G

    if not (STEEL_PLAUSIBLE_MIN_G <= derived_steel <= STEEL_PLAUSIBLE_MAX_G):
        print(f'[DOMAIN] Anchor REJECTED: steel_g={derived_steel:.1f}g '
              f'out of plausible range [{STEEL_PLAUSIBLE_MIN_G}, '
              f'{STEEL_PLAUSIBLE_MAX_G}]', flush=True)
        _candidate_window = []
        return

    _steel_g          = round(derived_steel, 1)
    _steel_source     = 'ANCHOR'
    _cylinder_state   = 'TRACKING'
    _candidate_window = []
    _save_config()
    hub_logger.log_domain('ANCHOR_COMPLETE', steel_g=_steel_g, mean_gross=round(mean_gross, 1))
    hub_logger.log_domain('STATE_CHANGE', new_state='TRACKING', source='ANCHOR')

    print(f'[DOMAIN] *** ANCHOR COMPLETE: mean_gross={mean_gross:.1f}g '
          f'steel_g={_steel_g}g source=ANCHOR  TRACKING ***', flush=True)


def get_state_snapshot():
    return {
        'grams':               None,
        'quality':             None,
        'sigma':               None,
        'ts':                  None,
        'temp_c':              None,
        'gas_pct':             None,
        'gas_g':               None,
        'alert_level':         None,
        'days_remaining':      None,
        'burn_rate_g_per_day': None,
        'predicted_empty':     None,
        'burn_rate_source':    None,
        'cylinder_state':      _cylinder_state,
        'steel_source':        _steel_source,
        'brand':               _brand,
        'approximate':         None,
        'steel_g':             _steel_g,
        'install_mode':        _install_mode,
    }


def set_install_mode(mode, brand=None):
    global _cylinder_state, _brand, _steel_source, _steel_g
    global _install_mode, _candidate_window

    _install_mode     = mode
    _candidate_window = []

    if mode == 'FRESH':
        _cylinder_state = 'BOOTSTRAP_ANCHOR'
        _brand          = brand   # may be None — brand not required for fresh
        _steel_g        = None
        _steel_source   = None

    elif mode == 'PARTIAL_BRAND':
        _brand          = brand
        _steel_g        = BRAND_STEEL_G.get(brand, STEEL_UNKNOWN_PRIOR_G)
        _steel_source   = 'LOOKUP'
        _cylinder_state = 'TRACKING'

    elif mode == 'PARTIAL_PRIOR':
        _brand          = brand   # may be None
        _steel_g        = STEEL_UNKNOWN_PRIOR_G
        _steel_source   = 'PRIOR'
        _cylinder_state = 'TRACKING'

    _save_config()
    hub_logger.log_domain('STATE_CHANGE', new_state=_cylinder_state, source=f'INSTALL_{mode}')
    print(f'[DOMAIN] install mode set: mode={mode} brand={brand} '
          f'state={_cylinder_state} steel_g={_steel_g}', flush=True)


def set_uninstall_mode():
    """Explicit user-initiated uninstall via WebUI button.
    Clears steel_g completely — next install will need full anchor window.
    Never called by automatic logic — only by user action."""
    global _cylinder_state, _steel_g, _steel_source, _steel_anchored_at
    global _candidate_window, _removal_start_ts
    _cylinder_state    = 'UNINSTALLED'
    _steel_g           = None
    _steel_source      = None
    _steel_anchored_at = None
    _candidate_window  = []
    _removal_start_ts  = None
    _save_config()
    print('[DOMAIN] set_uninstall_mode: explicit user action — steel_g cleared, UNINSTALLED',
          flush=True)
    hub_logger.log_domain('STATE_CHANGE', new_state='UNINSTALLED',
                          source='USER_EXPLICIT_UNINSTALL')


def compute_analytics(current_gas_g, cylinder_state='TRACKING'):
    import sqlite3
    from datetime import datetime, timedelta

    _TS_FMT  = '%d %b %Y  %H:%M:%S'
    _db_path = os.path.join(os.path.dirname(_CONFIG_PATH), 'data', 'monitor.db')

    def _none_result(source, elapsed=None):
        return {
            'burn_rate_g_per_day': None, 'days_remaining': None,
            'predicted_empty':     None, 'burn_rate_source': source,
            'elapsed_days':        elapsed,
        }

    try:
        now = datetime.now()

        # Load anchor timestamp from config
        anchor_ts = None
        try:
            with open(_CONFIG_PATH) as f:
                cfg = json.load(f)
            sat = cfg.get('steel_anchored_at')
            if sat:
                anchor_ts = datetime.strptime(sat, _TS_FMT)
        except Exception:
            pass

        # Fallback: query earliest TRACKING reading
        if anchor_ts is None:
            try:
                conn = sqlite3.connect(_db_path)
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute(
                    "SELECT ts FROM readings WHERE cylinder_state='TRACKING' "
                    "AND gas_g IS NOT NULL ORDER BY rowid ASC LIMIT 1"
                )
                row = cur.fetchone()
                conn.close()
                if row:
                    anchor_ts = datetime.strptime(row['ts'], _TS_FMT)
            except Exception:
                pass

        if anchor_ts is None:
            return _none_result('WAITING')

        elapsed_days  = (now - anchor_ts).total_seconds() / SECONDS_PER_DAY
        elapsed_hours = elapsed_days * 24.0

        if elapsed_hours < MIN_DATA_HOURS:
            return _none_result('WAITING', elapsed_days)

        total_consumed_g = NET_GAS_G - current_gas_g
        if total_consumed_g <= 0:
            return _none_result('NO_CONSUMPTION', elapsed_days)

        source    = None
        burn_rate = None

        if elapsed_days < BURN_RATE_WINDOW_DAYS:
            # Not enough history yet — use cumulative from anchor
            burn_rate = total_consumed_g / elapsed_days
            source    = 'CUMULATIVE'
        else:
            # Try rolling window
            cutoff = now - timedelta(days=BURN_RATE_WINDOW_DAYS)
            try:
                conn = sqlite3.connect(_db_path)
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute(
                    "SELECT ts, AVG(gas_g) as gas_g FROM readings "
                    "WHERE cylinder_state='TRACKING' AND gas_g IS NOT NULL "
                    "GROUP BY ts ORDER BY ts ASC"
                )
                rows = cur.fetchall()
                conn.close()
            except Exception as e:
                print(f'[DOMAIN] compute_analytics rolling query failed: {e}', flush=True)
                rows = []

            parsed = []
            for row in rows:
                try:
                    ts = datetime.strptime(row['ts'], _TS_FMT)
                    if ts >= cutoff:
                        parsed.append((ts, row['gas_g']))
                except Exception:
                    continue

            if len(parsed) >= 2:
                first_ts, first_gas = parsed[0]
                last_ts,  last_gas  = parsed[-1]
                window_days  = (last_ts - first_ts).total_seconds() / SECONDS_PER_DAY
                window_hours = window_days * 24.0
                delta = first_gas - last_gas
                if delta > 0 and window_hours >= MIN_DATA_HOURS:
                    burn_rate = delta / window_days
                    source    = 'ROLLING'

            if source is None:
                burn_rate = total_consumed_g / elapsed_days
                source    = 'CUMULATIVE_FALLBACK'

        if burn_rate < MIN_BURN_RATE_G_PER_DAY:
            return _none_result('BELOW_MIN', elapsed_days)

        # Only apply MAX ceiling in normal TRACKING state
        # In LOW_GAS, any burn rate above MIN is valid - user MUST see a result
        if cylinder_state != 'LOW_GAS' and burn_rate > MAX_BURN_RATE_G_PER_DAY:
            return _none_result('ABOVE_MAX', elapsed_days)

        days_remaining  = round(current_gas_g / burn_rate, 1)
        predicted_empty = (now + timedelta(days=days_remaining)).strftime('%d %b %Y')

        return {
            'burn_rate_g_per_day': round(burn_rate, 1),
            'days_remaining':      days_remaining,
            'predicted_empty':     predicted_empty,
            'burn_rate_source':    source,
            'elapsed_days':        elapsed_days,
        }

    except Exception as e:
        print(f'[DOMAIN] compute_analytics error: {e}', flush=True)
        return _none_result('ERROR')


def _ols_burn_rate(points):
    """
    OLS linear regression of gas_g vs elapsed days across the full point set.
    points: [(datetime, gas_g), ...] sorted oldest to newest, len >= 2.
    Returns (burn_rate_g_per_day, r2, n) or None if computation fails.
    Burn rate = -slope: positive means gas is decreasing.
    """
    n = len(points)
    if n < 2:
        return None
    t0 = points[0][0]
    xs = [(ts - t0).total_seconds() / SECONDS_PER_DAY for ts, _ in points]
    ys = [g for _, g in points]

    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    ss_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    ss_xx = sum((x - mean_x) ** 2 for x in xs)
    if ss_xx == 0.0:
        return None

    slope     = ss_xy / ss_xx
    intercept = mean_y - slope * mean_x
    ss_res    = sum((y - (intercept + slope * x)) ** 2 for x, y in zip(xs, ys))
    ss_tot    = sum((y - mean_y) ** 2 for y in ys)
    r2        = 1.0 - ss_res / ss_tot if ss_tot > 0.0 else 0.0
    return (-slope, r2, n)


def compute_analytics_ols(current_gas_g, cylinder_state='TRACKING'):
    """
    Experimental variant of compute_analytics using OLS regression for the rolling window.
    Preserves all adaptive logic (cumulative / rolling / fallback), sanity bounds,
    and TRACKING-only filter. Adds r2 and ols_n to the result dict.
    DO NOT use in production until backtest comparison reviewed.
    """
    import sqlite3
    from datetime import datetime, timedelta

    _TS_FMT  = '%d %b %Y  %H:%M:%S'
    _db_path = os.path.join(os.path.dirname(_CONFIG_PATH), 'data', 'monitor.db')

    def _none_result_ols(source, elapsed=None):
        return {
            'burn_rate_g_per_day': None, 'days_remaining': None,
            'predicted_empty':     None, 'burn_rate_source': source,
            'elapsed_days':        elapsed, 'r2': None, 'ols_n': None,
        }

    try:
        now = datetime.now()

        anchor_ts = None
        try:
            with open(_CONFIG_PATH) as f:
                cfg = json.load(f)
            sat = cfg.get('steel_anchored_at')
            if sat:
                anchor_ts = datetime.strptime(sat, _TS_FMT)
        except Exception:
            pass

        if anchor_ts is None:
            try:
                conn = sqlite3.connect(_db_path)
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute(
                    "SELECT ts FROM readings WHERE cylinder_state='TRACKING' "
                    "AND gas_g IS NOT NULL ORDER BY rowid ASC LIMIT 1"
                )
                row = cur.fetchone()
                conn.close()
                if row:
                    anchor_ts = datetime.strptime(row['ts'], _TS_FMT)
            except Exception:
                pass

        if anchor_ts is None:
            return _none_result_ols('WAITING')

        elapsed_days  = (now - anchor_ts).total_seconds() / SECONDS_PER_DAY
        elapsed_hours = elapsed_days * 24.0

        if elapsed_hours < MIN_DATA_HOURS:
            return _none_result_ols('WAITING', elapsed_days)

        total_consumed_g = NET_GAS_G - current_gas_g
        if total_consumed_g <= 0:
            return _none_result_ols('NO_CONSUMPTION', elapsed_days)

        source    = None
        burn_rate = None
        r2        = None
        ols_n     = None

        if elapsed_days < BURN_RATE_WINDOW_DAYS:
            burn_rate = total_consumed_g / elapsed_days
            source    = 'CUMULATIVE'
        else:
            cutoff = now - timedelta(days=BURN_RATE_WINDOW_DAYS)
            try:
                conn = sqlite3.connect(_db_path)
                conn.row_factory = sqlite3.Row
                cur = conn.cursor()
                cur.execute(
                    "SELECT ts, AVG(gas_g) as gas_g FROM readings "
                    "WHERE cylinder_state='TRACKING' AND gas_g IS NOT NULL "
                    "GROUP BY ts ORDER BY ts ASC"
                )
                rows = cur.fetchall()
                conn.close()
            except Exception as e:
                print(f'[DOMAIN] compute_analytics_ols rolling query failed: {e}', flush=True)
                rows = []

            parsed = []
            for row in rows:
                try:
                    ts = datetime.strptime(row['ts'], _TS_FMT)
                    if ts >= cutoff:
                        parsed.append((ts, row['gas_g']))
                except Exception:
                    continue

            if len(parsed) >= 2:
                window_days  = (parsed[-1][0] - parsed[0][0]).total_seconds() / SECONDS_PER_DAY
                window_hours = window_days * 24.0
                ols_result   = _ols_burn_rate(parsed)
                if ols_result is not None:
                    ols_br, ols_r2, ols_n_pts = ols_result
                    if ols_br > 0 and window_hours >= MIN_DATA_HOURS:
                        if ols_r2 < R2_MIN_THRESHOLD:
                            source = 'ROLLING_LOW_CONFIDENCE'
                        else:
                            burn_rate = ols_br
                            r2        = ols_r2
                            ols_n     = ols_n_pts
                            source    = 'ROLLING_OLS'

            if burn_rate is None:
                burn_rate = total_consumed_g / elapsed_days
                if source is None:
                    source = 'CUMULATIVE_FALLBACK'

        if burn_rate < MIN_BURN_RATE_G_PER_DAY:
            return _none_result_ols('BELOW_MIN', elapsed_days)

        if cylinder_state != 'LOW_GAS' and burn_rate > MAX_BURN_RATE_G_PER_DAY:
            return _none_result_ols('ABOVE_MAX', elapsed_days)

        days_remaining  = round(current_gas_g / burn_rate, 1)
        predicted_empty = (now + timedelta(days=days_remaining)).strftime('%d %b %Y')

        return {
            'burn_rate_g_per_day': round(burn_rate, 1),
            'days_remaining':      days_remaining,
            'predicted_empty':     predicted_empty,
            'burn_rate_source':    source,
            'elapsed_days':        elapsed_days,
            'r2':                  round(r2, 4) if r2 is not None else None,
            'ols_n':               ols_n,
        }

    except Exception as e:
        print(f'[DOMAIN] compute_analytics_ols error: {e}', flush=True)
        return _none_result_ols('ERROR')


def process_reading(grams, quality, sigma, hub_ts):
    global _cylinder_state, _steel_g, _steel_source, _candidate_window
    global _first_reading_check, _last_alert_level, _removal_start_ts

    # STEP 1 — first-reading cross-check (fires once per hub session)
    if not _first_reading_check:
        _first_reading_check = True
        if _cylinder_state == 'TRACKING' and _steel_g is not None:
            expected_min = _steel_g - 3000.0
            if grams < expected_min:
                print(f'[DOMAIN] CROSS-CHECK FAIL: gross={grams:.1f} '
                      f'expected_min={expected_min:.1f} - transitioning to UNINSTALLED',
                      flush=True)
                _cylinder_state = 'CYLINDER_ABSENT'
                # steel_g intentionally preserved — cylinder may have just been absent during
                # power cut or HX711 startup artifact. Weight-match on return will confirm.
                _save_config()
                hub_logger.log_domain('STATE_CHANGE', new_state='CYLINDER_ABSENT', source='CROSS_CHECK_FAIL')

    print(f'[DOMAIN] process_reading: grams={grams:.1f} state={_cylinder_state}', flush=True)

    snapshot = get_state_snapshot()
    snapshot['grams']   = round(grams, 1)
    snapshot['quality'] = quality
    snapshot['sigma']   = round(sigma, 2)
    snapshot['ts']      = hub_ts

    # STEP 2 — state machine dispatch
    if _cylinder_state == 'UNINSTALLED':
        if grams > 500.0:
            pass  # platform not empty but no install mode set — wait for set_install_mode()
        # return snapshot with no gas%

    elif _cylinder_state == 'BOOTSTRAP_ANCHOR':
        _run_anchor_window(grams)
        # return snapshot — gas% still None until anchor fires

    elif _cylinder_state == 'TRACKING':
        gas_g, gas_pct = _compute_gas(grams)

        if grams > REFILL_GROSS_MIN_G:
            print(f'[DOMAIN] Refill detected: gross={grams:.1f}g - re-anchoring', flush=True)
            _cylinder_state   = 'BOOTSTRAP_ANCHOR'
            _candidate_window = []
            hub_logger.log_domain('STATE_CHANGE', new_state='BOOTSTRAP_ANCHOR', source='REFILL_DETECTED')

        elif grams < 500.0:
            if _removal_start_ts is None:
                _removal_start_ts = time.time()
                print(f'[DOMAIN] Cylinder low/removed: grace window started ({REMOVAL_GRACE_S}s)', flush=True)
            elif time.time() - _removal_start_ts > REMOVAL_GRACE_S:
                print(f'[DOMAIN] Grace expired: transitioning to UNINSTALLED', flush=True)
                _cylinder_state   = 'CYLINDER_ABSENT'
                # steel_g intentionally preserved for weight-match on return
                _candidate_window = []
                _removal_start_ts = None
                _save_config()
                hub_logger.log_domain('STATE_CHANGE', new_state='CYLINDER_ABSENT', source='CYLINDER_REMOVED')

        else:
            _removal_start_ts = None

            _a           = compute_analytics(gas_g, cylinder_state='TRACKING')
            elapsed_days = _a.get('elapsed_days')
            alert_level  = _evaluate_alerts(
                gas_g,
                days_remaining=_a.get('days_remaining'),
                elapsed_days=elapsed_days,
                burn_rate=_a.get('burn_rate_g_per_day'),
            )

            snapshot['gas_g']               = gas_g
            snapshot['gas_pct']             = gas_pct
            snapshot['alert_level']         = alert_level
            snapshot['days_remaining']      = _a['days_remaining']
            snapshot['burn_rate_g_per_day'] = _a['burn_rate_g_per_day']
            snapshot['predicted_empty']     = _a['predicted_empty']
            snapshot['burn_rate_source']    = _a.get('burn_rate_source')

            if alert_level != _last_alert_level:
                hub_logger.log_domain('ALERT', level=alert_level, gas_g=round(gas_g, 1))
                _last_alert_level = alert_level

            if gas_g < ALERT_AMBER_G:
                _cylinder_state = 'LOW_GAS'
                print(f'[DOMAIN]  LOW_GAS: gas_g={gas_g:.1f}g', flush=True)
                hub_logger.log_domain('STATE_CHANGE', new_state='LOW_GAS', gas_g=round(gas_g, 1))

            # If we just transitioned to LOW_GAS but analytics returned None (ABOVE_MAX ceiling),
            # re-call with LOW_GAS to bypass the ceiling
            if _cylinder_state == 'LOW_GAS' and (
                    _a is None or _a.get('burn_rate_g_per_day') is None):
                _a = compute_analytics(gas_g, cylinder_state='LOW_GAS')
                if _a is not None:
                    snapshot['burn_rate_g_per_day'] = _a.get('burn_rate_g_per_day')
                    snapshot['days_remaining']      = _a.get('days_remaining')
                    snapshot['predicted_empty']     = _a.get('predicted_empty')
                    snapshot['burn_rate_source']    = _a.get('burn_rate_source')

    elif _cylinder_state == 'LOW_GAS':
        gas_g, gas_pct = _compute_gas(grams)

        if grams > REFILL_GROSS_MIN_G:
            print(f'[DOMAIN] Refill detected from LOW_GAS: re-anchoring', flush=True)
            _cylinder_state   = 'BOOTSTRAP_ANCHOR'
            _candidate_window = []
            hub_logger.log_domain('STATE_CHANGE', new_state='BOOTSTRAP_ANCHOR', source='REFILL_FROM_LOW_GAS')

        elif grams < 500.0:
            if _removal_start_ts is None:
                _removal_start_ts = time.time()
                print(f'[DOMAIN] Cylinder low/removed from LOW_GAS: grace window started ({REMOVAL_GRACE_S}s)', flush=True)
            elif time.time() - _removal_start_ts > REMOVAL_GRACE_S:
                print(f'[DOMAIN] Grace expired from LOW_GAS: transitioning to UNINSTALLED', flush=True)
                _cylinder_state   = 'CYLINDER_ABSENT'
                # steel_g intentionally preserved for weight-match on return
                _candidate_window = []
                _removal_start_ts = None
                _save_config()
                hub_logger.log_domain('STATE_CHANGE', new_state='CYLINDER_ABSENT', source='REMOVED_FROM_LOW_GAS')

        else:
            _removal_start_ts = None

            _a           = compute_analytics(gas_g, cylinder_state='LOW_GAS')
            elapsed_days = _a.get('elapsed_days')
            alert_level  = _evaluate_alerts(
                gas_g,
                days_remaining=_a.get('days_remaining'),
                elapsed_days=elapsed_days,
                burn_rate=_a.get('burn_rate_g_per_day'),
            )

            snapshot['gas_g']               = gas_g
            snapshot['gas_pct']             = gas_pct
            snapshot['alert_level']         = alert_level
            snapshot['days_remaining']      = _a['days_remaining']
            snapshot['burn_rate_g_per_day'] = _a['burn_rate_g_per_day']
            snapshot['predicted_empty']     = _a['predicted_empty']
            snapshot['burn_rate_source']    = _a.get('burn_rate_source')

            if alert_level != _last_alert_level:
                hub_logger.log_domain('ALERT', level=alert_level, gas_g=round(gas_g, 1))
                _last_alert_level = alert_level

            if gas_g >= ALERT_AMBER_G:
                _cylinder_state = 'TRACKING'
                hub_logger.log_domain('STATE_CHANGE', new_state='TRACKING', source='ALERT_CLEAR')

    elif _cylinder_state == 'CYLINDER_ABSENT':
        if _steel_g is not None and grams >= (_steel_g - 500.0):
            # Weight matches known steel — same cylinder returned. Resume TRACKING
            # directly without anchor rebuild. No human intervention needed.
            _cylinder_state   = 'TRACKING'
            _removal_start_ts = None
            _candidate_window = []
            _save_config()
            print(f'[DOMAIN] Cylinder returned: gross={grams:.1f}g >= steel_g={_steel_g:.1f}g-500 '
                  f'— resuming TRACKING directly', flush=True)
            hub_logger.log_domain('STATE_CHANGE', new_state='TRACKING', source='CYLINDER_RETURN')
        elif grams > 500.0:
            # Something on platform but weight is well below steel_g — unknown object or
            # different cylinder. Run anchor to establish new identity.
            _cylinder_state   = 'BOOTSTRAP_ANCHOR'
            _candidate_window = []
            _save_config()
            print(f'[DOMAIN] Unknown weight: gross={grams:.1f}g, expected >={_steel_g - 500.0 if _steel_g else "?"}g '
                  f'— going BOOTSTRAP_ANCHOR', flush=True)
            hub_logger.log_domain('STATE_CHANGE', new_state='BOOTSTRAP_ANCHOR',
                                  source='UNKNOWN_WEIGHT_ON_PLATFORM')
        # else grams <= 500g — nothing on platform, stay CYLINDER_ABSENT

    elif _cylinder_state == 'EMPTY':
        pass  # future stub — treat same as TRACKING for now

    # Reflect any state transitions into snapshot
    snapshot['cylinder_state'] = _cylinder_state
    snapshot['steel_g']        = _steel_g
    snapshot['steel_source']   = _steel_source

    g = snapshot.get('gas_g')
    snapshot['usable_g'] = round(max(0.0, g - FUNCTIONAL_ZERO_G), 1) if g is not None else None

    return snapshot
