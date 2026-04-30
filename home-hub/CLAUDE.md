# CLAUDE.md — home-hub
# Arduino UNO Q (AQ2) | App Lab | Python + C++ + BLE
# Updated: 2026-04-29

## How We Work
Claude is ORCHESTRATOR. Mahesh is EXECUTOR.
- ONE chunk at a time — never multiple files in one response
- State target file + why before writing any code
- Wait for confirmation before next chunk
- If a chunk fails, diagnose before retrying
- Never proceed past a failed step

## Current status
- gas_monitor.py: DONE — skeleton in python/services/gas_monitor.py
- sketch.ino: DONE — Zephyr-compatible HX711 bit-bang, get_weight() Bridge RPC
- splash.html: YT display working — gas view not yet added
- gas_dashboard.html: NOT CREATED yet
- Next task: gas_dashboard.html + splash.html gas panel

## Board
- MPU: QRB2210, Debian Linux, Python in Docker at ~/ArduinoApps/home-hub/
- MCU: STM32U585, Zephyr, C++ sketch
- Bridge: LPUART1, 9600 baud, Bridge.call() blocks / Bridge.notify() fire-and-forget
- BLE: BlueZ on MPU side. le transport ONLY — auto kills adapter permanently.
- Docker /app = host ~/ArduinoApps/home-hub/. sockets: in app.yaml = broken.
- JCTL header = 1.8V ONLY. MCU headers = 3.3V (A0/A1 not 5V tolerant).

## Project structure
~/ArduinoApps/home-hub/
├── app.yaml                      ← network_mode:host, port 7000, NO sockets:
├── CLAUDE.md                     ← this file
├── python/
│   ├── main.py                   ← orchestrator only, no logic
│   ├── config.py                 ← ALL thresholds here
│   ├── queue_engine.py           ← YT queue [STABLE — do not touch]
│   ├── local_engine.py           ← local files [STABLE — do not touch]
│   ├── ble_gatt_serve.py         ← GATT server [STABLE — do not touch]
│   ├── bt_manager.py             ← BT stub [do not expand without approval]
│   └── services/
│       └── gas_monitor.py        ← gas service [ACTIVE — in development]
├── sketch/sketch.ino             ← MCU: HX711 + LPUART [ACTIVE]
├── assets/
│   ├── splash.html               ← SPA [modify carefully, never remove existing divs]
│   ├── gas_dashboard.html        ← gas view [NOT CREATED YET]
│   └── videos/                   ← [DO NOT TOUCH]
└── data/gas_monitor.db           ← SQLite, auto-created on first run

## Module ownership
| Module          | Owns                      | Must NOT do             |
|-----------------|---------------------------|-------------------------|
| queue_engine    | YT queue state            | touch other services    |
| local_engine    | local file list + play    | touch other services    |
| ble_gatt_serve  | GATT server + CMD routing | touch other services    |
| gas_monitor     | sensor + SQLite + predict | touch other services    |
| main.py         | wiring only               | own any logic           |

Cross-module coordination → hook/callback in main.py only.
bt_manager.py — stub only. Exists to satisfy ble_gatt_serve.py imports. All BT management functions are no-ops. Do not expand without approval.

## Never violate
1. BLE scan: le transport ONLY. auto kills adapter → sudo reboot only recovery.
2. sockets: in app.yaml = broken. D-Bus via socat at /app/dbus.sock only.
3. Chromium: one instance only. Never kill/relaunch. Socket.IO show/hide only.
4. Video commands: write_cmd() → Socket.IO only. Never file-based.
5. Local videos: /videos/filename.mp4 — NOT /assets/videos/.
6. BT audio: A2DP D-Bus only. HDMI broken permanently on QRB2210.
7. BT_LIST/BT_SCAN: D-Bus direct only — never bluetoothctl, disrupts A2DP.
8. LightDM: exactly ONE [Seat:*] section — second one breaks auto-login silently.
9. launcher.sh filename must NOT contain "chromium" — pkill -f matches full path.
10. Tare: ONLY from cylinder_templates SQLite table. Never hardcode.
11. Weight unit: kg everywhere internally. Convert only at display layer.
12. No hardcoding: all paths dynamic (SCRIPT_DIR/APP_NAME/APP_DIR). Works for any user/folder.

## Active patterns

```python
# BLE D-Bus setup (always use exactly this, no variations)
import os, sys, ctypes
os.environ['GI_TYPELIB_PATH'] = '/app/typelibs'
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'
for lib in ['libm.so.6','libcap.so.2','libpcre2-8.so.0','libselinux.so.1',
            'libaudit.so.1','libcap-ng.so.0','libexpat.so.1','libdbus-1.so.3',
            'libapparmor.so.1','libsystemd.so.0','libgirepository-2.0.so.0']:
    try: ctypes.CDLL(f'/app/wheels/{lib}')
    except Exception as e: print(f'[BLE] {lib}: {e}', flush=True)
sys.path.insert(0, '/usr/lib/python3/dist-packages')
import dbus, dbus.mainloop.glib
from gi.repository import GLib

# write_cmd — display routing (Socket.IO only, never file-based)
def write_cmd(cmd):
    if cmd == "STOP":
        ui.send_message("player_control", {"action": "stop"})
    elif cmd.startswith("LOCAL:"):
        ui.send_message("play_local_display", {"filename": cmd[6:]})
    else:
        ui.send_message("play_video_display", {"video_id": cmd})

# push_evt — BLE notify + Socket.IO
def push_evt(data):
    try: ble.push_evt(data)
    except Exception: pass
    ui.send_message(data.get("event", "evt"), data)
```

```bash
# Python file edit pattern (always use this, never sed/regex)
python3 << 'EOF'
with open('/path/file.py', 'r') as f: content = f.read()
content = content.replace('''OLD''', '''NEW''')
with open('/path/file.py', 'w') as f: f.write(content)
print("Done")
EOF
python3 -c "import ast; ast.parse(open('/path/file.py').read()); print('OK')"
```

## BLE UUIDs (DO NOT CHANGE — hardcoded in Flutter app)
Service:  a01c0000-0000-0000-0000-000000000000
CMD char: a01c0001-0000-0000-0000-000000000000  (WRITE, phone→board)
EVT char: a01c0002-0000-0000-0000-000000000000  (NOTIFY, board→phone)

## Bridge RPC — MCU functions provided
| Function           | Args | Returns                                              |
|--------------------|------|------------------------------------------------------|
| read_weight_packet | none | dict: weight_kg, raw_kg, stable, sensor_ok, timestamp |
| read_battery_pct   | none | int 0-100                                            |
| set_led_red        | bool | none                                                 |
| set_led_green      | bool | none                                                 |

## Gas monitor rules
- REFILL_THRESHOLD_KG = 8.0 (config.py)
- PREDICTION_WINDOW_DAYS = 7 (config.py)
- SENSOR_SAMPLE_COUNT = 20 (config.py)
- Measurement cycle: 6hr MCU RTC wake
- Tare: cylinder_templates SQLite table only
- Unit: kg internally everywhere

## Coding rules
- Target file as first line of every code response
- No magic numbers — config.py or #define
- snake_case functions, UPPER_SNAKE_CASE constants
- Every UART read/write: timeout + retry
- Never patch with sed/regex — rewrite full function cleanly
- Always verify after Python edit: python3 -c "import ast; ast.parse(open('f').read()); print('OK')"

## Deploy
```bash
arduino-app-cli app stop user:home-hub
rm -rf ~/ArduinoApps/home-hub/.cache
arduino-app-cli app start user:home-hub
sleep 20 && arduino-app-cli app logs user:home-hub
```
After CLI creates it, verify with:
cat CLAUDE.md | wc -l
Then commit:
git add CLAUDE.md && git commit -m "docs: add CLAUDE.md for Claude CLI sessions" && git push
