# HANDOFF — Gas Cylinder Monitor V1
# Date: 2026-06-24 | File: HANDOFF_2026_06_24_FINAL_1.md
# Status: SKIP_TARE+SET_CAL verified. config.json path fixed. Boot 27.5s. System stable 17h.
# Next: 3E-005 water bowl anchor validation.

---

## Current position (one line)

SKIP_TARE+SET_CAL verified on boot=21. Boot time 27.5s (was 104s, 74% faster).
config.json path bug fixed (hub/config.json is real — hub/data/config.json is never read).
System ran 17h without reboot. Next: 3E-005.

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

## What changed this session (2026-06-24)

| Change | Detail |
|--------|--------|
| config.json path bug fixed | hub/config.json is what Docker reads. hub/data/config.json is never read — Docker does not mount that directory. Silent failure — no error. |
| cal_factor + tare_raw written to hub/config.json | cal_factor=36.2231, tare_raw=-107041.4 now present in the correct file |
| Hub sends SKIP_TARE not TARE | main.py on_node_connected() reads cal_factor from config.json, sends SKIP_TARE+SET_CAL:36.2231 |
| Boot time 103.9s → 27.5s | TARE phase (21s) skipped. TARE_WAIT resolves at t=7.2s with CMD_SKIP_TARE |
| System stable 17h | session=16 ran 11:33 IST Jun23 → 04:19 IST Jun24. No watchdog triggers. |
| BLE reconnect pattern confirmed normal | ~3-4 min disconnects, <30s recovery — not a bug |

---

## Node firmware — gas_monitor_v1

**Current boot count: boot=21**
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
| BLE_NOTIFY_INTERVAL_MS = 30000 | ✅ COMPLETE — WCN3990 limit |
| SKIP_TARE path | ✅ VERIFIED boot=21 — 27.5s total boot |

### Locked hardware values

| Constant | Value | Source |
|---|---|---|
| HX711 DT | GPIO4 | LOCKED hardware |
| HX711 SCK | GPIO3 | LOCKED hardware |
| cal_factor | 36.2231 raw/g | Verified boot=4,6,8,9,11,13,14,15,16,18,21 |
| sigma (boot=21) | ~3.7g | typical range |
| tare_raw (empty platform) | -107041.4 | boot=13 clean empty tare |
| NET_GAS_G | 14200.0g | BIS IS 3196 fixed |
| BLE_NOTIFY_INTERVAL_MS | 30000 | LOCKED 2026-06-23 — WCN3990 limit |

### Boot sequence

```
SETTLE (2s) → TARE_WAIT (hub sends SKIP_TARE+SET_CAL or TARE, 60s timeout)
  → SKIP_TARE path: NOISE (20s) → CAL via SET_CAL (0.1s) → RUNNING  [27.5s total]
  → TARE path:      TARE (21s) → NOISE (20s) → CAL (0.1s) → RUNNING [103.9s total]
  → N-TARE-CHECK: heavy load + SPIFFS valid → use saved tare (HEAVY_LOAD_THRESHOLD_G=2000g)

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
| Orchestrator (main.py) | ✅ COMPLETE — SKIP_TARE+SET_CAL on connect |
| hub_logger.py | ✅ COMPLETE — persistent hub.log |
| hub_watchdog.py | ✅ COMPLETE — READING_STALE_S=900, POST_ACTION_WAIT_S=120 |
| watchdog_host.sh | ✅ COMPLETE — full paths, sudo rules |
| gas-cylinder-watchdog.service | ✅ INSTALLED — systemd, auto-start |
| WebUI (index.html) | ✅ WORKING |
| config.json | ✅ CORRECT PATH — hub/config.json, cal_factor=36.2231 |

### Hub Python module structure (7 files)

```
hub/python/
├── main.py            ← orchestrator only, SKIP_TARE+SET_CAL on connect
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

### config.json — current state

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

**File location: hub/config.json** (NOT hub/data/config.json — Docker does not mount hub/data/).

With cal_factor + tare_raw populated, hub sends SKIP_TARE + SET_CAL on connect.
Boot time 27.5s. Tare corruption on reconnect permanently prevented.

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
- Hub sends SKIP_TARE + SET_CAL on connect (hub/config.json populated) ✅
- Node BLE notify rate 30s (WCN3990 stable) ✅
- Watchdog not triggering on normal BLE dropouts ✅
- System stable 17h without reboot ✅

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

## Hub BLE peripheral — design locked

Decision: BLE-only transport between hub and Flutter mobile app (boss decision).
Hub runs dual role: central (node connection) + peripheral (app connection).
Hardware confirmed: WCN3990 supports `le advertising` (from btmgmt info).
Implementation: raw D-Bus GATT server (same approach as existing central code).

Hub GATT service (GasCylHub):
- STATUS char: notify 30s — {gas_pct, gas_g, days_remaining, alert_level}
- ANALYTICS char: read on demand — paginated daily burn data
- CMD char: write — SET_BRAND, SETUP, REQUEST_HISTORY_PAGE
- RESPONSE char: notify — hub replies to CMD
- VOICE char: write+notify — query text in, answer_te+answer_en out

This is NOT yet built. Design is locked. Build after G5.

---

## UI/UX design — locked

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
- BLE supervision timeout disconnects every ~4min — expected, not a bug

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
| config.json path | hub/config.json only — hub/data/config.json is never mounted by Docker |

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
3. Check stability: `last reboot | head -5` — confirm no reboots since Jun23 16:30 IST
4. Hub running: `bash deploy.sh` if needed, WebUI at 192.168.88.20:7000
5. Node: boot=21 or higher, gas_monitor_v1 with BLE_NOTIFY_INTERVAL_MS=30000
6. **Verify hub sends SKIP_TARE not TARE** — check docker logs for "CMD_SKIP_TARE" on connect
7. config.json: confirm cal_factor=36.2231 and tare_raw=-107041.4 in hub/config.json (not hub/data/)
8. Platform: empty, node showing grams near 0.0
9. First action: 3E-005 water bowl experiment — prepare bowl+water+plate
10. Before 3E-005: change 4 domain.py constants (see 3E-005 section above)

---

## CLI prompt for session close (run this if CLI survived)

```
Read these files before touching anything:
~/ArduinoApps/gas-cylinder-monitor/docs/CLAUDE.md
~/ArduinoApps/gas-cylinder-monitor/docs/SESSIONS.md
~/ArduinoApps/gas-cylinder-monitor/docs/LEARNINGS_AND_INSIGHTS.md

[then issue the session close prompt]
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_24_FINAL_1.md fully before responding.
Context: SKIP_TARE+SET_CAL verified (boot=21, 27.5s boot time).
config.json path fixed — hub reads hub/config.json.
System ran 17h without reboot. BLE supervision-timeout dropouts normal.
Today: run 3E-005 water bowl anchor validation.
Start by confirming system stability (last reboot | head -5),
confirm hub sends SKIP_TARE on connect (check docker logs),
then run the 3E-005 experiment."

---

*End of handoff. Boot 27.5s. System stable. Next: 3E-005.*
