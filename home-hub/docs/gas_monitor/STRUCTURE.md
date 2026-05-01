# Gas Cylinder Monitor — File Structure
# home-hub service | Arduino UNO Q AQ3 | Updated: 2026-04-30

---

## Overview

The gas monitor is a **service inside home-hub**, not a standalone App Lab app.
It does not have its own `app.yaml`, `deploy.sh`, or Docker container.
It runs inside the home-hub container alongside queue_engine, local_engine, and ble_gatt_serve.

App Lab project root: `~/ArduinoApps/home-hub/`
Inside Docker: `/app/` maps to the same directory.

---

## Directory Tree

```
~/ArduinoApps/home-hub/
│
├── app.yaml                          App Lab config — name, ports, network_mode:host
├── deploy.sh                         Stop + clear cache + start (always use this)
├── setup.sh                          One-time board setup
├── CLAUDE.md                         Primary session context — read at every CLI session
│
├── python/
│   ├── main.py                       ORCHESTRATOR — wires all services, owns no logic
│   ├── config.py                     ALL thresholds and paths — never hardcode elsewhere
│   ├── ble_gatt_serve.py             GATT server, routes CMD to modules [STABLE]
│   ├── queue_engine.py               YouTube queue state machine [STABLE]
│   ├── local_engine.py               Local file management [STABLE]
│   ├── bt_manager.py                 BT stub — all functions no-ops [DO NOT EXPAND]
│   └── services/
│       ├── __init__.py               Package marker
│       └── gas_monitor.py            Gas service — sensor, SQLite, prediction [ACTIVE]
│
├── sketch/
│   ├── sketch.ino                    MCU entry point — HX711 + Bridge RPC [ACTIVE]
│   ├── ScaleHX711.cpp                Custom Zephyr bit-bang HX711 library [FLAT — required]
│   ├── ScaleHX711.h                  HX711 header [FLAT — required]
│   ├── sketch.yaml                   Library declarations (ScaleHX711 is local, not listed)
│   └── HX711/                        Original bogde library — reference only, NOT compiled
│       └── ...
│
├── assets/
│   ├── splash.html                   SPA — home/youtube/local divs, weight widget [ACTIVE]
│   ├── gas_dashboard.html            Full gas view — NOT CREATED YET
│   ├── admin.html                    Dev backdoor
│   ├── index.html                    WebUI dashboard
│   └── socket.io.min.js              Local copy — CDN does NOT work in App Lab
│
├── data/
│   └── gas_monitor.db                SQLite — auto-created on first run [DO NOT COMMIT]
│
├── docs/
│   └── gas_monitor/
│       ├── PROJECT_CONTEXT.md        Problem, user, platform, version history
│       ├── SPEC.md                   Hardware, Bridge RPC, MCU/Linux spec, schema
│       ├── ARCHITECTURE.md           Data flow, failure modes, module boundaries
│       └── STRUCTURE.md              This file
│
├── app/lib/                          Flutter app source (Android)
│   ├── main.dart
│   ├── models/
│   │   ├── board_event.dart
│   │   └── queue_item.dart
│   ├── services/
│   │   ├── ble_service.dart          BLE central, all commands, EVT handler
│   │   └── board_state.dart          State: queue + local files + gas status
│   ├── screens/
│   │   └── home_screen.dart
│   └── widgets/
│       ├── connect_section.dart
│       ├── youtube_section.dart
│       ├── player_controls.dart
│       ├── bt_audio_section.dart
│       ├── queue_section.dart
│       ├── queue_controls.dart
│       ├── local_section.dart
│       └── gas_section.dart          Gas card widget — NOT CREATED YET
│
├── wheels/                           Pre-built ARM64 Python wheels + shared .so libs
├── typelibs/                         GObject typelibs for dbus-python inside Docker
└── .cache/                           GITIGNORED — Docker venv, build artefacts
```

---

## File Ownership

| File | Processor | Language | Owns | Must NOT |
|------|-----------|----------|------|----------|
| `python/main.py` | MPU | Python | Wiring only | Own any logic |
| `python/config.py` | MPU | Python | All thresholds | Be imported by sketch |
| `python/services/gas_monitor.py` | MPU | Python | Sensor, SQLite, prediction, alerts | Touch other services |
| `python/ble_gatt_serve.py` | MPU | Python | GATT server, CMD routing | Own logic |
| `python/queue_engine.py` | MPU | Python | YouTube queue state | Touch other services |
| `python/local_engine.py` | MPU | Python | Local file management | Touch other services |
| `python/bt_manager.py` | MPU | Python | BT D-Bus (stub) | Be expanded without approval |
| `sketch/sketch.ino` | MCU | C++/Zephyr | HX711 reading, Bridge RPC handlers | Import Python modules |
| `sketch/ScaleHX711.cpp` | MCU | C++ | HX711 bit-bang protocol | Use shiftIn/shiftOut |
| `assets/splash.html` | MPU | HTML/JS | LCD SPA, all view divs | Remove existing divs |
| `assets/gas_dashboard.html` | MPU | HTML/JS | Full gas view | Be created without approval |
| `data/gas_monitor.db` | MPU | SQLite | All gas readings, templates | Be committed to git |

---

## Naming Rules

| Entity | Convention | Example |
|--------|-----------|---------|
| Python functions | snake_case | `_predict_refill_days()` |
| Python constants | UPPER_SNAKE_CASE | `REFILL_THRESHOLD_KG` |
| Python private functions | leading underscore | `_read_sensor()` |
| C++ functions | camelCase or snake_case | `readWeight()` |
| C++ constants | UPPER_SNAKE_CASE or `#define` | `SENSOR_SAMPLE_COUNT` |
| SQLite tables | lowercase, underscore | `cylinder_templates` |
| Socket.IO events | snake_case | `weight_update`, `gas_prediction` |
| BLE CMD commands | UPPER with colon separator | `GAS_STATUS`, `GAS_TARE` |
| BLE EVT event field | snake_case | `gas_refill_alert` |
| Doc files | UPPER_SNAKE_CASE.md | `ARCHITECTURE.md` |

---

## What Goes Where

| Content | File | Rule |
|---------|------|------|
| All numeric thresholds | `python/config.py` | Never hardcode in logic files |
| Database path | `python/config.py` as `GAS_DB_PATH` | Computed from `__file__`, not hardcoded |
| Tare values | `data/gas_monitor.db` → `cylinder_templates` table | Never hardcode tare in Python or C++ |
| MCU pin assignments | `sketch/sketch.ino` as `#define` constants | Never hardcode pin numbers inline |
| Bridge RPC function names | `sketch/sketch.ino` `Bridge.provide(...)` | Must match Python `bridge.call("...")` exactly |
| Socket.IO event names | `assets/splash.html` JS and `gas_monitor.py` | Must match exactly — no variants |
| BLE UUIDs | `python/ble_gatt_serve.py` | Never change — hardcoded in Flutter app |
| Service init | `python/main.py` | Cross-module coordination only |

---

## Files That Must Never Be Edited Directly

| File | Reason |
|------|--------|
| `data/gas_monitor.db` | Binary SQLite — use sqlite3 CLI or Python to inspect/modify |
| `python/__pycache__/` | Auto-generated bytecode |
| `python/services/__pycache__/` | Auto-generated bytecode |
| `.cache/` | Docker build artefacts — deleted on every deploy |
| `wheels/` | Pre-built ARM64 binaries — do not rebuild unless explicitly needed |
| `typelibs/` | GObject typelibs — do not modify |
| `app/android/local.properties` | Local SDK path — gitignored, machine-specific |
| `app/pubspec.lock` | Flutter dependency lock — do not edit manually |

---

## Files That Must Never Be Committed

Add to `.gitignore` if not already present:

```
.cache/
data/gas_monitor.db
dbus.sock
app/android/local.properties
app/build/
**/__pycache__/
```

---

## Deploy & Edit Patterns

### Deploy after any change
```bash
cd ~/ArduinoApps/home-hub
bash deploy.sh
```

### Force full recompile (sketch changes not taking effect)
```bash
rm -rf ~/ArduinoApps/home-hub/.cache && rm -rf ~/.arduino15/internal
bash deploy.sh
```

### Edit Python files (never use sed/regex)
```bash
python3 << 'EOF'
with open('/home/arduino/ArduinoApps/home-hub/python/services/gas_monitor.py', 'r') as f:
    content = f.read()
content = content.replace('''OLD''', '''NEW''')
with open('/home/arduino/ArduinoApps/home-hub/python/services/gas_monitor.py', 'w') as f:
    f.write(content)
print("Done")
EOF
python3 -c "import ast; ast.parse(open('python/services/gas_monitor.py').read()); print('OK')"
```

### Inspect SQLite database
```bash
sqlite3 /home/arduino/ArduinoApps/home-hub/data/gas_monitor.db
.tables
SELECT * FROM readings ORDER BY timestamp DESC LIMIT 5;
SELECT * FROM cylinder_templates;
.quit
```
