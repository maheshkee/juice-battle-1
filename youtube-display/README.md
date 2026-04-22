# youtube-display

Stream YouTube videos to an external display from your phone — using an Arduino UNO Q board as the media server.

---

## What It Does

```
Phone browser → sends YouTube URL → Arduino UNO Q → plays video fullscreen on LCD
Phone browser → pause / resume / stop / volume → controls playback in real time
```

- Home screen with live clock displayed on LCD at all times
- No YouTube controls visible — clean fullscreen video
- Video loops automatically
- WiFi control from any browser on the same network
- BLE URL delivery (v1.2, in progress — requires Flutter phone app)

---

## Hardware Required

| Item | Details |
|---|---|
| Arduino UNO Q | ABX00162 — QRB2210 MPU + STM32U585 MCU |
| External display | Any HDMI monitor or USB-C DisplayPort monitor |
| USB-C hub | Anker or Noovoo — for HDMI output (not Apple dongles) |
| Power | USB-C 5V/3A, or 7-24V on VIN pin |

**Display connection:**
- Monitor with USB-C DP input: plug USB-C cable directly from board to monitor
- HDMI monitor: USB-C hub (with its own power) → HDMI cable → monitor

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Phone (same WiFi network)                                  │
│  Browser opens http://BOARD_IP:7000                         │
│  Sends YouTube URL via Socket.IO                            │
└─────────────────────┬───────────────────────────────────────┘
                      │ WiFi / Socket.IO
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Arduino UNO Q — MPU (QRB2210, Debian Linux)                │
│                                                             │
│  App Lab (Docker)                                           │
│  ├── main.py          — WebUI events + BLE URL handler      │
│  ├── ble_central.py   — BLE scanner (v1.2)                  │
│  └── WebUI brick      — Socket.IO server at port 7000       │
│                                                             │
│  Host system                                                │
│  ├── launcher.sh      — Chromium kiosk manager              │
│  ├── dbus-bridge      — D-Bus socket bridge for BLE         │
│  └── Xorg / XFCE      — Display server                      │
└─────────────────────┬───────────────────────────────────────┘
                      │ cmd.txt file bridge
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Chromium (kiosk mode)                                      │
│  ├── splash.html      — Home screen with clock              │
│  └── player.html      — YouTube IFrame player               │
│       └── YouTube CDN — streams video                       │
└─────────────────────┬───────────────────────────────────────┘
                      │ MIPI-DSI → ANX7625 → USB-C → DisplayPort
                      ▼
               External LCD Display
```

---

## Project File Structure

```
youtube-display/
├── setup.sh              ← run once per board
├── deploy.sh             ← run to start/restart app
├── README.md             ← this file
├── app.yaml              ← App Lab config
├── python/
│   ├── main.py           ← Python entry point
│   ├── ble_central.py    ← BLE central scanner
│   └── requirements.txt  ← Python wheel dependencies
├── sketch/
│   ├── sketch.ino        ← MCU sketch (minimal Bridge only)
│   └── sketch.yaml       ← Arduino Zephyr profile
├── assets/
│   ├── index.html        ← Phone controller UI
│   ├── splash.html       ← LCD home screen
│   ├── player.html       ← YouTube iframe player
│   ├── admin.html        ← Developer backdoor panel
│   └── socket.io.min.js  ← Socket.IO client library
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

This installs all system dependencies, configures auto-login, creates the launcher service, sets timezone, and prepares everything for production use. Takes 2-5 minutes.

### Step 3 — Reboot

```bash
sudo reboot
```

After reboot, the board will automatically start the App and show the home screen on the display.

### Step 4 — Deploy app

```bash
bash deploy.sh
```

### Step 5 — Use it

Open your phone browser and go to:
```
http://BOARD_IP:7000
```

Paste a YouTube URL and tap **Play on Display**.

---

## Supported URL Formats

```
https://www.youtube.com/watch?v=VIDEO_ID
https://youtube.com/watch?v=VIDEO_ID&t=42s
https://youtu.be/VIDEO_ID
https://www.youtube.com/shorts/VIDEO_ID
```

---

## Phone Controller UI

Open `http://BOARD_IP:7000` in any browser on the same WiFi network.

| Control | Action |
|---|---|
| Play on Display | Starts video on LCD |
| ⏸ Pause | Pauses video |
| ▶ Resume | Resumes video |
| ⏹ Stop | Stops video, returns to home screen |
| 🔉 Vol − | Decreases volume |
| 🔊 Vol + | Increases volume |

---

## Developer Access

### SSH backdoor

```bash
# From your laptop — always works regardless of what's on screen
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

Provides: Show home screen, Stop launcher, Reboot board buttons.

### View live logs

```bash
arduino-app-cli app logs user:youtube-display
```

### Manual video trigger (bypass phone UI)

```bash
echo -n "dQw4w9WgXcQ" > ~/ArduinoApps/youtube-display/cmd.txt
```

### Manual stop

```bash
echo -n "STOP" > ~/ArduinoApps/youtube-display/cmd.txt
```

---

## System Configuration (done by setup.sh)

| What | Where | Why |
|---|---|---|
| LightDM auto-login | `/etc/lightdm/lightdm.conf` | No password prompt on boot |
| App Lab GUI hidden | `~/.config/autostart/ArduinoAppLab.desktop` | Prevents flash on screen during transitions |
| Launcher autostart | `~/.config/autostart/youtube-display-launcher.desktop` | Starts kiosk on desktop login |
| dbus-bridge service | `/etc/systemd/system/dbus-bridge.service` | Bridges D-Bus into Docker for BLE |
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
  → launcher.sh waits for port 7000
  → WebUI brick ready
  → Chromium opens splash.html (home screen with clock)
  → Board ready for use
```

Total boot-to-ready time: ~90 seconds

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Black screen on boot | LightDM auto-login not configured | Run `bash setup.sh` |
| App Lab GUI appears on screen | ArduinoAppLab.desktop not disabled | Run `bash setup.sh` |
| "Site not reached" on display | App not ready yet | Wait 90s from power-on |
| Video shows thumbnail only | Chromium opened URL as tab in existing session | `bash deploy.sh` |
| Video not playing, only audio | RAM pressure | Run `pkill -f WebKitWebProcess` |
| BLE D-Bus failed | dbus-bridge not running | `sudo systemctl restart dbus-bridge` |
| Clock shows wrong time | NTP or timezone | `sudo timedatectl set-timezone Asia/Kolkata` |
| App status: failed on boot | Race condition on startup | `bash deploy.sh` manually |

---

## Roadmap

| Version | Feature | Status |
|---|---|---|
| v1.0 | WiFi URL → IFrame YouTube → LCD | ✅ Complete |
| v1.1 | Smooth transitions, no flash | 🔄 In progress |
| v1.2 | BLE URL delivery (board = central, phone = peripheral) | 🔄 Board side done, Flutter app pending |
| v2.0 | Replace Chromium+IFrame with mpv+Invidious (lower RAM) | 📋 Planned |
| v2.1 | QR code pairing — unique board ↔ phone bonding | 📋 Planned |
| v3.0 | Stream any internet video (not just YouTube) | 📋 Planned |
| v4.0 | Stream video from phone local storage | 📋 Planned |
| deploy | Mass deployment via arduino-app-cli + custom board image | 📋 Planned |

---

## BLE Technical Details (v1.2)

**Service UUID:** `a01c0000-0000-0000-0000-000000000000`  
**URL Characteristic:** `a01c0001-0000-0000-0000-000000000000`  
Properties: Read + Notify  
Value: YouTube URL as UTF-8 string

The board acts as **BLE central** — it scans for devices advertising the service UUID, connects, and reads/subscribes to the URL characteristic. The phone acts as **BLE peripheral** — requires the Flutter app (in development).

---

## Known Issues

- Brief desktop flash during video→home transition (XFCE desktop visible for ~0.3s)
- RAM usage is high (~1.3Gi) — Chromium + docker + arduino-app-cli. Board has 1.7Gi.
- App status shows `failed` on fresh boot sometimes — `bash deploy.sh` fixes it
- BLE connection `le-connection-abort-by-local` with some Android devices (Android RPA address rotation issue)

---

## Hardware Notes

- **USB-C port is shared** between display output and power input. If using for display, power the board via VIN pin (7-24V) or JANALOG 5V pin.
- **Apple USB-C dongles are incompatible** — use Anker or Noovoo hubs.
- **Voltage warning:** MPU headers (JCTL, JMEDIA) are 1.8V. MCU headers (JDIGITAL, JANALOG) are 3.3V. Never mix.
- **GPU acceleration disabled** (`--disable-gpu`) — Chromium uses software rendering. Video playback works but uses more CPU.

---

## Dependencies

### System packages
- `socat` — D-Bus socket bridge
- `libcairo2-dev`, `libgirepository-2.0-dev` — GObject/dbus Python bindings
- `curl` — port readiness check in launcher
- `chromium` — video player (pre-installed on AQ2)

### Python (installed via wheels)
- `dbus-python` 1.4.0
- `pycairo` 1.29.0
- `pygobject` 3.56.2

### App Lab Bricks
- `arduino:web_ui` — WebSocket server at port 7000

---

*Arduino UNO Q — QRB2210 MPU (Debian Linux) + STM32U585 MCU (Zephyr RTOS)*
