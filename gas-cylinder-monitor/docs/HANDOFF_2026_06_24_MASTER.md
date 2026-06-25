# MASTER HANDOFF — Gas Cylinder Monitor V1
# Gratian Technologies | gratiantechnologies/project13
# Date: 2026-06-24 | Version: MASTER (read this before anything else)

---

## READ THIS FIRST

This document is the complete entry point for any new chat session.
It contains everything needed to continue work without re-explaining context.
Read it fully before touching any file, running any command, or asking any question.

Working mode — non-negotiable:
- Chat = design, architecture, planning, CLI prompts only
- Claude Code CLI = all code, all file writes, on AQ3 only
- Never write code in chat. Never skip design in chat.

---

## What this product is

Indian household LPG gas cylinder weight monitor. Sits under the gas cylinder in
the kitchen. Measures weight continuously to track how much gas remains, predict
when it will run out, and alert the household before they run out mid-cooking.

**Why weight?** LPG cylinders are opaque. Weight is the only reliable proxy for
gas remaining. BIS IS 3196 mandates exactly 14,200g net gas in all Indian domestic
LPG cylinders — this is a fixed legal constant used in all gas% calculations.

**System pipeline:**
```
3× YZC-161A 20kg load cells (parallel wired)
    → GISLAB HX711 ADC (raw bit-bang, no library)
        → ESP32-C3 SuperMini (BLE GATT node)
            → BLE (transport, 30s notify interval)
                → AQ3 hub (QRB2210/WCN3990, Python/Docker)
                    → SQLite database
                        → WebUI (192.168.88.20:7000)
                            → Flutter mobile app (BLE from hub, future)
```

Node outputs ONLY: `{grams, quality, sigma}` — nothing else.
Hub owns ALL domain logic: gas%, steel derivation, alerts, state machine.

---

## Hardware

### Node
| Component | Detail |
|---|---|
| MCU | ESP32-C3 SuperMini |
| ADC | GISLAB HX711 (green PCB) |
| Load cells | 3× YZC-161A 20kg (parallel wired, same colour twisted together) |
| HX711 DT | GPIO4 (LOCKED — never change) |
| HX711 SCK | GPIO3 (LOCKED — never change) |
| HX711 VCC | 3.3V only (green PCB clone) |
| Flash tool | Arduino IDE on Windows, COM11 |
| Board setting | ESP32C3 Dev Module, USB CDC On Boot ENABLED |
| Upload speed | 921600 normal / 115200 fallback |
| Library | NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon |
| BLE device name | GasCylMonitor |
| BLE MAC | 10:00:3B:CD:63:32 |

### Hub
| Component | Detail |
|---|---|
| Board | Arduino UNO Q AQ3 (QRB2210/WCN3990) |
| OS | Debian Linux (aarch64, Cortex-A53) |
| SSH | arduino@AQ3 (hostname) or 192.168.88.20 |
| Hub stack | Python 3 / SQLite / Docker (Arduino App Lab) |
| BLE chip | WCN3990 (Qualcomm — has known firmware bugs) |
| WebUI | 192.168.88.20:7000 |
| Deploy | `cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh` |

### Claude Code CLI
Pinned to v2.1.129. `DISABLE_AUTOUPDATER=1` in `~/.bashrc`.
NEVER upgrade — v2.1.131+ breaks on Cortex-A53 (missing atomics instruction).

---

## Current state — as of 2026-06-24

### Node
- Boot count: **boot=21**
- Firmware: `gas_monitor_v1` — all node layers complete
- Boot time: **27.5 seconds** (was 104s — SKIP_TARE path working)
- Sigma: 4.14g
- SPIFFS: `cal_factor=36.2231`, `tare_raw=-106955.5`

### Hub
- System stable: **17+ hours** without reboot (session=16 ran Jun23 11:33 → Jun24 04:19 IST)
- Hub sends: **SKIP_TARE + SET_CAL:36.2231** on connect (not TARE)
- config.json: `cal_factor=36.2231`, `tare_raw=-107041.4` populated
- Watchdog: running, no false fires since BUG-3/4 fixes

### Immediate next step
**3E-005 — water bowl anchor validation.** Everything is ready.

---

## Locked constants — never change without re-derivation

| Constant | Value | Source | File |
|---|---|---|---|
| NET_GAS_G | 14200.0g | BIS IS 3196 — legally fixed | domain.py |
| cal_factor | 36.2231 raw/g | Verified 18 boots | SPIFFS + config.json |
| tare_raw (empty) | ~-107000 raw | Varies ±200 per boot (thermal drift — normal) | SPIFFS |
| BLE_NOTIFY_INTERVAL_MS | 30000 (30s) | WCN3990 hardware limit | gas_monitor_v1.ino |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0g | Fixed constant | domain.py |
| ALERT_AMBER_G | 2000.0g | Locked 2026-06-12 | domain.py |
| ALERT_RED_G | 1000.0g | Locked 2026-06-12 | domain.py |
| DAILY_USE_DEFAULT_G | 350.0g | Locked 2026-06-12 | domain.py |
| STEEL_UNKNOWN_PRIOR_G | 16500.0g | Conservative — underestimate safer | domain.py |
| HEAVY_LOAD_THRESHOLD_G | 2000.0g | Production. Was 1000g DEV (restored) | node |

---

## BLE UUIDs — locked

| Item | Value |
|---|---|
| Service | aa206b91-235b-42aa-b370-453a3feedf35 |
| Weight char | b9b25bb1-f2a9-4545-b48f-295ab2789f41 |
| Log char | d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c |
| CMD char | c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                        ← read every session start
├── hub/
│   ├── app.yaml
│   ├── deploy.sh
│   ├── config.json                  ← THE real config (NOT hub/data/config.json)
│   ├── assets/index.html            ← WebUI
│   ├── data/
│   │   └── monitor.db               ← SQLite
│   ├── logs/
│   │   ├── hub/hub.log              ← persistent hub log
│   │   └── node/                    ← downloaded node journals
│   └── python/
│       ├── main.py                  ← orchestrator only, zero domain logic
│       ├── ble_subscriber.py        ← BLE transport only
│       ├── log_transfer.py          ← log pipeline only
│       ├── domain.py                ← ALL domain logic (G4 core)
│       ├── db.py                    ← SQLite abstraction only
│       ├── hub_logger.py            ← persistent hub.log, session counter
│       └── hub_watchdog.py          ← 3-level watchdog
├── node/
│   └── gas_monitor_v1/              ← production node firmware
│       ├── gas_monitor_v1.ino       ← orchestrator + state machine
│       ├── hx711.h / hx711.cpp
│       ├── tare.h / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h / cal.cpp
│       ├── weight.h / weight.cpp
│       ├── ble.h / ble.cpp
│       ├── health.h / health.cpp
│       ├── journal.h / journal.cpp
│       └── log_transfer.h / log_transfer.cpp
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    └── HANDOFF_*.md
```

**CRITICAL:** `hub/config.json` is the real config file — baked into Docker at deploy.
`hub/data/config.json` is NOT mounted into the container. Writing there has zero effect.

---

## Node boot sequence

```
SETTLE (2s)
    ↓
TARE_WAIT (0–60s) — waits for hub command
    ├── Hub sends SKIP_TARE → loads SPIFFS tare (production path, boot=21, 7.2s)
    ├── Hub sends TARE → fresh 21s tare (first install only)
    └── 60s timeout fires → N-TARE-CHECK:
            gross > 2000g? → use saved SPIFFS tare (hub offline + cylinder on)
            gross < 2000g? → fresh tare (hub offline + platform empty)
    ↓
NOISE (20s) — sigma characterisation, every boot
    ↓
CAL (0.1s) — receives SET_CAL from hub, or loads SPIFFS, or 120s fallback
    ↓
RUNNING
    - HX711 read every 100ms
    - BLE notify every 30s ONLY (WCN3990 crash if faster)
    - All events journaled to SPIFFS continuously
    - Journal transferred to hub on every BLE connect
```

---

## Hub state machine (domain.py)

```
UNINSTALLED
    ↓ (setup endpoint called with mode=FRESH)
BOOTSTRAP_ANCHOR
    - Hub waits for 5 stable readings within ANCHOR_SPREAD_THRESHOLD_G=30g
    - Derives: steel_g = gross_g - 14200
    - Saves: steel_g, steel_source=ANCHOR to config.json
    ↓ (anchor complete)
TRACKING
    - gas_g = gross_g - steel_g
    - gas_pct = gas_g / 14200 * 100
    - Fires AMBER alert when gas_g < 2000g
    - Fires RED alert when gas_g < 1000g
    ↓ (gross drops near 0 — cylinder removed)
UNINSTALLED (cycle repeats)
```

### Brand steel lookup (bootstrap prior, replaced by anchor)
```python
BRAND_STEEL_G = {
    'Indane': 15300.0,
    'HP':     14900.0,
    'Bharat': 15100.0,
}
STEEL_UNKNOWN_PRIOR_G = 16500.0  # conservative — underestimate gas = safer
```

---

## Hub command sequence on node connect

```
1. Hub connects to GasCylMonitor (by name — not UUID, QRB2210 BlueZ limitation)
2. If config.json has cal_factor:
       → send SKIP_TARE (t+1.0s)
       → send SET_CAL:36.2231 (t+2.0s)
   Else (first install, no saved cal):
       → send TARE
3. send DUMP_LOG (node transfers SPIFFS journal)
4. send CLEAR_LOG (wipe SPIFFS after transfer)
```

---

## Tare and cal_factor — the complete logic

### The pair rule
tare_raw and cal_factor are ALWAYS a pair from the same physical session.
Hub stores them together in config.json with session timestamp.
Never use tare from session N with cal_factor from session M.

### Cal_factor source hierarchy (priority order)
```
Priority 1 (best):   Hub sends SET_CAL → g_cal_degraded=false
Priority 2 (degraded): Hub offline → SPIFFS loaded → g_cal_degraded=true
Priority 3 (last resort): 120s timeout → 36.0g fallback → g_cal_degraded=true
```

### What produces a bad tare
- Hub sends TARE while weight is on platform → tare zeroes out cylinder → all readings wrong
- FIX: Hub sends SKIP_TARE when cal_factor in config.json (implemented, verified boot=21)
- Tare_raw should always be ~-107000. Positive value = corruption.

### What produces a bad cal_factor
- Hardware change (cells replaced/rewired) → requires re-derivation
- SPIFFS corrupt → falls to 120s fallback (36.0g, ±3%)
- First boot, hub offline → fallback (hub corrects on connect)
- Temperature drift → ±5% across sessions (acceptable V1, V2 re-derives via anchor)

### Cal_factor re-derivation (not yet built — needs 3E-005 first)
At every fresh cylinder anchor event, hub re-derives automatically:
```
cal_factor = (gross_raw - tare_raw) / (steel_g + 14200)
```
A 29.5kg reference — 130x better accuracy than 227g development weight.

---

## BLE stability — everything that was fixed

### BUG-1: WCN3990 crashes at 10Hz BLE notify
- Symptom: SSH drops every 8 minutes, board reboots
- Kernel log: `Bluetooth: hci0: Frame reassembly failed (-84)`
- Root cause: BLE notify every 100ms (every HX711 read) = 10Hz sustained
- Fix: `BLE_NOTIFY_INTERVAL_MS = 30000` — decouple notify from read rate
- Verified: boot=16 ran 99 minutes. Previously crashed every 8 minutes.

### BUG-2: POST_ACTION_WAIT_S=30 too short
- Symptom: Level 3 reboot fires 161s after Level 2 bluetooth restart
- Root cause: 30s not enough for BT restart + hub reconnect + first reading
- Fix: `POST_ACTION_WAIT_S = 120`

### BUG-3: hciconfig not available inside Docker
- Symptom: `hci0_up=False` on every health check — watchdog fires constantly
- Root cause: `hciconfig` and `bluetoothctl` are host tools — not in Docker container
- Fix: health check uses `reading_fresh` only. Never use host tools from Docker.
- Rule: from inside Docker, the ONLY observable signal is application-level (readings)

### BUG-4: READING_STALE_S=300 too short for BLE dropout cycle
- Symptom: Watchdog fires during normal 3-4 minute BLE dropouts
- Root cause: BLE disconnects every ~4min (supervision timeout), reconnects in ~30s
- Fix: `READING_STALE_S = 900` (15 minutes)

### Watchdog architecture (Docker boundary pattern)
```
Inside Docker (hub_watchdog.py):
    Detects stale readings → writes trigger file to data/ (shared volume)

Outside Docker (watchdog_host.sh via systemd service):
    Polls data/ → reads trigger → runs host commands
    Level 2: sudo /usr/bin/systemctl restart bluetooth
    Level 3: sudo /sbin/reboot
```

### Watchdog constants (locked)
```python
CHECK_INTERVAL_S      = 60
READING_STALE_S       = 900
CONSECUTIVE_FAIL_GATE = 2
POST_ACTION_WAIT_S    = 120
```

### Sudoers on AQ3 host (installed by setup.sh)
```
arduino ALL=(ALL) NOPASSWD: /sbin/reboot
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
```
Full paths mandatory. `systemctl` ≠ `/usr/bin/systemctl` — sudoers matches exact path.

---

## Normal BLE dropout — not a failure

BLE disconnects every ~3-4 minutes during normal operation. Node reconnects in ~30s.
This is supervision timeout behaviour — expected with 30s notify interval.
The watchdog (READING_STALE_S=900) will NOT fire on normal dropouts.
SPIFFS journal preserved during dropout — no events lost.
Do NOT investigate unless dropouts exceed 15 minutes.

---

## BlueZ quirks on QRB2210 — permanent rules

| Rule | Detail |
|---|---|
| Match by Name, not UUID | SetDiscoveryFilter with UUIDs array silently ignored on QRB2210 |
| GetManagedObjects on StartDiscovery | InterfacesAdded only fires for new devices. Cached devices need explicit poll. |
| No hcitool lescan | Always fails on QRB2210 — use bluetoothctl for diagnostics |
| BLE scan transport=le only | auto transport kills BT adapter (hardware bug) |
| D-Bus not in Docker | Use socat bridge service (dbus-bridge-gas-cylinder-monitor.service) |
| hciconfig not in Docker | Use reading_fresh as health signal instead |

---

## HX711 hardware rules — permanent

| Rule | Detail |
|---|---|
| DT = GPIO4 | LOCKED. Never change. |
| SCK = GPIO3 | LOCKED. Never change. |
| VCC = 3.3V | Green PCB clone. 5V will damage. |
| Raw bit-bang only | No library. Port from stm32-hx711-modular. |
| noInterrupts() during read | Mandatory during 25-pulse read sequence |
| Corrupt filters | LONG_MIN, -1, 0x7FFFFF — all three always |
| Never Erase All Flash | Wipes SPIFFS. Lower baud to 115200 instead. |

---

## Load cell wiring (3-cell parallel)

Same-colour wires twisted together → directly to HX711. No junction box needed.
Unequal load distribution gives correct total — proven via Wheatstone bridge + KCL.
CAL_FACTOR unchanged by parallel wiring.

```
Cell 1 Red  ─┐
Cell 2 Red  ─┼─ HX711 E+
Cell 3 Red  ─┘

Cell 1 Black ─┐
Cell 2 Black ─┼─ HX711 E-
Cell 3 Black ─┘

Cell 1 White ─┐
Cell 2 White ─┼─ HX711 A+
Cell 3 White ─┘

Cell 1 Green ─┐
Cell 2 Green ─┼─ HX711 A-
Cell 3 Green ─┘
```

---

## config.json — current state

File location: `~/ArduinoApps/gas-cylinder-monitor/hub/config.json`
(NOT hub/data/config.json — that file is never read by the container)

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

---

## Node layer status — all complete

| Layer | Status | Detail |
|---|---|---|
| 1A Modular sketch | ✅ COMPLETE | Orchestrator + 9 modules |
| 1B Load cell health | ✅ COMPLETE | g_health, DEGRADED on sigma>12g |
| 1C/D Timing + journal | ✅ COMPLETE | SPIFFS journal, boot counter |
| N1 Journal→SPIFFS | ✅ COMPLETE | Persists across power cycles |
| 1E BLE log streaming | ✅ COMPLETE | DUMP_LOG, transfer, CLEAR_LOG |
| 1F STATE_TARE_WAIT | ✅ COMPLETE | 60s timeout, TARE/SKIP_TARE |
| BLE-CMD char | ✅ COMPLETE | TARE/SET_CAL/DUMP_LOG/CLEAR_LOG/SKIP_TARE |
| CAL timeout | ✅ COMPLETE | 120s → 36.0g fallback → g_cal_degraded |
| g_cal_degraded flag | ✅ COMPLETE | BLE payload DEGRADED, journal unaffected |
| N-TARE-CHECK | ✅ COMPLETE | Hub-offline self-protect. Verified boot=16. |
| BLE_NOTIFY_INTERVAL | ✅ COMPLETE | 30000ms — WCN3990 crash fix |
| SKIP_TARE path | ✅ COMPLETE | Verified boot=21. Boot time 27.5s. |

---

## Hub layer status — all complete

| Component | Status | Detail |
|---|---|---|
| ble_subscriber.py | ✅ COMPLETE | Auto-reconnect, _connecting guard |
| log_transfer.py | ✅ COMPLETE | Full pipeline, abort-safe |
| domain.py | ✅ COMPLETE | G4 state machine, gas%, anchors |
| db.py | ✅ COMPLETE | SQLite abstraction |
| main.py | ✅ COMPLETE | 92 lines, orchestrator only |
| hub_logger.py | ✅ COMPLETE | Persistent hub.log, session counter |
| hub_watchdog.py | ✅ COMPLETE | 4 bugs fixed, reading_fresh health |
| watchdog_host.sh | ✅ COMPLETE | Systemd service, full paths |
| gas-cylinder-watchdog.service | ✅ INSTALLED | Auto-start on boot |
| WebUI | ✅ WORKING | Dark, live readings, GOOD badge |

---

## 3E-005 — Water bowl anchor validation (NEXT EXPERIMENT)

### Purpose
Prove the end-to-end anchor flow works before using a real cylinder.
Water simulates gas. Bowl+plate simulates the cylinder steel.

### Physical setup
| Item | Weight |
|---|---|
| Bowl empty | 406g |
| Plate | 59g |
| Bowl + plate (steel equivalent) | 465g |
| Water in bowl | 4535g |
| Total gross on platform | ~5000g ± 10g |

### domain.py constants to change for this test
```python
# Change these 4 ONLY for 3E-005. Revert ALL to production after.
NET_GAS_G             = 4535.0    # TEST. PRODUCTION=14200.0
ANCHOR_GROSS_MIN_G    = 4800.0    # TEST. PRODUCTION=26000.0
STEEL_PLAUSIBLE_MIN_G = 200.0     # TEST. PRODUCTION=13000.0
STEEL_PLAUSIBLE_MAX_G = 2000.0    # TEST. PRODUCTION=18000.0
```

### Setup endpoint command
```bash
python3 -c "
import socketio
sio = socketio.Client()
sio.connect('http://192.168.88.20:7000')
sio.emit('setup', {'mode': 'FRESH', 'brand': None})
import time; time.sleep(2)
sio.disconnect()
"
```

### Pass criteria
- [ ] Hub transitions UNINSTALLED → BOOTSTRAP_ANCHOR after setup called
- [ ] Anchor fires after 5 stable readings (logs show ANCHOR COMPLETE)
- [ ] steel_g ≈ 465g (bowl + plate)
- [ ] gas_pct = 100% immediately after anchor
- [ ] gas_pct drops as water is removed
- [ ] AMBER alert fires when gas_g < 2000g (gross < 2465g)
- [ ] config.json shows steel_source=ANCHOR

---

## Build sequence — locked order

```
1. 3E-005 anchor validation (water bowl)     ← NEXT
2. 3E-008 temperature drift characterisation
3. 3E-009 6hr long-run stability
4. 3E-010 load cell failure injection
5. G5 analytics — burn rate, days remaining from real data
6. Hub BLE peripheral — raw D-Bus GATT server for Flutter app
7. WebUI G7 — full dashboard, gas gauge, brand picker
```

---

## Hub BLE peripheral — design locked (not yet built)

BLE-only transport between hub and Flutter mobile app (boss decision).
Hub dual role: central (connects to node) + peripheral (serves app).
WCN3990 confirmed supports `le advertising` (from btmgmt info).
Implementation: raw D-Bus GATT server (consistency with existing central code).

Hub GATT service (GasCylHub):
- STATUS char: notify 30s — {gas_pct, gas_g, days_remaining, alert_level}
- ANALYTICS char: read — paginated daily burn data
- CMD char: write — SET_BRAND, SETUP, REQUEST_HISTORY_PAGE
- RESPONSE char: notify — hub replies to CMD
- VOICE char: write+notify — query in, Telugu+English answer out

---

## UI/UX design — locked

Three surfaces:
1. Wall display — dark, always-on, days remaining large, gas gauge arc
2. Flutter mobile app — 4 screens: home, analytics, voice, settings
3. Voice — Telugu + English TTS (flutter_tts + speech_to_text)

Flutter packages: `flutter_blue_plus`, `flutter_tts`, `speech_to_text`
Hub REST: `/api/status`, `/api/analytics/daily`, `/api/voice/query`
Hub WebSocket: `ws://hub/ws/live`

---

## Key learnings — things discovered the hard way

**Architecture:**
- Hardware health and calibration confidence are independent signals. Never conflate them.
  g_cal_degraded = calibration fallback. g_health.quality = hardware fault. Different things.
- Steel cancels in delta calculations. Consumption/burn rate are immune to unknown steel from day 1.
- Underestimating gas is safer than overestimating. Conservative prior (16,500g not 15,000g).
- Hub is source of truth. SPIFFS is recoverable cache. config.json is the authority.

**BLE on WCN3990:**
- 10Hz BLE notify crashes WCN3990 firmware after ~8 minutes. 30s minimum.
- SetDiscoveryFilter with UUIDs silently ignored. Match by name only.
- InterfacesAdded only fires for new devices. Cached devices need GetManagedObjects poll.
- hcitool lescan always fails. Use bluetoothctl for diagnostics.
- auto transport kills BT adapter. Use le transport only.
- D-Bus not accessible inside Docker. Use socat bridge.

**HX711:**
- LONG_MIN, -1, and 0x7FFFFF are all corrupt values. All three filters always.
- noInterrupts() mandatory during 25-pulse read sequence.
- SPIFFS survives power cycle but not reflash. Accumulation tests: power cycle only.

**Calibration:**
- cal_factor must never be hardcoded. Always from config.json or SPIFFS.
- Cross-boot cal_factor is invalid if tare baseline differs between sessions.
- Use noise_recompute_sigma() after CAL to rescale already-collected samples.
- Tare validated every boot: 5-sample, spread <600 raw, 3 retries.

**Debugging discipline:**
- Most bad readings = code/timing issue, not hardware.
- Diagnose with log evidence before any fix.
- "How do we know the bug is solved?" — always answer this before moving on.
- Never proceed after "fix" without a verification command.

**Docker:**
- config.json baked at deploy from hub/config.json — NOT hub/data/config.json.
- Docker mounts don't include hub/data/ unless explicitly in docker-compose.
- Host tools (hciconfig, bluetoothctl) not available in container.
- Trigger file pattern: container writes to shared volume → host script acts.

---

## Critical rules — never violate

| Rule | Detail |
|---|---|
| BLE notify ≥ 30s | WCN3990 crashes at 10Hz. Never increase rate. |
| No hciconfig in Docker | Not available. Use reading_fresh for health. |
| Sudoers full paths | /usr/bin/systemctl not systemctl. Exact match. |
| config.json = hub/config.json | NOT hub/data/config.json. |
| tare + cal = PAIR | Always from same session. Never split. |
| No TARE on reconnect | Hub sends SKIP_TARE+SET_CAL when cal_factor present. |
| No gas% without steel | Always subtract steel_g first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| BlueZ: match by Name | Not UUID. QRB2210 limitation. |
| Claude Code CLI pinned | v2.1.129. DISABLE_AUTOUPDATER=1. Never upgrade. |
| No hardcoding | All paths dynamic (SCRIPT_DIR). No usernames, hostnames, absolute paths. |
| SPIFFS ≠ reflash | Power cycle for accumulation tests. Never Erase All Flash. |
| Hub = orchestrator only | main.py zero domain logic. All logic in domain.py. |
| Node outputs {grams,quality,sigma} | Nothing else. Hub owns all interpretation. |
| BLE notify decoupled | HX711 read rate (100ms) ≠ BLE notify rate (30s). Always. |

---

## Deferred items (carry forward every session)

- DUMP_LOG anomaly: boot=6 t≈4678 duplicate unknown commands — investigate after G5
- HUB-001: auto-retare on cylinder removal — V2
- Rcal shunt calibration resistor (CD4066B + 180kΩ, GPIO5=RCAL_EN) — V2
- N1 journal→SPIFFS: required before 3E-010 overnight test (may need before 3E-010)
- Cross-check 1 (verify gross after SKIP_TARE vs steel_g) — needs 3E-005 first
- Cal_factor re-derivation from cylinder anchor — needs 3E-005 first
- BLE supervision timeout disconnects every ~4min — not a failure, do not investigate

---

## Quick reference commands

```bash
# Deploy hub
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh

# Live hub logs
docker logs gas-cylinder-monitor-hub-main-1 -f

# Check stability (no reboots)
last reboot | head -5

# Check hub sending SKIP_TARE
docker logs gas-cylinder-monitor-hub-main-1 --since 5m | grep -E "SKIP|TARE|SET_CAL"

# Check watchdog health
cat ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | grep WATCHDOG | tail -10

# Check config.json
cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json | python3 -m json.tool

# Restart bluetooth (host side)
sudo /usr/bin/systemctl restart bluetooth

# SCP node sketch from AQ3 to Windows
scp arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/node/gas_monitor_v1/* C:\Users\mahes\Documents\Arduino\gas_monitor_v1\
```

---

## Session start checklist

Before doing anything else:

1. Read this document fully
2. Confirm: `last reboot | head -5` — no reboots after Jun 24 04:30 IST
3. Confirm hub running: `docker logs gas-cylinder-monitor-hub-main-1 --tail 5 | grep HUB`
4. Confirm SKIP_TARE working: grep for "sent SKIP_TARE" in recent hub logs
5. Confirm node boot count in serial monitor (should be 21 or higher)
6. Confirm config.json has cal_factor=36.2231 at hub/config.json
7. State working mode explicitly: chat = design, CLI = code
8. For 3E-005: prepare bowl (406g) + plate (59g) + 4535g water before starting

---

## Opening prompt for next session

```
Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_24_MASTER.md fully before responding.
Context: BLE stable 17h. Boot time 27.5s via SKIP_TARE+SET_CAL verified boot=21.
System fully stable. config.json path fixed. Ready for 3E-005.
Today: run 3E-005 water bowl anchor validation.
Start by confirming system stability (last reboot | head -5),
then confirm hub sends SKIP_TARE (docker logs grep SKIP_TARE),
then generate the project roadmap tracker before running the experiment.
```

---

## SCP this file to AQ3

```powershell
scp C:\Users\mahes\Downloads\HANDOFF_2026_06_24_MASTER.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/
```

---

*End of master handoff. System is stable and ready for 3E-005.*
*Gratian Technologies | gratiantechnologies/project13 | 2026-06-24*
