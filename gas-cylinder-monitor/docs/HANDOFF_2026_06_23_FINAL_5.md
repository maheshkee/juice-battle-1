# SESSION HANDOFF — 2026-06-23 FINAL_5
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_22_FINAL_3.md

---

## How to use this document
Read this file fully before responding. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
CAL timeout fix complete and verified on boot=8. g_cal_degraded flag
implemented and working. G4 hub domain logic is next — design fully locked
in this document. Node is healthy. Hub is running.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify+cmd)
→ UNO Q AQ3 hub (Python, BlueZ, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp, computes gas%.
Gas% = (gross − steel) / 14200 × 100. Never computed on node.

---

## Hardware — locked

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3, IP 192.168.88.20 |
| ESP32-C3 SuperMini | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, 3.3V VCC ONLY |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | Fibre plate, 3 cells at 3 corners |
| Wiring | Direct twisted/soldered — NOT breadboard |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V |
| GND | GND | |
| GPIO4 | SDO (DOUT) | INPUT_PULLUP mandatory |
| GPIO3 | SCK | OUTPUT |

### 3-cell parallel wiring
All 3 red → E+ | All 3 black → E− | All 3 green → A+ | All 3 white → A−

---

## Arduino IDE — locked

- Package: esp32 by Espressif v3.0.7 (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- Libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon

---

## Flash recovery procedure (locked)

If normal flash fails consistently at same percentage:
1. Try again once — may be transient
2. If still failing: lower Upload Speed to 115200 in Tools menu — flash again
3. NEVER use "Erase All Flash" to fix flash failures — it wipes 2nd stage bootloader
4. If chip is already erased and no COM port visible:
   - Check Device Manager — USB Serial/JTAG controller may still enumerate
   - Use esptool directly with --no-stub and merged.bin at 115200
   - merged.bin: C:\Users\mahes\AppData\Local\arduino\sketches\[hash]\gas_monitor_v1.ino.merged.bin
   - Command: esptool.exe --chip esp32c3 --port COMX --baud 115200 --no-stub write_flash 0x0 [merged.bin]

---

## Locked values — hardware verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | 36.2231 raw/g (boot=7, boot=8) | VERIFIED |
| cal_factor (session 6 and prior) | 36.2689 raw/g | VERIFIED |
| cal_factor range (this platform) | 34.47–36.27 raw/g | VERIFIED |
| sigma (boot=8) | 3.10g | VERIFIED |
| sigma healthy range | 2.96–6.92g across boots | VERIFIED |
| NOISE_SIGMA_PASS_G | 8.0g | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0g | LOCKED |
| BUF_SIZE (delay-line) | 40 ticks = 4 seconds | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| CAL timeout (new) | 120s → 36.0 fallback | LOCKED |
| CAL fallback value | 36.0 raw/g | LOCKED |
| Boot time (SPIFFS fast-load path) | ~103.8s | VERIFIED |
| Node boot count at session end | boot=8 | VERIFIED |

### Hub constants locked
| Constant | Value | Note |
|---|---|---|
| DAILY_USE_DEFAULT_G | 350.0 | V1 prior — L-064 |
| ALERT_AMBER_G | 2000.0 | ~5-6 days at 350g/day |
| ALERT_RED_G | 1000.0 | ~2-3 days at 350g/day |
| MIN_HISTORY_DAYS | 7 | statistical minimum |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0 | from observed ±15g platform noise |
| ANCHOR_STABILITY_WINDOW_G | 50.0 | TODO: tighten after 3E-009 |
| ANCHOR_MIN_GROSS_G | 26000.0 | fresh full cylinder detection threshold |
| STEEL_UNKNOWN_PRIOR_G | 16500.0 | conservative prior — partial unknown install |
| HEAVY_LOAD_THRESHOLD_G | 5000.0 | node self-protect during TARE_WAIT |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Weight char:     b9b25bb1-f2a9-4545-b48f-295ab2789f41  (notify)
Command char:    c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b  (write-without-response)
Log char:        d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c  (notify)
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
Weight payload:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
Command format:  ASCII string, NO trailing newline e.g. "TARE" "SKIP_TARE" "SET_CAL:36.2231"
```

---

## Boot sequence — locked

```
SETTLE (2s autonomous)
  → TARE_WAIT (hub commands TARE or SKIP_TARE, 60s timeout)
    → [self-protect on timeout: if heavy load detected, use saved tare — see N-TARE-CHECK]
      → TARE (N=200 fresh, or load from SPIFFS if SKIP_TARE)
        → [N-TARE-CHECK] (compare fresh tare vs saved)
          → NOISE (autonomous)
            → CAL (hub sends SET_CAL, or load SPIFFS, or 120s timeout → 36.0 fallback)
              → RUNNING
```

---

## Node layer status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE |
| 1C — Timing instrumentation | ✅ COMPLETE |
| 1D — Structured Serial journal | ✅ COMPLETE |
| BLE command characteristic | ✅ COMPLETE |
| STATE_TARE_WAIT | ✅ COMPLETE — 60s timeout, delay(10) watchdog fix |
| Tare SPIFFS save/load | ✅ COMPLETE |
| STATE_RETARE | ✅ COMPLETE (stub) |
| N-TARE-CHECK | ✅ COMPLETE — 1000g threshold (DEV); restore 2000g before production |
| NimBLE advertising restart | ✅ COMPLETE |
| N1 — Journal → SPIFFS | ✅ COMPLETE — file_bytes accumulation verified |
| 1E — BLE log streaming | ✅ COMPLETE — full pipeline verified boot=6 |
| CAL timeout fallback (120s → 36.0) | ✅ COMPLETE — boot=8 verified |
| g_cal_degraded flag | ✅ COMPLETE — BLE payload override only, journal unaffected |
| SET_CAL accepted in STATE_RUNNING | ✅ COMPLETE — sanity gate 30.0–45.0g |
| N-TARE-CHECK hub-offline extension | ❌ NOT BUILT — pre-production required |
| TODO 1B-stuck | ❌ DEFERRED |
| TODO 1B-persistence | ❌ DEFERRED |

---

## Hub layer status

| Component | Status |
|---|---|
| BLE subscriber | ✅ WORKING — auto-reconnects |
| WebUI | ✅ LIVE at 192.168.88.20:7000 |
| SQLite | ✅ RUNNING |
| DEV mode auto-anchor | ✅ WORKING |
| PROD mode scaffold | ✅ WORKING |
| DEV/PROD toggle | ✅ WORKING |
| Two-level alerts | ✅ WORKING |
| node_status topbar | ✅ WORKING |
| IST timestamp | ✅ WORKING |
| Log directory | ✅ COMPLETE — logs/node/ saves per transfer |
| Log char subscription | ✅ COMPLETE |
| DUMP_LOG trigger | ✅ COMPLETE — fires 5s after connect |
| CLEAR_LOG after verify | ✅ COMPLETE |
| Duplicate connect guard | ✅ COMPLETE — _connecting flag |
| Duplicate LOG_START guard | ✅ COMPLETE |
| Gas domain logic (G4) | ❌ NOT BUILT — NEXT |
| HUB-WATCHDOG | ❌ NOT BUILT — pre-production required |

---

## g_cal_degraded — design locked (session 2026-06-23)

```
Global:  static bool g_cal_degraded = false;

Set true:   CAL timeout fires (120s, no hub, no SPIFFS)
            → g_cal_factor = 36.0f
            → g_cal_degraded = true

Set false:  SET_CAL received in STATE_RUNNING
            → g_cal_factor = new value
            → g_cal_degraded = false

BLE payload builder:
    const char* quality_out = g_cal_degraded ? "DEGRADED" : g_health.quality;
    // only payload sees override — journal always records true hardware health

Journal:    always receives g_health.quality directly — ground truth preserved
```

Key principle: hardware health and calibration confidence are independent signals.
g_health.quality = hardware health (health_check() owns it)
g_cal_degraded   = calibration confidence (CAL state machine owns it)
Never conflate them.

---

## Anomaly flagged — deferred

boot=6, t≈4678: Two DUMP_LOG commands received as "Unknown command" before
a third DUMP_LOG was accepted correctly. Hub _connecting guard did not prevent
duplicate sends on this reconnect. Not a data integrity issue — idempotent
command, duplicate transfer guard caught it. Investigate after G4.

---

## G4 — FULL DESIGN LOCKED (do not re-derive in next session)

### G4 overview
G4 is entirely hub-side Python. No node firmware changes required.
G4 adds: brand/install setup, steel derivation, state machine, gas% calculation,
bootstrap regimes, production robustness cross-checks.

---

### G4.1 — Install modes (four paths)

User sees a setup screen on first launch (state=UNINSTALLED).
Three buttons — one choice required before system can track:

```
[ Fresh / Full cylinder ]
    → BOOTSTRAP_ANCHOR state
    → wait for gross > 26000g stable window
    → steel_g = mean(window) - 14200
    → steel_source = "ANCHOR"
    → transitions to TRACKING on anchor event

[ Partially used — I know my brand ]
    → shows sub-buttons: [ Indane ] [ HP ] [ Bharat ]
    → BOOTSTRAP_LOOKUP state
    → steel_g = lookup_table[brand]
    → steel_source = "LOOKUP"
    → transitions to TRACKING immediately (gas% live from first reading)
    → self-corrects to ANCHOR on next fresh cylinder

[ Partially used — brand unknown ]
    → BOOTSTRAP_PRIOR state
    → steel_g = STEEL_UNKNOWN_PRIOR_G = 16500.0g  (conservative)
    → steel_source = "PRIOR"
    → transitions to TRACKING immediately
    → self-corrects to ANCHOR on next fresh cylinder
```

Why 16500g (conservative, not midpoint 15000g):
Underestimating gas remaining is safer than overestimating.
User orders refill slightly early = mild inconvenience.
User runs out of gas unexpectedly = much worse outcome.
Lean toward showing less gas than actual.

WebUI approximate indicator (shown when steel_source != "ANCHOR"):
- LOOKUP: "~67% remaining  ✦ Estimated — improves after next refill"
- PRIOR:  "~58% remaining  ✦ Rough estimate — select brand or wait for next refill"
- ANCHOR: "67% remaining"  (no indicator — full accuracy)
Tilde prefix + footnote. No alarm language. Honest and actionable.

---

### G4.2 — Brand lookup table

```python
BRAND_STEEL_G = {
    "Indane": 15300.0,
    "HP":     14900.0,
    "Bharat": 15100.0,
}
# Values are population averages. Individual cylinders vary ±200-300g.
# Used ONLY for BOOTSTRAP_LOOKUP. Not used when steel_source=ANCHOR.
# TODO: validate against measured steel_g values after 3E-005
```

Brand stored in config.json as string key "brand".
Setup endpoint: POST /api/config/brand  {"brand": "Indane"}
G7 replaces this endpoint with logo picker UI — same backend.

---

### G4.3 — Steel derivation (windowed average)

```python
ANCHOR_MIN_GROSS_G        = 26000.0   # fresh full cylinder threshold
ANCHOR_STABILITY_WINDOW_G = 50.0      # max spread across window
                                       # TODO: tighten after 3E-009
ANCHOR_MIN_READINGS       = 5         # minimum stable readings required

# Logic (runs every reading in BOOTSTRAP_ANCHOR or on fresh cylinder detection):
if gross_g > ANCHOR_MIN_GROSS_G:
    add gross_g to candidate_window
    if len(window) >= ANCHOR_MIN_READINGS:
        spread = max(window) - min(window)
        if spread < ANCHOR_STABILITY_WINDOW_G:
            steel_g = mean(window) - 14200.0
            → validate steel_g (see G4.4)
            → save to config, transition to TRACKING
else:
    clear candidate_window  # reset on any reading below threshold
                            # prevents partial windows from transient loads
```

Why windowed average not single reading:
steel_g is a permanent constant for 45-60 day cylinder lifetime.
A single reading's noise bakes error into every gas% permanently.
N=5 readings reduces noise by sqrt(5) ≈ 2.2x.
Stability gate filters transient disturbances simultaneously.
Same window serves dual purpose: stability confirmation + steel_g mean.

---

### G4.4 — Anchor validation (sanity check)

After deriving steel_g from anchor:

```python
STEEL_PLAUSIBLE_MIN_G = 13000.0
STEEL_PLAUSIBLE_MAX_G = 18000.0

if not (STEEL_PLAUSIBLE_MIN_G <= steel_g <= STEEL_PLAUSIBLE_MAX_G):
    log warning: "Anchor rejected — steel_g={} out of plausible range"
    clear candidate_window
    do NOT transition — keep waiting
    # Could be wrong object, corrupt reading, platform not empty at tare
```

---

### G4.5 — State machine (explicit states)

```
UNINSTALLED
    ↓ user completes install setup
BOOTSTRAP_ANCHOR   ← fresh cylinder path, waiting for stable > 26kg
BOOTSTRAP_LOOKUP   ← partial + brand known, lookup table active
BOOTSTRAP_PRIOR    ← partial + unknown brand, 16500g prior active
    ↓ fresh cylinder anchor event fires (any bootstrap state)
TRACKING           ← exact steel_g from BIS anchor, full accuracy
    ↓ gas_g < ALERT_AMBER_G
LOW_GAS            ← same calculation as TRACKING, alerts active
    ↓ gas_g < ALERT_RED_G × 0.15 (future)
EMPTY              ← future stub
```

Transitions (complete):
```
UNINSTALLED      → BOOTSTRAP_*   : user selects install mode
BOOTSTRAP_ANCHOR → TRACKING      : anchor event — stable window > 26kg
BOOTSTRAP_LOOKUP → TRACKING      : anchor event — self-corrects from lookup
BOOTSTRAP_PRIOR  → TRACKING      : anchor event — self-corrects from prior
TRACKING         → LOW_GAS       : gas_g drops below ALERT_AMBER_G
LOW_GAS          → TRACKING      : refill — gross > 26kg, re-anchor, new steel_g
LOW_GAS          → EMPTY         : gas_g < 2% (future stub)
TRACKING         → UNINSTALLED   : cylinder removed — gross drops near zero
LOW_GAS          → UNINSTALLED   : cylinder removed in low gas condition
ANY              → BOOTSTRAP_ANCHOR : fresh cylinder detected after removal
```

Gas% computed ONLY in TRACKING and LOW_GAS:
```python
gas_g   = gross_g - steel_g
gas_pct = gas_g / 14200.0 * 100.0
```
Never computed in UNINSTALLED or BOOTSTRAP states.

Alerts evaluated in TRACKING and LOW_GAS:
```python
if gas_g < ALERT_RED_G:    alert_level = "RED"
elif gas_g < ALERT_AMBER_G: alert_level = "AMBER"
else:                        alert_level = "NORMAL"
```

---

### G4.6 — config.json schema (hub side)

```json
{
  "brand": "Indane",
  "install_mode": "FRESH",
  "steel_source": "ANCHOR",
  "steel_g": 15243.0,
  "steel_anchored_at": "2026-06-23T14:32:00+05:30",
  "cylinder_state": "TRACKING",
  "cal_factor": 36.2231,
  "tare_raw": -107303.2,
  "cal_tare_session": "2026-06-22T10:15:00+05:30"
}
```

cal_factor + tare_raw always stored as a PAIR with timestamp.
Hub is source of truth. Node SPIFFS is a cache.
If SPIFFS is corrupt or empty, hub restores from this file via SET_CAL + SKIP_TARE.

---

### G4.7 — Production robustness cross-checks

**Cross-check 1 — First reading after SKIP_TARE (reflash detection):**
```python
# Fires on first reading after hub sends SKIP_TARE
if cylinder_state == "TRACKING":
    expected_min = steel_g + 0           # cylinder could be nearly empty
    expected_max = steel_g + 14200       # cylinder could be full
    tolerance    = 3000.0                # generous for drift + noise

    if gross_g < expected_min - tolerance:
        log warning: "Gross implausibly low — possible reflash or disturbance"
        transition to UNINSTALLED
        WebUI: "Platform reading unexpected. Please re-run setup."
```

This catches: sketch reflash (wipes SPIFFS), severe platform disturbance,
corrupt tare_raw from SPIFFS. Self-healing — user re-runs setup, system recovers.

**Cross-check 2 — Hub offline at node boot (Scenario A):**
This is a NODE-SIDE fix — see N-TARE-CHECK extension below.
Hub cannot protect against this. Node must self-protect.

---

### G4.8 — Files to create/modify in G4

Read these files first before touching anything:
```
~/ArduinoApps/gas-cylinder-monitor/hub/python/main.py
~/ArduinoApps/gas-cylinder-monitor/hub/python/ble_subscriber.py
~/ArduinoApps/gas-cylinder-monitor/hub/python/db.py
~/ArduinoApps/gas-cylinder-monitor/hub/assets/index.html
~/ArduinoApps/gas-cylinder-monitor/hub/app.yaml
```

Expected changes:
```
main.py          — state machine, gas% calc, anchor logic, cross-checks,
                   install mode handler, brand endpoint
db.py            — new columns: cylinder_state, steel_g, steel_source,
                   brand, install_mode, gas_pct, alert_level
index.html       — install setup screen (four paths), approximate indicator,
                   gas% display wired to real calculation
config.json      — new schema (G4.6 above) — create if not exists
```

---

## N-TARE-CHECK extension — pre-production node fix

**Problem:** Hub offline at node boot. TARE_WAIT times out (60s). Node performs
fresh tare. If cylinder is on platform, fresh tare zeroes out the cylinder weight.
Cal_factor loaded from SPIFFS is now paired with a wrong tare_raw. All readings
wrong by ~29000g. Hub comes online later and sees gross ≈ 0g despite TRACKING.

**Fix (node-side, gas_monitor_v1.ino):**
In the TARE_WAIT timeout handler, before executing fresh tare:

```cpp
// If SPIFFS has saved tare_raw and cal_factor, compute approximate gross
// to detect if a heavy load is present on the platform.
// If heavy load detected: do NOT fresh tare — load saved tare instead.
// Prevents zeroing out a cylinder when hub is offline at boot.

float saved_tare = tare_load_from_spiffs();
float saved_cal  = cal_load_last();

if (saved_tare != 0.0f && saved_cal > 0.0f) {
    float approx_gross = (current_raw - saved_tare) / saved_cal;
    if (approx_gross > HEAVY_LOAD_THRESHOLD_G) {  // 5000g
        // Heavy load present — hub offline — use saved tare
        g_tare_raw = saved_tare;
        g_cal_factor = saved_cal;
        g_cal_degraded = true;  // hub offline — flag as degraded
        journal: "TARE_WAIT timeout, heavy load detected, using saved tare, hub offline"
        // proceed to NOISE → CAL (CAL will load from SPIFFS too)
    }
    // else: approx_gross low — platform appears empty — fresh tare is correct
}
```

When hub comes online later: sends SET_CAL → g_cal_degraded clears.
Hub cross-check 1 catches any implausible reading and transitions to UNINSTALLED if needed.

This fix is NOT part of G4. It is a separate node flash. Schedule after G4.

---

## Cal_factor production robustness — architecture locked

```
Source hierarchy (priority order at every boot):

1. Hub sends SET_CAL             ← always if hub online at boot
   (hub config.json has paired cal_factor from original session)

2. SPIFFS cache                  ← fallback if hub offline
   (restored from last SET_CAL received)

3. 120s timeout → 36.0 fallback ← last resort
   g_cal_degraded = true
   hub corrects as soon as it connects

Refresh events:
   Every boot (hub sends SET_CAL)
   Every fresh cylinder anchor (hub derives new cal_factor awareness)
   After 3E-008: consider periodic drift correction in V2

Hub config.json is the source of truth.
Node SPIFFS is a recoverable cache.
```

---

## HUB-WATCHDOG — pre-production required (design unchanged)

WCN3990 Qualcomm chip firmware crash (hardware error 0x00) confirmed.
bluetoothctl power on returns "Failed to set power on" — only sudo reboot recovers.
Three escalation levels — see HANDOFF_2026_06_18_FINAL_2.md for full design.
MUST BE BUILT before production deployment.

---

## Critical BLE fixes — carry forward always

Fix 1 — Match by Name not UUID on QRB2210
Fix 2 — Cached devices don't re-trigger InterfacesAdded
Fix 3 — NimBLE advertising must restart on disconnect
Fix 4 — hcitool lescan always fails on QRB2210
Fix 5 — App Lab WebUI on_message callbacks need (sid, data)
Fix 6 — hub write_command must strip newline before WriteValue
Fix 7 — BLESubscriber._connecting guard prevents duplicate connect
Fix 8 — on_log_line LOG_START guard prevents duplicate transfer
Fix 9 — delay(10) in STATE_TARE_WAIT prevents FreeRTOS watchdog starvation

---

## Build order — locked

```
1. G4 hub domain logic          ← NEXT (this session)
2. N-TARE-CHECK extension       ← node flash, after G4
3. 3E-005 anchor validation     ← end-to-end proof, hub derives steel
4. 3E-008 temperature drift     ← characterise cal_factor drift with heat
5. 3E-009 6hr stability         ← characterise drift budget over duty cycle
6. 3E-010 failure injection     ← verify health module catches open cell
7. G5 analytics                 ← burn rate from real data, days remaining
8. HUB-WATCHDOG                 ← mandatory before production
9. WebUI G7                     ← full dashboard, logo picker, three-tab
```

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/
│       ├── gas_monitor_v1.ino
│       ├── hx711.h / hx711.cpp
│       ├── tare.h  / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h   / cal.cpp
│       ├── weight.h / weight.cpp
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp
│       ├── journal.h / journal.cpp
│       ├── log_transfer.h / log_transfer.cpp
├── hub/
│   ├── app.yaml
│   ├── deploy.sh
│   ├── assets/index.html
│   ├── data/monitor.db
│   ├── data/config.json          ← G4 will populate this fully
│   ├── logs/
│   │   └── node/
│   └── python/
│       ├── main.py
│       ├── ble_subscriber.py
│       └── db.py
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── HANDOFF_2026_06_18_FINAL_2.md
    ├── HANDOFF_2026_06_22_FINAL_3.md
    └── HANDOFF_2026_06_23_FINAL_5.md  ← this file
```

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Named constants only. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Build order discipline | Verify each layer before building on top. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". |
| BLE on QRB2210 | Match by Name not UUID. Always check known devices on connect. |
| NimBLE onWrite signature | Always two parameters: (NimBLECharacteristic* c, NimBLEConnInfo& connInfo) |
| NimBLE advertising restart | Always restart in onDisconnect(). Non-negotiable. |
| write_command | Always strip newline before WriteValue |
| Flash erase | Never use Erase All Flash — lower baud to 115200 instead |
| CLEAR_LOG | Hub must verify file exists and size > 0 BEFORE sending CLEAR_LOG |
| Log transfer pacing | One line per HX711 DOUT event (~10Hz) |
| TARE_WAIT yield | delay(10) mandatory — prevents FreeRTOS watchdog |
| g_cal_degraded | Overrides BLE payload only. Journal always records true hardware health. |
| steel_source | Always tag steel_g with its source: ANCHOR / LOOKUP / PRIOR |
| Approximate indicator | Show when steel_source != ANCHOR. Never hide uncertainty from user. |
| ANCHOR_STABILITY_WINDOW_G | Named constant with TODO comment — tune after 3E-009 |

---

## Learnings from this session (to append to LEARNINGS_AND_INSIGHTS.md)

L-071: g_cal_degraded is a calibration confidence flag, not a hardware health
flag. These are independent signals. g_health.quality = hardware health, owned
by health_check(). g_cal_degraded = calibration confidence, owned by CAL state
machine. BLE payload uses g_cal_degraded to override quality when cal is a
fallback. Journal always records true hardware health. Never conflate them.

L-072: SET_CAL accepted mid-session in STATE_RUNNING is correct because
cal_factor is a pure mathematical scalar, not a physical zero reference.
Swapping it mid-session means "use this better conversion ratio from now."
No physical reality is violated. tare_raw cannot be swapped mid-session —
it encodes physical state and requires a deliberate RETARE event.

L-073: Windowed average for steel_g derivation is mandatory because steel_g
is a permanent constant for the cylinder lifetime (~45-60 days). A single
noisy reading bakes platform drift error into every gas% permanently.
N stable readings reduce noise by sqrt(N) and the stability gate filters
transient disturbances simultaneously. One mechanism solves two problems.

L-074: Explicit state machine (UNINSTALLED/BOOTSTRAP_*/TRACKING/LOW_GAS/EMPTY)
is correct over a flat alert-flag model. Future features (duty cycle changes,
watchdog escalation, prediction gating, EMPTY detection) need clean state
boundaries. Adding states is additive. Flags inside a flat model become
tangled over time.

L-075: Conservative prior (STEEL_UNKNOWN_PRIOR_G = 16500g) is correct over
midpoint (15000g) for unknown-brand partial cylinder install. The two error
modes are asymmetric: underestimating gas = user orders refill early (mild
inconvenience). Overestimating gas = user runs out mid-cooking (much worse).
Always lean toward showing less gas than actual when calibration is uncertain.

L-076: The lookup table earns its place specifically for the partial-cylinder
cold-start scenario — not for normal tracking. When a fresh cylinder is present,
the BIS anchor (steel = gross - 14200) is 130x more accurate than any lookup.
The lookup is a bootstrap prior only. After first fresh cylinder, the anchor
replaces it permanently. Two separate regimes: bootstrap (lookup) and tracked
(anchor). Never mix them.

L-077: Hub offline at TARE_WAIT timeout is a real production failure mode.
Node falls back to fresh tare — correct for empty platform, catastrophic if
cylinder present. Fix: node reads current raw during TARE_WAIT, computes
approximate gross using saved SPIFFS tare_raw and cal_factor. If approx_gross
> HEAVY_LOAD_THRESHOLD_G (5000g), use saved tare instead of fresh tare.
Node self-protects without hub involvement. Hub cross-check catches any
residual error on reconnect.

---

## Session summary (to append to SESSIONS.md)

Session date: 2026-06-23
Goal: CAL timeout fix + g_cal_degraded flag + G4 full design
What was built:
  - 120s timeout in STATE_CAL → 36.0g fallback → g_cal_degraded = true
  - SET_CAL accepted in STATE_RUNNING — updates cal_factor and sigma immediately
  - g_cal_degraded = false when real SET_CAL received
  - g_cal_degraded overrides BLE payload quality only
  - Journal always records true hardware health (g_health.quality unaffected)
  - g_cal_factor sanity gate in RUNNING: 30.0–45.0g rejects corrupt values
  - G4 full design locked: install modes, state machine, steel derivation,
    lookup table, bootstrap regimes, conservative prior, production cross-checks
What was verified on hardware:
  - boot=8: CAL SPIFFS fast-load path — cal_factor=36.2231 loaded in 0.1s
  - quality=GOOD throughout — g_cal_degraded correctly false when SPIFFS valid
  - Sigma boot=8 = 3.10g — healthy
  - DUMP_LOG / CLEAR_LOG pipeline working on boot=8
Gate result: CAL timeout fix VERIFIED. G4 design LOCKED.
Node boot count at session end: boot=8

---

## Windows laptop setup

SCP path: C:\Users\mahes\Documents\Arduino\
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED
Upload Speed: 921600 (normal) / 115200 (fallback)

---

## Hub deploy commands

```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh
docker logs gas-cylinder-monitor-hub-main-1 | grep -E "\[LOG\]|\[BLE_SUB\]|\[G4\]" | tail -20
bluetoothctl power off && sleep 2 && bluetoothctl power on
sudo reboot   # if bluetoothctl power on fails (WCN3990 crash)
```

---

## Session start checklist

1. Read this document fully
2. Confirm working mode: chat = design only, CLI = code only
3. Current position: G4 hub domain logic is next
4. Hub running: bash deploy.sh if needed, WebUI at 192.168.88.20:7000
5. Node: boot=8, gas_monitor_v1 with CAL timeout + g_cal_degraded flashed
6. N-TARE-CHECK threshold: currently 1000g (DEV) — restore 2000g before production
7. First action: read main.py, ble_subscriber.py, db.py before writing anything
8. G4 design is fully locked in this document — do not re-derive

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_23_FINAL_5.md fully before responding.
Context: CAL timeout fix complete and verified on boot=8.
g_cal_degraded flag working — journal sees true hardware health,
BLE payload sees DEGRADED when cal is a fallback.
Today: build G4 hub domain logic.
All G4 design decisions are fully locked in this handoff under
the G4 section — read them before touching any file.
Start by reading main.py, ble_subscriber.py, db.py on AQ3,
then confirm what G4 needs to add or change in each file
before writing a single line of code."

---

*End of handoff. Next chat is ready.*
