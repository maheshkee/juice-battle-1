# SESSION HANDOFF — 2026-06-18 FINAL_1
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes all previous HANDOFF files.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Node sketch fully clean (boot=35 verified). Seven bugs fixed. BLE command
characteristic built. Tare SPIFFS persistence built. STATE_TARE_WAIT built.
Next: N-TARE-CHECK (post-tare self-check) then N1 (journal → SPIFFS).

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
- NimBLE version note: onWrite callback requires TWO parameters:
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override

---

## Locked values — hardware-verified boot=35

| Parameter | Value | Status |
|---|---|---|
| cal_factor | 36.2689 raw/g (loaded from SPIFFS) | VERIFIED |
| cal_factor range (this platform) | 34.47–36.27 raw/g | VERIFIED |
| sigma (boot=35) | 3.16g | VERIFIED — healthy |
| sigma (boot=31) | 5.44g | VERIFIED — healthy |
| sigma healthy range | 4.68–5.44g across boots | VERIFIED |
| threshold_g | 4 × sigma | LOCKED |
| NOISE_SIGMA_PASS_G | 8.0f | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0f | LOCKED |
| BUF_SIZE (delay-line) | 40 ticks = 4 seconds | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| tare source | N=200 samples, saved to SPIFFS | LOCKED |
| zero accuracy | ~±5g | VERIFIED |
| weight accuracy | ±6g on 1000g | VERIFIED boot=31 |

### Boot timing — verified 2026-06-18
| Phase | Duration |
|---|---|
| SETTLE | ~2.1s |
| TARE_WAIT | 0–60s (hub command or timeout) |
| TARE | ~21.1s (N=200 at 10 SPS) |
| NOISE | ~20.1s (N=200 at 10 SPS) |
| CAL | ~0.1s (SPIFFS load) or variable (interactive) |
| Total boot (timeout path) | ~103.9s |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Weight char:     b9b25bb1-f2a9-4545-b48f-295ab2789f41  (notify)
Command char:    c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b  (write-without-response)
Log char:        d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c  (notify — reserved 1E)
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
Weight payload:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
Command format:  ASCII string e.g. "TARE\n" "SKIP_TARE\n" "SET_CAL:36.2689\n"
```

---

## Boot sequence — V1 design (locked)

```
SETTLE (2s autonomous)
  → TARE_WAIT (hub commands TARE or SKIP_TARE, 60s timeout)
    → TARE (N=200 fresh, or load from SPIFFS if SKIP_TARE)
      → NOISE (autonomous, uses saved cal_factor from SPIFFS for gram units)
        → CAL (hub sends SET_CAL, or load SPIFFS, or interactive fallback)
          → RUNNING
```

Hub is decision maker. Node never decides tare path alone.
SKIP_TARE always paired with matching SET_CAL from same original session.

---

## Cal factor — V1 design (locked this session)

Four production cases:
1. First ever boot: Hub derives cal_factor from cylinder using BIS anchor + company lookup table. Saves to config.json. Sends SET_CAL to node.
2. Power cycle, platform empty: Hub sends TARE + SET_CAL with saved value. Hub cross-checks gross reading ±5%.
3. Power cut, cylinder on platform: Hub sends SKIP_TARE + SET_CAL (paired values from same original session).
4. Cylinder replaced: Hub sends RETARE → node retares → hub derives new cal_factor from new cylinder → cross-checks ±5% against old → updates config.json.

Rules:
- Cal_factor and tare are always a PAIR in hub config.json
- Cylinder IS the calibration reference (29.5kg → 130× better than 227g dev weight)
- Hub derives, node stores and uses
- CAL timeout needed: 120s → 36.0 fallback → DEGRADED (NOT YET BUILT)

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino    ← orchestrator + state machine
│       ├── hx711.h / hx711.cpp   ← raw bit-bang
│       ├── tare.h  / tare.cpp    ← tare + SPIFFS save/load
│       ├── noise.h / noise.cpp   ← noise floor (samples in raw counts)
│       ├── cal.h   / cal.cpp     ← cal_factor + SPIFFS
│       ├── weight.h / weight.cpp ← rolling mean + delay-line (BUF_SIZE=40)
│       ├── ble.h   / ble.cpp     ← weight notify + command char + log char
│       ├── health.h / health.cpp ← health checks (stuck guard in place)
│       ├── journal.h / journal.cpp ← serial event log
│       └── config.json           ← cal_history, tare_raw, cal_factor
├── node/hw_test/                 ← standalone hardware diagnostic sketch
├── hub/                          ← DEPLOYED, RUNNING
│   ├── app.yaml
│   ├── deploy.sh
│   ├── assets/index.html
│   ├── data/monitor.db           ← SQLite
│   └── python/
│       ├── main.py
│       ├── ble_subscriber.py
│       └── db.py
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md ← last entry L-063
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_18_FINAL_1.md ← this file
```

---

## Node Layer status — end of 2026-06-18

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE (stuck guard in place) |
| 1C — Timing instrumentation | ✅ COMPLETE |
| 1D — Structured Serial journal | ✅ COMPLETE |
| BLE command characteristic | ✅ COMPLETE — TARE/SKIP_TARE/SET_CAL/RETARE/DUMP_LOG/CLEAR_LOG |
| STATE_TARE_WAIT | ✅ COMPLETE — 60s timeout, verified boot=31/33/35 |
| Tare SPIFFS save/load | ✅ COMPLETE — tare_save/load_from_spiffs() |
| STATE_RETARE | ✅ COMPLETE (stub — hub side not built) |
| NOISE threshold fix | ✅ COMPLETE — 8.0g PASS / 15.0g WARN |
| Stuck false positive fix | ✅ COMPLETE — skip_stuck guard |
| cal_factor before NOISE fix | ✅ COMPLETE — loads SPIFFS before NOISE |
| Double-division sigma fix | ✅ COMPLETE — samples stored as raw counts |
| BUF_SIZE=40 false event fix | ✅ COMPLETE |
| Journal → SPIFFS (N1) | ❌ NOT BUILT — next session |
| 1E BLE log streaming | ❌ NOT BUILT — after N1 |
| N-TARE-CHECK post-tare self-check | ❌ NOT BUILT — next session |
| CAL timeout fallback | ❌ NOT BUILT — 120s → 36.0 → DEGRADED |
| TODO 1B-stuck (proper fix) | ❌ DEFERRED |
| TODO 1B-persistence | ❌ DEFERRED |

---

## Known TODOs — deferred, tracked

| ID | Description | Fix |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f — stuck check never uses real variance | Expose variance from tare.cpp through TareResult struct |
| TODO 1B-persistence | prev_cal_factor/prev_sigma_g not read from config.json at boot | Read/write at boot and after CAL_SUCCESS |
| CAL-TIMEOUT | No timeout on interactive CAL — node hangs if hub off and SPIFFS empty | 120s timeout → 36.0 fallback → DEGRADED quality |

---

## Bugs fixed this session (summary)

| Bug | Root cause | Fix |
|---|---|---|
| sigma=25g, 48% weight | Loose load cell wire at junction | Physical reconnect |
| NOISE=WARN every boot (F1) | Thresholds calibrated for single-cell STM32 | PASS=8g, WARN=15g |
| quality=DEGRADED every boot (F2) | tare_variance_raw=0.0f always, stuck check always fired | skip_stuck guard |
| NOISE=WARN after threshold fix | g_cal_factor=0.0f during NOISE → raw counts vs gram threshold | Load SPIFFS cal_factor before NOISE |
| sigma=0.09g, 200+ false events | Samples stored in grams, noise_recompute_sigma divided again | Store raw counts, divide once at sigma_g |
| False WEIGHT_EVENT REMOVED | BUF_SIZE=20 → rolling mean variance exceeded threshold | BUF_SIZE=40 |
| onWrite compile error | NimBLE v1.4+ requires NimBLEConnInfo& second parameter | Add second parameter to onWrite |

---

## Hub — current state

| Component | Status |
|---|---|
| BLE subscriber | WORKING — auto-reconnects |
| WebUI | LIVE at 192.168.88.20:7000 |
| SQLite | Running — readings stored |
| Gas domain logic (Group 4) | NOT BUILT |
| Log directory (logs/node/, logs/hub/) | NOT BUILT |
| Hub-side event log | NOT BUILT |

Hub deploy command:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh
```

Hub log monitoring:
```bash
docker logs gas-cylinder-monitor-hub-main-1 --follow
```

---

## Observability design — locked (not yet built)

Log transport two triggers:
1. Node auto-pushes when SPIFFS file reaches 25KB
2. Hub requests via DUMP_LOG on detecting new boot number

Transfer protocol: LOG_START sentinel → lines → LOG_END sentinel → hub saves → hub sends CLEAR_LOG → node deletes file.
Transfer blocked during all boot phases. Only in STATE_RUNNING.

Log directory on AQ3:
```
logs/node/node_YYYY-MM-DD_bootNN.log   ← one per boot session
logs/hub/hub_YYYY-MM-DD.log            ← one per day, appended
```

WebUI design: three tabs — Live (weight + boot phase summary), Boot log (full session), Serial feed (live journal stream + command input box).

---

## Next session build order

```
1. N-TARE-CHECK  ← post-tare self-check (node detects weight on platform)
   Design in chat → CLI prompt → flash → verify

2. N1 — Journal → SPIFFS file
   journal.cpp appends every line to /node_journal.log
   RAM counter g_journal_file_bytes, initialised from SPIFFS on boot
   Transfer pending flag set at 25KB

3. 1E — BLE log char streaming
   Node notifies each journal line via log char (d7b3e2f...)
   Hub receives live feed

4. N-LOG-TRANSFER — full DUMP_LOG / CLEAR_LOG FSM
   LOG_START / LOG_END sentinels
   Hub saves to logs/node/
   Hub sends CLEAR_LOG after confirmed write

5. Hub log directory and hub-side event log

6. WebUI serial feed panel (three tabs)

7. CAL timeout fix (120s → 36.0 fallback)

8. 3E-008 temperature drift experiment

THEN: hub Group 4 domain logic (lookup table, BIS anchor, cal derivation)
THEN: 3E-005 anchor validation
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
| Module contract | Computation modules = pure functions. Service modules (journal) own state. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". |
| BLE on QRB2210 | Match by Name not UUID. Always check known devices on connect. |
| Noise samples in raw counts | NEVER store grams in s_samples[]. Cal_factor applied once at sigma_g. |
| Tare + cal_factor are a PAIR | Hub stores and sends both together. Never mix sessions. |
| NimBLE onWrite signature | Always two parameters: (NimBLECharacteristic* c, NimBLEConnInfo& connInfo) |
| SCP | Use IP 192.168.88.20 if hostname AQ3 fails. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |
| No code in chat | Even simple fixes go via CLI prompt. No exceptions. |
| Modular + orchestrator | .ino = state machine only. No sensor math. No averaging. Modules are pure. |

---

## Critical BLE fixes — verified (carry forward always)

### Fix 1 — InterfacesAdded UUID filter ignored on QRB2210
UUIDs in InterfacesAdded payload are empty until ServicesResolved.
Fix: match on device Name, not UUID, in _interfaces_added().

### Fix 2 — Cached devices don't re-trigger InterfacesAdded
Fix: _check_known_devices() called after every StartDiscovery().

### Fix 3 — hcitool lescan always fails on QRB2210
Use bluetoothctl to diagnose BLE issues. Never hcitool.

---

## Windows laptop setup

SCP path: `C:\Users\mahes\Documents\Arduino\`
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED

WebUI auto-launch script: `C:\Users\mahes\scripts\gas_monitor_webui_launcher.py`
Installed in Windows Startup folder. Polls 192.168.88.20:7000, opens browser when ready.

---

## Session start checklist

1. Read this document fully
2. Confirm working mode: chat = design only, CLI = code only
3. Current position: node clean on boot=35, BLE command char built, tare SPIFFS built
4. Hub running: bash deploy.sh if needed, WebUI at 192.168.88.20:7000
5. Flash latest sketch if not already: SCP from AQ3 → Arduino IDE → COM11
6. First action: design N-TARE-CHECK in chat before any CLI

---

## SCP command to save this file to board

From Windows laptop:
```powershell
scp HANDOFF_2026_06_18_FINAL_1.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_18_FINAL_1.md
```

Then on AQ3:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: session close 2026-06-18 — 7 bugs fixed, BLE command char, tare SPIFFS, next=N-TARE-CHECK" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_18_FINAL_1.md fully before responding.
Context: Node sketch clean on boot=35 — all false positives eliminated.
BLE command characteristic built. STATE_TARE_WAIT built. Tare SPIFFS persistence built.
Today we design and build N-TARE-CHECK (post-tare self-check for weight on platform),
then N1 (journal → SPIFFS file).
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
