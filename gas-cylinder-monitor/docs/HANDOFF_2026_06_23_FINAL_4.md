# SESSION HANDOFF — 2026-06-23 FINAL_4
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_22_SESSION7_1E_BLE_LOG_STREAMING.md

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
CAL timeout fix complete and verified on boot=8. g_cal_degraded flag implemented.
G4 domain logic is next.

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
| Arduino UNO Q AQ3 | arduino@AQ3, IP 192.168.1.161 |
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
Direct to HX711. Twisted or soldered. NOT breadboard.

---

## Arduino IDE — locked

- Package: esp32 by Espressif v3.0.7 (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- Libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon
- NimBLE onWrite ALWAYS two parameters: (NimBLECharacteristic* c, NimBLEConnInfo& connInfo)

---

## Locked values — hardware verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | 36.2689 raw/g (loaded from SPIFFS) | VERIFIED |
| cal_factor range (this platform) | 34.47–36.27 raw/g | VERIFIED |
| sigma healthy range | 3.16–5.44g across boots | VERIFIED |
| NOISE_SIGMA_PASS_G | 8.0g | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0g | LOCKED |
| BUF_SIZE (delay-line) | 40 ticks = 4 seconds | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| tare_raw empty platform | -105,000 to -106,000 raw counts | VERIFIED |
| zero accuracy | ~±5g | VERIFIED |
| weight accuracy | ±6g on 1000g | VERIFIED |
| Boot time (timeout path) | ~103.9s | VERIFIED |
| Node boot count (session end) | boot=8 | VERIFIED |

### Hub constants locked
| Constant | Value | Note |
|---|---|---|
| DAILY_USE_DEFAULT_G | 350.0 | V1 prior — see L-064 |
| ALERT_AMBER_G | 2000.0 | ~5-6 days at 350g/day |
| ALERT_RED_G | 1000.0 | ~2-3 days at 350g/day |
| MIN_HISTORY_DAYS | 7 | statistical minimum — never dynamic |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0 | from observed ±15g platform noise |

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
Command format:  ASCII string without trailing newline e.g. "TARE" "SKIP_TARE" "SET_CAL:36.2689"
```

---

## Boot sequence — locked

```
SETTLE (2s autonomous)
  → TARE_WAIT (hub commands TARE or SKIP_TARE, 60s timeout)
    → TARE (N=200 fresh, or load from SPIFFS if SKIP_TARE)
      → [N-TARE-CHECK] (compare fresh tare vs saved — detect load on platform)
        → NOISE (autonomous, uses saved cal_factor for gram units)
          → CAL (hub sends SET_CAL, or load SPIFFS, or 120s timeout → 36.0 fallback + g_cal_degraded=true)
            → RUNNING
```

Hub is decision maker. Node never decides tare path alone.
SKIP_TARE always paired with matching SET_CAL from same original session.
SET_CAL accepted in STATE_RUNNING — updates g_cal_factor in place, clears g_cal_degraded.

---

## Node layer status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE (skip_stuck guard in place) |
| 1C — Timing instrumentation | ✅ COMPLETE |
| 1D — Structured Serial journal | ✅ COMPLETE |
| BLE command characteristic | ✅ COMPLETE — TARE/SKIP_TARE/SET_CAL/RETARE/DUMP_LOG/CLEAR_LOG |
| STATE_TARE_WAIT | ✅ COMPLETE — 60s timeout, verified multiple boots |
| Tare SPIFFS save/load | ✅ COMPLETE |
| STATE_RETARE | ✅ COMPLETE (stub — hub side not built) |
| N-TARE-CHECK | ✅ COMPLETE — 1000g threshold (DEV); production = 2000g |
| NimBLE advertising restart | ✅ COMPLETE — restarts on disconnect |
| N1 — Journal → SPIFFS | ✅ COMPLETE — journal_append, g_journal_file_bytes, g_transfer_pending |
| 1E — BLE log streaming | ✅ COMPLETE — DUMP_LOG/stream/LOG_END/CLEAR_LOG pipeline verified |
| CAL timeout fallback | ✅ COMPLETE — 120s → 36.0 fallback → g_cal_degraded=true |
| g_cal_degraded flag | ✅ COMPLETE — overrides BLE payload quality; journal sees true health |
| TODO 1B-stuck | ❌ DEFERRED |
| TODO 1B-persistence | ❌ DEFERRED |

---

## Hub layer status

| Component | Status |
|---|---|
| BLE subscriber | ✅ WORKING — auto-reconnects |
| WebUI | ✅ LIVE at 192.168.1.161:7000 |
| SQLite | ✅ RUNNING — readings stored |
| DEV mode auto-anchor | ✅ WORKING — 3-reading spread window, spurious re-anchor fixed |
| PROD mode scaffold | ✅ WORKING — Calibrating... placeholder |
| DEV/PROD toggle | ✅ WORKING — WebUI pill, SQLite flag |
| Two-level alerts | ✅ WORKING — amber pct<20%, red grams<50g |
| node_status topbar | ✅ WORKING — green dot, MAC, name |
| IST timestamp | ✅ WORKING |
| Log directory | ✅ COMPLETE — logs/node/ created, files saved per transfer |
| Gas domain logic (Group 4) | ❌ NOT BUILT — NEXT |
| HUB-WATCHDOG | ❌ NOT BUILT — PRE-PRODUCTION REQUIRED |

---

## HUB-WATCHDOG — pre-production required (design locked)

WCN3990 Qualcomm chip can firmware-crash (hardware error 0x00).
No software recovery possible — only sudo reboot works.
Proven in session 2026-06-18. See L-065, L-070.

Three escalation levels:
- Level 1 (0-2 min failure): bluetoothctl power on → restart bluetooth → retry
- Level 2 (2-5 min failure): modprobe -r btusb && modprobe btusb → restart → retry
- Level 3 (>10 min failure): write /tmp/reboot_requested → host systemd reboots

Reboot mechanism: Docker container writes trigger file, host systemd service reboots.
Constants: BT_FAILURE_SOFT=120s, BT_FAILURE_ADAPTER=300s, BT_FAILURE_REBOOT=600s.
MUST BE BUILT before device goes into a production kitchen.

---

## Critical BLE fixes — carry forward always

### Fix 1 — Match by Name not UUID on QRB2210
UUIDs in InterfacesAdded payload are empty until ServicesResolved.
Fix: match on device Name in _interfaces_added().

### Fix 2 — Cached devices don't re-trigger InterfacesAdded
Fix: _check_known_devices() called after every StartDiscovery().

### Fix 3 — NimBLE advertising must restart on disconnect
Fix: NimBLEDevice::startAdvertising() in onDisconnect() callback.
Without this: node invisible after every hub reconnect.

### Fix 4 — hcitool lescan always fails on QRB2210
Use bluetoothctl to diagnose BLE issues. Never hcitool.

### Fix 5 — App Lab WebUI on_message callbacks need (sid, data)
def on_set_dev_mode(sid, data) — NOT def on_set_dev_mode(data).

### Fix 6 — write_command must strip trailing newline
hub write_command: cmd_clean = cmd.strip() before WriteValue.
Node strcmp requires exact match without \n.

### Fix 7 — delay(10) mandatory in STATE_TARE_WAIT
Without yield: FreeRTOS watchdog fires at ~12s (IDLE task starvation).
delay(10) per tick is sufficient — does not affect command response time.

---

## g_cal_degraded — calibration confidence flag (2026-06-23)

g_cal_degraded is separate from hardware health (g_health.quality).

| Signal | Owner | Meaning |
|---|---|---|
| g_health.quality | health_check() | Hardware health — sensor, wiring, stability |
| g_cal_degraded | CAL state machine | Calibration confidence — is cal_factor real or fallback? |

Rules:
- g_cal_degraded = true when STATE_CAL times out at 120s → uses 36.0 fallback
- g_cal_degraded = false when real SET_CAL received (in STATE_CAL or STATE_RUNNING)
- BLE payload quality: overridden to DEGRADED when g_cal_degraded = true
- Journal: always records true hardware health — never masked by g_cal_degraded
- SET_CAL accepted in STATE_RUNNING: swaps g_cal_factor in place, clears g_cal_degraded

cal_factor is a pure mathematical scalar. Swapping it mid-session is safe.
tare_raw cannot be swapped mid-session — it encodes physical zero reference state.

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino    ← orchestrator + state machine
│       ├── hx711.h / hx711.cpp   ← raw bit-bang
│       ├── tare.h  / tare.cpp    ← tare + N-TARE-CHECK + SPIFFS
│       ├── noise.h / noise.cpp   ← noise floor (raw counts)
│       ├── cal.h   / cal.cpp     ← cal_factor + SPIFFS
│       ├── weight.h / weight.cpp ← rolling mean + delay-line (BUF_SIZE=40)
│       ├── ble.h   / ble.cpp     ← weight notify + command char + log char + g_mtu_ready
│       ├── health.h / health.cpp ← health checks (skip_stuck guard)
│       ├── journal.h / journal.cpp ← serial + SPIFFS event log
│       ├── log_transfer.h / log_transfer.cpp ← DUMP_LOG FSM (IDLE/SENDING/DONE)
│       └── config.json           ← cal_history, tare_raw, cal_factor, boot counter
├── hub/
│   ├── app.yaml
│   ├── deploy.sh                 ← includes BT power-on, passwordless after setup
│   ├── setup_sudoers.sh          ← run once on new device: sudo bash setup_sudoers.sh
│   ├── DEVICE_SETUP.md           ← one-time commissioning guide
│   ├── assets/index.html         ← WebUI with topbar, toggle, alerts
│   ├── data/monitor.db           ← SQLite (readings + config tables)
│   ├── logs/node/                ← node journal files per transfer
│   └── python/
│       ├── main.py               ← DEV/PROD mode, anchor, alerts, node_status, log handler
│       ├── ble_subscriber.py     ← BlueZ D-Bus, log char, cmd char, _connecting guard
│       └── db.py                 ← SQLite abstraction + dev_mode functions
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md ← last entry L-085
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_23_FINAL_4.md ← this file
```

---

## Next session build order

```
1. G4 hub domain logic                            ← NEXT
   Brand config, steel derivation, state machine,
   gas% calculation, anchor trigger Option B

2. 3E-005 anchor validation experiment

3. 3E-008 temperature drift experiment

4. 3E-009 6-hour stability soak

5. 3E-010 failure injection test

6. G5 analytics (burn rate, days remaining)

7. HUB-WATCHDOG (before production deployment)

8. WebUI G7 (logo picker, polish)
```

---

## G4 DESIGN DECISIONS LOCKED

These decisions were made in chat on 2026-06-23. Do not re-debate.
Read all of these before writing a single line of G4 code.

### Brand selection
- Three brands: Indane, HP, Bharat
- Stored in config.json as string key "brand"
- G4: simple one-time POST endpoint /api/config/brand
- G7: replaced with logo picker UI
- Purpose: anchor validation sanity check

### Steel derivation
- Windowed average over N stable readings
- Spread across window < ANCHOR_STABILITY_WINDOW_G = 50.0g
- Named constant with comment: # TODO tune after 3E-009
- Same window used for stability gate AND steel_g mean

### Anchor trigger — Option B locked
- gross > 26000g AND stable for N readings
- Window resets on any reading below 26000g
- Prevents false anchors from transient heavy objects

### State machine — explicit states
```
UNINSTALLED → TRACKING → LOW_GAS → EMPTY (future stub)
```

Transitions:
```
UNINSTALLED → TRACKING    : anchor event — stable window > 26kg
TRACKING    → LOW_GAS     : gas_pct < ALERT_AMBER_PCT (derived from ALERT_AMBER_G)
LOW_GAS     → TRACKING    : refill — gross > 26kg, re-anchor, new steel_g
LOW_GAS     → EMPTY       : gas_pct < 2% (future stub)
TRACKING    → UNINSTALLED : cylinder removed — gross drops near zero
LOW_GAS     → UNINSTALLED : cylinder removed in low gas condition
```

### LOW_GAS vs TRACKING — separate states, not a flag
- LOW_GAS and TRACKING are explicit separate states (not a flag inside TRACKING)
- Reason: future features (EMPTY detection, polling frequency changes, watchdog
  escalation, prediction module) need clean state boundaries
- Adding states is additive. Adding flags to a flat model becomes tangled.
- Both states share same gas% calculation and same steel_g reference

### Gas% formula
```
gas_pct = (gross_g - steel_g) / 14200 * 100
```
Computed ONLY in TRACKING and LOW_GAS. Never in UNINSTALLED.

### Alert constants (locked)
```python
DAILY_USE_DEFAULT_G       = 350.0
ALERT_AMBER_G             = 2000.0
ALERT_RED_G               = 1000.0
ANCHOR_STABILITY_WINDOW_G = 50.0   # TODO tune after 3E-009
ANCHOR_MIN_GROSS_G        = 26000.0
```

### Unknown DUMP_LOG anomaly — deferred
- boot=6 t~4678: two DUMP_LOG commands received as "Unknown command"
- Third DUMP_LOG accepted correctly
- Flagged for investigation — deferred until after G4

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Build order discipline | Verify each layer before building on top. |
| Module contract | Computation modules = pure functions. Service modules own state. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". |
| BLE on QRB2210 | Match by Name not UUID. Always check known devices on connect. |
| Noise samples in raw counts | NEVER store grams in s_samples[]. Cal_factor applied once. |
| Tare + cal_factor are a PAIR | Hub stores and sends both together. Never mix sessions. |
| NimBLE onWrite signature | Always two parameters: (NimBLECharacteristic* c, NimBLEConnInfo& connInfo) |
| NimBLE advertising restart | Always restart in onDisconnect(). Non-negotiable. |
| App Lab on_message callbacks | Always (sid, data) — never just (data). |
| SCP | Use IP 192.168.1.161 if hostname AQ3 fails. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |
| No code in chat | Even simple fixes go via CLI prompt. No exceptions. |
| Hub anchor | 3-reading spread window only. Never 2-reading consecutive gate. |
| Docker binaries | Never call host binaries (bluetoothctl etc) from inside container. |
| write_command | Strip trailing newline before WriteValue. |
| STATE_TARE_WAIT | Must have delay(10) — FreeRTOS watchdog rule. |
| g_cal_degraded vs health | These are independent signals. Never conflate. |
| Gas% states | Compute gas% ONLY in TRACKING and LOW_GAS. Never in UNINSTALLED. |

---

## Windows laptop setup

SCP path: `C:\Users\mahes\Documents\Arduino\`
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED

WebUI auto-launch: `C:\Users\mahes\scripts\gas_monitor_webui_launcher.py`
Polls 192.168.1.161:7000, opens browser when hub is ready.

---

## Hub deploy commands

```bash
# Deploy (after setup_sudoers.sh run once)
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh

# Monitor logs
docker logs gas-cylinder-monitor-hub-main-1 --follow

# Check BT adapter
bluetoothctl show | grep Powered
```

---

## Session start checklist

1. Read this document fully
2. Confirm working mode: chat = design only, CLI = code only
3. Current position: G4 hub domain logic is next
4. Hub running: bash deploy.sh if needed, WebUI at 192.168.1.161:7000
5. Node: boot=8, gas_monitor_v1 with CAL timeout + g_cal_degraded flashed
6. N-TARE-CHECK threshold: currently 1000g (DEV) — restore 2000g before production
7. Read G4 DESIGN DECISIONS LOCKED section above before any design
8. First action: read main.py, ble_subscriber.py, db.py on AQ3 before writing anything

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_23_FINAL_4.md fully before responding.
Context: CAL timeout fix complete and verified on boot=8.
g_cal_degraded flag working - journal sees true hardware health,
BLE payload sees DEGRADED when cal is fallback.
Today: design and build G4 hub domain logic.
All G4 design decisions are locked in this handoff under
G4 DESIGN DECISIONS LOCKED section - read them before designing anything.
Start by reading main.py, ble_subscriber.py, db.py on AQ3,
then confirm what G4 adds to each file before writing a single line."

---

*End of handoff. Next chat is ready.*
