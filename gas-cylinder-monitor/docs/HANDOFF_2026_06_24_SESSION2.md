# MASTER HANDOFF — Gas Cylinder Monitor V1
# Gratian Technologies | gratiantechnologies/project13
# Date: 2026-06-24 SESSION 2 | Read this before anything else

---

## READ THIS FIRST

This document is the complete entry point for any new chat session.
Read it fully before touching any file, running any command, or making any decision.

Working mode — non-negotiable:
- Chat = design, architecture, planning, CLI prompts only
- Claude Code CLI on AQ3 = all code, all file writes
- Never write code in chat. Never skip design in chat.
- All handoff documents created in chat, never delegated to CLI.

Philosophy — always:
- First principles: never "it just works". Always: why does it work, what breaks if it didn't.
- Evidence before diagnosis. Logs before any fix.
- One chunk at a time. Verify before proceeding.
- Structured experiments: named sequentially (3E-xxx), parameters locked before execution.

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
| Upload speed | 921600 normal / 115200 fallback (never Erase All Flash) |
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

## Current state — as of 2026-06-24 Session 2 end

### Node
- Boot count: **boot=25** (after 3 platform swap tests)
- Firmware: `gas_monitor_v1` — all node layers complete, no changes this session
- Boot time: **46.8 seconds** (TARE path, new platform) / **27.5s** (SKIP_TARE path)
- Sigma: 3.60g (new platform, slightly better than old platform 4.56g)
- SPIFFS: `cal_factor=36.2231`, `tare_raw=-88281.3` (new platform, current)

### Hub
- System uptime: stable since Jun 23 17:03 IST — no reboots since BUG fixes
- Hub correctly sends: **TARE when cylinder_state=UNINSTALLED, SKIP_TARE otherwise**
- config.json: `cal_factor=36.2231`, `tare_raw=-88281.3` (updated automatically after fresh tare)
- Watchdog: running, no false fires

### Platform validation completed this session
Three-run platform swap test — all PASSED:
```
Run 1: new plate  → tare_raw=-88281.3   → readings ~0g  ✓
Run 2: old plate  → tare_raw=-106766.0  → readings ~0g  ✓
Run 3: new plate  → tare_raw=-88281.3   → readings ~8g  ✓ (within sigma band)

Old plate is 510g heavier than new plate:
(-106766.0 - (-88281.3)) / 36.2231 = 510.3g — confirmed by geometry.
```

### Immediate next step
**3E-005 — water bowl anchor validation.** System is ready. Platform is stable.
New plate is now the production platform. tare_raw=-88281.3 locked in SPIFFS + config.json.

---

## What changed this session (new — not in previous handoff)

### BUG-5 FOUND AND FIXED: Hub sent SKIP_TARE unconditionally

**Discovery:** Platform plate was changed. Node power cycled. Hub sent SKIP_TARE
(old behaviour — unconditional). Old tare_raw loaded from SPIFFS. New plate weight
(~510g heavier) appeared as a reading. WebUI showed 530g on empty platform.

**Root cause:** Hub's connect logic sent SKIP_TARE always, regardless of cylinder_state.
The assumption "tare is already valid" was wrong when the physical platform changed.

**Fix (implemented, deployed, verified):**
```python
# ble_subscriber.py — _send_tare_commands()
cylinder_state = config.get("cylinder_state", "UNINSTALLED")

if cylinder_state == "UNINSTALLED":
    send TARE + SET_CAL     # platform should be empty, safe to tare fresh
else:
    send SKIP_TARE + SET_CAL  # cylinder present, protect tare baseline
```

**Also fixed:** After fresh TARE, hub parses the boot journal (domain.py) and updates
tare_raw in config.json automatically. Journal line parsed:
`[BOOT] event=PHASE_COMPLETE phase=TARE result=OK mean=<value>`

**Verified:** boot=23 tare_raw=-88281.3 updated in config.json correctly ✓

### New principle: tare baseline absorbs the platform permanently

The tare is not "zero weight." It is "zero weight as defined by whatever is
permanently resting on the load cells." The platform plate, a rubber mat, a metal
drip tray, a cloth — all are absorbed into tare_raw at the moment of taring.
They become invisible to the system. Only what sits on top matters.

**Production implications:**
- User can place rubber mat/drip tray BEFORE power-on → gets absorbed into tare ✓
- User changing platform must power off first, swap plate, then power on ✓
- System self-adapts: cylinder_state=UNINSTALLED → fresh TARE → new platform absorbed ✓
- Steel cancels in consumption: gas_g = gross_g - steel_g → mat weight cancels out ✓

### N-TARE-CHECK already handles hub-absent platform-change case

When hub is offline at boot, N-TARE-CHECK does the same decision:
```
delta_g = (live_raw - saved_tare_raw) / cal_factor
delta_g > 2000g → use saved tare (cylinder present)
delta_g < 2000g → fresh tare (platform empty or just mat)
```
Same logic, same threshold. Hub-present = hub decides. Hub-absent = node decides.
Both paths always agree for same physical state.

### Known minor issue: tare_raw updated 3× after DUMP_LOG

`[DOMAIN] tare_raw updated: -88281.3` appears 3 times after boot.
Same value each time — no corruption. Caused by multiple LOG_END firings from
multiple DUMP_LOG cycles in same session. Low priority fix. Not a correctness problem.

### RETARE deferred to V2

Design locked: WebUI button (Option B — user-explicit). Visible only when
cylinder_state=UNINSTALLED. Option A (automatic) rejected — too dangerous
(could fire with cylinder on platform if delta logic is wrong).
Node-side RETARE command handler also needed (not built). Deferred post-V1.

---

## Hub command sequence on node connect — UPDATED

**Previous (wrong):** Always sent SKIP_TARE + SET_CAL.

**Current (correct):**
```
1. Hub connects to GasCylMonitor (by name)
2. Reads cylinder_state from config.json

   If cylinder_state == "UNINSTALLED":
       → send TARE (t+1.0s)
       → send SET_CAL:36.2231 (t+2.0s)
       → last_boot_used_tare = True
   Else (BOOTSTRAP_*, TRACKING, LOW_GAS):
       → send SKIP_TARE (t+1.0s)
       → send SET_CAL:36.2231 (t+2.0s)
       → last_boot_used_tare = False

3. send DUMP_LOG
4. After LOG_END: if last_boot_used_tare → parse journal → update tare_raw in config.json
5. send CLEAR_LOG
```

---

## Tare baseline — full design (first principles)

### Core principle
tare_raw absorbs EVERYTHING permanently resting on the load cells:
- the load cell platform plate
- any rubber mat
- any drip tray
- any cloth or sheet placed before tare

None of these are "weight." They are part of the scale itself.

### Platform change procedure (production)
```
Step 1: Power off node (unplug USB) — mandatory first
Step 2: Make physical change (swap plate, add mat, etc.)
Step 3: Ensure platform is empty (cylinder removed)
Step 4: Power on node
Step 5: Hub sees cylinder_state=UNINSTALLED → sends TARE
Step 6: New platform absorbed into tare_raw automatically
```

### Why steel cancels even with mat under cylinder
```
At tare:  tare_raw = empty platform (no mat)
User adds mat, then cylinder, then anchor fires:
  steel_g = gross_g - 14200 = (mat + cylinder_full) - 14200

During use:
  gas_g = gross_g - steel_g
        = (mat + cylinder_now) - (mat + cylinder_full - 14200)
        = cylinder_now - cylinder_full + 14200
        = gas remaining  ← mat cancels perfectly ✓
```

---

## Node boot sequence (complete)

```
t=0.0   Power on
t=0.3   journal_init — SPIFFS mount, load journal

t=0.3-2.3  SETTLE phase (2 seconds)
        → ADC stabilisation, no BLE yet

t=2.3   SETTLE complete
        → BLE starts advertising
        → hub connects, MTU negotiated (255 bytes)
        → TARE_WAIT begins — 60s window
        → node sends NOTHING yet (no heartbeats, no weight)

t=5-6   Hub sends TARE or SKIP_TARE

        TARE path (cylinder_state=UNINSTALLED):
            → node takes 5-sample tare (~21s)
            → saves new tare_raw to SPIFFS
            → boot time ~46.8s total

        SKIP_TARE path (cylinder on platform):
            → loads tare_raw from SPIFFS (0.1s)
            → boot time ~27.5s total

        60s timeout path (hub absent):
            → N-TARE-CHECK: delta > 2000g → use SPIFFS tare
            →              delta < 2000g → fresh tare

t+20s   NOISE phase (20s) — sigma characterisation
t+0.1s  CAL phase — applies SET_CAL, or SPIFFS, or 120s fallback
        → BOOT_COMPLETE logged

        RUNNING:
        → HX711 read every 100ms
        → BLE notify every 30s ONLY
        → Journal to SPIFFS continuously
        → DUMP_LOG on every BLE connect
```

---

## Hub state machine (domain.py)

```
UNINSTALLED
    ↓ (setup endpoint called with mode=FRESH)
BOOTSTRAP_ANCHOR
    - Hub waits for N=5 stable readings
    - All readings > ANCHOR_GROSS_MIN_G (4800g test / 26000g production)
    - Spread < ANCHOR_SPREAD_THRESHOLD_G = 30g
    - Derives: steel_g = mean(window) - NET_GAS_G
    - Validates: STEEL_PLAUSIBLE_MIN_G < steel_g < STEEL_PLAUSIBLE_MAX_G
    - Saves: steel_g, steel_source=ANCHOR to config.json
    ↓ (anchor complete)
TRACKING
    - gas_g = gross_g - steel_g
    - gas_pct = gas_g / NET_GAS_G * 100
    - AMBER alert: gas_g < 2000g
    - RED alert: gas_g < 1000g
    - days_remaining = gas_g / DAILY_USE_DEFAULT_G
    ↓ (gross drops near 0 — cylinder removed)
UNINSTALLED (cycle repeats — refill path self-heals)
```

---

## Locked constants — never change without re-derivation

| Constant | Value | Source | File |
|---|---|---|---|
| NET_GAS_G | 14200.0g | BIS IS 3196 — legally fixed | domain.py |
| cal_factor | 36.2231 raw/g | Verified 18+ boots | SPIFFS + config.json |
| tare_raw | -88281.3 raw | New platform, verified 3 runs | SPIFFS + config.json |
| BLE_NOTIFY_INTERVAL_MS | 30000 (30s) | WCN3990 hardware limit | gas_monitor_v1.ino |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0g | Fixed constant | domain.py |
| ALERT_AMBER_G | 2000.0g | Locked 2026-06-12 | domain.py |
| ALERT_RED_G | 1000.0g | Locked 2026-06-12 | domain.py |
| DAILY_USE_DEFAULT_G | 350.0g | Locked 2026-06-12 | domain.py |
| STEEL_UNKNOWN_PRIOR_G | 16500.0g | Conservative | domain.py |
| HEAVY_LOAD_THRESHOLD_G | 2000.0g | Production (was 1000g DEV) | node |

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
│       ├── ble_subscriber.py        ← BLE + TARE/SKIP_TARE decision logic
│       ├── log_transfer.py          ← log pipeline only
│       ├── domain.py                ← ALL domain logic + tare_raw parser
│       ├── db.py                    ← SQLite abstraction only
│       ├── hub_logger.py            ← persistent hub.log, session counter
│       └── hub_watchdog.py          ← 3-level watchdog
├── node/
│   └── gas_monitor_v1/              ← production node firmware
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    └── HANDOFF_*.md
```

**CRITICAL:** `hub/config.json` is the real config — baked into Docker at deploy.
`hub/data/config.json` does NOT exist and is never read by the container.

---

## config.json — current state

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
  "tare_raw": -88281.3,
  "cal_tare_session": "boot23_verified_2026-06-24"
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
| N-TARE-CHECK | ✅ COMPLETE | Hub-offline self-protect. Threshold 2000g. |
| BLE_NOTIFY_INTERVAL | ✅ COMPLETE | 30000ms — WCN3990 crash fix |
| SKIP_TARE path | ✅ COMPLETE | Verified boot=21. Boot time 27.5s. |
| TARE path | ✅ COMPLETE | Verified boot=23. Boot time 46.8s. |

---

## Hub layer status — all complete

| Component | Status | Detail |
|---|---|---|
| ble_subscriber.py | ✅ COMPLETE | TARE/SKIP_TARE decision + _send_tare_commands() |
| log_transfer.py | ✅ COMPLETE | Full pipeline, abort-safe |
| domain.py | ✅ COMPLETE | G4 state machine, gas%, anchors, tare_raw parser |
| db.py | ✅ COMPLETE | SQLite abstraction |
| main.py | ✅ COMPLETE | Orchestrator only, on_log_line_wrapper |
| hub_logger.py | ✅ COMPLETE | Persistent hub.log, session counter |
| hub_watchdog.py | ✅ COMPLETE | 4 bugs fixed, reading_fresh health |
| watchdog_host.sh | ✅ COMPLETE | Systemd service, full paths |
| WebUI | ✅ WORKING | Dark, live readings, GOOD badge |

---

## 3E-005 — Water bowl anchor validation (NEXT)

### Purpose
Prove end-to-end anchor flow works before using a real cylinder.
Water simulates gas. Bowl+plate simulates the cylinder steel.
Hub must transition UNINSTALLED → BOOTSTRAP_ANCHOR → TRACKING unassisted.

### Physical setup
| Item | Weight |
|---|---|
| Bowl empty | 406g |
| Plate | 59g |
| Bowl + plate (steel equivalent) | 465g |
| Water in bowl | 4535g |
| Total gross on platform | ~5000g ± 10g |

### domain.py constants — change for 3E-005, revert ALL after

```python
# CHANGE for test:
NET_GAS_G             = 4535.0    # TEST. PRODUCTION = 14200.0
ANCHOR_GROSS_MIN_G    = 4800.0    # TEST. PRODUCTION = 26000.0
STEEL_PLAUSIBLE_MIN_G = 200.0     # TEST. PRODUCTION = 13000.0
STEEL_PLAUSIBLE_MAX_G = 2000.0    # TEST. PRODUCTION = 18000.0

# REVERT immediately after test — never leave test values in production
```

### Physical procedure (critical — read before touching anything)

```
Phase A — Change domain.py constants + deploy

Phase B — Experiment:
  Step 1: Confirm platform empty, readings ~0g
  Step 2: Call setup endpoint (see command below)
  Step 3: Wait 60s — load cells need to settle after placing bowl
  Step 4: Place bowl + plate on platform (empty)
  Step 5: Add 4535g water to bowl carefully
  Step 6: Stand back. Do NOT touch for 150s minimum (5 readings × 30s)
  Step 7: Watch hub logs for ANCHOR COMPLETE / state=TRACKING
  Step 8: Verify steel_g ≈ 465g in config.json
  Step 9: Verify gas_pct = 100%
  Step 10: Remove water incrementally, watch gas% drop
  Step 11: Verify AMBER alert fires when gas_g < 2000g

Phase C — Revert all 4 constants + redeploy immediately after
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

### Why platform must not be touched during anchor collection
The anchor needs 5 readings within 30g spread, all above ANCHOR_GROSS_MIN_G.
One bad reading (nudge, bump) wipes the entire candidate window.
Hub starts counting from zero. 150s more wait minimum.
Viscoelastic creep: load cells drift for 30-60s after load placed. Wait before setup call.

### Anchor timing
- Minimum time after setup call: 150s (5 readings × 30s)
- Realistic: 3-5 minutes (settling + window accumulation)
- If anchor does not fire: check hub logs for spread values

### Pass criteria
- [ ] Hub transitions UNINSTALLED → BOOTSTRAP_ANCHOR after setup called
- [ ] Anchor fires (logs: ANCHOR COMPLETE or state=TRACKING)
- [ ] steel_g ≈ 465g (bowl + plate)
- [ ] gas_pct = 100% immediately after anchor
- [ ] gas_pct drops as water is removed
- [ ] AMBER alert fires when gas_g < 2000g (gross < 2465g)
- [ ] config.json shows steel_source=ANCHOR

---

## BLE stability — everything fixed

### BUG-1: WCN3990 crashes at 10Hz BLE notify
- Fix: `BLE_NOTIFY_INTERVAL_MS = 30000`

### BUG-2: POST_ACTION_WAIT_S=30 too short
- Fix: `POST_ACTION_WAIT_S = 120`

### BUG-3: hciconfig not available inside Docker
- Fix: health check uses `reading_fresh` only

### BUG-4: READING_STALE_S=300 too short for BLE dropout
- Fix: `READING_STALE_S = 900`

### BUG-5 (NEW this session): Hub sent SKIP_TARE unconditionally
- Fix: TARE if cylinder_state=UNINSTALLED, SKIP_TARE otherwise
- Plus: tare_raw auto-updated in config.json from boot journal after fresh TARE

### Watchdog constants (locked)
```python
CHECK_INTERVAL_S      = 60
READING_STALE_S       = 900
CONSECUTIVE_FAIL_GATE = 2
POST_ACTION_WAIT_S    = 120
```

### Sudoers on AQ3 host
```
arduino ALL=(ALL) NOPASSWD: /sbin/reboot
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart bluetooth
```
Full paths mandatory. Exact path match.

---

## Normal BLE dropout — not a failure

BLE disconnects every ~3-4 minutes (supervision timeout). Reconnects in ~30s.
Watchdog (900s) will NOT fire. SPIFFS journal preserved. Do not investigate
unless dropout exceeds 15 minutes.

---

## BlueZ quirks on QRB2210 — permanent rules

| Rule | Detail |
|---|---|
| Match by Name not UUID | SetDiscoveryFilter UUID array silently ignored |
| GetManagedObjects on StartDiscovery | InterfacesAdded only fires for new devices |
| No hcitool lescan | Always fails — use bluetoothctl for diagnostics |
| BLE scan transport=le only | auto transport kills BT adapter |
| D-Bus not in Docker | Use socat bridge service |
| hciconfig not in Docker | Use reading_fresh as health signal |

---

## HX711 hardware rules — permanent

| Rule | Detail |
|---|---|
| DT = GPIO4 | LOCKED. Never change. |
| SCK = GPIO3 | LOCKED. Never change. |
| VCC = 3.3V | Green PCB clone. 5V will damage. |
| Raw bit-bang only | No library. |
| noInterrupts() during read | Mandatory during 25-pulse sequence |
| Corrupt filters | LONG_MIN, -1, 0x7FFFFF — all three always |
| Never Erase All Flash | Wipes SPIFFS. Lower baud to 115200 instead. |
| Power cycle ≠ reflash | SPIFFS survives power cycle, not reflash |

---

## Load cell wiring (3-cell parallel)

Same-colour wires twisted together → directly to HX711. No junction box.
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

## Build sequence — locked order

```
1. ✅ G4 — hub domain logic, 5-module refactor, state machine, gas%
2. ✅ N-TARE-CHECK + HEAVY_LOAD_THRESHOLD_G restored to 2000g
3. ✅ BUG-5 fix — TARE/SKIP_TARE decision + tare_raw auto-update
4. ▶ 3E-005 — water bowl anchor validation         ← NEXT
5. ○ 3E-008 — temperature drift characterisation
6. ○ 3E-009 — 6hr long-run stability
7. ○ 3E-010 — load cell failure injection
8. ○ G5/G6 — analytics + prediction (gate: 7 days TRACKING data)
9. ○ G7 WebUI — gas gauge arc, trend, brand picker, Telugu+English
10. ○ Hub BLE peripheral — D-Bus GATT server for Flutter app
```

---

## Key learnings — hard-won this session

**Tare baseline:**
- tare_raw absorbs EVERYTHING permanently on platform. Platform is part of the scale.
- Changing platform requires: power off → swap → power on → fresh tare absorbs new platform.
- Steel cancels in gas consumption — mat/tray under cylinder has no effect on readings.
- Hardware truth (live weight) is more reliable than software state (cylinder_state).
- N-TARE-CHECK and hub TARE decision use same threshold (2000g) — always agree.

**RETARE (V2):**
- Option B: user button — safest. User visually confirms empty platform before pressing.
- Option A (automatic) rejected: can fire with cylinder on platform if logic wrong → catastrophic.
- Requires node-side RETARE handler in STATE_RUNNING (not yet built).

**Journal timing:**
- DUMP_LOG fires before boot phases complete — journal contains previous session entries.
- Hub parses tare_raw from journal after DUMP_LOG completes.
- last_boot_used_tare flag guards against updating config.json on SKIP_TARE boots.

---

## Critical rules — never violate

| Rule | Detail |
|---|---|
| BLE notify ≥ 30s | WCN3990 crashes at 10Hz |
| No hciconfig in Docker | Not available. Use reading_fresh. |
| Sudoers full paths | /usr/bin/systemctl. Exact match. |
| config.json = hub/config.json | NOT hub/data/ |
| tare + cal = PAIR | Always same session. Never split. |
| cylinder_state=UNINSTALLED → TARE | Otherwise SKIP_TARE. |
| No gas% without steel | Always subtract steel_g first. |
| No timestamps on node | Hub stamps on receipt. No RTC. |
| BlueZ: match by Name | Not UUID. QRB2210 limitation. |
| Claude Code CLI pinned | v2.1.129. DISABLE_AUTOUPDATER=1. |
| No hardcoding | All paths dynamic (SCRIPT_DIR). |
| SPIFFS ≠ reflash | Power cycle for tests. Never Erase All Flash. |
| Hub = orchestrator only | main.py zero domain logic. |
| Node outputs {grams,quality,sigma} | Hub owns all interpretation. |
| Power off before platform change | Never change platform while node running. |
| 3E-005 test constants → revert | Never leave test values in production. |

---

## Deferred items (V2 or post-3E-005)

- RETARE command — WebUI button, user-explicit, node handler needed (V2)
- DUMP_LOG triple-fire after tare update — minor cosmetic, same value, no harm
- DUMP_LOG anomaly: boot=6 t≈4678 duplicate unknown commands — post-G5
- HUB-001: auto-retare on cylinder removal — V2
- Rcal shunt calibration resistor (CD4066B + 180kΩ, GPIO5=RCAL_EN) — V2
- Cal_factor re-derivation from cylinder anchor — after 3E-005
- Cross-check: verify gross after SKIP_TARE vs steel_g — after 3E-005
- G5/G6: analytics + prediction — gate: 7 days TRACKING data after 3E-005

---

## Quick reference commands

```bash
# Deploy hub
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh

# Live hub logs
docker logs gas-cylinder-monitor-hub-main-1 -f

# Tail hub logs
docker logs gas-cylinder-monitor-hub-main-1 --tail 20

# Check stability (no reboots)
last reboot | head -5

# Check TARE/SKIP_TARE decision
docker logs gas-cylinder-monitor-hub-main-1 --since 5m | grep -E "SKIP|TARE|SET_CAL"

# Check tare_raw updated
docker logs gas-cylinder-monitor-hub-main-1 --since 5m | grep "tare_raw updated"

# Check config.json
cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json | python3 -m json.tool

# Check watchdog
cat ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | grep WATCHDOG | tail -10

# Restart bluetooth (host side only)
sudo /usr/bin/systemctl restart bluetooth
```

---

## Session start checklist

Before doing anything else:

1. Read this document fully
2. `last reboot | head -5` — confirm no new reboots after Jun 24 17:03 IST
3. `docker logs gas-cylinder-monitor-hub-main-1 --tail 5` — confirm hub running
4. Check TARE/SKIP_TARE: grep logs for "sent TARE" or "sent SKIP_TARE"
5. `cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json` — confirm tare_raw=-88281.3 and cal_factor=36.2231
6. State working mode: chat = design, CLI = code
7. For 3E-005: prepare bowl (406g) + plate (59g) + 4535g water + kitchen scale before starting

---

## Opening prompt for next session

```
Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_24_SESSION2.md fully before responding.

Context: Platform swap test (3 runs) complete and PASSED.
BUG-5 fixed: hub now sends TARE when cylinder_state=UNINSTALLED.
tare_raw auto-updates in config.json after fresh tare.
New platform: tare_raw=-88281.3, sigma=3.60g, boot=25.
System stable. Ready for 3E-005.

Today: run 3E-005 water bowl anchor validation.
Start by confirming stability (last reboot | head -5),
then confirm tare_raw=-88281.3 in config.json,
then generate CLI prompts for domain.py constant changes,
then run the experiment.
```

---

## SCP this file to AQ3

```powershell
scp C:\Users\mahes\Downloads\HANDOFF_2026_06_24_SESSION2.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/
```

---

*End of handoff. System stable. Platform validated. Ready for 3E-005.*
*Gratian Technologies | gratiantechnologies/project13 | 2026-06-24 Session 2*
