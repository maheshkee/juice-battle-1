# ble-display

A BLE Hub + YouTube display system running on the **Arduino UNO Q** (ABX00162).

The board acts as a **BLE central** — it scans and connects to BLE peripherals (sensors, ESP32 devices, phones). It also acts as a **BLE peripheral** — advertising as `BLE-Hub` so the companion phone app can connect and control it.

A connected HDMI display shows YouTube videos, a clock, or an idle screen — all controlled from a phone app or the browser WebUI.

---

## Hardware Required

- Arduino UNO Q (SKU: ABX00162)
- HDMI display connected to the board
- Phone with the BLE Hub Flutter app installed

---

## Project Structure

```
ble-display/
├── app.yaml                    # App Lab config
├── assets/
│   ├── index.html              # WebUI dashboard (browser control)
│   ├── app.js                  # WebUI logic
│   ├── display.html            # Fullscreen display page (shown on HDMI)
│   ├── display.js              # Display logic (YouTube IFrame, clock, idle)
│   ├── style.css               # Shared styles
│   └── libs/
│       └── socket.io.min.js    # Local Socket.IO client (must be copied in)
├── python/
│   ├── main.py                 # Main App Lab Python app
│   └── requirements.txt        # Python dependencies
├── setup/
│   ├── setup.sh                # One-time board setup script
│   └── chromium-launcher.py    # Chromium kiosk launcher (runs as systemd service)
├── sketch/
│   ├── sketch.ino              # MCU sketch (LED control via Bridge)
│   └── sketch.yaml             # Sketch dependencies
├── typelibs/                   # GObject typelib files (board-specific, not in git)
└── wheels/                     # Pre-built Python wheels (board-specific, not in git)
```

---

## Architecture

```
Phone (Flutter app)
    | BLE (connects to BLE-Hub advertisement)
    v
Arduino UNO Q  <--->  BLE sensors / ESP32 devices
    |
    | Socket.IO (port 7000)
    v
Browser WebUI  (http://<board-ip>:7000)

Arduino UNO Q
    |
    | HTTP (port 8080) + Socket.IO
    v
Chromium (kiosk, HDMI display)
    - Idle screen with particles
    - Clock screen
    - YouTube IFrame player
```

---

## BLE Protocol

The board advertises as `BLE-Hub` with service UUID `a00b0000-0000-0000-0000-000000000000`.

| Characteristic | UUID | Direction | Purpose |
|---|---|---|---|
| Command | `a00b0002-...` | Phone → Board | Send commands |
| Event | `a00b0003-...` | Board → Phone | Push state updates as JSON |

### Command Protocol

All commands are UTF-8 strings written to the Command characteristic:

```
YT:<url>              Send a YouTube URL to play
CMD:LED_ON            Turn MCU LED on
CMD:LED_OFF           Turn MCU LED off
CMD:LED_TOGGLE        Toggle MCU LED
CMD:MODE_IDLE         Switch display to idle screen
CMD:MODE_YOUTUBE      Switch display to YouTube screen
CMD:MODE_CLOCK        Switch display to clock screen
CMD:PLAYER_PAUSE      Pause video
CMD:PLAYER_RESUME     Resume video
CMD:PLAYER_STOP       Stop video and return to idle
CMD:PLAYER_MUTE       Mute video
CMD:PLAYER_UNMUTE     Unmute video
CMD:SCAN_START        Start BLE scan for nearby devices
CMD:SCAN_STOP         Stop BLE scan
CMD:CONNECT:<mac>     Connect to BLE device by MAC address
CMD:DISCONNECT:<mac>  Disconnect BLE device
CMD:FORGET:<mac>      Remove device from trusted list
CMD:GET_STATUS        Push full board state to phone
```

### Event Protocol

Board pushes JSON notifications to the phone via notify on `a00b0003`. Each message has an `event` key:

```json
{"event": "full_status", "mode": "idle", "led": false, "scanning": false, ...}
{"event": "mode_update", "mode": "youtube"}
{"event": "led_status", "state": true}
{"event": "scan_results", "devices": [...]}
{"event": "device_connected", "mac": "...", "name": "..."}
{"event": "url_update", "url": "...", "video_id": "..."}
```

---

## Setup

### Prerequisites on the board

```bash
sudo apt install chromium socat xdotool
```

### Step 1 — Import into App Lab

1. Open the zip in a file manager
2. Edit `app.yaml` inside the zip — make sure it contains `network_mode: "host"`:
```yaml
name: ble_display
description: ""
ports: []
bricks:
- arduino:web_ui: {}
network_mode: "host"
```
3. Import the edited zip in App Lab

### Step 2 — Copy binary dependencies

The `wheels/` and `typelibs/` folders contain board-specific compiled files that are not in the repo. Copy them from an existing working project:

```bash
cp -r ~/ArduinoApps/ble_arduino/wheels/   ~/ArduinoApps/ble_display/
cp -r ~/ArduinoApps/ble_arduino/typelibs/ ~/ArduinoApps/ble_display/
```

Also copy the local Socket.IO library:

```bash
cp ~/ArduinoApps/ble_arduino/assets/libs/socket.io.min.js \
   ~/ArduinoApps/ble_display/assets/libs/
```

### Step 3 — Run setup script

```bash
chmod +x ~/ArduinoApps/ble_display/setup/setup.sh
bash ~/ArduinoApps/ble_display/setup/setup.sh
```

This installs two systemd services:
- `dbus-bridge-ble_display.service` — exposes D-Bus socket inside App Lab container
- `chromium-launcher-ble_display.service` — launches Chromium in kiosk mode on the HDMI display

### Step 4 — Flash the MCU sketch

In App Lab, flash `sketch/sketch.ino` to the MCU. This enables LED control via Bridge.

### Step 5 — Enable Run at startup

In App Lab settings, enable **Run at startup** so the app starts automatically on boot.

### Step 6 — Reboot

```bash
sudo reboot
```

After reboot the display should show the idle screen and the board is ready.

---

## Every Time You Use the Board

The services start automatically on boot. To verify:

```bash
sudo systemctl status dbus-bridge-ble_display.service
sudo systemctl status chromium-launcher-ble_display.service
```

Open the WebUI in a browser:

```
http://<board-ip>:7000
```

Or open the BLE Hub Flutter app on your phone and tap **Scan**.

---

## Useful Commands

```bash
# Check dbus-bridge
sudo systemctl status dbus-bridge-ble_display.service

# Check chromium launcher
sudo systemctl status chromium-launcher-ble_display.service

# View chromium launcher logs
sudo journalctl -u chromium-launcher-ble_display.service -n 30

# Restart everything
sudo systemctl restart dbus-bridge-ble_display.service
sudo systemctl restart chromium-launcher-ble_display.service

# Check dbus socket exists
ls -la ~/ArduinoApps/ble_display/dbus.sock

# Check launcher socket exists
ls -la ~/ArduinoApps/ble_display/launcher.sock
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| WebUI not loading | Check board IP and that App Lab is running |
| BLE-Hub not found in phone app | Check App Lab is running, `network_mode: "host"` in app.yaml |
| Display shows nothing | Check `chromium-launcher` service is running |
| Video buffers but does not play | Restart chromium-launcher service |
| `SystemBus failed` | Check `dbus-bridge` service is running and `dbus.sock` exists |
| After reboot not working | Check both systemd services are enabled and running |
| App not working after import | Make sure `app.yaml` has `network_mode: "host"` before importing |

---

## Before Pushing to GitHub / Exporting Zip

Clean up runtime files:

```bash
sudo systemctl stop dbus-bridge-ble_display.service
sudo systemctl stop chromium-launcher-ble_display.service
rm -f ~/ArduinoApps/ble_display/dbus.sock
rm -f ~/ArduinoApps/ble_display/launcher.sock
rm -rf ~/ArduinoApps/ble_display/.cache
```

The `wheels/`, `typelibs/`, `.cache/`, `dbus.sock`, and `launcher.sock` are excluded from git via `.gitignore`.

---

## Phone App

The companion Flutter app (`ble-hub-app/`) connects to the board via BLE and provides:
- YouTube URL input with history
- Player controls (pause, resume, stop, mute)
- Display mode switching (idle, YouTube, clock)
- LED control
- BLE device scanner and manager (connects/disconnects sensors through the board)
- Live event log

See `ble-hub-app/README.md` for Flutter setup instructions.