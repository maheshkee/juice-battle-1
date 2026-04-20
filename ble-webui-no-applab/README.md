# BLE WebUI - No AppLab

**Arduino UNO Q - BLE GATT Peripheral + Web Dashboard + MCU LED Control**

Fully independent of Arduino App Lab. No app.yaml, no App.run(), no AppLab dependency.
Direct Unix socket + MessagePack RPC to the arduino-router daemon.

---

## What This Project Does

- MPU (QRB2210, Debian Linux) advertises as BLE peripheral `UNO-Q-BLE`
- Phone running nRF Connect connects and writes to a BLE characteristic
- Writing `1` turns the MCU green LED (LED3_G / PH11) ON via Bridge RPC
- Writing `0` turns it OFF
- Every BLE event, Bridge call, and MCU response appears live on a web dashboard
- Web dashboard streams events in real time via Server-Sent Events (SSE)

---

## Architecture

```
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
```

---

## Project Structure

```
ble-webui-no-applab/
|-- setup.sh             One-time prerequisites check and install
|-- run.py               Single entry point: compile + upload + start
|-- sketch/
|   +-- sketch.ino       MCU firmware
|-- python/
|   |-- main.py          Application entry point
|   |-- state.py         Thread-safe shared state + SSE event bus
|   |-- bridge.py        ArduinoBridge - raw socket + msgpack
|   |-- ble_server.py    BlueZ GATT server - BLE peripheral
|   +-- web_handler.py   Flask HTTP server + SSE /events
+-- assets/
    |-- index.html       Dashboard UI
    |-- style.css        Dark theme stylesheet
    +-- app.js           SSE listener + live event log
```

---

## BLE Service Definition

| Property     | Value                                              |
|--------------|----------------------------------------------------|
| Device name  | UNO-Q-BLE                                         |
| Service UUID | 0000FFE0-0000-1000-8000-00805F9B34FB               |
| LED char     | 0000FFE1-0000-1000-8000-00805F9B34FB write+notify  |
| Status char  | 0000FFE2-0000-1000-8000-00805F9B34FB read+notify   |
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

## Getting Started

### Step 1 - Clone the repo (first time on a new board)

```bash
git clone git@github.com:gratiantechnologies/project13.git
cd project13/ble-webui-no-applab
```

### Step 2 - Run setup (one time only per board)

```bash
bash setup.sh
```

Installs Python dependencies and verifies all system prerequisites.

Expected output (all green):
```
  [OK]   msgpack installed
  [OK]   flask installed
  [OK]   arduino-router running
  [OK]   bluetooth running
  [OK]   BLE adapter UP
  [OK]   Board detected on network
  All checks passed. Run: python3 run.py
```

### Step 3 - Run (every time)

```bash
python3 run.py
```

This single command does everything:
1. Compiles the MCU sketch
2. Verifies compilation passed (exits with error if not)
3. Auto-detects the board IP on the network
4. Uploads the sketch to the MCU over WiFi
5. Waits 4 seconds for MCU to reboot
6. Starts the full application (BLE + Web UI + Bridge)

Expected output:
```
====================================================
  BLE WebUI No AppLab - Starting Up
====================================================

[>] Compiling MCU sketch...
    [OK]   Sketch compiled successfully

[>] Detecting board on network...
    [OK]   Board found at 192.168.1.154

[>] Uploading sketch to MCU via 192.168.1.154...
    [OK]   Sketch uploaded successfully

[>] Waiting for MCU to reboot (4 seconds)...
    [OK]   MCU ready

[>] Starting BLE WebUI application...

[main] INFO: BLE WebUI v1 running
[main] INFO: Web UI  : http://192.168.1.154:5000
[main] INFO: BLE name: UNO-Q-BLE
[ble]  INFO: GATT registered
[ble]  INFO: Advertising as UNO-Q-BLE
```

---

## Testing the Full Stack

| Step | Action                            | Expected Result                       |
|------|-----------------------------------|---------------------------------------|
| 1    | Browser: http://board-ip:5000     | Dashboard loads                       |
| 2    | nRF Connect - scan                | UNO-Q-BLE appears                     |
| 3    | nRF Connect - connect             | Service FFE0 visible                  |
| 4    | Subscribe to FFE1 and FFE2 notify | Subscribed                            |
| 5    | Write 01 to FFE1                  | LED3_G lights up green                |
| 6    | Check web dashboard               | ble_write + led + mcu_response logged |
| 7    | Write 00 to FFE1                  | LED3_G turns off                      |
| 8    | Check web dashboard               | Events logged correctly               |

---

## System Health Check

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

# Is the board visible on network?
arduino-cli board list

# Are all Python dependencies installed?
python3 -c "import msgpack, flask, dbus; from gi.repository import GLib; print('ALL OK')"
```

---

## Key Concepts

**No App Lab** - Communicates directly with arduino-router via Unix socket and MessagePack
RPC. No IDE dependency at runtime. Runs standalone from the terminal.

**arduino-router** - System daemon that owns /dev/ttyHS1 and routes RPC calls between Linux
processes and the MCU. Never open /dev/ttyHS1 directly while it is running.

**Bridge RPC primitives:**
- `call(method, args)`   - Send REQUEST to MCU, block until RESPONSE (synchronous)
- `notify(method, args)` - Fire-and-forget NOTIFY to MCU, no response (async)
- `on(method, fn)`       - Subscribe to incoming NOTIFYs from MCU

**Active-low LED** - `digitalWrite(LED3_G, LOW)` turns ON. `HIGH` turns OFF.

**BLE ASCII vs raw byte** - nRF Connect sends ASCII characters. Writing "1" sends byte 49.
The code handles both: `b == 1 or b == 49`.

**Function registry** - `Bridge.provide("set_led", fn)` registers a RAM-based entry on the
MCU rebuilt every boot by setup(). Router forwards calls to registered methods only.

**$/register** - Internal RPC method used by router and RouterBridge to subscribe clients
to specific method names. Called automatically by bridge.on() and Bridge.provide().

---

## Version History

| Version | Description                                                          |
|---------|----------------------------------------------------------------------|
| v1.0    | BLE GATT peripheral + MCU LED control + Web dashboard - zero AppLab |
