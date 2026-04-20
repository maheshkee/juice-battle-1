# BLE WebUI - No AppLab

**Arduino UNO Q - BLE GATT Peripheral + Web Dashboard + MCU LED Control**

Fully independent of Arduino App Lab. No app.yaml, no App.run(), no AppLab dependency of any kind.
Direct Unix socket + MessagePack RPC to the arduino-router daemon.

---

## What This Project Does

- MPU (QRB2210, Debian Linux) advertises as BLE peripheral UNO-Q-BLE
- Phone running nRF Connect connects and writes to a BLE characteristic
- Writing 1 turns the MCU green LED (LED3_G / PH11) ON via Bridge RPC
- Writing 0 turns it OFF
- Every BLE event, Bridge call, and MCU response appears live on a web dashboard
- Web dashboard streams events in real time via Server-Sent Events (SSE)

---

## Architecture
Phone (nRF Connect)
|  BLE 2.4GHz
v
MPU - Debian Linux (QRB2210)
|-- ble_server.py    BlueZ GATT peripheral (advertise + receive writes)
|-- bridge.py        ArduinoBridge - Unix socket + MessagePack RPC
|-- web_handler.py   Flask web server - dashboard + SSE stream
|-- state.py         Thread-safe shared application state
+-- main.py          Entry point - wires all modules together
|
|  UART /dev/ttyHS1 @ 115200 baud (via arduino-router daemon)
v
MCU - Zephyr OS (STM32U585)
+-- sketch.ino       Bridge.provide("set_led") + Bridge.provide("get_led")
Controls LED3_G (PH11, active-low)

---

## Project Structure
ble-webui-no-applab/
|-- sketch/
|   +-- sketch.ino           MCU firmware - Bridge RPC handlers + LED control
|-- python/
|   |-- main.py              Entry point - run this to start everything
|   |-- state.py             Thread-safe shared state + SSE event bus
|   |-- bridge.py            ArduinoBridge - raw socket + msgpack
|   |-- ble_server.py        BlueZ GATT server - BLE peripheral + advertise
|   +-- web_handler.py       Flask HTTP server - web UI + SSE /events
+-- assets/
|-- index.html           Dashboard UI
|-- style.css            Dark theme stylesheet
+-- app.js               SSE listener + live event log

---

## BLE Service Definition

| Property     | Value                                              |
|--------------|----------------------------------------------------|
| Device name  | UNO-Q-BLE                                         |
| Service UUID | 0000FFE0-0000-1000-8000-00805F9B34FB              |
| LED char     | 0000FFE1-0000-1000-8000-00805F9B34FB write+notify |
| Status char  | 0000FFE2-0000-1000-8000-00805F9B34FB read+notify  |
| Write 01     | LED ON                                             |
| Write 00     | LED OFF                                            |

---

## Hardware

| Component   | Detail                          |
|-------------|---------------------------------|
| Board       | Arduino UNO Q (ABX00162)        |
| MPU         | Qualcomm QRB2210 - Debian Linux |
| MCU         | STM32U585 - Zephyr OS           |
| BLE radio   | WCBN3536A (on MPU side)         |
| LED         | LED3_G - PH11 - active-low      |
| UART bridge | /dev/ttyHS1 @ 115200 baud       |

---

## Setup From Scratch - Complete Step-by-Step

### Stage 1 - Verify system prerequisites (SSH into board)

```bash
# 1. Check arduino-router is running
systemctl status arduino-router
# Expected: active (running)

# 2. Check Unix socket exists
ls -la /var/run/arduino-router.sock
# Expected: srw-rw-rw- ... /var/run/arduino-router.sock

# 3. Check UART is owned by router
sudo fuser /dev/ttyHS1
# Expected: a PID number (the router process)

# 4. Check BLE adapter
hciconfig
# Expected: hci0 ... UP RUNNING

# 5. Check BlueZ is running
systemctl status bluetooth
# Expected: active (running)
```

---

### Stage 2 - Install Python dependencies (on board via SSH)

```bash
# Install msgpack
pip install msgpack --break-system-packages

# Verify
python3 -c "import msgpack; print(msgpack.__version__)"

# Install Flask
pip install flask --break-system-packages

# Verify
python3 -c "import flask; print(flask.__version__)"

# Verify D-Bus and GLib (pre-installed on board)
python3 -c "import dbus; from gi.repository import GLib; print('dbus and GLib ok')"

# Verify all dependencies at once
python3 -c "import msgpack, flask, dbus; from gi.repository import GLib; print('ALL OK')"
```

---

### Stage 3 - Flash the MCU sketch

**Option A - From Windows (recommended for first time):**

```powershell
# Compile
arduino-cli compile --fqbn arduino:zephyr:unoq D:\path\to\ble-webui-no-applab\sketch

# Upload via USB (find your port with: arduino-cli board list)
arduino-cli upload -p COM5 --fqbn arduino:zephyr:unoq D:\path\to\ble-webui-no-applab\sketch

# Expected: New upload port: COM5 (serial)
```

**Option B - From Linux on the board itself:**

```bash
# Compile (all --library flags are required - dependencies not auto-resolved on Linux)
arduino-cli compile \
  --fqbn arduino:zephyr:unoq \
  --library ~/.arduino15/internal/Arduino_RouterBridge_0.4.1_d378119a47d2c8c4/Arduino_RouterBridge \
  --library ~/.arduino15/internal/Arduino_RPClite_0.2.1_ce72ff552a496aef/Arduino_RPClite \
  --library ~/.arduino15/internal/MsgPack_0.4.2_a0d4adc5044d022c/MsgPack \
  --library ~/.arduino15/internal/DebugLog_0.8.4_c199e2cf6415ecc8/DebugLog \
  --library ~/.arduino15/internal/ArxContainer_0.7.0_007f0bb2a1cdefe3/ArxContainer \
  --library ~/.arduino15/internal/ArxTypeTraits_0.3.2_d65e2aabfeed7838/ArxTypeTraits \
  ~/project13/ble-webui-no-applab/sketch/

# Expected: Sketch uses X bytes (Y%) of program storage space.

# Upload via network - board uploads to its own MCU over WiFi
arduino-cli upload \
  --port 192.168.1.154 \
  --protocol network \
  --fqbn arduino:zephyr:unoq \
  ~/project13/ble-webui-no-applab/sketch/

# Expected: New upload port: 192.168.1.154 (network)
```

---

### Stage 4 - Clone the project and run

```bash
# Clone the repo
git clone git@github.com:gratiantechnologies/project13.git

# Navigate to the project
cd project13/ble-webui-no-applab

# Run the project
python3 python/main.py
```

Expected startup output:
[main] INFO: Connecting to bridge...
[main] INFO: ============================================
[main] INFO:   BLE WebUI v1 running
[main] INFO:   Web UI  : http://192.168.1.154:5000
[main] INFO:   BLE name: UNO-Q-BLE
[main] INFO:   Write 01 to LED char -> LED ON
[main] INFO:   Write 00 to LED char -> LED OFF
[main] INFO: ============================================
[ble]  INFO: GATT registered
[ble]  INFO: Advertising as UNO-Q-BLE

---

### Stage 5 - Test the full stack

| Step | Action                                   | Expected Result                          |
|------|------------------------------------------|------------------------------------------|
| 1    | Browser open http://board-ip:5000        | Dashboard loads                          |
| 2    | nRF Connect - scan for BLE              | UNO-Q-BLE appears in scan list           |
| 3    | nRF Connect - connect to UNO-Q-BLE      | Service FFE0 visible                     |
| 4    | Subscribe to FFE1 and FFE2 notify       | Subscribed successfully                  |
| 5    | Write 01 to FFE1 characteristic         | LED3_G lights up green on board          |
| 6    | Check web dashboard                      | ble_write + led + mcu_response logged    |
| 7    | Write 00 to FFE1 characteristic         | LED3_G turns off                         |
| 8    | Check web dashboard                      | Events logged correctly                  |

---

## System Health Check Commands

```bash
# Is the router running?
systemctl status arduino-router

# Does the socket exist?
ls -la /var/run/arduino-router.sock

# Is UART locked by the router?
sudo fuser /dev/ttyHS1

# Is the BLE adapter up?
hciconfig

# Is BlueZ running?
systemctl status bluetooth

# Are Python dependencies installed?
python3 -c "import msgpack, flask, dbus; from gi.repository import GLib; print('ALL OK')"
```

---

## Key Concepts

**No App Lab** - Communicates directly with arduino-router via Unix socket and MessagePack RPC.
No IDE dependency at runtime. The project runs standalone from the terminal.

**arduino-router** - System daemon that owns /dev/ttyHS1 and routes RPC calls between Linux
processes and the MCU. Never open /dev/ttyHS1 directly while it is running.

**Bridge RPC primitives:**
- call(method, args)   - Send REQUEST to MCU, block until RESPONSE arrives (synchronous)
- notify(method, args) - Fire-and-forget NOTIFY to MCU, no response expected (async)
- on(method, fn)       - Subscribe to incoming NOTIFYs from MCU

**Active-low LED** - digitalWrite(LED3_G, LOW) turns the LED ON. HIGH turns it OFF.
This is a hardware wiring convention on the UNO Q board.

**BLE ASCII vs raw byte** - nRF Connect sends text characters. Writing "1" sends byte 49
(ASCII '1'), not byte value 1. The code handles both cases: b == 1 or b == 49.

**Function registry** - Bridge.provide("set_led", fn) registers the function in a RAM-based
lookup table on the MCU, rebuilt every boot by setup(). The router forwards incoming RPC
calls to registered methods only.

**$/register** - Internal RPC method used by both router and RouterBridge to subscribe
clients to specific method names. Called automatically when you use bridge.on() in Python
or Bridge.provide() in the sketch.

---

## Version History

| Version | Description                                                        |
|---------|--------------------------------------------------------------------|
| v1.0    | BLE GATT peripheral + MCU LED control + Web dashboard - zero AppLab |

---

## License

MIT
