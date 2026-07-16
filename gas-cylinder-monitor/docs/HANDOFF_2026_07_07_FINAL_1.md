# HANDOFF — 2026-07-07 · Session 63 Close · FINAL_1

> Load HANDOFF_2026_07_01_SESSION60_MASTER_REFERENCE.md for full architectural
> detail, hardware specs, complete fix history, and every design decision's reasoning.
> This document is the fast-continuity entry point only.

---

## ONE-LINE STATE

3E-009 stability campaign is **complete** (PASS, 68h 22m, 99.78% coverage).
DHT22 firmware is written and committed. **Hub is ready. Node is NOT yet flashed.**
The single physical gate before 3E-008 Phase A can begin: wire the DHT22 and flash.

---

## FIRST THING TO DO

**Physically wire the DHT22, then say go-ahead to flash.**

Wiring (confirmed safe GPIO, no conflicts):

| DHT22 pin | Connects to |
|---|---|
| Pin 1 — VDD | 3.3V (same rail as HX711) |
| Pin 2 — DATA | GPIO5 on ESP32-C3 **AND** one leg of 10kΩ resistor |
| Pin 3 — NULL | leave unconnected |
| Pin 4 — GND | GND |
| 10kΩ other leg | 3.3V |

The pull-up resistor on DATA is **mandatory**. Without it the single-bus line floats
and reads are all NAN or random. This is not optional.

After wiring:
1. Flash the node firmware (Arduino IDE, COM11, ESP32C3 Dev Module, same settings as always)
2. Restart the hub service: `arduino-app-cli app restart gas-cylinder-monitor`
3. Verify temp_c is reaching the DB:

```bash
sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
  "SELECT id, ts, grams, temp_c FROM readings ORDER BY id DESC LIMIT 5;"
```

If temp_c shows real values (not NULL), the pipeline is confirmed end-to-end.
If temp_c is NULL, the firmware is not sending or the hub is not parsing — diagnose
before launching 3E-008.

---

## WHAT WAS DONE THIS SESSION (Session 63, 2026-07-07)

**3E-009 attempt #3 — declared PASS:**
- 68h 22m continuous TRACKING, 99.78% coverage (8187/8205 readings)
- Zero WCN3990 crashes, zero host reboots, Fix 2 (WiFi power save off) held 72h+
- Thermal findings: 607g intraday swing, +147g/+182g nightly baseline drift
- Weight-vs-time chart built from actual CSV data — chart is in this session's chat

**DHT22 integration — firmware + hub pipeline complete, not yet flashed:**
- dht_sensor.h/cpp: reads DHT22 on GPIO5 via DHTesp library, once per 30s tick
- BLE seam extended: {grams, quality, sigma, temp_c} — boss-approved, locked
- Hub: db.py has temp_c column (idempotent migration), ble_subscriber parses it,
  main.py threads it through

**OLS burn rate — implemented, NOT yet the production path:**
- compute_analytics_ols() in domain.py mirrors compute_analytics() exactly but
  uses linear regression across all window readings instead of first-minus-last
- R2_MIN_THRESHOLD = 0.3 (provisional — calibrate from clean 7-day data)
- ROLLING_LOW_CONFIDENCE source string added
- Switch to production: gated on R² calibration after 3E-008 thermal correction
- BURN_RATE_WINDOW_DAYS = 7.0 (restored to production value from 0.14583 test)
- SECONDS_PER_DAY = 86400 named constant (replaced 5 bare literals)

**3E-008 analysis infrastructure — ready, not yet run:**
- hub/analysis/3e008/export_trial.py — exports trial from DB given boundary row ID
- hub/analysis/3e008/fit_creep_thermal.py — fits creep model + thermal regression
- hub/analysis/3e008/README.md
- scipy 1.18.0 + numpy 2.5.1 confirmed on AQ3 host, added to setup.sh
- EXPERIMENT_PROGRAM.md has the full 3E-008 protocol appended

**Documentation locked this session:**
- INTERFACE_CONTRACTS.md §1.1: seam extension
- ANALYTICS_SPECIFICATION.md §11.1: endpoint-difference limitation documented
- MEASUREMENT_AND_CALIBRATION_SPECIFICATION.md §41: drift correction architecture
- EXPERIMENT_PROGRAM.md: 3E-008 full protocol

---

## OPEN ITEMS — PRIORITY ORDER

| Item | Status | Notes |
|---|---|---|
| Wire DHT22 + flash firmware | **DO THIS FIRST** | See wiring table above |
| Verify temp_c in DB | After flash | 5-row query above |
| 3E-008 Phase A trial 1 | After temp_c verified | Place stone, record boundary row ID, log 24h+ |
| Level 3 watchdog status | Suspected still disabled | 1 LEVEL3_REBOOT_TRIGGERED during attempt #3 but no actual reboot — check watchdog_host.sh |
| OLS production switch | Gated on 3E-008 data | Do not switch until R² threshold calibrated |
| 3E-009 attempt #3 CSV | Exported, in Downloads | 3E-009-attempt3-full.csv — no temp_c column (DHT22 not present during that run) |
| CYLINDER_ABSENT redesign | Designed, unblocked | Ready to implement in domain.py |
| 12 test constants revert | Not started | Only before real production unit ships |
| config.json path mismatch | Known open | `_CONFIG_PATH` grep in source to find real path |
| WebUI stale-on-load bug | Backlogged | Push last-known-state on connect |

---

## 3E-008 PHASE A QUICK REFERENCE

Once DHT22 is confirmed working:

1. Remove stone if present. Wait 15-20 min (creep recovery).
2. Fresh tare with platform empty.
3. Place 20kg stone. **Record the DB row ID immediately** — this is the boundary.
   ```bash
   sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
     "SELECT MAX(id) FROM readings;"
   ```
4. Leave undisturbed for 24h minimum. Both grams and temp_c log automatically.
5. After 24h:
   ```bash
   python3 hub/analysis/3e008/export_trial.py --start-id <BOUNDARY_ID> --out trial_1.csv
   python3 hub/analysis/3e008/fit_creep_thermal.py --csv trial_1.csv
   ```
6. Repeat at two different times of day (trials 2 and 3, at least 6h start offset).

---

## WORKING PRINCIPLES — unchanged, still in force

- All design/analysis in chat; all code via Claude Code CLI on AQ3 only
- No hardcoded paths, usernames, hostnames, interface names
- One verified chunk at a time — base working system before compounding
- No raw log dumps into chat — aggregates and targeted queries only
- `ssh arduino@AQ3` — hostname, never IP
- Never compare `ts` with range operators — use id boundary after LIKE match
- Claude Code CLI pinned at v2.1.129, DISABLE_AUTOUPDATER=1
- BLE notify interval minimum 30s — never change
- Node never auto-tares on boot — only on explicit hub TARE command
- Temperature travels with the sensor node, not the hub

---

*Session 63 · Gratian Technologies · Project 13*
