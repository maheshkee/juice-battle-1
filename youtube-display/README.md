# youtube-display

Stream YouTube videos to an external display from your phone — using an Arduino UNO Q board as the media server.

---

## What It Does

```
Phone app (Flutter) → BLE → Arduino UNO Q → plays video fullscreen on LCD
Phone app → pause / resume / stop / volume → controls playback in real time
```

- Home screen with live clock displayed on LCD at all times
- No YouTube controls visible — clean fullscreen video
- Video loops automatically
- BLE control from Flutter phone app (v1.2)
- WiFi control from any browser on the same network (legacy)
- Cursor hidden on display at all times

---

## Hardware Required

| Item | Details |
|---|---|
| Arduino UNO Q | ABX00162 — QRB2210 MPU + STM32U585 MCU |
| External display | Any HDMI monitor or USB-C DisplayPort monitor |
| USB-C hub | Anker or Noovoo — for HDMI output (not Apple dongles) |
| Power | USB-C 5V/3A, or 7-24V on VIN pin |
| Android phone | Flutter app installed |

**Display connection:**
- Monitor with USB-C DP input: plug USB-C cable directly from board to monitor
- HDMI monitor: USB-C hub (with its own power) → HDMI cable → monitor

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Phone (Flutter app — yt_display_app)                       │
│  Scans BLE → connects to board → writes URL + commands      │
└─────────────────────┬───────────────────────────────────────┘
                      │ BLE (GATT Write)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Arduino UNO Q — MPU (QRB2210, Debian Linux)                │
│                                                             │
│  App Lab (Docker)                                           │
│  ├── main.py           — WebUI events + BLE command handler │
│  ├── ble_gatt_serve.py — BLE peripheral GATT server         │
│  └── WebUI brick       — Socket.IO server at port 7000      │
│                                                             │
│  Host system                                                │
│  ├── launcher.sh       — Chromium kiosk manager             │
│  ├── unclutter         — Hides mouse cursor on display      │
│  ├── dbus-bridge       — D-Bus socket bridge for BLE        │
│  └── Xorg / XFCE       — Display server                     │
└─────────────────────┬───────────────────────────────────────┘
                      │ cmd.txt file bridge
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Chromium (kiosk mode)                                      │
│  ├── splash.html       — Home screen with clock             │
│  └── player.html       — YouTube IFrame player              │
│       └── YouTube CDN  — streams video                      │
└─────────────────────┬───────────────────────────────────────┘
                      │ MIPI-DSI → ANX7625 → USB-C → DisplayPort
                      ▼
               External LCD Display
```

---

## BLE Architecture (v1.2)

```
Board = Peripheral (advertises, hosts characteristics, receives writes)
Phone = Central (scans, connects, writes URL + commands)
```

**Service UUID:** `a01c0000-0000-0000-0000-000000000000`
**CMD Characteristic:** `a01c0001-0000-0000-0000-000000000000` — WRITE

**Write protocol:**
| What phone sends | Board action |
|---|---|
| Raw YouTube URL | Extract video ID, play on LCD |
| `CMD:PAUSE` | Pause video |
| `CMD:RESUME` | Resume video |
| `CMD:STOP` | Stop video, return to home screen |
| `CMD:VOL_UP` | Volume +10 |
| `CMD:VOL_DOWN` | Volume -10 |

---

## Project File Structure

```
youtube-display/
├── setup.sh              ← run once per board
├── deploy.sh             ← run to start/restart app
├── README.md             ← this file
├── app.yaml              ← App Lab config (network_mode: host required)
├── python/
│   ├── main.py           ← Python entry point
│   ├── ble_gatt_serve.py ← BLE peripheral GATT server (v1.2)
│   ├── ble_central.py    ← legacy BLE scanner (replaced in v1.2)
│   └── requirements.txt  ← Python wheel dependencies
├── sketch/
│   ├── sketch.ino        ← MCU sketch (minimal Bridge only)
│   └── sketch.yaml       ← Arduino Zephyr profile
├── assets/
│   ├── index.html        ← Phone controller UI (WiFi)
│   ├── splash.html       ← LCD home screen (clock + BLE status)
│   ├── player.html       ← YouTube iframe player
│   ├── admin.html        ← Developer backdoor panel
│   └── socket.io.min.js  ← Socket.IO client library
├── app/                  ← Flutter phone app source (yt_display_app)
├── wheels/               ← Pre-built Python wheels + .so libs (BLE)
└── typelibs/             ← GObject introspection typelibs (BLE)
```

---

## Quick Start (fresh board)

### Step 1 — Clone the repo

```bash
ssh arduino@AQ2.local
cd ~/ArduinoApps
git clone <YOUR_REPO_URL> youtube-display
cd youtube-display
```

### Step 2 — Run setup (once per board)

```bash
bash setup.sh
```

This installs all system dependencies, configures auto-login, creates the
launcher service, sets timezone, installs unclutter, and prepares everything
for production use. Takes 2-5 minutes.

### Step 3 — Reboot

```bash
sudo reboot
```

After reboot, the board will automatically start the app and show the home
screen on the display.

### Step 4 — Deploy app

```bash
bash deploy.sh
```

### Step 5 — Install Flutter app on phone

Build the APK from `app/yt_display_app/` or install pre-built APK:
```bash
# On Windows
cd app\yt_display_app
flutter build apk --debug
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### Step 6 — Use it

Open the Flutter app on your phone, tap **SCAN**, connect to **YT-Display**,
paste a YouTube URL and tap send.

---

## Supported URL Formats

```
https://www.youtube.com/watch?v=VIDEO_ID
https://youtube.com/watch?v=VIDEO_ID&t=42s
https://youtu.be/VIDEO_ID
https://www.youtube.com/shorts/VIDEO_ID
```

---

## Developer Access

### SSH

```bash
ssh arduino@BOARD_IP

# Show desktop (kills kiosk Chromium)
debug-mode

# Return to splash screen
kiosk-mode

# Restart app cleanly
bash ~/ArduinoApps/youtube-display/deploy.sh
```

### Admin panel (hidden URL)

```
http://BOARD_IP:7000/admin.html
```

### View live logs

```bash
arduino-app-cli app logs user:youtube-display
```

### Manual video trigger (bypass phone UI)

```bash
echo -n "dQw4w9WgXcQ" > ~/ArduinoApps/youtube-display/cmd.txt
echo -n "STOP"        > ~/ArduinoApps/youtube-display/cmd.txt
```

---

## System Configuration (done by setup.sh)

| What | Where | Why |
|---|---|---|
| LightDM auto-login | `/etc/lightdm/lightdm.conf` | No password prompt on boot |
| App Lab GUI hidden | `~/.config/autostart/ArduinoAppLab.desktop` | Prevents flash on screen |
| Launcher autostart | `~/.config/autostart/youtube-display-launcher.desktop` | Starts kiosk on desktop login |
| dbus-bridge service | `/etc/systemd/system/dbus-bridge.service` | Bridges D-Bus into Docker for BLE |
| unclutter | system package | Hides mouse cursor on display |
| Default app | `arduino-app-cli properties` | App starts automatically on boot |
| Timezone | Asia/Kolkata (IST) | Correct clock on splash screen |

---

## Boot Sequence

```
Power on
  → Linux boots (~45 seconds)
  → LightDM auto-logs in as arduino
  → XFCE desktop starts
  → youtube-display App starts automatically
  → dbus-bridge socket ready
  → XFCE autostart fires launcher.sh
  → unclutter hides cursor
  → launcher.sh waits for port 7000
  → WebUI brick ready
  → Chromium opens splash.html (home screen with clock)
  → Board advertises as YT-Display over BLE
  → Board ready for use
```

Total boot-to-ready time: ~90 seconds

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Black screen on boot | LightDM auto-login not configured | Run `bash setup.sh` |
| App Lab GUI appears on screen | ArduinoAppLab.desktop not disabled | Run `bash setup.sh` |
| Cursor visible on screen | unclutter not installed | `sudo apt install unclutter` |
| BLE D-Bus failed | dbus-bridge not running | `sudo systemctl restart dbus-bridge` |
| Phone can't find board | Board not advertising | Check logs for `[BLE] Advertising as YT-Display` |
| URL characteristic not found | Wrong UUID in phone app | Must be `a01c0001-0000-0000-0000-000000000000` |
| Video shows thumbnail only | Chromium reused existing session | `bash deploy.sh` |
| Clock shows wrong time | NTP or timezone | `sudo timedatectl set-timezone Asia/Kolkata` |
| App status: failed on boot | Race condition on startup | `bash deploy.sh` manually |

---

## Roadmap

| Version | Feature | Status |
|---|---|---|
| v1.0 | WiFi URL → IFrame YouTube → LCD | ✅ Complete |
| v1.1 | Smooth transitions, no flash | 🔄 Partial |
| v1.2 | Flutter BLE app, board as peripheral | ✅ Complete |
| v1.3 | Parent queue + kid viewing schedule | 🔄 In progress |
| v2.1 | QR code pairing — exclusive board ↔ phone bond | 📋 Planned |
| v3.0 | Stream any internet video URL | 📋 Planned |
| v4.0 | Offline USB video playback | 📋 Planned |

---

## Dependencies

### System packages
- `socat` — D-Bus socket bridge
- `unclutter` — hide mouse cursor on display
- `libcairo2-dev`, `libgirepository-2.0-dev` — GObject/dbus Python bindings
- `curl` — port readiness check in launcher
- `chromium` — video player (pre-installed on AQ2)

### Python (installed via wheels in project folder)
- `dbus-python` 1.4.0
- `pycairo` 1.29.0
- `pygobject` 3.56.2

### Flutter app dependencies
- `flutter_blue_plus` ^1.35.2
- `permission_handler` ^11.3.1
- `provider` ^6.1.2

### App Lab Bricks
- `arduino:web_ui` — WebSocket server at port 7000

---

## Known Issues

- Brief desktop flash during video→home transition (~0.3s)
- RAM usage is high (~1.3Gi) — Chromium + Docker + arduino-app-cli
- Phone name not yet shown on LCD splash screen (planned)

---

*Arduino UNO Q — QRB2210 MPU (Debian Linux) + STM32U585 MCU (Zephyr RTOS)*
