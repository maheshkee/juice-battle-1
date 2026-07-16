# HANDOFF — 2026-07-08 · Session 63 Close · FINAL_1

> Load HANDOFF_2026_07_01_SESSION60_MASTER_REFERENCE.md for full architectural
> detail, hardware specs, complete fix history, and every design decision's reasoning.

---

## ONE-LINE STATE

3E-008 Trial 1 complete and analysed. Trial 2 launching now.
CYLINDER_ABSENT state live. DHT22 live. tare_raw=None → fresh tare needed before 
Trial 2 stone placement.

---

## FIRST THING TO DO (if Trial 2 not yet started)

```bash
# Platform must be EMPTY. Wait 15-20min after removing stone.
# Restart hub — fresh tare fires automatically (tare_raw=None in config)
cd ~/ArduinoApps/gas-cylinder-monitor/hub
arduino-app-cli app restart .
# Wait for BOOT_COMPLETE + 90s for SPIFFS write
# Verify: cat hub/config.json | grep tare_raw  (should show a value, not null)
# Place stone → sqlite3 ... "SELECT MAX(id) FROM readings;"  → record boundary ID
```

Trial 2 must run for **24h minimum, ideally until next morning**.
Do not restart, do not touch platform.

---

## WHAT CHANGED THIS SESSION (Session 63, 2026-07-07/08)

### 3E-009 Attempt #3 — PASS (closed)
68h 22m, 99.78% coverage, 0 WCN3990 crashes, Fix 2 (WiFi power save) held 72h+.
Inter-day thermal baseline drift: +165g/night — confirms 3E-008 is mandatory.

### DHT22 — live and confirmed
- GPIO5, 10kΩ pull-up, DHTesp library
- BLE seam extended: {grams, quality, sigma, temp_c} — boss-approved, locked
- Hub pipeline complete, temp_c writing to DB, confirmed 28.8°C in readings

### OLS burn rate — implemented, not yet production
- compute_analytics_ols() in domain.py alongside existing compute_analytics()
- R2_MIN_THRESHOLD=0.3 (provisional), SECONDS_PER_DAY=86400, BURN_RATE_WINDOW_DAYS=7.0
- Switch to production: gated on 3E-008 completion + clean 7-day data

### CYLINDER_ABSENT state — implemented and verified (parallel chat work)
Four scenarios all PASS:
  - Power cut, both restart → CYLINDER_ABSENT → TRACKING in 30s automatically
  - Brief removal <120s → grace window, auto-resume TRACKING
  - Extended removal >120s → CYLINDER_ABSENT amber, auto-resume on return
  - Explicit "Remove cylinder" button → UNINSTALLED, steel_g cleared
New "Uninstall/Remove" button in index.html. Install button UNINSTALLED-only.
CYLINDER_ABSENT matcher: grams >= steel_g − 500g → straight back to TRACKING.

### CMD_TARE guard fixed
Old: `if steel_g is not None and tare_raw is not None`
New: `if tare_raw is not None`
steel_g is domain state, not platform calibration — they're independent.

### config.json mystery closed (permanently)
Both domain.py and ble_subscriber.py always resolved to hub/config.json.
hub/data/config.json was a June 23 stale artifact (deleted). Never a real mismatch.

### 3E-008 Trial 1 — complete and analysed
| Parameter | Measured | Notes |
|---|---|---|
| Fast creep τ₁ | 4721s = 1.31h ±0.59h | Single trial, low confidence |
| Fast creep B | −4.15g (downward) | Platform conditioned, tiny magnitude |
| Plateau A | 20210.56g ±0.41g | Reliable |
| Thermal α | 29.19 ±1.36 g/°C | Valid for slow changes only |
| Slow creep | ~3g/h, h=6→15 | Second component, τ₂ >>6h, not yet fitted |
| Ventilation event | h=15.2, 126g spike | Office opened, airflow event — expected |

Key finding: **two-component creep model needed**. Single exponential insufficient.
Trial 2 Phase A fit window must be 12h (not 6h) to capture τ₂.

### Analysis scripts — ready
hub/analysis/3e008/export_trial.py — exports trial CSV from DB by boundary row ID
hub/analysis/3e008/fit_creep_thermal.py — fits creep + thermal models
scipy 1.18.0, numpy 2.5.1 confirmed on AQ3

---

## CURRENT HARDWARE SYSTEM STATE

| Item | Value |
|---|---|
| tare_raw in config | None — fresh tare needed |
| steel_g | None |
| cylinder_state | UNINSTALLED |
| DHT22 | Live, GPIO5, writing temp_c |
| Node boot | 50 (from parallel chat), hub session 79 |
| 3E-008 Trial 1 CSV | hub/data/experiments/3E-008-trial-1-corrected.csv |
| Trial 1 boundary row | 2207296 |

---

## 3E-008 TRIAL 2 — BOUNDARY ROW TO RECORD

**Write the boundary row ID here after stone placement: _____________**

Stone initial reading target: ~20195-20215g (same stone, same platform)
Room condition: office open, ventilated, thermally stable (important — no closed/open event during trial)
Duration target: 24h minimum, ideally until next morning after full night

Export command (tomorrow):
```bash
python3 hub/analysis/3e008/export_trial.py \
  --start-id <BOUNDARY_ROW_ID> \
  --out hub/data/experiments/3E-008-trial-2.csv
```

Analysis command — NOTE: will need 12h fit window, not 6h.
The fit_creep_thermal.py CREEP_FIT_HOURS constant needs changing to 12.0 before
running Trial 2 analysis. Give this to Claude Code CLI when ready.

---

## MULTI-SYSTEM DESIGN (NEXT CHAT — DO NOT START NOW)

Four hardware systems under evaluation — full discussion in next chat:
a. **Current** — ESP32-C3 + HX711 + 3× YZC-161A (parallel wired)
b. **Upgrade** — ADS1230 + Adafruit 4543 (20kg disc, Product #4543) × 3
c. **Characterisation rig** — single YZC-161A + HX711 (baseline/comparison only)
d. **Single-point** — CZL601 single-point load cell + HX711 or ADS1230

Goal: understand, characterise, and select the best system for production.
Datasheets for CZL601 and ADS1230 to be shared in next chat.
No hardware decisions until 3E-008 (all 3 trials) is complete.

---

## PENDING ITEMS — PRIORITY ORDER

| Item | Status | Notes |
|---|---|---|
| 3E-008 Trial 2 | **Launching now** | 24h min, boundary row ID recorded above |
| 3E-008 Trial 3 | After Trial 2 | Different time-of-day launch |
| fit_creep_thermal.py Phase A window | Change 6h→12h | Before Trial 2 analysis |
| OLS production switch | After 3E-008 complete | Needs clean 7-day data + R² calibration |
| WebUI temp_c display | Diff ready, not applied | Apply + hub restart after next trial run |
| Level 3 watchdog status | Suspected still disabled | 1 LEVEL3 logged attempt#3 but no reboot |
| 12 test constants revert | Not started | Only before production unit ships |
| tare_raw null after fresh tare | Known secondary issue | Workaround: power-cycle node after TRACKING confirmed |
| Multi-system hardware design | Next chat | Do not start before full design discussion |

---

## WORKING PRINCIPLES — unchanged

- All design/analysis in chat; code via Claude Code CLI on AQ3 only
- No hardcoded paths, usernames, hostnames
- One verified chunk at a time
- No raw log dumps — aggregates and targeted queries only
- ssh arduino@AQ3 — hostname never IP
- Never compare ts with range operators — id boundary only
- Claude Code CLI pinned v2.1.129, DISABLE_AUTOUPDATER=1
- Temperature travels with sensor node, not hub
- BLE seam: {grams, quality, sigma, temp_c} — locked
- No production decisions until 3E-008 model is finalised

---

*Session 63 · Gratian Technologies · Project 13 · 2026-07-08*
