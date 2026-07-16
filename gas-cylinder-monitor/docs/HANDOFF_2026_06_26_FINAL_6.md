# SESSION HANDOFF — 2026-06-26 FINAL_6
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_25_SESSION1_3E005_complete.md

---

## How to use this document
Read this file fully before responding. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat responses — ever.

---

## Current position (one line)
G5 analytics + G7 WebUI complete and demo-validated. HUB-WATCHDOG fully deployed.
Node running unattended on wall charger (3E-009 long-run stability).
Come back Monday, power on hub, read stability data, then proceed.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A load cells → parallel junction → HX711 → ESP32-C3 SuperMini node
  (BLE GATT notify + cmd char, 30s notify interval)
→ Arduino UNO Q AQ3 hub (Python, BlueZ D-Bus, SQLite, Docker, WebUI port 7000)
```

Architectural seam is strict: node outputs `{grams, quality, sigma}` over BLE only.
Hub stamps timestamp, derives steel from anchor events, computes gas%, stores SQLite,
serves WebUI. Gas% = (gross − steel_g) / NET_GAS_G × 100. Never computed on node.

---

## Hardware — locked

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (never use IP), port 7000 |
| ESP32-C3 SuperMini | BLE sensor node, boot=34 at session end |
| GISLAB HX711 module | Green PCB, AVIAIC chip, 3.3V VCC ONLY — never 5V |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | Fibre plate, rubber mats, drip tray |
| Claude Code CLI | v2.1.129, DISABLE_AUTOUPDATER=1 in ~/.bashrc |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V — hardware damage |
| GND | GND | |
| GPIO4 | SDO (DOUT) | INPUT_PULLUP mandatory |
| GPIO3 | SCK | OUTPUT |

### 3-cell parallel wiring
All 3 red → E+ | All 3 black → E− | All 3 green → A+ | All 3 white → A−

### HX711 corrupt filters (all three required — never remove one)
- LONG_MIN, -1, 0x7FFFFF

---

## Arduino IDE — locked

| Setting | Value |
|---|---|
| Package | esp32 by Espressif v3.0.7 (NOT v3.3.9) |
| Board | ESP32C3 Dev Module |
| Port | COM11 |
| USB CDC On Boot | ENABLED — mandatory |
| Upload speed (normal) | default |
| Upload speed (if failing) | 115200 |
| Libraries | NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon |

Flash recovery: NEVER use "Erase All Flash" — destroys 2nd stage bootloader.
If upload fails: lower baud to 115200 only.

---

## BLE — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Weight char:     b9b25bb1-f2a9-4545-b48f-295ab2789f41  (notify)
Command char:    c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b  (write-without-response)
Log char:        d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c  (notify)
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
BLE notify interval: 30s (decoupled from HX711 read rate — WCN3990 crash prevention)
```

---

## Locked hardware values

| Parameter | Value | Status |
|---|---|---|
| cal_factor | 36.2231 raw/g | VERIFIED boot=13 |
| tare_raw | -88791.0 | VERIFIED boot=32, current platform |
| steel_g | 494.7g | VERIFIED boot=32, bowl anchor |
| sigma (bowl on platform, correct timing) | 3.19g | VERIFIED boot=32 |
| sigma (bowl added after noise phase) | 1817.25g | ARTEFACT — wrong timing |
| NOISE_SIGMA_PASS_G | 8.0g | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0g | LOCKED |
| BLE notify interval | 30s | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| CAL timeout | 120s → 36.0 fallback | LOCKED |
| POST_ACTION_WAIT_S | ≥120s | LOCKED |
| READING_STALE_S | 900s | LOCKED |

---

## ⚠️ CRITICAL — Production revert checklist (ALL 8 — revert together at final stage)

**ALL EIGHT must be reverted together before production test.**
**DO NOT revert any of these until G7 is fully confirmed stable and real cylinder test begins.**

| # | Constant | File | TEST value | PRODUCTION value |
|---|---|---|---|---|
| 1 | NET_GAS_G | domain.py | 4535.0 | 14200.0 |
| 2 | ANCHOR_GROSS_MIN_G | domain.py | 4800.0 | 26000.0 |
| 3 | STEEL_PLAUSIBLE_MIN_G | domain.py | 200.0 | 13000.0 |
| 4 | STEEL_PLAUSIBLE_MAX_G | domain.py | 2000.0 | 18000.0 |
| 5 | REFILL_GROSS_MIN_G | domain.py | 5500.0 | 29000.0 |
| 6 | MIN_DATA_HOURS | domain.py | 0.25 | 24.0 |
| 7 | BURN_RATE_WINDOW_DAYS | domain.py | 0.14583 | 7.0 |
| 8 | MIN_DAYS_FOR_DAY_ALERT | domain.py | 0.04167 | 2.0 |
| 9 | ALERT_AMBER_DAYS | domain.py | 0.10417 | 5.0 |
| 10 | ALERT_RED_DAYS | domain.py | 0.0625 | 3.0 |
| 11 | MAX_BURN_RATE_G_PER_DAY | domain.py | 100000.0 | 2000.0 |
| 12 | HEAVY_LOAD_THRESHOLD_G | gas_monitor_v1.ino | 1000 | 2000 |

Scaling ratio for time constants: 1:48 (30 min real = 1 day simulated)

---

## Hub domain constants — permanent (not in revert list)

| Constant | Value | Note |
|---|---|---|
| ALERT_AMBER_G | 2000.0 | Gram failsafe — always active from Day 0 |
| ALERT_RED_G | 1000.0 | Gram failsafe — always active from Day 0 |
| MIN_BURN_RATE_G_PER_DAY | 10.0 | Sanity floor — below this = sensor noise |
| DAILY_USE_DEFAULT_G | 350.0 | V1 prior — never shown to user |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0 | ±15g platform noise observed |
| ANCHOR_MIN_STABLE_READINGS | 5 | Validated 3E-005 |
| STEEL_UNKNOWN_PRIOR_G | 16500.0 | Conservative prior |
| REMOVAL_GRACE_S | 120.0 | Same for test and production |

---

## Hub module structure — current

```
hub/
├── python/
│   ├── main.py          (~100 lines — orchestrator only, no domain logic)
│   ├── ble_subscriber.py
│   ├── log_transfer.py
│   ├── domain.py        (G4 + G5 logic, all constants, compute_analytics)
│   ├── db.py
│   ├── hub_logger.py
│   └── hub_watchdog.py  (HubWatchdog class — running inside Docker)
├── assets/
│   └── index.html       (G7 WebUI — state pills, banners, analytics display)
├── watchdog_host.sh     (host-side daemon — systemd service installed)
├── gas-cylinder-watchdog.service  (systemd unit file)
├── config.json          (baked at deploy — NOT hub/data/config.json)
├── deploy.sh
├── setup.sh             (idempotent, includes IST timezone step)
└── app.yaml
```

Config path discipline: Docker reads `hub/config.json` baked at deploy time.
`hub/data/config.json` is NEVER mounted.

---

## Hub state machine — 4 states

```
UNINSTALLED
  → (user clicks Install cylinder in WebUI) → BOOTSTRAP_ANCHOR
    → (5 stable readings, spread <30g, all >ANCHOR_GROSS_MIN_G) → TRACKING
      → (gas_g < ALERT_AMBER_G OR days_remaining < ALERT_AMBER_DAYS) → LOW_GAS
        → (gas_g >= ALERT_AMBER_G AND days_remaining >= ALERT_AMBER_DAYS) → TRACKING

From TRACKING or LOW_GAS:
  gross < 500g for < REMOVAL_GRACE_S → stay current state
  gross < 500g for > REMOVAL_GRACE_S → UNINSTALLED (steel_g cleared)
  gross > REFILL_GROSS_MIN_G → BOOTSTRAP_ANCHOR (refill detected)
```

---

## G5 Analytics — compute_analytics() design

Adaptive burn rate strategy:
1. Gate: if elapsed < MIN_DATA_HOURS → return None (show — in WebUI)
2. total_consumed = NET_GAS_G - current_gas_g
3. If elapsed < BURN_RATE_WINDOW_DAYS → cumulative: burn_rate = total_consumed / elapsed_days (source=CUMULATIVE)
4. Else → try rolling window query from SQLite; if rolling fails → fall back to cumulative (source=CUMULATIVE_FALLBACK)
5. Sanity: burn_rate < MIN_BURN_RATE → None. If cylinder_state != LOW_GAS: burn_rate > MAX_BURN_RATE → None
6. LOW_GAS state bypasses MAX ceiling — user always sees analytics in alert state
7. Returns: {burn_rate_g_per_day, days_remaining, predicted_empty, burn_rate_source, elapsed_days}

---

## Dual-condition alert architecture

```
Condition A (gram failsafe — always active):
  gas_g < ALERT_RED_G  → RED
  gas_g < ALERT_AMBER_G → AMBER

Condition B (day-based — active after MIN_DAYS_FOR_DAY_ALERT):
  days_remaining < ALERT_RED_DAYS  → RED
  days_remaining < ALERT_AMBER_DAYS → AMBER

Either condition → alert fires. Condition A always protects even if burn rate fails.
```

---

## WebUI G7 — current state

Live at `192.168.88.20:7000`

| Element | Behaviour |
|---|---|
| Grams (large number) | Always visible when connected. Clamped to 0 minimum. UNINSTALLED shows 0g always. |
| SENSOR OK/DEGRADED/FAILED badge | Always visible — sensor quality only, not gas level |
| State pill | Always visible: PLATFORM EMPTY / CALIBRATING / TRACKING / LOW GAS / CRITICAL |
| Gas% + progress bar | Visible in TRACKING/LOW_GAS. Bar colour: green/amber/red follows alert_level |
| Alert banner | Visible on AMBER/RED: "Gas running low — consider booking a refill" / "Gas critical — cylinder may stop at any moment. Book now." |
| Days remaining | formatDays(): < 0.1 for very small, 1 decimal if < 2, integer if >= 2. Colour follows alert. |
| Daily use / empty by | Shows g/day and predicted date. Holds last known good. |
| Install cylinder button | Visible ONLY when cylinder_state=UNINSTALLED |

Socket.IO event `weight_update` payload:
`{grams, quality, sigma, ts, gas_pct, gas_g, alert_level, cylinder_state, steel_g, steel_source, burn_rate_g_per_day, days_remaining, predicted_empty, burn_rate_source}`

---

## HUB-WATCHDOG — fully operational

```
Python side (hub_watchdog.py inside Docker):
  - HubWatchdog class, daemon thread
  - update_last_reading() called on every weight reading in on_weight()
  - 3-level escalation: Level 1 (BT power cycle) → Level 2 (restart.trigger) → Level 3 (reboot.trigger)
  - Health check: reading_fresh (READING_STALE_S=900s) — hciconfig not available in Docker

Host side (watchdog_host.sh as systemd service):
  - gas-cylinder-watchdog.service: enabled and running
  - Polls every 30s for trigger files in hub/data/
  - Acts on restart.trigger (systemctl restart bluetooth) and reboot.trigger (reboot)
  - Sudoers rules in place for bluetooth restart and reboot
```

---

## Boot sequence — locked

```
SETTLE (2s) → TARE_WAIT (hub sends TARE or SKIP_TARE, 60s timeout)
  Hub: UNINSTALLED → send TARE | TRACKING/BOOTSTRAP_ANCHOR → send SKIP_TARE
→ TARE (N=200 fresh) or load from SPIFFS (SKIP_TARE)
  → N-TARE-CHECK (delta vs saved — if heavy load → use saved tare)
    → NOISE (20s autonomous)
      → CAL (hub sends SET_CAL:36.2231, or 120s timeout → 36.0 fallback)
        → RUNNING
```

N-TARE-CHECK HEAVY_LOAD_THRESHOLD_G is currently 1000g (dev). Restore to 2000g at final stage — requires node reflash.

---

## Current system state (session end 2026-06-26)

```
cylinder_state:   UNINSTALLED (bowl removed after end-to-end demo)
steel_g:          None (cleared after UNINSTALLED)
tare_raw:         -88791.0 (boot=32)
cal_factor:       36.2231
boot:             34
Hub Docker:       running, port 7000
Node:             POWERED ON, running on WALL CHARGER — 3E-009 in progress
Timezone:         IST (Asia/Kolkata) on host — Docker container TZ fix pending
```

---

## What was completed this session (Session 004 — 2026-06-25/26)

1. HUB-WATCHDOG: systemd service installed, verified active (running)
2. G5 analytics: adaptive burn rate (cumulative → rolling), compute_analytics redesigned
3. Dual-condition alert: Condition A gram failsafe + Condition B day-based
4. LOW_GAS ceiling bypass: analytics always shows in alert state
5. One-reading transition fix: TRACKING→LOW_GAS re-calls compute_analytics
6. G7 WebUI: state pills, alert banners, SENSOR OK badge, formatDays < 0.1, 0g UNINSTALLED
7. IST timezone fixed on host (Docker pending)
8. 5 new reference documents created (4 docx + 1 html concept)
9. Cooking intelligence vision documented (G8 session detection, G9 dish tagging, G10 calendar)
10. FUNCTIONAL_ZERO_G design decision documented
11. End-to-end demo validated: all 4 states, both alert conditions, grace window

---

## Pending items (carry forward)

| Item | Priority | Action needed |
|---|---|---|
| Docker TZ fix | HIGH | Add os.environ TZ + time.tzset() to top of main.py, deploy |
| 3E-009 analysis | HIGH | Monday: power on hub, read stability data |
| 3E-008 thermal drift | MEDIUM | After Monday analysis |
| 3E-010 failure injection | MEDIUM | After 3E-008 |
| Production revert (all 12 constants) | FINAL | Only when ready for real cylinder |

---

## What is next — Monday session plan

### Step 1 — Check system health
```bash
last reboot | head -5
docker logs gas-cylinder-monitor-hub-main-1 --tail 10
systemctl status gas-cylinder-watchdog.service
cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json | python3 -m json.tool
```

### Step 2 — Read 3E-009 stability data
```bash
sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
"SELECT COUNT(*), MIN(ts), MAX(ts), MIN(gas_g), MAX(gas_g), AVG(gas_g) FROM readings WHERE cylinder_state='TRACKING';"
```

### Step 3 — Analyse drift
- Total elapsed: ~60+ hours
- gas_g range: MAX - MIN = drift over the run
- If drift < ±50g over 60 hours → 3E-009 PASSED
- If drift > ±50g → investigate (temperature? creep? disturbance?)

### Step 4 — Proceed based on result
- PASSED → design 3E-008 thermal drift characterisation
- FAILED → investigate root cause before proceeding

---

## Key design principles (must always respect)

| Principle | Detail |
|---|---|
| No hardcoding | All paths derived dynamically — SCRIPT_DIR, APP_NAME, APP_DIR |
| Design in chat | Code via Claude Code CLI only — never write implementation code in chat |
| AQ3 hostname | Always arduino@AQ3 — never IP address |
| Seam contract | Node outputs grams only — hub owns all domain logic |
| No population averages | 473g/day or 350g/day never used in burn rate. Only real measured data. |
| tare_raw absorbs platform | Platform fixtures invisible after tare — mathematical cancellation |
| Separate thresholds | ANCHOR_GROSS_MIN_G ≠ REFILL_GROSS_MIN_G — never conflate |
| BLE rate ≠ HX711 rate | 30s BLE notify interval prevents WCN3990 crash |
| Grace window | 120s before UNINSTALLED — do not shorten |
| Alert state contract | In LOW_GAS/ALERT: always show burn_rate and days_remaining. Never show — |
| Config path | hub/config.json only — hub/data/config.json never mounted |
| Dual-condition alerts | Gram failsafe always active. Day-based active after MIN_DAYS_FOR_DAY_ALERT |
| FUNCTIONAL_ZERO_G | Not implemented — needs 3E-ZERO experiment. Never hardcode a value. |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                    ← read first every session
├── hub/
│   ├── python/
│   │   ├── domain.py            ← G4+G5 logic + all constants
│   │   ├── main.py              ← orchestrator
│   │   ├── ble_subscriber.py
│   │   ├── log_transfer.py
│   │   ├── db.py
│   │   ├── hub_logger.py
│   │   └── hub_watchdog.py
│   ├── assets/index.html        ← G7 WebUI
│   ├── watchdog_host.sh         ← host daemon
│   ├── gas-cylinder-watchdog.service
│   ├── config.json              ← runtime state (baked at deploy)
│   ├── deploy.sh
│   └── setup.sh
├── docs/
│   ├── SESSIONS.md
│   ├── LEARNINGS_AND_INSIGHTS.md
│   ├── EXPERIMENT_PROGRAM.md
│   ├── GasMonitor_Complete_Revert_Reference.docx
│   ├── GasMonitor_CookingIntelligence_Vision.docx
│   ├── GasMonitor_Platform_Operations_Reference.docx
│   ├── GasMonitor_FunctionalZero_Design.docx
│   └── HANDOFF_*.md
└── node/                        ← ESP32-C3 firmware (flash via Arduino IDE on Windows)
```

---

## Session start checklist for next chat (Monday)

Before doing anything:
1. `last reboot | head -5` — confirm node ran unattended without reboots
2. `docker logs gas-cylinder-monitor-hub-main-1 --tail 10` — hub alive
3. `systemctl status gas-cylinder-watchdog.service` — watchdog running
4. `cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json | python3 -m json.tool` — check cylinder_state
5. Run the SQLite 3E-009 stability query (see Step 2 above)
6. Confirm 12 constants still at TEST values before any experiment

---

## SCP command — copy this handoff to AQ3

```bash
scp HANDOFF_2026_06_26_FINAL_6.md arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/docs/
```

---

*Session 004 — 2026-06-25/26 — G5+G7+HUB-WATCHDOG complete. End-to-end demo passed.*
*3E-009 running unattended. Next: Monday stability analysis → 3E-008 → 3E-010 → production.*
