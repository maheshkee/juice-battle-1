# SESSION HANDOFF — 2026-06-16 FINAL
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Paste this into the next chat session to restore full context instantly.

---

## How to use this document
New chat reads this first. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No sketch.yaml in CLI prompts. No code written directly in chat.

---

## Current position (one line)
3E-003 COMPLETE AND PASSED. Full end-to-end working: ESP32 → BLE → Hub → WebUI.
Demo achieved. Next = accuracy investigation + session close docs + timestamps + logging.

---

## Demo target — ACHIEVED
Boss places weight on platform → hub receives grams via BLE → WebUI shows grams on screen.
Confirmed working 2026-06-15. Readings flowing every 15 seconds.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A → parallel junction → HX711 → ESP32-C3 (BLE GATT notify) → UNO Q hub (Python, BlueZ, SQLite, WebUI)
```

Transport: BLE-only. WiFi removed entirely.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp, computes gas%.
Gas% = (gross − steel) / 14200 × 100. Never computed on node.

---

## Hardware

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (hostname — IP changes, never use IP) |
| ESP32-C3 SuperMini | sensor node — owns all HX711 work |
| GISLAB HX711 module | green PCB, AVIAIC chip, 3.3V VCC ONLY |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | Fibre plate (food plate), triangle arrangement, 3 cells at 3 corners |
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
All 3 red wires → HX711 E+
All 3 black wires → HX711 E−
All 3 green wires → HX711 A+
All 3 white wires → HX711 A−
Direct to HX711 module pins. Twisted or soldered. NOT breadboard.

---

## Arduino IDE — locked setup

- Package: esp32 by Espressif Systems v3.0.7 (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED — mandatory
- SCP to: C:\Users\mahes\Documents\Arduino\[sketch_folder]\

---

## Locked values — hardware-verified

| Parameter | Value | Status | Locked |
|---|---|---|---|
| cal_factor (3-cell, shared plate) | 36.1 raw/g | ✅ PROVEN | 2026-06-12 |
| HW_VERIFY cal_factor confirmation | 35.63 raw/g | ✅ CONSISTENT (1.3% diff) | 2026-06-15 |
| Linear range | 200g – 1800g | ✅ PROVEN | 2026-06-12 |
| Min reliable weight | ~150g | ✅ PROVEN | 2026-06-12 |
| noise_std_g (BLE off, worst case) | 4.93g | ✅ LOCKED | 2026-06-15 |
| noise_std_g (BLE on, worst case) | 4.64g | ✅ LOCKED | 2026-06-15 |
| threshold_g (BLE on, production) | 18.54g | ✅ LOCKED | 2026-06-15 |
| BLE EMI penalty on 3-cell | ~1.0x | ✅ LOCKED | 2026-06-15 |
| tare_raw | NEVER hardcode | — | re-derived every boot |
| Cold boot settle (with plate) | 60–161s | ✅ PROVEN | 2026-06-12 |

---

## BLE UUIDs — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Char UUID:       b9b25bb1-f2a9-4545-b48f-295ab2789f41
Device name:     GasCylMonitor
Char properties: NOTIFY | READ
Payload format:  {"grams":29420.5,"quality":"GOOD","sigma":2.3}
```

---

## Experiment status

| Experiment | Status | Key output |
|---|---|---|
| E-000 raw read (single cell) | ✅ PASSED 2026-06-04 | bit-bang pattern proven |
| E-001 tare + cal + grams (single cell) | ✅ PASSED 2026-06-05 | cal_factor ~106.7 raw/g (VOID on 3-cell) |
| E-002 noise floor (single cell) | ✅ PASSED 2026-06-08 | STD 0.67g BLE-off (VOID on 3-cell) |
| E-003 BLE transport (single cell) | ✅ PASSED 2026-06-08 | STD 1.81g BLE-on (VOID on 3-cell) |
| 3E-001 cal_factor (3-cell) | ✅ PASSED 2026-06-12 | cal_factor = 36.1 raw/g LOCKED |
| 3E-002 noise floor (3-cell) | ✅ PASSED 2026-06-15 | BLE-on STD 4.64g, threshold 18.54g LOCKED |
| 3E-003 BLE transport (3-cell) | ✅ PASSED 2026-06-15 | ESP32 → hub → WebUI end-to-end working |
| 3E-004 accuracy investigation | ⏳ NEXT | Known weight vs measured — diagnose offset |
| 3E-004 measurement stability | 📋 PLANNED | Fixed load, extended duration |
| 3E-006A anchor validation | 📋 PLANNED | |
| 3E-006B consumption validation | 📋 PLANNED | |

---

## Sketches built so far

| Sketch | Location on AQ3 | Status |
|---|---|---|
| E000_raw_read.ino | node/E000_raw_read/ | DONE single cell |
| E001_tare_cal_grams.ino | node/E001_tare_cal_grams/ | DONE single cell |
| E002_noise_floor.ino | node/E002_noise_floor/ | DONE single cell |
| E003_ble_transport.ino | node/E003_ble_transport/ | DONE single cell BLE |
| 3E001_cal_factor_v5.ino | node/3E001_cal_factor_v5/ | DONE 3-cell |
| 3E001_cal_factor_v5_1.ino | node/3E001_cal_factor_v5_1/ | DONE + timing |
| 3E001_cal_factor_v5_2.ino | node/3E001_cal_factor_v5_2/ | DONE + per-iteration weight |
| 3E002_noise_floor_v1.ino | node/3E002_noise_floor_v1/ | DONE BLE off |
| 3E002_noise_floor_v1_ble.ino | node/3E002_noise_floor_v1_ble/ | DONE BLE on |
| 3E003_ble_transport_v1.ino | node/3E003_ble_transport_v1/ | DONE ← CURRENT PRODUCTION NODE |
| HW_VERIFY_3CELL.ino | node/HW_VERIFY_3CELL/ | DONE permanent diagnostic tool |
| STOP.ino | node/STOP/ | Available |
| HW_VERIFY.ino | node/HW_VERIFY/ | Single-cell only |

---

## Hub — COMPLETE AND DEPLOYED

Location: ~/ArduinoApps/gas-cylinder-monitor/hub/
App Lab ID: user:gas-cylinder-monitor/hub
WebUI URL: http://AQ3:7000

### Hub files
| File | Purpose |
|---|---|
| app.yaml | App Lab manifest |
| setup.sh | One-time board setup — builds wheels, socat service, typelibs |
| deploy.sh | Start/restart app — always use this, never manual docker |
| python/main.py | App Lab entry point — WebUI + BLE wiring |
| python/ble_subscriber.py | BLE central — raw dbus-python, GLib.MainLoop |
| assets/index.html | WebUI — shows grams, quality, sigma, timestamp |
| assets/socket.io.min.js | Local socket.io — no CDN |
| config.json | Device name, UUIDs, MAC cache |
| wheels/ | Pre-built .whl + .so libs — built by setup.sh |
| typelibs/ | GObject typelibs — copied by setup.sh |

### Deploy command
```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub
bash deploy.sh
```

### Logs
```bash
arduino-app-cli app logs user:gas-cylinder-monitor/hub --follow
```

---

## OPEN ISSUE — Accuracy / systematic offset

**Symptom:** Readings are proportional to weight placed but show systematic offset.
Examples from 2026-06-15 session:
- Empty platform: ~−10 to −25g (should be ~0g)
- ~180g reference weight: hub shows ~174–188g (close, ~5g error)
- ~220g: hub shows ~220g (good)
- ~689g: hub shows ~689g (good)
- ~1587g: hub shows ~1587g (good)

**Diagnosis (preliminary):** Tare reference mismatch between calibration session
(2026-06-12, tare_raw unknown) and this session (2026-06-15, tare_raw=-97535).
Cal_factor is correct (proportional response confirmed). Zero reference may have
drifted. This is a systematic offset, not a linearity problem.

**What next session must do:**
1. Place known reference weights (with exact gram values) on platform
2. Record: actual weight vs hub reading vs Serial Monitor reading
3. Calculate: offset = (measured − actual). Is it constant across weights?
4. If constant offset → tare drift → investigate re-tare mechanism
5. If offset scales with weight → cal_factor error → re-derive

Do NOT modify cal_factor before this data is collected.
Bring exact Serial Monitor data to next session for analysis.

---

## Key BlueZ finding — CRITICAL for all future BLE central projects

**Problem:** `org.freedesktop.DBus.Error.UnknownObject: Method "Connect" with
signature "" on interface "org.bluez.Device1" doesn't exist`

**Cause:** Calling adapter.RemoveDevice() then immediately trying to Connect() on
the same path. RemoveDevice deletes the path from BlueZ. The object no longer
exists. Connecting to a deleted path = UnknownObject error.

**Fix:** Do NOT call RemoveDevice before connecting. When a device is found via
InterfacesAdded signal, the object is live. Connect directly:

```python
def _connect(self, path):
    try:
        dev_obj = self.bus.get_object(BLUEZ, path)
        device  = dbus.Interface(dev_obj, DEVICE_IFACE)
        print('[BLE_SUB] Connecting...', flush=True)
        device.Connect()
        self.target_device = path
        print('[BLE_SUB] Connected', flush=True)
        time.sleep(4)  # wait for GATT service resolution
        GLib.idle_add(self._find_characteristic)
    except Exception as e:
        print(f'[BLE_SUB] Connect failed: {e}', flush=True)
        GLib.timeout_add(5000, lambda: self._start_scan() or False)
    return False
```

**Rule locked:** Never call RemoveDevice before Connect on a freshly discovered
device. RemoveDevice is only valid for clearing stale cache entries of devices
that are NOT currently being discovered.

**Also confirmed:** On first deploy after socat service restart, dbus.sock may
not exist immediately. deploy.sh must restart the socat service (not just check
if active) to guarantee a fresh socket file before the app starts.

---

## Hub BLE pattern — working reference (dbus-python, NOT bleak)

```python
# Env setup — MUST be before any dbus import
os.environ['GI_TYPELIB_PATH'] = '/app/typelibs'
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

# Load shared libs via ctypes
for lib in ['libm.so.6', 'libcap.so.2', ...]:
    ctypes.CDLL(f'/app/wheels/{lib}')

sys.path.insert(0, '/usr/lib/python3/dist-packages')

# Discovery filter — le transport ONLY, UUID filter
adapter.SetDiscoveryFilter(dbus.Dictionary({
    'UUIDs':     dbus.Array([SERVICE_UUID], signature='s'),
    'Transport': dbus.String('le')   # NEVER 'auto' — kills BT adapter on QRB2210
}, signature='sv'))

# Connect directly on InterfacesAdded — no RemoveDevice
# Subscribe via StartNotify + add_signal_receiver for PropertiesChanged
```

---

## App Lab / Docker pattern — confirmed working

```yaml
# app.yaml
network_mode: "host"
sockets:
  - "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
```

Socat systemd service: `dbus-bridge-gas-cylinder-monitor.service`
Creates: `~/ArduinoApps/gas-cylinder-monitor/hub/dbus.sock`
Inside container: `/app/dbus.sock`

requirements.txt must reference wheel files by exact path:
```
/app/wheels/dbus_python-1.4.0-cp313-cp313-linux_aarch64.whl
/app/wheels/pycairo-1.29.0-cp313-cp313-linux_aarch64.whl
/app/wheels/pygobject-3.56.3-cp313-cp313-linux_aarch64.whl
```

setup.sh auto-generates requirements.txt from actual wheel filenames — never hardcode.

---

## What next session must do — in order

### Priority 1 — Session close (do this first)
Run Claude Code CLI on AQ3 to update all project docs per SESSION_CLOSE_PROTOCOL.md:
- Update CLAUDE.md current position
- Update PROJECT_CONTEXT.md
- Append SESSIONS.md session block
- Append LEARNINGS_AND_INSIGHTS.md new L-entries (see below)
- Append RESEARCH.md hub/BLE findings
- Create HANDOFF_2026_06_15_SESSION1_3E003_hub_demo.md in docs/
- Git commit and push

### New L-entries to add (append to LEARNINGS_AND_INSIGHTS.md)

**L-XXX — BlueZ RemoveDevice before Connect causes UnknownObject error**
On QRB2210 BlueZ, calling adapter.RemoveDevice(path) then device.Connect(path)
immediately after fails with UnknownObject. RemoveDevice deletes the D-Bus object.
Fix: connect directly without RemoveDevice on freshly discovered devices.

**L-XXX — socat dbus.sock only exists after first restart, not first start**
On first systemd start, socat may not create the socket file immediately.
deploy.sh must always restart (not just check) the socat service to guarantee
fresh socket before app container starts.

**L-XXX — dbus-python requires libdbus-1-dev to build wheel**
pip3 wheel dbus-python fails with "Dependency dbus-1 not found" without libdbus-1-dev.
Fix: apt install libdbus-1-dev before building wheels.

**L-XXX — App Lab venv installs only what is in python/requirements.txt**
Wheels in wheels/ directory are not automatically installed. requirements.txt
must explicitly reference each wheel by its /app/wheels/ path. setup.sh must
auto-generate requirements.txt from actual wheel filenames present in wheels/
so version changes don't break deployment.

**L-XXX — BLE noise characterisation ordering: BLE must start AFTER Phase 2**
Noise characterisation measures the hardware floor. BLE is a noise source we
control. Even if BLE EMI penalty is empirically small (~1.0x), BLE must not
run during Phase 2 because any EMI contribution gets baked into threshold_g,
inflating the quality gate. Sequence: settle → tare → characterise → start BLE.

**L-XXX — handleRunning() needs DOUT wait inside collection loop**
readHX711() in 3E002 does not block for DOUT LOW. Called in tight loop without
DOUT check, most calls hit HX711 mid-conversion → 0L corrupt → fewer than 10
valid samples in 20 attempts → computeQuality() returns FAILED.
Fix: wait for DOUT LOW (max 200ms) before each readHX711() call in PHASE_RUNNING.

### Priority 2 — Accuracy investigation
Place known weights on platform. Record actual vs measured. Data goes in chat.
See OPEN ISSUE section above for investigation protocol.

### Priority 3 — Post-demo build queue (design in chat before any code)
1. Timestamps — millis-based on node, wall clock on hub. Both sides.
2. Unified log file — hub writes all events to rotating daily log.
3. HW_VERIFY_3CELL lift test integration into hub diagnostics.
4. Modular refactor of production node sketch.

---

## Key rules — never violate

| Rule | Detail |
|---|---|
| No hardcoding | cal_factor and tare always derived |
| No HX711 library | raw bit-bang only |
| Three corrupt filters | LONG_MIN, -1, 0x7FFFFF — always all three |
| noInterrupts() | mandatory during 25-pulse sequence |
| INPUT_PULLUP on DOUT | mandatory |
| Sign-extend bit 23 | mandatory |
| HX711 VCC = 3V3 only | NEVER 5V |
| GPIO4 = DT, GPIO3 = SCK | locked, never change |
| No String class | snprintf into char buf[] only |
| No blocking in loop() | millis() pacing only |
| float not double | safe default on ESP32-C3 |
| Tare after stability | never tare before Phase 0 + Phase 1 complete |
| BLE transport | BlueZ: "le" transport only, NO RemoveDevice before Connect |
| SCP hostname | always arduino@AQ3 — never IP address |
| Design in chat | all code written exclusively via Claude Code CLI on AQ3 |
| deploy.sh only | never start/stop app manually — always use deploy.sh |
| APP_NAME from app.yaml | never hardcode, never use basename — read from app.yaml |
| requirements.txt | auto-generated by setup.sh from actual wheel filenames |

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md
├── node/
│   ├── E000_raw_read/
│   ├── E001_tare_cal_grams/
│   ├── E002_noise_floor/
│   ├── E003_ble_transport/
│   ├── 3E001_cal_factor_v5/
│   ├── 3E001_cal_factor_v5_1/
│   ├── 3E001_cal_factor_v5_2/
│   ├── 3E002_noise_floor_v1/
│   ├── 3E002_noise_floor_v1_ble/
│   ├── 3E003_ble_transport_v1/    ← CURRENT PRODUCTION NODE SKETCH
│   ├── HW_VERIFY_3CELL/
│   ├── STOP/
│   └── HW_VERIFY/
├── hub/                           ← COMPLETE AND DEPLOYED
│   ├── app.yaml
│   ├── setup.sh
│   ├── deploy.sh
│   ├── python/
│   │   ├── main.py
│   │   ├── ble_subscriber.py
│   │   └── requirements.txt
│   ├── assets/
│   │   ├── index.html
│   │   └── socket.io.min.js
│   ├── wheels/
│   ├── typelibs/
│   └── config.json
└── docs/
    ├── CLAUDE.md
    ├── SESSIONS.md
    ├── LEARNINGS_AND_INSIGHTS.md
    ├── RESEARCH.md
    ├── PROJECT_CONTEXT.md
    ├── EXPERIMENT_PROGRAM.md
    ├── EXPERIMENT_HISTORY.md
    ├── SESSION_CLOSE_PROTOCOL.md
    └── HANDOFF_2026_06_16_FINAL.md ← this file
```

---

## Session start checklist for new chat

Before answering anything, confirm:
1. This document read fully
2. Working mode: chat = design only, CLI = code only
3. Current position: 3E-003 COMPLETE. Demo achieved. Hub deployed and running.
4. Platform: 3-cell YZC-161A parallel, fibre plate. cal_factor = 36.1 raw/g LOCKED.
5. Noise floor LOCKED: STD 4.64g BLE-on, threshold 18.54g BLE-on.
6. BLE UUIDs locked: Service aa206b91... Char b9b25bb1... Device GasCylMonitor
7. Hub running at user:gas-cylinder-monitor/hub, WebUI at AQ3:7000
8. Open issue: accuracy offset — needs known weight data from user before diagnosing
9. Session close docs NOT YET DONE — do this first via Claude Code CLI
10. BlueZ rule: NEVER RemoveDevice before Connect on fresh discovery

---

## SCP command to save this file to the board

From Windows laptop terminal:
```
scp HANDOFF_2026_06_16_FINAL.md arduino@AQ3:/home/arduino/ArduinoApps/gas-cylinder-monitor/docs/HANDOFF_2026_06_16_FINAL.md
```

Then on the board:
```
cd ~/ArduinoApps/gas-cylinder-monitor && git add -A && git commit -m "feat(3E-003): end-to-end BLE transport complete — hub deployed, demo achieved" && git push
```

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_16_FINAL.md fully before responding.
Context: 3E-003 COMPLETE. Full end-to-end working. Demo achieved.
Today we: (1) run session close docs via Claude Code CLI, (2) investigate
accuracy offset with known weight data, (3) begin post-demo build queue.
Start by confirming you read the handoff and state current position."

---

*End of handoff. Next chat is ready.*
