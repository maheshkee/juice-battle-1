# SESSION HANDOFF — 2026-06-23 FINAL_6
# Gas Cylinder Monitor V1
# Topic: G4 hub domain logic — modular reorg + state machine + gas%

---

## Opening prompt for next session

```
Read ~/ArduinoApps/gas-cylinder-monitor/CLAUDE.md fully.
Then read docs/HANDOFF_2026_06_23_FINAL_6.md.
Confirm you have read both before doing anything.

Next task: N-TARE-CHECK extension — restore TARE_CHECK_THRESHOLD_G from 1000g to 2000g
in node/gas_monitor_v1/gas_monitor_v1.ino for production. Then flash, verify boot=N clean,
confirm tare_check=CLEAN fires correctly at the new threshold.
After node flash: design 3E-005 anchor validation experiment in chat (not CLI).
```

---

## Current position

### Hub — G4 COMPLETE

Architecture: 5-module production system, DEV mode fully deleted.

| Module | File | Responsibility |
|---|---|---|
| Orchestrator | main.py (113 lines) | Wires callbacks, passes data — zero domain logic |
| BLE transport | ble_subscriber.py | Weight/log notify receive, command write |
| Log pipeline | log_transfer.py | LOG_START/LOG_END, temp file → logs/node/ |
| Domain logic | domain.py | Cylinder state machine, steel derivation, gas%, alerts |
| Storage | db.py | SQLite reads/writes, schema migrations |

State machine in domain.py:

| State | Meaning |
|---|---|
| UNINSTALLED | No install_mode set, or cylinder removed |
| BOOTSTRAP_ANCHOR | Waiting for 5-reading stable window to derive steel_g |
| TRACKING | steel_g known, computing gas%, watching for refill/removal |
| LOW_GAS | gas_g < 2000g — same as TRACKING but different alert level |
| EMPTY | Future stub |

Bootstrap regimes (set via `setup` socket.io event):
- FRESH → BOOTSTRAP_ANCHOR — wait for anchor from full cylinder
- PARTIAL_BRAND → TRACKING immediately using brand steel lookup table
- PARTIAL_PRIOR → TRACKING immediately using STEEL_UNKNOWN_PRIOR_G = 16500g

Anchor window: N=5 stable readings, spread < 50g, gross > 26000g.
steel_g = mean(window) − 14200g. Plausibility check: 13000g ≤ steel_g ≤ 18000g.

config.json G4 schema (all fields now present):
```json
{
  "device_name": "GasCylMonitor",
  "device_address": "10:00:3B:CD:63:32",
  "service_uuid": "...",
  "weight_char_uuid": "...",
  "reconnect_delay_s": 5.0,
  "scan_timeout_s": 10.0,
  "brand": null,
  "install_mode": null,
  "cylinder_state": "UNINSTALLED",
  "steel_g": null,
  "steel_source": null,
  "steel_anchored_at": null,
  "cal_factor": null,
  "tare_raw": null,
  "cal_tare_session": null
}
```

Hub is deployed at arduino@AQ3:7000 and running.

### Node — boot=9, all firmware complete except one threshold restore

Production sketch: `node/gas_monitor_v1/gas_monitor_v1.ino`
Boot sequence: SETTLE → TARE_WAIT → TARE → NOISE → CAL → RUNNING

Modules: hx711, tare (SPIFFS), noise, cal, weight, ble (command+log char), health,
         journal (SPIFFS), log_transfer

All verified working on boot=9.

**CRITICAL OPEN ITEM — must fix before production:**
TARE_CHECK_THRESHOLD_G is currently set to 1000g (DEV value for water container testing).
Production value must be 2000g (detects tare performed with a full LPG cylinder on platform).
File: `node/gas_monitor_v1/gas_monitor_v1.ino`
Search: `TARE_CHECK_THRESHOLD_G`
Change: `1000` → `2000`
Flash, verify boot=N clean, confirm tare_check=CLEAN fires at correct threshold.

**Deferred anomaly (not a blocker):**
boot=6 DUMP_LOG anomaly — observed during 1E session. Hub sent DUMP_LOG, node logged
"Unknown command" once before correct handling. Not reproduced since. Log preserved.
Not investigated — defer until 3E-005 produces anchor data worth examining in logs.

---

## What was built this session (G4 — 2026-06-23)

### Chunk 1 — log_transfer.py extracted from main.py
- New file: hub/python/log_transfer.py
- Owns: LOG_DIR, LOG_TMP, _log_tmp_file, _log_transfer_on, init(), on_log_line()
- CLEAR_LOG dependency injected via init(write_command_fn)
- Duplicate LOG_START guard retained

### Chunk 2–4 — domain.py created
- New file: hub/python/domain.py (304 lines)
- Constants: NET_GAS_G=14200, ANCHOR_STABILITY_WINDOW_G=50, ANCHOR_MIN_STABLE_READINGS=5,
  ANCHOR_GROSS_MIN_G=26000, STEEL_PLAUSIBLE_MIN/MAX, STEEL_UNKNOWN_PRIOR_G=16500,
  ALERT_AMBER_G=2000, ALERT_RED_G=1000, DAILY_USE_DEFAULT_G=350, BRAND_STEEL_G lookup
- load_config(), _save_config() (read-modify-write, never clobbers BLE keys)
- _compute_gas(), _evaluate_alerts(), _run_anchor_window()
- get_state_snapshot(), set_install_mode(), process_reading()

### Chunk 3 — main.py wired to domain
- main.py: 267 → 113 lines
- DEV mode deleted: all globals, constants, on_set_dev_mode(), DEV branch in on_weight()
- on_weight() now 8 lines: domain.process_reading() → db_insert_reading() → send_message()
- on_ui_connect() now 3 lines: domain.get_state_snapshot() → two send_message() calls
- on_setup() handler added, registered with ui.on_message('setup', on_setup)
- threading.Timer(5.0) DUMP_LOG on connect retained

### Chunk 5 — db.py schema additions
- db_init(): CREATE TABLE now includes gas_pct, gas_g, alert_level, cylinder_state
- ALTER TABLE loop (try/except) for SQLite version safety on existing DBs
- db_insert_reading(): expanded to 8 params with 4 new kwargs
- Removed: db_get_starting_weight(), db_set_starting_weight(), db_get_dev_mode(), db_set_dev_mode()

### Chunk 6 — index.html DEV toggle removal
- Removed: .toggle-pill and .toggle-opt CSS
- Removed: toggle-pill HTML div from topbar
- Removed: optDev, optProd JS variables
- Removed: applyMode() and setMode() functions
- Removed: socket.on('dev_mode_ack') listener
- Fixed: data.dev_mode block in applyUpdate() → cylinder_state === 'BOOTSTRAP_ANCHOR' check

---

## Next build order

1. **N-TARE-CHECK threshold restore** — node only, 1 line change, flash
   File: node/gas_monitor_v1/gas_monitor_v1.ino
   Change TARE_CHECK_THRESHOLD_G: 1000 → 2000
   Verify: boot=N+1, tare_check=CLEAN with empty platform, tare_check=SUSPECT with container on

2. **3E-005 anchor validation** — experiment, design in chat first
   Goal: confirm hub anchor fires correctly with real cylinder or water-simulation weight
   Simulate FRESH install: send setup FRESH via test script → place full water container → verify TRACKING state

3. **HUB-WATCHDOG** — pre-production requirement, do not defer past Group 5
   See CLAUDE.md backlog for design spec

---

## Key decisions locked this session

| Decision | Value | Rationale |
|---|---|---|
| Anchor stability window | 50g spread over 5 readings | Wider than ANCHOR_SPREAD_THRESHOLD_G=30g from DEV mode — covers IST platform noise |
| ANCHOR_GROSS_MIN_G | 26000g | BIS: 14.2kg gas + 15.3kg steel (Indane) = 29.5kg minimum; 26kg floor clears 500g safety margin |
| STEEL_UNKNOWN_PRIOR_G | 16500g | Conservative prior: leans toward LESS gas shown (L-043 conservative bias rule) |
| Setup endpoint | socket.io 'setup' event | Minimal surface: FRESH / PARTIAL_BRAND / PARTIAL_PRIOR modes |
| State machine vs flags | Explicit states | LOW_GAS as separate state, not a flag in TRACKING (L-085) |
| First-reading cross-check | gross < steel_g − 3000g → UNINSTALLED | Guards against hub restart when cylinder was removed while hub was down |

---

## G4 design decisions locked

### Domain constants (never hardcode elsewhere)
```python
NET_GAS_G                  = 14200.0   # BIS IS 3196, never change
ANCHOR_STABILITY_WINDOW_G  = 50.0      # max spread in anchor window
ANCHOR_MIN_STABLE_READINGS = 5         # window size
ANCHOR_GROSS_MIN_G         = 26000.0   # gross floor for fresh full cylinder
STEEL_PLAUSIBLE_MIN_G      = 13000.0
STEEL_PLAUSIBLE_MAX_G      = 18000.0
STEEL_UNKNOWN_PRIOR_G      = 16500.0   # conservative prior
ALERT_AMBER_G              = 2000.0    # ~5-6 days at 350g/day
ALERT_RED_G                = 1000.0    # ~2-3 days at 350g/day
DAILY_USE_DEFAULT_G        = 350.0
BRAND_STEEL_G = {'Indane': 15300.0, 'HP': 14900.0, 'Bharat': 15100.0}
```

### process_reading() snapshot keys
```python
{
  'grams', 'quality', 'sigma', 'ts',
  'gas_pct', 'gas_g', 'alert_level', 'days_remaining',
  'cylinder_state', 'steel_source', 'brand', 'steel_g',
  'approximate', 'install_mode'
}
```
gas_pct and gas_g are None when state is UNINSTALLED or BOOTSTRAP_ANCHOR.
alert_level: 'RED' | 'AMBER' | 'NORMAL' | None

### alert_level mapping (for UI consumption)
| alert_level | gas_g range | UI behaviour |
|---|---|---|
| None | state != TRACKING/LOW_GAS | No banner |
| NORMAL | > 2000g | No banner |
| AMBER | 1000–2000g | Amber banner, days_remaining |
| RED | < 1000g | Red pulsing banner, days_remaining |

Note: index.html currently checks data.alert (old DEV key). This needs updating in the
UI session when WebUI is rebuilt for G4 — applyUpdate() alert block must switch from
data.alert to data.alert_level with RED/AMBER/NORMAL values.

---

## Files changed this session

| File | Change |
|---|---|
| hub/python/log_transfer.py | NEW — extracted from main.py |
| hub/python/domain.py | NEW — full G4 state machine |
| hub/python/main.py | MODIFIED — 267→113 lines, DEV deleted, wired to domain |
| hub/python/db.py | MODIFIED — 4 new columns, 4 dead functions removed |
| hub/assets/index.html | MODIFIED — DEV/PROD toggle removed, calibrating-label fix |
| hub/config.json | MODIFIED — G4 schema fields added |
