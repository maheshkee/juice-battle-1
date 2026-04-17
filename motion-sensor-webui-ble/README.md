# 🟢 motion-sensor-webui-ble

**Multi-room PIR Motion Detector — Web Dashboard + BLE GATT + Remote Sensors**
Arduino UNO Q · SR602/HC-SR501 PIR · BLE GATT · ESP32 remote node · Arduino App Lab

---

## Version history

| Version | Status | What was added |
|---|---|---|
| v1.0 | ✅ Complete | SR602 PIR + web dashboard + event log |
| v1.1 | ✅ Complete | MCU RGB LEDs — red on detection, green on clear |
| v1.2 | ✅ Complete | BLE GATT server — phone connects and receives notifications |
| v1.3 | ✅ Complete | BLE scanner — connects to remote ESP32 sensor, multi-room dashboard |

---

## What this does

Detects human presence using PIR sensors — one local (SR602 on AQ2) and one remote (ESP32-C3 in another room). When motion is detected anywhere:

- Web dashboard updates in real time — separate status per room
- MCU RGB LEDs turn red (detection) or green (clear) on the local board
- BLE GATT characteristic notifies connected phone instantly
- Event log shows all events tagged by source room

---

## Architecture — the full dual-role BLE stack

```
Remote room                          Hub room (AQ2)
───────────                          ──────────────
ESP32-C3                             SR602 PIR → D2 pin
PIR → GPIO4                                ↓
  ↓ BLE GATT                        STM32U585 MCU
  ↓ Service: a00c0000...                   ↓ Bridge RPC
  ↓ Char: a00c0001...               QRB2210 MPU (Linux)
  ↓ Name: PIR-ESP32                        ├─ BLE Peripheral → Phone
         ↓                                 │  (GATT server, AQ2-Motion)
         └──── BLE ────────────────────────┤
                                           ├─ BLE Central → ESP32
                                           │  (GATT client, scanner)
                                           └─ WebUI → Browser (port 7000)
```

**AQ2 runs in BLE combo mode simultaneously:**
- **Peripheral role** — advertises as `AQ2-Motion`, phone connects to it
- **Central role** — connects to `PIR-ESP32`, subscribes to notifications

This is handled natively by BlueZ on Linux. Same `hci0` adapter does both at once.

---

## Hardware

### AQ2 (hub board)

| Component | Details |
|---|---|
| Board | Arduino UNO Q (AQ2) |
| Sensor | SR602 / HW-438 miniature PIR module |
| Connection | 3 jumper wires |

#### Wiring

| SR602 pin | UNO Q header | Pin | Wire |
|---|---|---|---|
| + (power) | JANALOG | Pin 4 — +3V3 | Red |
| − (ground) | JANALOG | Pin 6 — GND | Black |
| O (signal) | JDIGITAL | Pin 3 — D2 | Any |

### ESP32-C3 Super Mini (remote node)

| Component | Details |
|---|---|
| Board | ESP32-C3 Super Mini |
| Sensor | PIR sensor on GPIO4 |
| LED | Status LED on GPIO8 |
| BLE | Advertises as `PIR-ESP32` |
| Service UUID | `a00c0000-0000-0000-0000-000000000000` |
| Characteristic | `a00c0001-0000-0000-0000-000000000000` (Read + Notify) |

---

## Software structure

```
motion-sensor-webui-ble/
├── assets/
│   ├── index.html          ← HTML structure only
│   ├── style.css           ← all presentation
│   ├── app.js              ← socket + DOM logic, multi-room UI
│   └── libs/
│       └── socket.io.min.js
├── python/
│   ├── main.py             ← entry point, wires all modules
│   ├── config.py           ← all constants, remote sensor registry
│   ├── motion.py           ← local PIR Bridge handler
│   ├── web_handler.py      ← WebUI, socket events, multi-room state
│   ├── ble_manager.py      ← BLE peripheral (GATT server for phone)
│   └── ble_scanner.py      ← BLE central (GATT client for remote sensors)
├── sketch/
│   ├── sketch.ino          ← PIR read, edge detect, LED, Bridge.call
│   └── sketch.yaml         ← library dependencies
├── wheels/                 ← pre-built Python C extension wheels
├── typelibs/               ← GObject introspection typelibs
├── setup.sh                ← one-command board setup script
└── app.yaml
```

### Adding a new remote sensor

Open `python/config.py` and add one entry:

```python
REMOTE_SENSORS = {
    "ESP32-Room": {
        "mac":       "10:00:3B:CD:63:32",
        "char_uuid": "a00c0001-0000-0000-0000-000000000000",
    },
    "AQ1-Room": {                                    # ← add this
        "mac":       "XX:XX:XX:XX:XX:XX",
        "char_uuid": "a00b0001-0000-0000-0000-000000000000",
    },
}
```

That's it. The scanner connects automatically. The web UI creates a new card for the room. No other files need changing.

---

## BLE details

### AQ2 as peripheral (phone connects to this)
- Device name: `AQ2-Motion`
- Service UUID: `a00b0000-0000-0000-0000-000000000000`
- Characteristic: `a00b0001-0000-0000-0000-000000000000` (Read + Notify)
- Value: `0x01` detected / `0x00` clear

### AQ2 as central (connects to remote sensors)
- Runs `StartDiscovery()` to find devices
- Connects as GATT client
- Calls `StartNotify()` on motion characteristic
- Receives `PropertiesChanged` D-Bus signal on value change

### How BlueZ discovery works
BlueZ caches discovered devices at `/org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX`.
`Connect()` only works if the device is in this cache. The scanner runs
`StartDiscovery()` first to populate the cache, then connects. After first
successful connection BlueZ remembers the device across restarts.

---

## Setup on a new board

```bash
bash setup.sh
```

See `setup.sh` for what it installs. After setup, open App Lab and click Run.

---

## Running

1. Power on ESP32-C3 remote node (other room)
2. Open Arduino App Lab on AQ2
3. Open `motion-sensor-webui-ble` → click **Run**
4. Open browser: `http://192.168.1.154:7000`
5. Web UI shows:
   - **Local — AQ2** circle (green/orange)
   - **Remote sensors** section with ESP32-Room card
6. Open nRF Connect → scan for `AQ2-Motion` → Connect → subscribe to characteristic

---

## Roadmap

| Version | Status | Plan |
|---|---|---|
| v1.3 | ✅ Done | BLE scanner + multi-room dashboard |
| v1.4 | 🔲 Planned | AQ1 MCU BLE beacon — second remote room |
| v2.0 | 🔲 Planned | Alert messages — email / Telegram / webhook |
| v3.0 | 🔲 Planned | Custom mobile app — real push notifications |
| v4.0 | 🔲 Planned | External output — speaker / display |
| v5.0 | 🔲 Planned | Camera + person detection ML model |
| v6.0 | 🔲 Planned | Regional language TTS + multilingual UI |

---

## Key learnings from v1.3

- **BLE combo mode** — one adapter can be peripheral and central simultaneously. BlueZ handles this natively. No extra hardware needed.
- **BlueZ device cache** — `Connect()` requires the device to exist in BlueZ's object manager. Always run `StartDiscovery()` first if the device isn't cached.
- **GATT client pattern** — `StartNotify()` on a characteristic registers for push updates. `PropertiesChanged` D-Bus signal fires on every value change.
- **Separation of concerns** — adding a new remote sensor requires changing only `config.py`. The scanner, web handler, and UI update automatically.
- **Test hardware before debugging code** — always verify device is discoverable with `btmgmt find` or nRF Connect before chasing code issues.

---

*Built with Arduino App Lab 0.6.0 · BlueZ 5.82 · April 2026*
