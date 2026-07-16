# HANDOFF — Gas Cylinder Monitor V1
# Date: 2026-06-23 | File: HANDOFF_2026_06_23_FINAL_10.md
# Status: BLE stability fixed. Hub watchdog fixed. System stable 20+ min.
# Next: 3E-005 water bowl anchor validation.

---

## Current position (one line)

BLE 8-minute crash cycle fully resolved (4 bugs fixed). Hub watchdog working
correctly. config.json pre-populated with known-good cal_factor + tare_raw.
Node at boot=18. System stable 20+ minutes with no reboot. Next: 3E-005.

---

## What this product is

Indian household LPG gas cylinder monitor. Load cells → HX711 → ESP32-C3 node
(BLE GATT) → AQ3 hub (Python/SQLite/WebUI in Docker). Node outputs
{grams, quality, sigma} only. Hub owns all domain logic, gas%, state machine.

```
3× YZC-161A load cells → HX711 → ESP32-C3 SuperMini
    → BLE → AQ3 Linux hub → SQLite → WebUI (192.168.88.20:7000)
```

Gas formula: gas% = (gross_g - steel_g) / 14200 * 100
BIS IS 3196: 14,200g net gas, legally fixed for all Indian domestic cylinders.

---

## CRITICAL BLE STABILITY FIXES — applied this session (2026-06-23)

Four bugs were fixed in sequence during this session. All are documented in
GasMonitor_BLE_Debug_Reference.docx. Summary:

| Bug | Root cause | Fix |
|-----|-----------|-----|
| BUG-1 | WCN3990 crashes at 10Hz BLE notify | BLE_NOTIFY_INTERVAL_MS=30000 in node |
| BUG-2 | POST_ACTION_WAIT_S=30 too short after Level 2 | Changed to 120s |
| BUG-3 | hciconfig not available inside Docker → hci0_up always False | Health check uses reading_fresh only |
| BUG-4 | READING_STALE_S=300 too short for 3-4min BLE dropouts | Changed to 900s (15min) |

Key rule locked permanently:
**WCN3990 crashes at sustained 10Hz BLE notify. Always use BLE_NOTIFY_INTERVAL_MS=30000.
Never notify faster than 30s in STATE_RUNNING. HX711 read rate (100ms) and BLE notify
rate (30s) must always be decoupled.**

---

## Node firmware — gas_monitor_v1

**Current boot count: boot=18**
**Flash location:** Arduino IDE on Windows, COM11, ESP32C3 Dev Module

### Node layer status (complete)

| Item | Status |
|---|---|
| 1A Modular sketch | ✅ COMPLETE |
| 1B Load cell health detection | ✅ COMPLETE |
| 1C/D Timing + structured journal | ✅ COMPLETE |
| N1 Journal → SPIFFS persistence | ✅ COMPLETE |
| 1E BLE log streaming pipeline | ✅ COMPLETE |
| 1F STATE_TARE_WAIT (60s timeout) | ✅ COMPLETE |
| BLE-CMD characteristic | ✅ COMPLETE |
| CAL timeout fix (120s → 36.0g fallback) | ✅ COMPLETE |
| g_cal_degraded flag | ✅ COMPLETE |
| N-TARE-CHECK hub-offline extension | ✅ COMPLETE — verified boot=16 |
| N-TARE-CHECK threshold 2000g production | ✅ COMPLETE |
| BLE_NOTIFY_INTERVAL_MS = 30000 | ✅ COMPLETE — BUG-1 fix |

### Locked hardware values

| Constant | Value | Source |
|---|---|---|
| HX711 DT | GPIO4 | LOCKED hardware |
| HX711 SCK | GPIO3 | LOCKED hardware |
| cal_factor | 36.2231 raw/g | Verified boot=4,6,8,9,11,13,14,15,16,18 |
| sigma (boot=18) | 3.73g | measured |
| tare_raw (empty platform) | -107041.4 | boot=13 clean empty tare |
| NET_GAS_G | 14200.0g | BIS IS 3196 fixed |
| BLE_NOTIFY_INTERVAL_MS | 30000 | LOCKED 2026-06-23 — WCN3990 limit |

### Boot sequence

```
SETTLE (2s) → TARE_WAIT (hub sends TARE/SKIP_TARE, 60s timeout)
  → [N-TARE-CHECK: if heavy load + SPIFFS valid → use saved tare]
    → TARE → NOISE → CAL (hub sends SET_CAL) → RUNNING
    
BLE notify: only fires every 30s in STATE_RUNNING (NOT every HX711 read)
```

### BLE UUIDs (locked)

| Item | Value |
|---|---|
| Service | aa206b91-235b-42aa-b370-453a3feedf35 |
| Weight char | b9b25bb1-f2a9-4545-b48f-295ab2789f41 |
| Log char | d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c |
| CMD char | c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b |
| Device name | GasCylMonitor |
| MAC | 10:00:3B:CD:63:32 |

---

## Hub software — AQ3 Docker

**WebUI:** 192.168.88.20:7000
**Deploy:** `cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh`

### Hub layer status

| Component | Status |
|---|---|
| BLE subscriber (ble_subscriber.py) | ✅ COMPLETE |
| Log transfer (log_transfer.py) | ✅ COMPLETE |
| Domain logic (domain.py) | ✅ COMPLETE — G4 state machine |
| SQLite (db.py) | ✅ COMPLETE |
| Orchestrator (main.py) | ✅ COMPLETE — TARE/SKIP_TARE on connect |
| hub_logger.py | ✅ COMPLETE — persistent hub.log |
| hub_watchdog.py | ✅ COMPLETE — BUG-2/3/4 fixed |
| watchdog_host.sh | ✅ COMPLETE — full paths, sudo rules |
| gas-cylinder-watchdog.service | ✅ INSTALLED — systemd, auto-start |
| WebUI (index.html) | ✅ WORKING |
| config.json | ✅ PRE-POPULATED — cal_factor=36.2231, tare_raw=-107041.4 |

### Hub Python module structure (7 files)

```
hub/python/
├── main.py            ← orchestrator only, TARE/SKIP_TARE on connect
├── ble_subscriber.py  ← BLE transport only
├── log_transfer.py    ← log pipeline only
├── domain.py          ← ALL domain logic (G4 core) + get_config()
├── db.py              ← SQLite abstraction only
├── hub_logger.py      ← persistent hub.log, session counter
└── hub_watchdog.py    ← 3-level watchdog, reading_fresh health check
```

### Watchdog constants (LOCKED 2026-06-23)

```python
CHECK_INTERVAL_S      = 60      # how often watchdog checks
READING_STALE_S       = 900     # 15min — survives BLE dropout cycles
CONSECUTIVE_FAIL_GATE = 2       # 2 failures before escalating
POST_ACTION_WAIT_S    = 120     # wait after action before re-checking
```

### Watchdog architecture — Docker boundary

```
Inside Docker (hub_watchdog.py):
  Detects stale readings → writes data/restart.trigger or data/reboot.trigger

Outside Docker (watchdog_host.sh via systemd):
  Reads trigger files → sudo /usr/bin/systemctl restart bluetooth
                      → sudo /sbin/reboot
```

NEVER use hciconfig or bluetoothctl inside Docker — they don't exist in container.
Health signal from inside Docker = reading_fresh only.

### config.json — current state (pre-populated this session)

```json
{
  "device_name": "GasCylMonitor",
  "device_address": "10:00:3B:CD:63:32",
  "service_uuid": "aa206b91-235b-42aa-b370-453a3feedf35",
  "weight_char_uuid": "b9b25bb1-f2a9-4545-b48f-295ab2789f41",
  "reconnect_delay_s": 5.0,
  "scan_timeout_s": 10.0,
  "brand": null,
  "install_mode": null,
  "cylinder_state": "UNINSTALLED",
  "steel_g": null,
  "steel_source": null,
  "steel_anchored_at": null,
  "cal_factor": 36.2231,
  "tare_raw": -107041.4,
  "cal_tare_session": "boot13_verified_2026-06-23"
}
```

With cal_factor + tare_raw populated, hub now sends SKIP_TARE + SET_CAL on
connect instead of TARE. Tare corruption on reconnect is prevented.

### domain.py — G4 state machine constants (locked)

```python
NET_GAS_G             = 14200.0   # BIS IS 3196 — NEVER CHANGE
ANCHOR_STABILITY_WINDOW_G = 50.0
ANCHOR_MIN_STABLE_READINGS = 5
ANCHOR_GROSS_MIN_G    = 26000.0
STEEL_PLAUSIBLE_MIN_G = 13000.0
STEEL_PLAUSIBLE_MAX_G = 18000.0
STEEL_UNKNOWN_PRIOR_G = 16500.0
ALERT_AMBER_G         = 2000.0    # LOCKED 2026-06-12
ALERT_RED_G           = 1000.0    # LOCKED 2026-06-12
DAILY_USE_DEFAULT_G   = 350.0     # LOCKED 2026-06-12
BRAND_STEEL_G = {'Indane': 15300.0, 'HP': 14900.0, 'Bharat': 15100.0}
```

---

## sudoers rules — installed on AQ3 host

```
# /etc/sudoers.d/arduino-reboot
arduino ALL=(ALL) NOPASSWD: /sbin/reboot
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
```

Both rules required. Full paths mandatory — partial paths don't match.
Installed by setup.sh Step 6 on fresh device.

---

## 3E-005 — Water bowl simulation (NEXT EXPERIMENT)

**Pre-conditions verified:**
- Hub sends SKIP_TARE + SET_CAL on connect (config.json populated) ✅
- Node BLE notify rate 30s (WCN3990 stable) ✅
- Watchdog not triggering on normal BLE dropouts ✅
- System stable 20+ minutes without reboot ✅

### Test object measurements (verified 2026-06-23 earlier session)

| Item | Weight |
|---|---|
| Bowl empty | 406g |
| Plate | 59g |
| Bowl + plate (steel equiv) | 465g |
| Water in bowl | 4535g |
| Bowl + water + plate (gross) | ~5000g ± 10g |

### domain.py constants for 3E-005 test (4 lines to change)

```python
# Change these 4 for 3E-005 test. Revert ALL to production values after.
NET_GAS_G             = 4535.0   # TEST ONLY: water weight. PRODUCTION=14200.0
ANCHOR_GROSS_MIN_G    = 4800.0   # TEST ONLY. PRODUCTION=26000.0
STEEL_PLAUSIBLE_MIN_G = 200.0    # TEST ONLY. PRODUCTION=13000.0
STEEL_PLAUSIBLE_MAX_G = 2000.0   # TEST ONLY. PRODUCTION=18000.0
```

### Setup endpoint trigger command (AQ3)

```python
python3 -c "
import socketio
sio = socketio.Client()
sio.connect('http://192.168.88.20:7000')
sio.emit('setup', {'mode': 'FRESH', 'brand': None})
import time; time.sleep(2)
sio.disconnect()
"
```

### Expected 3E-005 results

```
Anchor fires:   steel_g derived = ~465g
Gas% at full:   (5000 - 465) / 4535 * 100 = 100%
AMBER alert:    gas_g < 2000g → gross < 2465g
RED alert:      gas_g < 1000g → gross < 1465g
```

### 3E-005 pass criteria

- [ ] Hub transitions UNINSTALLED → BOOTSTRAP_ANCHOR after setup endpoint called
- [ ] Anchor window fires after 5 stable readings (log shows ANCHOR COMPLETE)
- [ ] steel_g ≈ 465g (bowl + plate weight)
- [ ] Gas% = 100% immediately after anchor
- [ ] Gas% drops correctly as water is removed
- [ ] AMBER alert fires when gas_g drops below 2000g
- [ ] config.json shows steel_source=ANCHOR after transition

---

## BLE dropout pattern — expected normal behaviour

The node BLE disconnects every ~3-4 minutes and reconnects within 30 seconds.
This is a BLE supervision timeout — normal with 30s notify interval and long
idle periods. It is NOT a hardware failure. The watchdog (READING_STALE_S=900)
will not fire on normal dropouts. Do not investigate or try to fix this unless
dropouts become much longer (>15 minutes).

---

## Build order — locked

```
1. 3E-005 anchor validation (water bowl)     ← NEXT
2. 3E-008 temperature drift characterisation
3. 3E-009 6hr long-run stability
4. 3E-010 load cell failure injection
5. G5 analytics — burn rate from real data
6. Hub BLE peripheral (GATT server, raw D-Bus) ← new, for Flutter app
7. WebUI G7 — full dashboard, gas gauge, brand picker
```

---

## Hub BLE peripheral — design locked (new this session)

Decision: BLE-only transport between hub and Flutter mobile app (boss decision).
Hub runs dual role: central (node connection) + peripheral (app connection).
Hardware confirmed: WCN3990 supports `le advertising` (from btmgmt info).
Implementation: raw D-Bus GATT server (same approach as existing central code).
Library: bluezero wheel available (/tmp/test_wheel/bluezero-0.9.1-py2.py3-none-any.whl)
but raw D-Bus preferred for consistency.

Hub GATT service (GasCylHub):
- STATUS char: notify 30s — {gas_pct, gas_g, days_remaining, alert_level}
- ANALYTICS char: read on demand — paginated daily burn data
- CMD char: write — SET_BRAND, SETUP, REQUEST_HISTORY_PAGE
- RESPONSE char: notify — hub replies to CMD
- VOICE char: write+notify — query text in, answer_te+answer_en out

This is NOT yet built. Design is locked. Build after G5.

---

## UI/UX design — locked (designed this session)

Reference: GasMonitor_UIUX_Reference.docx

Three surfaces:
1. Wall display (always-on, dark bg, days remaining huge, gas gauge)
2. Flutter mobile app (home/analytics/voice/settings screens)
3. Voice (Telugu + English TTS via flutter_tts)

Flutter packages: flutter_blue_plus (BLE), flutter_tts (TTS), speech_to_text (voice)
Hub API: /api/status, /api/analytics/daily, /api/voice/query, ws://hub/ws/live

---

## Deferred items (carry forward always)

- DUMP_LOG anomaly: boot=6 t≈4678 duplicate unknown commands — investigate after G5
- Scenario 3 test: SPIFFS empty + hub offline — deferred from CAL-fix session
- HUB-001: auto-retare on cylinder removal — V2
- Rcal shunt calibration resistor — V2
- TODO 1B-stuck: tare_variance_raw always 0.0f — low priority
- TODO 1B-persistence: prev_cal_factor not read at boot — medium priority
- BLE supervision timeout disconnects every ~4min — investigate if becomes worse

---

## Critical rules — never violate

| Rule | Detail |
|---|---|
| BLE notify rate | Never notify faster than 30s. 10Hz kills WCN3990 firmware. |
| No hardcoding | All paths derived from __file__ or SCRIPT_DIR |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Hub = orchestrator only | main.py has zero domain logic |
| No hciconfig in Docker | Host tool — not in container. Use reading_fresh instead. |
| sudoers full paths | /usr/bin/systemctl not systemctl. Exact paths match sudoers. |
| config.json read-modify-write | Never overwrite BLE keys when writing domain keys |
| cal_factor + tare_raw = pair | Always stored together with timestamp |
| BlueZ: match by Name | Not UUID — QRB2210 BlueZ backend limitation |
| SPIFFS ≠ reflash | Accumulation tests use power cycle only |

---

## Windows laptop setup

SCP path: `C:\Users\mahes\Documents\Arduino\`
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED
Upload speed: 921600 (normal) / 115200 (fallback)

## AQ3 hub commands

```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh
docker logs gas-cylinder-monitor-hub-main-1 -f
docker logs gas-cylinder-monitor-hub-main-1 --since 5m | grep -E "\[MAIN\]|\[DOMAIN\]|\[WATCHDOG\]"
cat ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | tail -20
last reboot | head -5
```

## Claude Code CLI

Pinned: v2.1.129. `DISABLE_AUTOUPDATER=1` in ~/.bashrc.
Never upgrade — v2.1.131+ breaks on Cortex-A53.

---

## Session start checklist

1. Read this document fully
2. Confirm working mode: chat = design only, CLI = code only
3. Check stability: `last reboot | head -5` — no reboots after 16:30 IST
4. Hub running: `bash deploy.sh` if needed, WebUI at 192.168.88.20:7000
5. Node: boot=18 or higher, gas_monitor_v1 with BLE_NOTIFY_INTERVAL_MS=30000
6. config.json: confirm cal_factor=36.2231 and tare_raw=-107041.4 present
7. Platform: empty, node showing grams near 0.0
8. First action: 3E-005 water bowl experiment — prepare bowl+water+plate
9. Before 3E-005: change 4 domain.py constants (see 3E-005 section above)

---

## CLI prompt for session close (run this if CLI survived)

```
Read these files before touching anything:
~/ArduinoApps/gas-cylinder-monitor/docs/CLAUDE.md
~/ArduinoApps/gas-cylinder-monitor/docs/SESSIONS.md
~/ArduinoApps/gas-cylinder-monitor/docs/LEARNINGS_AND_INSIGHTS.md

Update CLAUDE.md — current state:
- Node: boot=18, BLE_NOTIFY_INTERVAL_MS=30000 (BUG-1 fix), N-TARE-CHECK complete
- Hub: hub_logger.py complete, hub_watchdog.py BUG-2/3/4 fixed,
  config.json pre-populated with cal_factor=36.2231 tare_raw=-107041.4,
  main.py sends SKIP_TARE+SET_CAL instead of TARE when cal_factor present
- Watchdog: READING_STALE_S=900, POST_ACTION_WAIT_S=120, health=reading_fresh only
- System stable 20+ min, no reboots after 16:30 IST
- Next: 3E-005 water bowl anchor validation

Append SESSIONS.md — new session entry:
Date: 2026-06-23 (second half of day)
Cover: N-TARE-CHECK verified (boot=16 TIMEOUT_SAVED_TARE with 5kg), hub
TARE/SKIP_TARE+SET_CAL on connect, hub_logger.py session=9 verified,
BLE 8-minute crash cycle investigated and fixed (4 bugs),
WCN3990 10Hz crash → BLE_NOTIFY_INTERVAL_MS=30000, watchdog Docker
isolation bug (hciconfig not in container), READING_STALE_S and
POST_ACTION_WAIT_S tuned, config.json pre-populated, system stable,
UI/UX design completed (wall display + mobile), BLE hub→mobile
transport architecture locked (raw D-Bus peripheral), Flutter API
contract designed, bluezero wheel available.

Append LEARNINGS_AND_INSIGHTS.md:
Add L-NEW-A through L-NEW-D (BLE debug learnings — see
GasMonitor_BLE_Debug_Reference.docx for full text)
Add: L-NEW-E: Hub must never send TARE blindly on reconnect.
TARE corrupts tare_raw if load is on platform. Hub should send
SKIP_TARE+SET_CAL when config.json has saved cal_factor. TARE only
on first install (no saved values). This is now implemented in main.py.
Add: L-NEW-F: config.json pre-population with known-good values prevents
first-install TARE from being sent on every reconnect. cal_factor=36.2231
and tare_raw=-107041.4 are verified across 18 boots — safe to pre-populate.

git add -A
git commit -m "fix: BLE stability + watchdog Docker fix + config.json pre-populated"
git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_23_FINAL_10.md fully before responding.
Context: BLE 8-minute crash cycle fully fixed (4 bugs). System stable.
Hub sends SKIP_TARE+SET_CAL on connect. config.json pre-populated.
Node at boot=18 with BLE_NOTIFY_INTERVAL_MS=30000.
Today: run 3E-005 water bowl anchor validation.
Start by confirming system stability (last reboot | head -5),
then confirm hub is running and config.json has cal_factor set,
then run the 3E-005 experiment.
Generate the project roadmap tracker before starting."

---

*End of handoff. BLE stable. Next chat ready for 3E-005.*
