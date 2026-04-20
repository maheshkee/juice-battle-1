# BLE GATT Dashboard — Arduino UNO Q

A BLE GATT server running on the Arduino UNO Q (AQ1/AQ2) with a WebUI dashboard.
Control the MCU LED, read sensor data, send text commands, and receive timestamp notifications
— all from a browser or a BLE app like nRF Connect.

---

## Hardware

- **Board:** Arduino UNO Q (SKU ABX00162)
- **MPU:** Qualcomm QRB2210 — runs Debian Linux, Python, App Lab
- **MCU:** STM32U585 — runs Arduino sketch, controls LED
- **BLE:** WCBN3536A module (Bluetooth 5.1)

---

## Project Structure

```
ble_arduino/
├── app.yaml                  # App Lab config
├── README.md                 # This file
├── assets/
│   ├── index.html            # Dashboard UI
│   ├── style.css             # Dashboard styles
│   ├── app.js                # Dashboard logic
│   └── libs/
│       └── socket.io.min.js  # WebSocket library
├── python/
│   ├── main.py               # Main app — BLE server + WebUI + Bridge
│   └── requirements.txt      # Python dependencies
├── setup/
│   ├── setup_s.sh            # Setup script (use this — wheels already in zip)
│   ├── full_setup.sh         # Full setup script (use this for fresh board — no wheels)
│   ├── libraries.txt         # Guide for adding new libraries
│   └── yaml                  # Reference for correct app.yaml content
├── sketch/
│   ├── sketch.ino            # MCU sketch — LED control via Bridge
│   └── sketch.yaml           # Sketch config
├── typelibs/                 # GLib/Gio/GObject/DBus typelibs
│   ├── DBus-1.0.typelib
│   ├── GLib-2.0.typelib
│   ├── GLibUnix-2.0.typelib
│   ├── GObject-2.0.typelib
│   └── Gio-2.0.typelib
└── wheels/                   # Pre-built Python wheels + shared libraries
    ├── dbus_python-1.4.0-cp313-cp313-linux_aarch64.whl
    ├── pycairo-1.29.0-cp313-cp313-linux_aarch64.whl
    ├── pygobject-3.56.2-cp313-cp313-linux_aarch64.whl
    └── *.so files            # Required shared libraries
```

---

## ⚠️ IMPORTANT — app.yaml

When you import the zip in App Lab, the `app.yaml` gets reset to its
default content and loses `network_mode: "host"` which is critical.

**The fix is to edit `app.yaml` inside the zip BEFORE importing:**

1. Get the zip file
2. Open the zip with any archive tool
3. Find `app.yaml` inside the zip and open it with a text editor
4. Replace its content with the content from `setup/yaml`:
```yaml
name: ble_arduino
description: ""
icon: 😀
ports: []
bricks:
- arduino:web_ui: {}
network_mode: "host"
```
5. Save and close the zip
6. Now import the edited zip in App Lab

**Without `network_mode: "host"` the app will not work.**

The `setup/yaml` file inside the zip is the reference for the correct
`app.yaml` content. Always use it when editing before import.

---

## BLE Details

| Property | Value |
|----------|-------|
| Device Name | `BLE` |
| Service UUID | `a00b0000-0000-0000-0000-000000000000` |
| Char 1 — Random Sensor | `a00b0001-0000-0000-0000-000000000000` — READ |
| Char 2 — Text Command | `a00b0002-0000-0000-0000-000000000000` — WRITE |
| Char 3 — Timestamp | `a00b0003-0000-0000-0000-000000000000` — NOTIFY |

---

## Dashboard Features

- BLE advertising status (Start / Stop)
- Connected device name display
- Random Sensor — read a random value from the board
- Text Command — send text from phone to board
- Timestamp — board pushes current time every 5 seconds
- Built-in LED control — toggle MCU LED from browser

---

## How It Works

```
nRF Connect / BLE App (Phone)
        │ BLE
        ▼
   BLE chip on board
        │ BlueZ / dbus
        ▼
   /run/dbus/system_bus_socket  (HOST)
        ▲
        │ socat proxy (dbus-bridge.service)
        │
   /app/dbus.sock  (CONTAINER = project folder)
        ▲
        │ dbus-python
        ▼
   python/main.py  (App Lab Docker container)
        │
        ├── WebUI → browser at :7000
        └── Bridge → arduino-router.sock → STM32 MCU sketch
```

**Key:** App Lab mounts the project folder as `/app` inside the container.
The `dbus-bridge` systemd service creates a Unix socket proxy at
`ble_arduino/dbus.sock` on the host, which is accessible inside
the container as `/app/dbus.sock`.

---

## Setup on a New Board

### Step 1 — Edit app.yaml inside the zip (BEFORE importing)

1. Open the zip file with any archive tool
2. Find `app.yaml` inside the zip
3. Replace its content with the content from `setup/yaml`
4. Save and close the zip

### Step 2 — Import zip in App Lab

Import the edited zip file via App Lab → My Apps → Import.

### Step 3 — Fix line endings (if zip was handled on Windows)

If the zip was downloaded or edited on a Windows machine, the shell
scripts will have Windows line endings which will cause errors like:
```
$'\r': command not found
```

Fix it by running:
```bash
sudo apt install dos2unix -y
dos2unix ~/ArduinoApps/ble_arduino/setup/setup_s.sh
```

### Step 4 — Run setup script

```bash
chmod +x ~/ArduinoApps/ble_arduino/setup/setup_s.sh
bash ~/ArduinoApps/ble_arduino/setup/setup_s.sh
```

### Step 5 — Run the app

1. Open **App Lab**
2. Click **Run**
3. Open browser at `http://<board-ip>:7000`
4. Open **nRF Connect** on phone and scan for `BLE`

---

## Every Time You Use the Board

After a reboot the `dbus-bridge` service starts automatically.
Before clicking Run, verify it is running:

```bash
sudo systemctl status dbus-bridge.service
```

If it is not running, start it manually:

```bash
sudo systemctl start dbus-bridge.service
```

Then click Run in App Lab.

---

## ⚠️ Precaution — dbus.sock Not Found

Before clicking Run, check that `dbus.sock` exists in the project root:

```bash
ls -la ~/ArduinoApps/ble_arduino/dbus.sock
```

If it is **not there**, it means the `dbus-bridge` service is pointing
to the wrong folder or is not running. Fix it by running:

```bash
sudo systemctl stop dbus-bridge.service
sudo systemctl daemon-reload
sudo systemctl start dbus-bridge.service
```

Then verify the socket was created:

```bash
ls -la ~/ArduinoApps/ble_arduino/dbus.sock
```

Also check the service is pointing to the correct path:

```bash
sudo systemctl status dbus-bridge.service
```

The output must show `ble_arduino/dbus.sock` — not any other folder name.
If it shows a different folder name, re-run the setup script and repeat the steps above.

---

## Useful Commands

```bash
# Check if dbus-bridge service is running
sudo systemctl status dbus-bridge.service

# Start the service manually
sudo systemctl start dbus-bridge.service

# Stop the service
sudo systemctl stop dbus-bridge.service

# Force restart the service
sudo systemctl stop dbus-bridge.service
sudo systemctl daemon-reload
sudo systemctl start dbus-bridge.service

# View service logs
sudo journalctl -u dbus-bridge.service -n 20

# Check if dbus socket exists
ls -la ~/ArduinoApps/ble_arduino/dbus.sock

# Clear App Lab cache (force reinstall of packages)
rm -rf ~/ArduinoApps/ble_arduino/.cache
```

---

## Before Exporting as Zip

Run these commands to clean up before exporting:

```bash
sudo systemctl stop dbus-bridge.service
rm -f ~/ArduinoApps/ble_arduino/dbus.sock
rm -rf ~/ArduinoApps/ble_arduino/.cache
```

Then export from App Lab.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| BLE not showing in nRF Connect | Check console for `✓ Advertisement registered` |
| `dbus.sock` not in project root | See Precaution section above |
| `SystemBus failed` error | Check `dbus-bridge.service` is running |
| `$'\r': command not found` | Run `dos2unix` on the script — see Step 3 above |
| WebUI not loading | Check board IP and make sure port 7000 is accessible |
| LED not responding | Check sketch is flashed — look for MCU flash logs in console |
| After reboot not working | Check `sudo systemctl status dbus-bridge.service` |
| App not working after import | Make sure `app.yaml` was edited inside zip before importing |

---

## Adding New Libraries

See `setup/libraries.txt` for the full guide.

**Quick reference:**
- Pure Python library → just add name to `requirements.txt`
- C extension library → build wheel on host, copy `.so` files, add `ctypes.CDLL` in `main.py`