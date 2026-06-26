# CLAUDE.md — gas-cylinder-monitor
# Board: Arduino UNO Q AQ3 | IP: 192.168.1.161 | user: arduino
# Last updated: 2026-06-26
# Read this FULLY before doing anything in this directory.

---

## What This Product Is

LPG cylinder weight monitor for Indian households. An **ESP32-C3 sensor node** reads a
20 kg load cell via HX711, computes gross weight in grams, sends
`{grams, quality, sigma}` over BLE to the **UNO Q hub**. The hub stamps a timestamp,
derives cylinder steel via anchor events, computes gas %, stores in SQLite, runs analytics
and prediction, and serves a WebUI.

Development phase uses water in a container — not a gas cylinder. Weight is weight.
No code path may be hardcoded for "gas" semantics.

```
Load cell → HX711 → ESP32-C3 (grams) ──BLE──▶ UNO Q hub (everything else)
            [------ node/ ----------]           [-------- hub/ --------------]
```

---

## Two Contexts — NEVER Blur These

The single biggest failure mode is writing node code in the hub or hub logic in the node.

---

### node/ context — ESP32-C3

**Board:** ESP32-C3 (in hand). Flashed via Arduino IDE / PlatformIO.
NOT App Lab, NOT Bridge, NOT Bridge.notify — ESP32 has no Bridge.

**Owns:**
- HX711 raw bit-bang (24-bit + 25th gain pulse)
- Three corrupt filters (LONG_MIN, -1, 0x7FFFFF)
- N-sample averaging
- Scale-zero tare (self-computing, never hardcoded)
- cal_factor derivation (never hardcoded; VOID the old STM32 value of 106.7)
- Noise characterisation (N=200 lab, N=50 production)
- BLE send → payload: `{grams: float, quality: "GOOD"|"DEGRADED"|"FAILED", sigma: float}`

**Node outputs grams only.** Never computes gas %. Has no clock, no history,
no steel knowledge.

**SAFETY GATE — check before powering:**
HX711 VCC is 5V. ESP32-C3 GPIO is 3.3V. **DOUT/SCK logic levels vs ESP32-C3 GPIO
tolerance must be verified before applying power. Level-shift if needed.**
This is the first gate of E-000. Do not skip it.

**Pins:** TBD at bring-up. The old DT=D7/SCK=D6 rule was an STM32U585 timer-conflict
constraint. It does **NOT** apply to the ESP32-C3. Pick any two GPIO; validate on ESP32.

**cal_factor:** The old value of 106.7 raw/g was STM32U585-specific. It is **VOID** on
ESP32-C3. Re-derive completely during E-000/calibration experiments.

**float vs double:** The double-broken bug (sum=0 on STM32U585) was platform-specific.
Re-verify on ESP32-C3. Use float as safe default until verified on hardware.

**No Bridge, no App Lab, no delay(3000)/Bridge.begin():** those are UNO Q App Lab
patterns only. ESP32-C3 firmware is standard Arduino/PlatformIO with WiFi libraries.

---

### hub/ context — UNO Q QRB2210 Linux

**Board:** UNO Q AQ3 at 192.168.1.161. App Lab / Docker / Python world.

**Owns:**
- BLE receive via BlueZ (listen for GATT notify from ESP32)
- Timestamp stamping on receipt (ESP32-C3 has no RTC)
- Cylinder steel derivation (anchor events from SQLite history)
- `gas% = (grams - steel) / 14200 × 100`
- SQLite storage (readings + refill_events tables)
- Analytics + burn rate + prediction
- WebUI (Flask / Socket.IO dashboard)
- BLE alerts (future)

**Hub NEVER touches:**
- A raw HX711 count
- A pin or bit-bang operation
- Any sensor register or timing
- Hub starts at "receive grams via BLE" — nothing before that

**Wheels/typelibs/socket.io:** live in home-hub/ — one `cp` away when WebUI phase arrives.
Do NOT copy now. Do NOT commit wheels/ to git.

---

## Non-Negotiable Rules (Both Contexts)

| Rule | Detail |
|------|--------|
| No hardcoding | cal_factor, tare, steel, thresholds — all derived or from config. No buried constants. |
| HX711 raw bit-bang | No external HX711 library. Copy from reference-code/stm32-hx711-modular/ PORT THE LOGIC, not the code. |
| Node→hub payload is grams | Never raw ADC counts. Never gas %. The seam is always grams. |
| Modules return {value, quality, diagnosis} | Never just a bool. GOOD/DEGRADED/FAILED enables graduated response. |
| Small → verify → compound | One chunk at a time, gated by hardware verification. Never jump ahead. |
| Adaptive retry | Never halt in production. 2s/10s/30s/60s backoff + degraded operation. |
| No blocking in state cases | One sample per loop() iteration. millis() pacing at TOP of loop(). |
| float is safe default | Re-verify double on ESP32-C3 before using it. |

---

## Every-Session Read Order

Before writing a single line of code:

1. `~/ArduinoApps/gas-cylinder-monitor/CLAUDE.md` ← this file
2. `~/ArduinoApps/WORKING_MODE.md`
3. `docs/PLAN.md` ← chunk-groups, where we are
4. `docs/SCOPE.md` ← V1 locked scope
5. `docs/PROJECT_CONTEXT.md` ← one-screen current state
6. `docs/HANDOFF.md` ← what the last session left
7. Relevant `docs/reference/specs/` for the current chunk-group
8. The design prompt from chat

Do not touch code until all eight are read.

---

## Hub Self-Contained Rule

Hub wheels/, typelibs/, and socket.io.min.js are built/copied by hub/setup.sh
from system sources only. No dependency on other projects.
Never copy from home-hub or youtube-display — those may not exist in production.
Do not commit wheels/ to git (.gitignore covers it).

NOTE 2026-06-15: hub/ is now self-contained. setup.sh builds wheels from source.
The home-hub copy pattern above is superseded for gas-cylinder-monitor hub.

---

## Current State - 2026-06-26

```
Status:         G5 analytics + G7 WebUI complete and demo-validated (2026-06-26)
                HUB-WATCHDOG systemd service deployed and verified
Boot:           boot=28 (post 3E-005 demo — node running unattended on wall charger)
tare_raw:       -89234.5 (boot=25, new platform, locked)
cal_factor:     36.2231 (locked, linear 200g-1800g confirmed)
sigma:          6.91g (boot=28 - noisy due to platform disturbed during noise phase)
                3.60g (boot=25 - clean reference value)
Hub state:      cylinder_state=UNINSTALLED, steel_g=None (reset after demo)
Hub modules:    main.py, ble_subscriber.py, log_transfer.py, domain.py, db.py,
                hub_logger.py, hub_watchdog.py
Hub port:       7000 (Docker, arduino@AQ3)
Docker path:    hub/config.json (baked at deploy - NOT hub/data/config.json)
Node:           ESP32-C3 SuperMini, boot=28, BLE GATT, 30s notify interval
                Running unattended on wall charger (3E-009 long-run stability experiment)
Wiring locked (do not change without re-verifying):
  ESP32-C3 GPIO4 = DOUT (SDO), GPIO3 = SCK
  HX711 VCC = 3.3V ONLY (never 5V)
  3-cell parallel: all redE+, all blackE-, all greenA+, all whiteA-
Arduino IDE locked:
  esp32 by Espressif v3.0.7, Board: ESP32C3 Dev Module
  Port: COM11, USB CDC On Boot: ENABLED
  Libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon
Domain constants - TEST values (MUST REVERT before production):
  NET_GAS_G              = 4535.0      PRODUCTION = 14200.0
  ANCHOR_GROSS_MIN_G     = 4800.0      PRODUCTION = 26000.0
  STEEL_PLAUSIBLE_MIN_G  = 200.0       PRODUCTION = 13000.0
  STEEL_PLAUSIBLE_MAX_G  = 2000.0      PRODUCTION = 18000.0
  REFILL_GROSS_MIN_G     = 5500.0      PRODUCTION = 29000.0
Time/analytics constants - TEST values (MUST REVERT before production):
  MIN_DATA_HOURS         = 0.25        PRODUCTION = 24.0
  BURN_RATE_WINDOW_DAYS  = 0.14583     PRODUCTION = 7.0
  MIN_DAYS_FOR_DAY_ALERT = 0.04167     PRODUCTION = 2.0
  ALERT_AMBER_DAYS       = 0.10417     PRODUCTION = 5.0
  ALERT_RED_DAYS         = 0.0625      PRODUCTION = 3.0
  MAX_BURN_RATE_G_PER_DAY= 100000.0    PRODUCTION = 2000.0
Permanent constants (same test and production - no revert needed):
  REMOVAL_GRACE_S        = 120.0
Node constants - TEST value (MUST REVERT before production):
  HEAVY_LOAD_THRESHOLD_G = 1000g (DEV) PRODUCTION = 2000g (requires reflash)
Completed this session:
  - HUB-WATCHDOG systemd service installed and verified
  - G5 compute_analytics: adaptive burn rate (cumulative from anchor →
    rolling window after BURN_RATE_WINDOW_DAYS)
  - Dual-condition alert logic: Condition A gram failsafe always active,
    Condition B day-based after MIN_DAYS_FOR_DAY_ALERT
  - G7 WebUI: state pill, alert banner, SENSOR OK badge, formatDays,
    < 0.1 display, UNINSTALLED shows 0g
  - IST timezone fixed on host
  - Docker container TZ fix applied in main.py (os.environ['TZ'] + time.tzset())
    — pending deploy
Current position: G5 analytics + G7 WebUI complete and demo-validated.
                  HUB-WATCHDOG fully deployed. 3E-009 long-run stability
                  experiment pending — node running unattended on wall charger
                  over weekend. 5 domain constants + 6 time/analytics constants
                  + HEAVY_LOAD_THRESHOLD_G still at TEST values — revert only
                  at final production stage.
Next action:      Deploy TZ fix (redeploy hub). Analyse 3E-009 data Monday.
                  3E-008 thermal drift after Monday. 3E-010 failure injection.
                  Then production revert + real cylinder test.
```

---

## NEVER DO (each caused a real bug — see docs/LEARNINGS.md for full history)

| Never do | Why | Context |
|----------|-----|---------|
| while(count < N) inside state case | Bridge interrupt accumulation → timeouts | STM32 bug 2026-05-05 |
| double accumulator in for loop | sum=0 on STM32U585 | STM32-specific bug |
| double array on stack in loop() | Stack corruption → hang | STM32-specific bug |
| Tare with weight on scale | cal_factor ≈ 0 → CAL_FAIL | Both platforms |
| @Bridge.on() in Python | AttributeError — doesn't exist | App Lab only |
| Bridge.notify before Python ready | Message lost silently | App Lab only |
| Hardcode threshold_g | Wrong for every environment | Both platforms |
| Hardcode cal_factor | Wrong for every load cell mounting + VOID on ESP32 | Both platforms |
| millis() guard inside state case | Stale reads | Both platforms |
| Monitor.begin() | Hangs MCU if Python handler missing | App Lab only |
| D2–D5 for HX711 on STM32 | Timer conflicts → 0x7FFFFF | STM32 ONLY, void on ESP32 |
| Use DT=D7/SCK=D6 on ESP32 | Those are STM32 timer-conflict constraints only | ESP32: pick any GPIO |
| Use cal_factor=106.7 on ESP32 | STM32 figure, VOID on ESP32-C3 | ESP32 bring-up gate |
| Skip 3.3V logic-level check | May damage ESP32-C3 GPIO or get corrupt reads | SAFETY gate |
| Use bleak service_uuids filter alone on QRB2210 | Filter ignored - returns all BLE devices | Use name filter in app layer (L-020) |
| Hardcode device MAC address | Breaks on hardware replacement/repair | Store in config.json, self-provision |
| Use "auto" BLE scan transport on QRB2210 | Kills Bluetooth adapter | Use "le" only |
| Start hub Python before BlueZ ready | BLE scan fails silently | Use After=bluetooth.target in systemd |
| RemoveDevice before Connect on fresh BLE discovery | Deletes the D-Bus object → UnknownObject error | BlueZ QRB2210 |
| "auto" transport in SetDiscoveryFilter | Kills BT adapter on QRB2210 | Hardware bug |
| deploy app without restarting socat service | dbus.sock may not exist | Hub |
| Hardcode APP_NAME in hub scripts | Read from app.yaml — folder name ≠ app name | Hub |
| List package names in requirements.txt for wheels | Must be /app/wheels/ file paths | Hub |
| Detect weight events by tick-to-tick delta in journal.cpp | journal is a service module — detection belongs in weight.cpp (computation module). Cross-module detection causes cascade events. | Node 2026-06-17 |
| Store grams in noise s_samples[] array | Double-division with noise_recompute_sigma() shrinks sigma from ~5g to 0.09g → threshold 0.36g → 200+ false WEIGHT_EVENTs | Node 2026-06-18 |
| Use hciconfig inside Docker | Not available in container — use reading_fresh only for BT health detection | Hub watchdog 2026-06-23 |
| Write config.json to hub/data/config.json | Docker mounts hub/ not hub/data/ — writes to hub/data/ have no effect (silent failure) | Hub 2026-06-24 |

---

## Known assumptions

- noise_recompute_sigma(): s_samples[] now correctly stores raw counts (fixed 2026-06-18 — see L-068). Division by cal_factor here is intentional and correct. Limitation: only valid on the standard single-boot sequence where NOISE runs before CAL. Any future recalibration flow that re-runs noise_update() after cal_factor is known must not call this function.

- health.cpp: tare_variance_raw is always 0.0f — tare.h does not yet expose variance. Stuck check (bit 1) always passes. TODO 1B-stuck: update TareResult struct to include a variance field and pass it through the orchestrator.

- health.cpp: g_prev_cal_factor and g_prev_sigma_g are set from the current boot only — no config.json persistence yet. Cal drift and erratic checks skip every boot via the -1.0f first-boot sentinel. TODO 1B-persistence: read prev values from config.json at startup (before STATE_SETTLE), write cur values to config.json after CAL_SUCCESS.

- health.cpp: noise_recompute_sigma() unit assumption (raw-count samples) is unchanged — the recomputed sigma fed into health_check() is only valid on the standard single-boot sequence. See noise_recompute_sigma() assumption above.
