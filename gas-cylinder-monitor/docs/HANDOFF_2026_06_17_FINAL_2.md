# SESSION HANDOFF — 2026-06-17 FINAL_2
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes FINAL_1 — includes BLE pipeline verification and fixes

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat.

---

## Current position (one line)
Node Layer 1 complete (1A+1B+1C+1D). BLE pipeline verified end-to-end.
Node→BLE→Hub→WebUI live and working. Reconnect after flash working.
Next: 3E-006B — minimum detectable removal experiment.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify)
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

---

## Locked values — hardware-verified

| Parameter | Value | Status |
|---|---|---|
| cal_factor | NOT hardcoded — derived every boot | LOCKED |
| cal_factor typical | ~36 raw/g (3-cell parallel) | VERIFIED |
| sigma | 3.48–3.68g (boot-to-boot variation normal) | VERIFIED |
| zero accuracy | ~±3g | VERIFIED |
| weight accuracy | ±7g across 200g–1700g | VERIFIED |
| threshold_g | 4 × sigma | LOCKED |
| linear range | 200g–1700g | VERIFIED |

### Boot timing — verified 2026-06-17
| Phase | Duration |
|---|---|
| SETTLE | ~2.1s |
| TARE | ~21s (200 samples × 10 SPS) |
| NOISE | ~20s (200 samples × 10 SPS) |
| CAL | variable (human input — development only) |
| Total boot | ~60s excluding CAL wait |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Char UUID:       b9b25bb1-f2a9-4545-b48f-295ab2789f41
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
Payload format:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
```

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/           ← CURRENT PRODUCTION NODE SKETCH
│       ├── gas_monitor_v1.ino    ← orchestrator
│       ├── hx711.h / hx711.cpp
│       ├── tare.h  / tare.cpp
│       ├── noise.h / noise.cpp
│       ├── cal.h   / cal.cpp
│       ├── weight.h / weight.cpp
│       ├── ble.h   / ble.cpp
│       ├── health.h / health.cpp
│       ├── journal.h / journal.cpp
│       ├── README.md
│       └── config.json
├── hub/                          ← DEPLOYED, RUNNING
│   ├── app.yaml
│   ├── deploy.sh
│   ├── python/
│   │   ├── main.py
│   │   ├── ble_subscriber.py     ← BLE fixed 2026-06-17
│   │   └── requirements.txt
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md  ← last entry L-055
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── PLAN.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_17_FINAL_2.md  ← this file
```

---

## Node Layer 1 — ALL COMPLETE

| Item | Status |
|---|---|
| 1A — Modular sketch port | ✅ COMPLETE |
| 1B — Load cell health detection | ✅ COMPLETE |
| 1C — Timing instrumentation | ✅ COMPLETE 2026-06-17 |
| 1D — Structured event journal | ✅ COMPLETE 2026-06-17 |

---

## Journal format — locked

```
#SEQ t=T boot=B [TAG] event=NAME key=val key=val
```

| Tag | Event | When |
|---|---|---|
| [BOOT] | START | Once on boot |
| [BOOT] | PHASE_COMPLETE | Each phase exits |
| [BOOT] | BOOT_COMPLETE | Entering STATE_RUNNING |
| [RUN] | QUALITY_CHANGE | Quality transitions only |
| [RUN] | WEIGHT_EVENT | Delta > 4×sigma |
| [HB] | HEARTBEAT | Every 30 seconds |
| [FAULT] | PHASE_FAIL | Phase failure |

---

## Hub — deployed and working

| Component | Status |
|---|---|
| BLE subscriber | WORKING — auto-reconnects after node flash |
| WebUI | LIVE at 192.168.88.20:7000 — showing real weight |
| SQLite | Running — no gas logic yet |
| Gas domain logic | NOT BUILT — after experiments |

### Hub deploy command
```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh
```

### Hub log monitoring
```bash
docker logs gas-cylinder-monitor-hub-main-1 --follow
```

---

## Critical BLE fixes — verified 2026-06-17

### Fix 1 — InterfacesAdded UUID filter ignored on QRB2210
BlueZ SetDiscoveryFilter UUIDs array is silently ignored on this platform.
UUIDs in InterfacesAdded payload are empty until ServicesResolved.
Fix: match on device Name, not UUID, in _interfaces_added().

### Fix 2 — Cached devices don't re-trigger InterfacesAdded
BlueZ only fires InterfacesAdded for newly discovered devices.
Known devices from previous sessions never trigger the callback.
Fix: _check_known_devices() called after every StartDiscovery().
Walks GetManagedObjects() and connects to matching DEVICE_NAME directly.

### Fix 3 — hcitool lescan always fails on QRB2210
hcitool uses HCI socket directly — bypasses BlueZ daemon.
Always fails with I/O error on this platform.
Rule: use bluetoothctl to diagnose BLE issues, never hcitool.

### Sudoers rule — required for passwordless deploy
File: /etc/sudoers.d/gas-cylinder-monitor
If missing on fresh board setup, deploy.sh will prompt for password.
```
arduino ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dbus-bridge-gas-cylinder-monitor.service, /usr/bin/systemctl start dbus-bridge-gas-cylinder-monitor.service, /usr/bin/systemctl stop dbus-bridge-gas-cylinder-monitor.service, /usr/bin/systemctl status dbus-bridge-gas-cylinder-monitor.service
```

---

## Transport observability — deferred (Option C)

| Item | When | What |
|---|---|---|
| Node BLE journal entries | Next session | ADVERTISING, CLIENT_CONNECTED, CLIENT_DISCONNECTED in ble.cpp |
| Hub persistent log file | When hub domain logic built | Rotating log, survives restarts |
| WebUI transport status panel | When WebUI built | Adapter status, scan/connected, last rx |
| deploy.sh adapter health check | Soon | Verify hci0 up before container starts |

---

## Known TODOs — deferred, tracked

| ID | Description | Fix |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f — stuck check always fails | Update TareResult struct to expose variance |
| TODO 1B-persistence | prev_cal_factor/prev_sigma_g not read from config.json | Read/write at boot and after CAL_SUCCESS |

---

## Next session — 3E-006B: minimum detectable removal

### What this experiment answers
What is the smallest weight removal the system reliably detects?
threshold_g = 4 × sigma ≈ 14g. Does the system actually detect
a 15g removal reliably? 20g? 50g? Hardware must tell us.

### Setup needed
- Water container on platform (simulates cylinder)
- Measuring cup — remove precise water amounts
- Kitchen scale — verify removed amounts independently
- Start large (200g), step down until detection fails

### What to measure
- Smallest delta that triggers WEIGHT_EVENT type=REMOVED reliably
- False negative rate at threshold boundary
- Ticks until WEIGHT_EVENT fires after removal

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived. Never constants. |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Build order discipline | Verify each layer before building on top. |
| Computation vs service modules | Computation = pure function. Service (journal) = stateful. |
| Sentinel = -1.0f | Never 0.0f for "no previous value". |
| BLE on QRB2210 | Match by name not UUID. Always check known devices. |
| SCP | Use IP 192.168.88.20 if hostname AQ3 fails. |
| Design in chat | All code written exclusively via Claude Code CLI on AQ3. |

---

## Session start checklist

1. This document read fully
2. Working mode confirmed: chat = design only, CLI = code only
3. Current position: Node Layer 1 complete, BLE pipeline live
4. Hub running: deploy.sh if needed, WebUI at 192.168.88.20:7000
5. Next action: 3E-006B — design experiment in chat first

---

## SCP to board

```powershell
scp HANDOFF_2026_06_17_FINAL_2.md arduino@192.168.88.20:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_17_FINAL_2.md
```

Then commit:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "docs: add HANDOFF_2026_06_17_FINAL_2" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_17_FINAL_2.md fully before responding.
Context: Node Layer 1 complete. BLE pipeline verified end-to-end.
Hub WebUI live at 192.168.88.20:7000 showing real weight.
Today we design and run 3E-006B — minimum detectable removal experiment.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
