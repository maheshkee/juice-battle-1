# BLE Display — Arduino UNO Q

A BLE central hub and YouTube display running on the Arduino UNO Q.
Scans for nearby BLE devices, connects to multiple peripherals simultaneously,
collects their data, and shows it on a connected monitor. Also plays YouTube
videos fullscreen on the monitor — controlled from a web dashboard on any
browser on the same network.

---

## Hardware

- **Board:** Arduino UNO Q (SKU ABX00162)
- **MPU:** Qualcomm QRB2210 — runs Debian Linux, Python, App Lab
- **MCU:** STM32U585 — runs Arduino sketch, controls LED
- **BLE:** WCBN3536A module (Bluetooth 5.1) — central mode
- **Display:** Any HDMI monitor via HDMI-to-USB-C adapter
- **Power:** Powered USB hub (power + display + data through single USB-C)

---

## Project Structure

```
ble_display/
├── app.yaml                        # App Lab config (network_mode: host required)
├── requirements.txt                # Points to python/requirements.txt
├── README.md                       # This file
├── assets/
│   ├── index.html                  # Web dashboard
│   ├── app.js                      # Dashboard logic
│   ├── style.css                   # Dashboard styles
│   ├── display.html                # Kiosk display page (idle / youtube / clock)
│   ├── display.js                  # YouTube IFrame API + Socket.IO
│   └── libs/
│       └── socket.io.min.js        # Copy from ble_arduino project
├── python/
│   ├── main.py                     # BLE central hub + YouTube orchestrator
│   └── requirements.txt            # Python dependencies
├── sketch/
│   ├── sketch.ino                  # MCU sketch — LED control via Bridge
│   └── sketch.yaml                 # Sketch config
├── setup/
│   ├── setup.sh                    # One-shot board setup script
│   ├── chromium-launcher.py        # Host-side Chromium controller + HTTP server
│   └── yaml                        # Reference for correct app.yaml content
├── typelibs/                       # Copied from ble_arduino by setup.sh
└── wheels/                         # Copied from ble_arduino by setup.sh
```

---

## IMPORTANT — app.yaml

When you export the zip in App Lab, `app.yaml` gets reset and loses
`network_mode: "host"` which is critical. **Without it BLE will not work.**

**Edit `app.yaml` inside the zip BEFORE importing:**

1. Get the zip file
2. Open the zip with any archive tool
3. Find `app.yaml` inside and open it with a text editor
4. Replace its content with the content from `setup/yaml`:

```yaml
name: ble-display
description: ""
icon: "[TV]"
ports: [7000]
bricks:
  - arduino:web_ui: {}
network_mode: "host"
```

5. Save and close the zip
6. Now import the edited zip in App Lab

---

## BLE Details

| Property | Value |
|----------|-------|
| Mode | Central (scanner + GATT client) |
| Signal filter | Named devices with RSSI >= -79 dBm only |
| Auto-connect | Trusted devices reconnect on boot |
| Characteristics | Battery, temperature, heart rate, manufacturer, custom UUIDs |
| Trusted storage | `/app/trusted_devices.json` inside container |

---

## Display Modes

| Mode | What shows |
|------|-----------|
| `idle` | Animated screensaver — default on boot |
| `youtube` | YouTube IFrame player fullscreen |
| `clock` | Live fullscreen clock with seconds progress bar |

---

## How It Works

```
BLE Peripherals (phone, sensors, watches, any BLE device)
        | BLE
        v
   WCBN3536A (BLE central — scans + connects)
        | BlueZ / D-Bus
        v
   /run/dbus/system_bus_socket  (HOST)
        ^
        | socat proxy (dbus-bridge-<your-project>.service)
        |
   /app/dbus.sock  (CONTAINER = project folder)
        | dbus-python
        v
   python/main.py  (App Lab container)
        |
        |-- scans BLE, connects peripherals, reads characteristics
        |-- auto-connects trusted devices on boot
        |-- handles YouTube URL + player commands
        |-- WebUI dashboard at http://<board-ip>:7000
        v
   display.html (served by chromium-launcher on port 8080)
        | YouTube IFrame API
        v
   Monitor (fullscreen kiosk)
```

**Key:** The `chromium-launcher` service runs on the host independently of
App Lab. It serves `assets/` on port 8080 and launches Chromium at boot
so the idle screen appears before App Lab even starts.

---

## Setup on a New Board

### Step 1 — Edit app.yaml inside the zip (BEFORE importing)

See the IMPORTANT section above.

### Step 2 — Import zip in App Lab

App Lab -> My Apps -> Import -> select the edited zip.

### Step 3 — Copy socket.io.min.js

```bash
mkdir -p ~/ArduinoApps/ble_display/assets/libs
cp ~/ArduinoApps/ble_arduino/assets/libs/socket.io.min.js \
   ~/ArduinoApps/ble_display/assets/libs/
```

### Step 4 — Run setup script

```bash
chmod +x ~/ArduinoApps/ble_display/setup/setup.sh
bash ~/ArduinoApps/ble_display/setup/setup.sh
```

The script does everything in one shot — copies wheels and typelibs,
installs both systemd services, disables App Lab browser and blueman
autostart, and configures lightdm autologin.

### Step 5 — Enable Run at startup

In App Lab open the project, click the dropdown next to Run, and enable
**Run at startup**. This starts Python automatically on every boot.

### Step 6 — Reboot

```bash
sudo reboot
```

After reboot the idle screen appears on the monitor automatically.
Open the dashboard at `http://<board-ip>:7000`.

---

## Every Time You Use the Board

The board is fully automatic after setup. On every boot:

1. XFCE starts silently (no App Lab window, no Bluetooth popups)
2. `chromium-launcher` waits for X server, then launches Chromium
3. Idle screen appears on monitor
4. App Lab starts Python in background (Run at startup)
5. `display.html` connects to Socket.IO
6. BLE scan starts, trusted devices auto-connect

No manual steps needed.

---

## Auto-Connect Setup

For reliable auto-connect that survives reboots, also pair at OS level:

```bash
bluetoothctl trust <MAC>
bluetoothctl pair <MAC>
```

Accept the pairing dialog on the device. After this BlueZ handles
reconnection natively — the same way earbuds reconnect to a phone.

Check if a device is properly trusted:

```bash
bluetoothctl info <MAC>
```

Look for `Paired: yes` and `Trusted: yes`.

---

## Precaution — dbus.sock Not Found

Before clicking Run, check that `dbus.sock` exists in the project root:

```bash
ls -la ~/ArduinoApps/ble_display/dbus.sock
```

If it is not there, restart the service:

```bash
sudo systemctl stop dbus-bridge-ble_display.service
sudo systemctl daemon-reload
sudo systemctl start dbus-bridge-ble_display.service
```

Then verify:

```bash
ls -la ~/ArduinoApps/ble_display/dbus.sock
```

---

## Useful Commands

```bash
# Service status
sudo systemctl status dbus-bridge-ble_display.service
sudo systemctl status chromium-launcher-ble_display.service

# Restart services
sudo systemctl restart dbus-bridge-ble_display.service
sudo systemctl restart chromium-launcher-ble_display.service

# View chromium-launcher logs
sudo journalctl -u chromium-launcher-ble_display.service -n 30

# View dbus-bridge logs
sudo journalctl -u dbus-bridge-ble_display.service -n 20

# Check sockets
ls -la ~/ArduinoApps/ble_display/dbus.sock
ls -la ~/ArduinoApps/ble_display/launcher.sock

# Clear App Lab cache
rm -rf ~/ArduinoApps/ble_display/.cache

# Bluetooth management
bluetoothctl devices
bluetoothctl info <MAC>
bluetoothctl trust <MAC>
bluetoothctl pair <MAC>
bluetoothctl remove <MAC>
```

---

## Before Exporting as Zip

```bash
sudo systemctl stop dbus-bridge-ble_display.service
sudo systemctl stop chromium-launcher-ble_display.service
rm -f ~/ArduinoApps/ble_display/dbus.sock
rm -f ~/ArduinoApps/ble_display/launcher.sock
rm -rf ~/ArduinoApps/ble_display/.cache
```

Then export from App Lab and edit `app.yaml` inside the zip before importing.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Idle screen not showing on boot | Check `chromium-launcher-ble_display.service` status |
| Site can't be reached on monitor | App Lab not started yet — check Run at startup is enabled |
| BLE popup shows no devices | Tap refresh — devices must have a name and RSSI >= -79 |
| Auto-connect not working | Run `bluetoothctl trust` + `pair` at OS level |
| `dbus.sock` missing | See Precaution section above |
| `SystemBus failed` | Check `dbus-bridge-ble_display.service` is running |
| Bluetooth popups on monitor | `pkill blueman-applet` and check `~/.config/autostart/blueman.desktop` |
| App Lab window on monitor | Check `~/.config/autostart/ArduinoAppLab.desktop` has `Hidden=true` |
| App not working after import | Fix `app.yaml` inside zip before importing |
| YouTube not playing | Check internet: `ping -c 2 youtube.com` |
| URL rejected | Must be a valid `youtube.com` or `youtu.be` link |
| Characteristics all failed | Device disconnected mid-discovery — reconnect and try again |