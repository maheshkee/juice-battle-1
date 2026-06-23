import os
import json
import subprocess

# ── Physical constants ────────────────────────────────────────────────────────
NET_GAS_G = 14200.0  # BIS IS 3196 — fixed for 14.2 kg domestic cylinder, never change

# ── Anchor detection ─────────────────────────────────────────────────────────
ANCHOR_STABILITY_WINDOW_G  = 50.0  # TODO: tune after 3E-009
ANCHOR_MIN_STABLE_READINGS = 5     # TODO: validate after 3E-005
ANCHOR_GROSS_MIN_G         = 26000.0  # gross floor for a fresh full cylinder

# ── Steel plausibility bounds ─────────────────────────────────────────────────
STEEL_PLAUSIBLE_MIN_G  = 13000.0
STEEL_PLAUSIBLE_MAX_G  = 18000.0
STEEL_UNKNOWN_PRIOR_G  = 16500.0  # conservative prior — lean toward less gas shown

# ── Alert thresholds — LOCKED 2026-06-12 ─────────────────────────────────────
ALERT_AMBER_G       = 2000.0
ALERT_RED_G         = 1000.0
DAILY_USE_DEFAULT_G = 350.0

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
_brand               = None
_steel_source        = None   # 'ANCHOR' | 'LOOKUP' | 'PRIOR' | None
_steel_g             = None   # derived steel weight in grams
_install_mode        = None   # 'FRESH' | 'PARTIAL_BRAND' | 'PARTIAL_PRIOR'
_candidate_window    = []     # anchor candidate readings list
_first_reading_check = False  # True after first reading post-connect


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

        with open(_CONFIG_PATH, 'w') as f:
            json.dump(cfg, f, indent=2)
        print(f'[DOMAIN] config saved: state={_cylinder_state} steel_g={_steel_g}', flush=True)
    except Exception as e:
        print(f'[DOMAIN] config save failed: {e}', flush=True)


def _compute_gas(gross_g):
    gas_g   = gross_g - _steel_g
    gas_pct = round(gas_g / NET_GAS_G * 100.0, 1)
    gas_g   = round(gas_g, 1)
    return (gas_g, gas_pct)


def _evaluate_alerts(gas_g):
    if gas_g < ALERT_RED_G:
        return ('RED',   max(1, round(gas_g / DAILY_USE_DEFAULT_G)))
    if gas_g < ALERT_AMBER_G:
        return ('AMBER', max(1, round(gas_g / DAILY_USE_DEFAULT_G)))
    return ('NORMAL', None)


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

    print(f'[DOMAIN] *** ANCHOR COMPLETE: mean_gross={mean_gross:.1f}g '
          f'steel_g={_steel_g}g source=ANCHOR  TRACKING ***', flush=True)


def get_state_snapshot():
    return {
        'grams':          None,
        'quality':        None,
        'sigma':          None,
        'ts':             None,
        'gas_pct':        None,
        'gas_g':          None,
        'alert_level':    None,
        'days_remaining': None,
        'cylinder_state': _cylinder_state,
        'steel_source':   _steel_source,
        'brand':          _brand,
        'approximate':    None,
        'steel_g':        _steel_g,
        'install_mode':   _install_mode,
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
    print(f'[DOMAIN] install mode set: mode={mode} brand={brand} '
          f'state={_cylinder_state} steel_g={_steel_g}', flush=True)


def process_reading(grams, quality, sigma, hub_ts):
    global _cylinder_state, _steel_g, _steel_source, _candidate_window
    global _first_reading_check

    # STEP 1 — first-reading cross-check (fires once per hub session)
    if not _first_reading_check:
        _first_reading_check = True
        if _cylinder_state == 'TRACKING' and _steel_g is not None:
            expected_min = _steel_g - 3000.0
            if grams < expected_min:
                print(f'[DOMAIN] CROSS-CHECK FAIL: gross={grams:.1f} '
                      f'expected_min={expected_min:.1f} - transitioning to UNINSTALLED',
                      flush=True)
                _cylinder_state = 'UNINSTALLED'
                _steel_g        = None
                _steel_source   = None
                _save_config()

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
        alert_level, days_remaining = _evaluate_alerts(gas_g)

        if grams > ANCHOR_GROSS_MIN_G:
            print(f'[DOMAIN] Refill detected: gross={grams:.1f}g - re-anchoring', flush=True)
            _cylinder_state   = 'BOOTSTRAP_ANCHOR'
            _candidate_window = []

        elif grams < 500.0:
            print(f'[DOMAIN] Cylinder removed: gross={grams:.1f}g', flush=True)
            _cylinder_state   = 'UNINSTALLED'
            _steel_g          = None
            _steel_source     = None
            _candidate_window = []
            _save_config()

        else:
            snapshot['gas_g']          = gas_g
            snapshot['gas_pct']        = gas_pct
            snapshot['alert_level']    = alert_level
            snapshot['days_remaining'] = days_remaining

            if gas_g < ALERT_AMBER_G:
                _cylinder_state = 'LOW_GAS'
                print(f'[DOMAIN]  LOW_GAS: gas_g={gas_g:.1f}g', flush=True)

    elif _cylinder_state == 'LOW_GAS':
        gas_g, gas_pct = _compute_gas(grams)
        alert_level, days_remaining = _evaluate_alerts(gas_g)

        if grams > ANCHOR_GROSS_MIN_G:
            print(f'[DOMAIN] Refill detected from LOW_GAS: re-anchoring', flush=True)
            _cylinder_state   = 'BOOTSTRAP_ANCHOR'
            _candidate_window = []

        elif grams < 500.0:
            print(f'[DOMAIN] Cylinder removed from LOW_GAS', flush=True)
            _cylinder_state = 'UNINSTALLED'
            _steel_g        = None
            _steel_source   = None
            _save_config()

        else:
            snapshot['gas_g']          = gas_g
            snapshot['gas_pct']        = gas_pct
            snapshot['alert_level']    = alert_level
            snapshot['days_remaining'] = days_remaining

            if gas_g >= ALERT_AMBER_G:
                _cylinder_state = 'TRACKING'

    elif _cylinder_state == 'EMPTY':
        pass  # future stub — treat same as TRACKING for now

    # Reflect any state transitions into snapshot
    snapshot['cylinder_state'] = _cylinder_state
    snapshot['steel_g']        = _steel_g
    snapshot['steel_source']   = _steel_source

    return snapshot
