# HANDOFF — Gas Cylinder Monitor V1
# Date: 2026-06-23 | File: HANDOFF_2026_06_23_FINAL_6.md
# Status: G4 COMPLETE — next = N-TARE-CHECK extension + 3E-005

---

## Current position (one line)

G4 hub domain logic complete and verified. Hub is production architecture.
Node at boot=9. Next: N-TARE-CHECK extension (node flash) then 3E-005 anchor
validation with water bowl simulation.

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

## Node firmware — gas_monitor_v1

**Current boot count: boot=9**
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
| N-TARE-CHECK hub-offline extension | ❌ NEXT NODE FLASH |
| N-TARE-CHECK threshold restore 2000g | ❌ NEXT NODE FLASH (currently 1000g DEV) |

### Node modules

```
gas_monitor_v1/
├── gas_monitor_v1.ino   ← orchestrator + state machine
├── hx711.h/cpp          ← raw bit-bang, DT=GPIO4 SCK=GPIO3, 3.3V only
├── tare.h/cpp           ← tare derivation + SPIFFS save/load
├── noise.h/cpp          ← noise floor characterisation
├── cal.h/cpp            ← cal_factor + SPIFFS save/load
├── weight.h/cpp         ← rolling mean + delay-line detector
├── ble.h/cpp            ← BLE GATT notify + CMD characteristic
├── health.h/cpp         ← load cell health checks
├── journal.h/cpp        ← serial event log (pure reporter)
└── log_transfer.h/cpp   ← DUMP_LOG/LOG_START/LOG_END/CLEAR_LOG pipeline
```

### Locked hardware values

| Constant | Value | Source |
|---|---|---|
| HX711 DT | GPIO4 | LOCKED hardware |
| HX711 SCK | GPIO3 | LOCKED hardware |
| cal_factor | ~36.2231 raw/g | boot=8 SPIFFS verified |
| sigma (boot=9) | 3.80g | measured |
| tare_raw | ~-107075.7 | boot=9 measured |
| NET_GAS_G | 14200.0g | BIS IS 3196 fixed |

### Boot sequence

```
SETTLE (2s) → TARE_WAIT (hub sends TARE/SKIP_TARE, 60s timeout)
→ TARE → NOISE → CAL (hub sends SET_CAL) → RUNNING
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
| BLE subscriber (ble_subscriber.py) | ✅ COMPLETE — clean, no changes needed |
| Log transfer (log_transfer.py) | ✅ COMPLETE — extracted from main.py in G4 |
| Domain logic (domain.py) | ✅ COMPLETE — G4 full state machine |
| SQLite (db.py) | ✅ COMPLETE — G4 schema columns added |
| Orchestrator (main.py) | ✅ COMPLETE — 92 lines, DEV mode deleted |
| WebUI (index.html) | ✅ WORKING — DEV toggle removed |
| Gas domain logic G4 | ✅ COMPLETE — this session |
| HUB-WATCHDOG | ❌ NOT BUILT — pre-production required |

### Hub Python module structure (5 files, each single responsibility)

```
hub/python/
├── main.py            ← orchestrator only, 92 lines, zero logic
├── ble_subscriber.py  ← BLE transport only (untouched in G4)
├── log_transfer.py    ← log pipeline only (extracted in G4)
├── domain.py          ← ALL domain logic (G4 core)
└── db.py              ← SQLite abstraction only
```

### domain.py — G4 state machine (locked design)

States: UNINSTALLED → BOOTSTRAP_ANCHOR / BOOTSTRAP_LOOKUP / BOOTSTRAP_PRIOR
        → TRACKING → LOW_GAS → EMPTY (stub)

Key transitions:
- UNINSTALLED → BOOTSTRAP_*     : user calls set_install_mode()
- BOOTSTRAP_ANCHOR → TRACKING   : anchor window fires (5 stable readings > 26kg)
- TRACKING → LOW_GAS            : gas_g < ALERT_AMBER_G (2000g)
- LOW_GAS → TRACKING            : refill detected (gross > 26kg)
- TRACKING/LOW_GAS → UNINSTALLED: cylinder removed (gross < 500g)

Gas% formula: gas% = (gross_g - steel_g) / 14200.0 * 100

### domain.py — Production constants (LOCKED)

```python
NET_GAS_G             = 14200.0   # BIS IS 3196 — NEVER CHANGE
ANCHOR_STABILITY_WINDOW_G = 50.0  # TODO: tune after 3E-009
ANCHOR_MIN_STABLE_READINGS = 5    # TODO: validate after 3E-005
ANCHOR_GROSS_MIN_G    = 26000.0   # fresh full cylinder threshold
STEEL_PLAUSIBLE_MIN_G = 13000.0
STEEL_PLAUSIBLE_MAX_G = 18000.0
STEEL_UNKNOWN_PRIOR_G = 16500.0   # conservative prior
ALERT_AMBER_G         = 2000.0    # LOCKED 2026-06-12
ALERT_RED_G           = 1000.0    # LOCKED 2026-06-12
DAILY_USE_DEFAULT_G   = 350.0     # LOCKED 2026-06-12
BRAND_STEEL_G = {'Indane': 15300.0, 'HP': 14900.0, 'Bharat': 15100.0}
```

### config.json — G4 schema (current state after session)

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
  "cal_factor": null,
  "tare_raw": null,
  "cal_tare_session": null
}
```

### Hub folder structure

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   └── gas_monitor_v1/       ← current production node sketch
├── hub/
│   ├── app.yaml
│   ├── deploy.sh
│   ├── assets/index.html     ← WebUI (DEV toggle removed)
│   ├── data/monitor.db       ← SQLite (G4 schema)
│   ├── data/config.json      ← domain state (G4 schema)
│   ├── logs/node/            ← node log files saved here
│   └── python/
│       ├── main.py
│       ├── ble_subscriber.py
│       ├── log_transfer.py
│       ├── domain.py
│       └── db.py
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    └── HANDOFF_2026_06_23_FINAL_6.md  ← this file
```

---

## 3E-005 — Water bowl simulation (NEXT EXPERIMENT)

### Test object measurements (verified this session)

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
ANCHOR_GROSS_MIN_G    = 4800.0   # TEST ONLY: below 5000 with margin. PRODUCTION=26000.0
STEEL_PLAUSIBLE_MIN_G = 200.0    # TEST ONLY: bowl+plate steel. PRODUCTION=13000.0
STEEL_PLAUSIBLE_MAX_G = 2000.0   # TEST ONLY: bowl+plate steel. PRODUCTION=18000.0
```

### Expected 3E-005 results

```
Anchor fires:   steel_g derived = ~465g  (mean_gross - 4535)
Gas% at full:   (5000 - 465) / 4535 * 100 = 100%
AMBER alert:    gas_g < 2000g → gross < 2465g → ~56% water remaining
RED alert:      gas_g < 1000g → gross < 1465g → ~22% water remaining
10% increments: remove ~453g water per step
```

### 3E-005 pass criteria

- [ ] Hub transitions UNINSTALLED → BOOTSTRAP_ANCHOR after setup endpoint called
- [ ] Anchor window fires after 5 stable readings (log shows ANCHOR COMPLETE)
- [ ] steel_g ≈ 465g (bowl + plate weight)
- [ ] Gas% = 100% immediately after anchor
- [ ] Gas% drops correctly as water is removed
- [ ] AMBER alert fires when gas_g drops below 2000g
- [ ] config.json shows steel_source=ANCHOR after transition

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

---

## N-TARE-CHECK extension — pre-production node flash

**Must be built BEFORE 3E-005. This is the next node flash.**

Problem: Hub offline at node boot → TARE_WAIT times out → fresh tare zeroes
cylinder weight → all readings wrong by ~29kg.

Fix (node-side, in TARE_WAIT timeout handler):

```cpp
// In TARE_WAIT timeout: if SPIFFS has saved tare+cal AND heavy load detected
// → use saved tare instead of fresh tare.
float saved_tare = tare_load_from_spiffs();
float saved_cal  = cal_load_last();
if (saved_tare != 0.0f && saved_cal > 0.0f) {
    float approx_gross = (current_raw - saved_tare) / saved_cal;
    if (approx_gross > HEAVY_LOAD_THRESHOLD_G) {  // 2000g production
        // use saved tare, set g_cal_degraded = true
    }
}
```

Also in same flash: restore `HEAVY_LOAD_THRESHOLD_G` from 1000g (DEV) to 2000g.

---

## Build order — locked

```
1. N-TARE-CHECK extension + restore 2000g threshold  ← NEXT (node flash)
2. 3E-005 anchor validation (water bowl)             ← after N-TARE-CHECK
3. 3E-008 temperature drift characterisation
4. 3E-009 6hr long-run stability
5. 3E-010 load cell failure injection
6. G5 analytics — burn rate from real data
7. HUB-WATCHDOG — mandatory before production
8. WebUI G7 — full dashboard, gas gauge, brand picker
```

---

## Deferred items (carry forward always)

- DUMP_LOG anomaly: boot=6 t≈4678 duplicate unknown commands — investigate after G5
- Scenario 3 test: SPIFFS empty + hub offline — deferred from CAL-fix session
- HUB-001: auto-retare on cylinder removal — V2
- HUB-002: disturbance detection — V2 (needs G5 burn rate)
- Rcal shunt calibration resistor — V2
- TODO 1B-stuck: tare_variance_raw always 0.0f — low priority
- TODO 1B-persistence: prev_cal_factor not read at boot — medium priority

---

## Critical rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | All paths derived from __file__ or SCRIPT_DIR |
| No HX711 library | Raw bit-bang only. Three corrupt filters always. |
| No gas% without steel | Always subtract steel first. |
| No timestamps on node | Hub stamps on receipt. ESP32-C3 has no RTC. |
| Hub = orchestrator only | main.py has zero domain logic |
| Modular orchestra | Each file answers one question, no "and" in the answer |
| config.json read-modify-write | Never overwrite BLE keys when writing domain keys |
| cal_factor + tare_raw = pair | Always stored together with timestamp |
| BlueZ: match by Name | Not UUID — QRB2210 BlueZ backend limitation |
| SPIFFS ≠ reflash | Accumulation tests use power cycle only |

---

## Windows laptop setup

SCP path: `C:\Users\mahes\Documents\Arduino\`
Flash: Arduino IDE, COM11, ESP32C3 Dev Module, USB CDC On Boot ENABLED
Upload speed: 921600 (normal) / 115200 (fallback)
Recovery: `esptool --no-stub --baud 115200` with merged.bin

## AQ3 hub commands

```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh
docker logs gas-cylinder-monitor-hub-main-1 --since 2m | grep -E "\[MAIN\]|\[DOMAIN\]"
bluetoothctl power off && sleep 2 && bluetoothctl power on
sudo reboot   # if bluetoothctl power on fails (WCN3990 crash)
```

## Claude Code CLI

Pinned: v2.1.129. `DISABLE_AUTOUPDATER=1` in ~/.bashrc.
Never upgrade — v2.1.131+ breaks on Cortex-A53.

---

## Session start checklist

1. Read this document fully
2. Confirm working mode: chat = design only, CLI = code only
3. Hub running: `bash deploy.sh` if needed, WebUI at 192.168.88.20:7000
4. Node: boot=9, gas_monitor_v1 with CAL timeout + g_cal_degraded flashed
5. config.json: confirm cylinder_state=UNINSTALLED before starting
6. First action: N-TARE-CHECK extension design in chat, then CLI
7. After node flash verified: 3E-005 water bowl experiment

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_23_FINAL_6.md fully before responding.
Context: G4 complete. Hub is production architecture, 5 modules,
state machine live. Node at boot=9.
Today: build N-TARE-CHECK hub-offline extension (node flash),
then run 3E-005 anchor validation with water bowl.
Start by confirming you read the handoff and state current position.
Then generate the project roadmap tracker."

---

*End of handoff. G4 complete. Next chat is ready.*
