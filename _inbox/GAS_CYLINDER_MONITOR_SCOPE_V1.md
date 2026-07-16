# Gas Cylinder Monitor — V1 Scope

**Board:** AQ3 (192.168.1.161) — STM32U585 MCU + QRB2210 MPU  
**App:** gas-cylinder-monitor  
**Status:** Locked — session 2026-06-03

---

## Product Goal

Monitor the weight of an LPG gas cylinder in an Indian household. Derive
gas remaining, percentage, and days-remaining from real weight readings.
No government averages. No assumed consumption values. Every number comes
from this household's actual sensor readings.

---

## Version Strategy

Three versions handle progressively complex first-install scenarios.
Once running, all versions converge to the same steady-state: every
replacement is a fresh delivered cylinder (V1 assumption holds permanently
after first install).

| Version | Install condition | How S is known |
|---------|-----------------|----------------|
| V1 | Fresh full cylinder always | g = 14.2 (BIS law) → S = G − 14.2, instant |
| V2 | Partial, brand known by user | S ≈ brand average → approximate % |
| V3 | Partial, brand unknown | S ∈ [14.5, 15.8] → interval estimate |

V2 and V3 handle only the one-time cold-start edge case. V1 is the
normal steady-state for every household after their first delivery.

---

## V1 Core Assumption

Every cylinder placed on the scale is a fresh domestic delivery containing
exactly 14.2 kg of gas, as mandated by BIS standard IS 3196. The system
does not handle partial cylinders, unknown brands, or commercial sizes.
If a cylinder is already on the scale at first boot, the system waits
for the next delivery (Option A — see First Boot section).

---

## State Machine

### States

**UNINSTALLED**
- Condition: `"cylinder"` key absent from `config.json`
- Display: `"Place new cylinder"`
- No gas readings, no percentage, no days estimate

**TRACKING**
- Condition: `"cylinder"` key present in `config.json`
- All outputs live (gas_kg, gas_pct, days, burn_rate)
- burn_rate and days show `"—"` until MIN_HOURS_BURNRATE hours of data exist

**LOW GAS**
- Same tracking logic as TRACKING
- Additionally: BLE alert fired, screen warning shown
- Fires when: `gas_kg < LOW_GAS_KG` OR `days_remaining < LOW_GAS_DAYS`

### Transitions

| From | Event | To |
|------|-------|----|
| UNINSTALLED | G jump > REFILL_THRESHOLD_KG | TRACKING |
| TRACKING | gas < LOW_GAS_KG or days < LOW_GAS_DAYS | LOW GAS |
| TRACKING | G < CYLINDER_REMOVED_KG | UNINSTALLED |
| LOW GAS | G jump > REFILL_THRESHOLD_KG | TRACKING |
| LOW GAS | G < CYLINDER_REMOVED_KG | UNINSTALLED |

---

## V1 Outputs

| Output | Type | Available from |
|--------|------|---------------|
| Gas remaining (kg) | Exact — `G − S` | First install event |
| Gas remaining (%) | Exact — `gas / 14.2 × 100` | First install event |
| Days remaining | `"—"` then self-improving | After MIN_HOURS_BURNRATE |
| Burn rate (g/day) | Real data only, rolling window | After MIN_HOURS_BURNRATE |
| Last updated | Timestamp | Always |
| State | UNINSTALLED / TRACKING / LOW GAS | Always |

No government averages. No assumed burn rate. Burn rate is 100% derived
from this household's actual sensor readings. Any hardcoded consumption
value is a prohibited assumption.

---

## V1 Explicit Exclusions

- Partial cylinder at install — system stays UNINSTALLED until G-jump
- Brand selection or any user input for tare weight
- Commercial cylinder sizes (5 kg, 19 kg)
- Any assumed or population-average burn rate
- V2/V3 logic of any kind
- Multi-cell load cell support (single cell, V1 only)

---

## First Boot Behavior (Option A)

System starts in UNINSTALLED on first power-on regardless of what is on
the scale. If a cylinder is already present, it is ignored. The system
shows "Place new cylinder" and waits for a G-jump event.

Recommended install flow: deploy hardware just before or at the same time
as a new cylinder delivery. The delivery event becomes the first
calibration anchor.

Rationale: V1 assumes fresh full cylinders. Tracking an existing partial
cylinder without knowing S would require V2/V3 logic. Option A keeps V1
scope clean and honest.

---

## Calibration Architecture

### Principle: cal_factor must be fresh before G_new is measured

G_new is measured AFTER tare and cal_factor are both validated. Not
before. The order of events on every cylinder change is fixed:

```
Step 1 — Cylinder removed
  G drops below CYLINDER_REMOVED_KG
  Capture raw_empty_platform from MCU

Step 2 — Auto-tare (immediate, always)
  tare_raw_new = raw_empty_platform
  Written to config.json["calibration"]["tare_raw"]
  Corrects zero-drift of load cell without user action

Step 3 — Cal_factor validation (before new cylinder arrives)
  Uses old cylinder's stored raw_at_install and old tare_raw:

  implied_cal_factor = (raw_at_install_old − tare_raw_old)
                       / ((S_prev + 14.2) × 1000)

  Where S_prev = steel weight of the old cylinder (stored at its install)

  If |implied − stored| / stored > CAL_DRIFT_THRESHOLD:
    → Log drift event
    → Update cal_factor in config.json
    → Flag for operator review

  If no S_prev exists (very first cylinder ever): skip this step.
  Trust initial calibration.

Step 4 — New cylinder placed (G jumps > REFILL_THRESHOLD_KG)
  raw_at_install_new = MCU reading (N-sample average)

  G_new = (raw_at_install_new − tare_raw_new) / cal_factor
          ← uses fresh tare (Step 2) and validated cal_factor (Step 3)

  S_new = G_new − CAPACITY_KG
  delta_S = S_new − S_prev  (logged per refill, brand change visible)

  Store in config.json["cylinder"]:
    tare_kg, install_weight_kg, install_ts, install_raw, capacity_kg

  Store in refill_events table:
    full calibration context (see Schema section)
```

### S tracking across cylinders

Every cylinder has a unique steel weight (S) — varies by brand and batch.
V1 tracks S per cylinder and computes the delta on each replacement.

- `S_new = G_new − CAPACITY_KG` (derived at each install)
- `delta_S = S_new − S_prev` (logged in refill_events)
- If `|delta_S| > DELTA_S_ANOMALY_KG`: flag as anomaly
  (extreme brand change, unexpected cylinder, or measurement error)
- Full S history available in refill_events for future multi-cycle
  cal_factor validation

### Auto-tare rationale

Zero-drift (load cell output drifting over days/weeks with no load change)
is the primary long-term calibration problem. Auto-tare on every cylinder
removal corrects this continuously without user intervention. The dead zone
between platform-empty reading (~0 g) and minimum cylinder weight (~14500 g)
makes removal detection unambiguous.

---

## Burn Rate

**No government averages. No assumed values. Ever.**

Rules:
- Minimum data window before computing: MIN_HOURS_BURNRATE = 24 hours
- Before 24h: show `"—"` for burn_rate and days_remaining
- Computation: `burn_rate = gas_consumed_since_install / hours_since_install × 24`
- Window cap: after BURN_RATE_WINDOW_DAYS, use rolling window (last 7 days only)
- Only reads from current cylinder's install timestamp onward

Self-improving accuracy (no explicit accuracy metric needed — window size
determines accuracy naturally):

| Time since install | Data used | Accuracy |
|-------------------|-----------|----------|
| 0–24 h | — | Not shown |
| 24–48 h | 1 day | Rough (may miss sessions) |
| 3–7 days | 3–7 days | Improving |
| 7+ days | Rolling 7-day | Stable, personalized |

---

## Config Files

### config.py — all thresholds, never hardcoded in logic

```python
# Cylinder detection
REFILL_THRESHOLD_KG    = 6.0   # G jump between readings → new cylinder installed
CAPACITY_KG            = 14.2  # BIS domestic regulation IS 3196, V1 fixed
CYLINDER_REMOVED_KG    = 2.0   # G below this → cylinder absent (dead zone 0.0075–14.5 kg)

# Alert thresholds
LOW_GAS_KG             = 2.0   # alert when gas_remaining drops below this
LOW_GAS_DAYS           = 10    # alert when days_remaining drops below this

# Calibration
CAL_DRIFT_THRESHOLD    = 0.03  # flag cal_factor drift if implied vs stored > 3%
DELTA_S_ANOMALY_KG     = 1.0   # flag if ΔS between cylinders exceeds this

# Burn rate
BURN_RATE_WINDOW_DAYS  = 7     # rolling window for burn_rate computation
MIN_HOURS_BURNRATE     = 24    # minimum hours of data before computing burn_rate

# Heartbeat
HEARTBEAT_MIN          = 15    # record one weight snapshot every N minutes
```

### config.json — runtime state (written by Python, read by Python and UI)

```json
{
  "calibration": {
    "cal_factor": 106.7,
    "tare_raw": -14000,
    "cal_ts": "2026-06-03T08:00:00"
  },
  "cylinder": {
    "tare_kg": 15.5,
    "install_weight_kg": 29.7,
    "install_ts": "2026-06-03T08:15:00",
    "install_raw": -1520000,
    "capacity_kg": 14.2
  }
}
```

- Absence of `"cylinder"` key = UNINSTALLED state
- `install_raw` stored for cal_factor re-validation on next removal
- `calibration.tare_raw` updated on every auto-tare event (Step 2)
- `calibration.cal_factor` updated only when drift detected (Step 3)

---

## SQLite Schema

```sql
-- Append-only weight readings. Never deleted.
CREATE TABLE readings (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    ts        TEXT    NOT NULL,      -- ISO 8601
    gross_kg  REAL    NOT NULL,      -- G from MCU (what scale reads)
    gas_kg    REAL    NOT NULL,      -- G - tare_kg (computed)
    gas_pct   REAL    NOT NULL       -- gas_kg / 14.2 * 100
);

-- One row per cylinder change. Full calibration context preserved.
CREATE TABLE refill_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    ts              TEXT    NOT NULL,
    old_gross_kg    REAL,            -- last G before cylinder removed
    old_tare_kg     REAL,            -- S of the old cylinder
    new_gross_kg    REAL    NOT NULL, -- G at new cylinder install
    new_tare_kg     REAL    NOT NULL, -- S of new cylinder (G_new - 14.2)
    delta_tare_kg   REAL,            -- new_tare - old_tare (brand delta)
    old_tare_raw    INTEGER,         -- raw ADC value of old tare
    new_tare_raw    INTEGER,         -- raw ADC value after auto-tare
    cal_factor_used REAL    NOT NULL, -- cal_factor at time of new install
    cal_drift_pct   REAL             -- detected drift at Step 3 (null if none)
);
```

Two tables. All derived metrics (burn_rate, days_remaining, brand history)
are computed from these tables on demand. No cached derived tables in V1.

---

## Threshold Derivations

### REFILL_THRESHOLD_KG = 6.0 kg

Formula: minimum expected G-jump when user replaces cylinder at LOW_GAS_KG threshold.

```
min_new_full_G  = min_tare + (CAPACITY - fill_tolerance)
                = 14.5 + (14.2 - 0.15) = 28.55 kg

max_old_G at LOW_GAS_KG=2.0:
                = max_tare + LOW_GAS_KG
                = 15.8 + 2.0 = 17.8 kg

min_jump = 28.55 - 17.8 = 10.75 kg
```

6.0 kg threshold gives 4.75 kg safety margin. Even a household replacing
with 8.75 kg remaining (14+ days at any normal burn rate) would still
trigger detection. Was previously 8.0 kg — reduced to accommodate
LOW_GAS_DAYS = 10 (time-based alert fires with more gas remaining).

### CYLINDER_REMOVED_KG = 2.0 kg

Dead zone logic: load cell noise floor = 7.5 g peak-to-peak = 0.0075 kg.
Minimum cylinder weight (empty steel, lightest brand) = 14.5 kg.
Any threshold in [0.1, 10.0] kg correctly detects removal.
2.0 kg is a round number with 267× noise margin and 7.25 kg gap below
minimum cylinder weight.

### LOW_GAS_KG = 2.0 kg

Roughly 2-4 days of gas remaining at typical household consumption.
Combined with LOW_GAS_DAYS = 10, whichever threshold fires first
triggers the alert.

### LOW_GAS_DAYS = 10 days

Indian LPG delivery requires booking in advance and typically arrives
3-5 days later. 10 days gives 5-7 days buffer after alert before expected
delivery, with remaining margin for delays.

### MIN_HOURS_BURNRATE = 24 hours

Minimum window to capture at least one morning and one evening cooking
session. Windows shorter than 12 hours may contain zero cooking events,
producing a spurious 0 g/day estimate. 24 hours is the conservative safe
minimum. No assumed consumption rate is used at any point.

---

## HX711 Hardware Constants (AQ3, locked)

```
DT pin:       D7 (only — STM32U585 timer conflicts on all others)
SCK pin:      D6 (only)
VCC:          5V (not 3.3V — HX711 requirement)
CAL_FACTOR:   106.7 raw/g (verified across 3 runs, 2026-05-04)
Load cell:    YZC-161A 20 kg
Wiring:       Red→E+, Black→E-, Green→A+, White→A-
Noise floor:  std ~1.87g, pp ~7.50g (Phase 1 good run)
Corrupt filters: LONG_MIN, -1, 0x7FFFFF (always applied)
```

---

## Bridge Pattern (MCU → Python)

```cpp
// MCU loop() — fire-and-forget, non-blocking
Bridge.notify("weight_event", payload);
```

```python
# Python — receive and process
Bridge.provide("weight_event", handle_weight)
```

Weight event payload: `{"gross_kg": 29.42, "ts": "2026-06-03T08:16:00"}`

---

## Calibration Sequence Summary (Quick Reference)

```
Cylinder removed
    │
    ▼
Auto-tare                  ← always, immediate
tare_raw_new = raw_empty
    │
    ▼
Cal_factor validation      ← using old cylinder's stored raw_at_install
implied = (raw_old − tare_old) / ((S_prev + 14.2) × 1000)
if drift > 3%: update cal_factor
    │
    ▼
[system ready — fresh tare and cal_factor in place]
    │
    ▼
New cylinder placed (G jump > 6.0 kg)
G_new = (raw_new − tare_new) / cal_factor
S_new = G_new − 14.2
delta_S = S_new − S_prev
    │
    ▼
TRACKING state — gas = G_current − S_new
```

