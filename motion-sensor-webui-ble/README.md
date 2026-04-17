# 🟢 motion-sensor-webui-ble

**PIR Motion Detector with Live Web Dashboard + BLE Advertising**
Arduino UNO Q · SR602 PIR sensor · BLE GATT · Arduino App Lab

---

## Version history

| Version | Status | What was added |
|---|---|---|
| v1.0 | ✅ Complete | SR602 PIR + web dashboard + event log |
| v1.1 | ✅ Complete | MCU RGB LEDs — red on detection, green on clear |
| v1.2 | ✅ Complete | BLE GATT server — phone can connect and receive notifications |

---

## What this does

Detects human presence using a miniature SR602 PIR sensor. When motion is detected:

- Web dashboard updates in real time (orange circle + event log)
- MCU RGB LEDs turn red (detection) or green (clear)
- BLE advertisement updates — phone sees `AQ2-Motion` in scanner
- GATT characteristic notifies connected phone with `0x01` (detected) or `0x00` (clear)

---

## Architecture — the full stack

```
SR602 PIR sensor (hardware)
      ↓  digital HIGH/LOW on D2
STM32U585 MCU  (Arduino sketch — Zephyr OS)
      ↓  Bridge.call("motion_event", state)
QRB2210 MPU  (Python — Debian Linux)
      ├─→  Socket.IO → Browser dashboard (port 7000)
      └─→  BlueZ D-Bus → BLE GATT → Phone (nRF Connect / custom app)
```

### The two processors

| Processor | Role | Code |
|---|---|---|
| STM32U585 (MCU) | Real-time sensor reading, edge detection, LED control | `sketch/sketch.ino` |
| QRB2210 (MPU) | Web server, BLE advertising, GATT server, event routing | `python/` |

---

## Hardware

| Component | Details |
|---|---|
| Board | Arduino UNO Q (AQ2) |
| Sensor | SR602 / HW-438 miniature PIR module |
| Connection | 3 jumper wires |

### Wiring

| SR602 pin | UNO Q header | Pin | Wire |
|---|---|---|---|
| + (power) | JANALOG | Pin 4 — +3V3 | Red |
| − (ground) | JANALOG | Pin 6 — GND | Black |
| O (signal) | JDIGITAL | Pin 3 — D2 | Any |

> SR602 is 3.3V native — no level shifting required.

---

## Software structure

```
motion-sensor-webui-ble/
├── assets/
│   ├── index.html          ← HTML structure only
│   ├── style.css           ← all presentation
│   ├── app.js              ← all socket + DOM logic
│   └── libs/
│       └── socket.io.min.js
├── python/
│   ├── main.py             ← entry point, wires all modules
│   ├── config.py           ← all constants (UUIDs, paths, lib names)
│   ├── motion.py           ← PIR Bridge handler, state management
│   ├── web_handler.py      ← WebUI setup, socket events
│   └── ble_manager.py      ← BLE advertisement + GATT server
├── sketch/
│   ├── sketch.ino          ← PIR read, edge detect, LED, Bridge.call
│   └── sketch.yaml         ← library dependencies
├── wheels/                 ← pre-built Python C extension wheels
├── typelibs/               ← GObject introspection typelibs
├── setup.sh                ← one-command board setup script
└── app.yaml
```

### Why modular Python?

Each file has one job. Adding a new feature (email alerts, Telegram, speaker output) means adding one new file and one import in `main.py` — never touching existing code.

```python
# main.py is just wiring
ble = BLEManager()
ui  = web_handler.setup()
motion.setup(lambda state: [web_handler.broadcast_motion(state), ble.update(state)])
App.run()
```

### Why split frontend files?

- `index.html` — what is on the page (structure)
- `style.css` — how it looks (presentation)
- `app.js` — how it behaves (logic)

Change the layout without touching JS. Change colors without touching HTML. Clean separation.

---

## BLE details

### Advertisement
- Device name: `AQ2-Motion`
- Manufacturer data: `0xFF 0xFF` + `0x01` (detected) or `0x00` (clear)
- Visible in any BLE scanner (nRF Connect, LightBlue, etc.)

### GATT server
- Service UUID: `a00b0000-0000-0000-0000-000000000000`
- Characteristic UUID: `a00b0001-0000-0000-0000-000000000000`
- Properties: Read + Notify
- Value: `0x01` (motion detected) or `0x00` (area clear)

### How to connect with nRF Connect
1. Open nRF Connect → Scanner tab
2. Find `AQ2-Motion`
3. Tap Connect
4. Expand service `a00b0000...`
5. Tap the subscribe (↓) button on characteristic `a00b0001...`
6. Wave hand at sensor — phone receives `0x01` notification instantly

---

## Setup on a new board

```bash
# One command — installs all dependencies, builds wheels, starts D-Bus bridge
bash setup.sh
```

### What setup.sh does
1. Installs system packages: `libcairo2-dev`, `libgirepository-2.0-dev`, `libdbus-1-dev`, `socat`
2. Builds `dbus-python` and `PyGObject` wheels from source
3. Copies 11 shared libraries into `wheels/`
4. Copies 5 GObject typelibs into `typelibs/`
5. Creates and starts `dbus-bridge.service` (socat socket relay)
6. Updates `app.yaml` with correct socket and network config

### Why wheels and shared libs?
App Lab runs Python inside Docker. `dbus-python` is a C extension — it needs system libraries that aren't inside Docker. We pre-build the wheel on the host, copy the `.so` files, and load them via `ctypes` before importing dbus. The D-Bus socket is forwarded into Docker via socat.

---

## Running

1. Open Arduino App Lab
2. Open `motion-sensor-webui-ble`
3. Click **Run** — sketch compiles, Python starts (~60s)
4. Open browser: `http://192.168.1.154:7000`
5. Wait 60 seconds for PIR warmup
6. Open nRF Connect → Scanner → find `AQ2-Motion`

---

## Dependencies

### Sketch libraries (sketch.yaml)
- `Arduino_RouterBridge (0.3.0)` + dependencies

### Python
- `arduino.app_utils` — App, Bridge (App Lab built-in)
- `arduino.app_bricks.web_ui` — WebUI Brick
- `dbus-python 1.4.0` — D-Bus Python bindings (pre-built wheel)
- `PyGObject 3.56.2` — GLib/GIO Python bindings (pre-built wheel)

---

## Roadmap

| Version | Status | Plan |
|---|---|---|
| v1.2 | ✅ Done | BLE GATT server — phone notifications |
| v1.3 | 🔲 Planned | AQ1 MCU BLE beacon — remote room sensor |
| v2.0 | 🔲 Planned | Alert messages — email / Telegram / webhook |
| v3.0 | 🔲 Planned | Custom mobile app — real push notifications |
| v4.0 | 🔲 Planned | External output device — speaker / visual alert |

---

## Key learnings from building this

- App Lab runs Python inside Docker — C extension modules need pre-built wheels + shared libs copied in
- `sys.path.insert(0, '/usr/lib/python3/dist-packages')` makes system dbus importable without pip
- D-Bus socket at `/run/dbus/system_bus_socket` is not accessible inside Docker by default — socat bridge forwards it
- BLE D-Bus callbacks only fire when `GLib.MainLoop().run()` is running — must run in a thread
- `threading.Event()` with `wait(timeout)` is the clean way to synchronise a background BLE thread with the main thread
- JANALOG holds power pins (+3V3, GND). JDIGITAL holds digital I/O. They are on opposite sides of the board.
- PIR sensors detect change in IR — stationary persons eventually stop triggering
- Active-low LEDs: write LOW to turn ON, HIGH to turn OFF

---

*Built with Arduino App Lab 0.6.0 · BlueZ 5.82 · April 2026*
