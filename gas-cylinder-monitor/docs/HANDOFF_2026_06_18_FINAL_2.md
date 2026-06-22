# SESSION HANDOFF — 2026-06-18 FINAL_2
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_18_FINAL_1.md

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
First end-to-end DEV mode demo working on hardware. Hub DEV mode, auto-anchor,
percentage tracking, two-level alerts all verified. Node advertising restart fixed.
Next: N1 (journal → SPIFFS), then hub CAL timeout fix, then hub Group 4.

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
Log char:        d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c  (notify — reserved)
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
Weight payload:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
Command format:  ASCII string e.g. "TARE\n" "SKIP_TARE\n" "SET_CAL:36.2689\n"
```

---

## Boot sequence — locked

```
SETTLE (2s autonomous)
  → TARE_WAIT (hub commands TARE or SKIP_TARE, 60s timeout)
    → TARE (N=200 fresh, or load from SPIFFS if SKIP_TARE)
      → [N-TARE-CHECK] (compare fresh tare vs saved — detect load on platform)
        → NOISE (autonomous, uses saved cal_factor for gram units)
          → CAL (hub sends SET_CAL, or load SPIFFS, or interactive fallback)
            → RUNNING
```

Hub is decision maker. Node never decides tare path alone.
SKIP_TARE always paired with matching SET_CAL from same original session.

---

## Node layer status

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE (skip_stuck guard in place) |
| 1C — Timing instrumentation | ✅ COMPLETE |
| 1D — Structured Serial journal | ✅ COMPLETE |
| BLE command characteristic | ✅ COMPLETE — TARE/SKIP_TARE/SET_CAL/RETARE/DUMP_LOG(stub)/CLEAR_LOG(stub) |
| STATE_TARE_WAIT | ✅ COMPLETE — 60s timeout, verified multiple boots |
| Tare SPIFFS save/load | ✅ COMPLETE |
| STATE_RETARE | ✅ COMPLETE (stub — hub side not built) |
| N-TARE-CHECK | ✅ COMPLETE — 1000g threshold (DEV); production = 2000g |
| NimBLE advertising restart | ✅ COMPLETE — restarts on disconnect |
| N1 — Journal → SPIFFS | ❌ NOT BUILT — NEXT |
| 1E — BLE log streaming | ❌ NOT BUILT — after N1 |
| CAL timeout fallback | ❌ NOT BUILT — HIGH priority |
| TODO 1B-stuck | ❌ DEFERRED |
| TODO 1B-persistence | ❌ DEFERRED |

---

## Hub layer status

| Component | Status |
|---|---|
| BLE subscriber | ✅ WORKING — auto-reconnects |
| WebUI | ✅ LIVE at 192.168.88.20:7000 |
| SQLite | ✅ RUNNING — readings stored |
| DEV mode auto-anchor | ✅ WORKING — 3-reading spread window |
| PROD mode scaffold | ✅ WORKING — Calibrating... placeholder |
| DEV/PROD toggle | ✅ WORKING — WebUI pill, SQLite flag |
| Two-level alerts | ✅ WORKING — amber pct<20%, red grams<50g |
| node_status topbar | ✅ WORKING — green dot, MAC, name |
| IST timestamp | ✅ WORKING |
| Gas domain logic (Group 4) | ❌ NOT BUILT |
| HUB-WATCHDOG | ❌ NOT BUILT — PRE-PRODUCTION REQUIRED |
| Log directory | ❌ NOT BUILT |

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
│       ├── ble.h   / ble.cpp     ← weight notify + command char + advertising restart
│       ├── health.h / health.cpp ← health checks (skip_stuck guard)
│       ├── journal.h / journal.cpp ← serial event log
│       └── config.json           ← cal_history, tare_raw, cal_factor
├── hub/
│   ├── app.yaml
│   ├── deploy.sh                 ← includes BT power-on, passwordless after setup
│   ├── setup_sudoers.sh          ← run once on new device: sudo bash setup_sudoers.sh
│   ├── DEVICE_SETUP.md           ← one-time commissioning guide
│   ├── assets/index.html         ← WebUI with topbar, toggle, alerts
│   ├── data/monitor.db           ← SQLite (readings + config tables)
│   └── python/
│       ├── main.py               ← DEV/PROD mode, anchor, alerts, node_status
│       ├── ble_subscriber.py     ← BlueZ D-Bus, IST timestamp, callbacks
│       └── db.py                 ← SQLite abstraction + dev_mode functions
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md ← last entry L-070
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    ├── HANDOFF_2026_06_18_FINAL_1.md
    ├── HANDOFF_2026_06_18_SESSION2_HUB_DEVMODE_DEMO.md
    └── HANDOFF_2026_06_18_FINAL_2.md ← this file
```

---

## Next session build order

```
1. N1 — Journal → SPIFFS file                     ← NEXT NODE ITEM
   journal.cpp appends every line to /node_journal.log
   RAM counter g_journal_file_bytes, initialised from SPIFFS file size on boot
   Transfer pending flag set at 25KB

2. 1E — BLE log char streaming
   Node notifies each journal line via log char (d7b3e2f...)
   Hub receives live feed, saves to temp file

3. N-LOG-TRANSFER — full DUMP_LOG / CLEAR_LOG FSM
   LOG_START / LOG_END sentinels
   Hub saves to logs/node/node_YYYY-MM-DD_bootNN.log
   Hub sends CLEAR_LOG only after confirmed write

4. Hub log directory and hub-side event log

5. CAL timeout fix — HIGH PRIORITY
   120s timeout on STATE_CAL → use 36.0 fallback → DEGRADED quality
   Prevents node hanging forever when hub is offline and SPIFFS is empty

6. 3E-008 temperature drift experiment

7. HUB-WATCHDOG (before production deployment)

8. Hub Group 4 domain logic
   Company lookup table, BIS anchor, steel derivation
   State machine: UNINSTALLED → TRACKING → LOW_GAS
```

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
| SCP | Use IP 192.168.88.20 if hostname AQ3 fails. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |
| No code in chat | Even simple fixes go via CLI prompt. No exceptions. |
| Hub anchor | 3-reading spread window only. Never 2-reading consecutive gate. |
| Docker binaries | Never call host binaries (bluetoothctl etc) from inside container. |

---

## Windows laptop setup

SCP path: `C:\Users\mahes\Documents\Arduino\`
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED

WebUI auto-launch: `C:\Users\mahes\scripts\gas_monitor_webui_launcher.py`
Polls 192.168.88.20:7000, opens browser when hub is ready.

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
3. Current position: N1 (journal→SPIFFS) is next node item
4. Hub running: bash deploy.sh if needed, WebUI at 192.168.88.20:7000
5. Node: boot=41, gas_monitor_v1 with advertising restart fix flashed
6. N-TARE-CHECK threshold: currently 1000g (DEV) — note to restore 2000g before production
7. First action: design N1 in chat before any CLI work

---

## SCP command — save this file to board

From Windows laptop PowerShell:
```powershell
scp HANDOFF_2026_06_18_FINAL_2.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_18_FINAL_2.md
```

Then on AQ3:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_18_FINAL_2" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_18_FINAL_2.md fully before responding.
Context: First end-to-end DEV mode demo verified. Hub working. Node boot=41 clean.
Today we design and build N1 — journal lines appended to /node_journal.log on SPIFFS,
with RAM counter g_journal_file_bytes, transfer pending flag at 25KB.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
