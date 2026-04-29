# youtube-display

Stream YouTube videos to an external display from your phone — using an Arduino UNO Q board as the media server. Controlled entirely from a Flutter phone app over Bluetooth Low Energy. Audio plays through a paired Bluetooth speaker.

---

## What It Does

```
Phone app (Flutter) → BLE → Arduino UNO Q → plays video fullscreen on LCD
Phone app → pause / resume / stop / volume → controls playback in real time
Phone app → BT AUDIO section → scan / pair / connect / disconnect BT speakers
```

- Home screen with live clock displayed on LCD at all times
- No YouTube controls visible — clean fullscreen video
- Video loops automatically
- BLE control from Flutter phone app (v1.2)
- WiFi control from any browser on the same network (legacy)
- Cursor hidden on display at all times
- Bluetooth speaker management from app — no SSH needed

---

## Hardware Required

| Item | Details |
|---|---|
| Arduino UNO Q | ABX00162 — QRB2210 MPU + STM32U585 MCU |
| External display | Any HDMI monitor or USB-C DisplayPort monitor |
| USB-C hub | Anker or Noovoo — for HDMI output (not Apple dongles) |
| Bluetooth speaker | A2DP capable — see BT compatibility note below |
| Power | USB-C 5V/3A, or 7-24V on VIN pin |
| Android phone | Flutter app installed |

**Display connection:**
- Monitor with USB-C DP input: plug USB-C cable directly from board to monitor
- HDMI monitor: USB-C hub (with its own power) → HDMI cable → monitor

**Audio:**
- HDMI/DP audio is NOT supported on this board (QRB2210 ELD driver limitation)
- Use a Bluetooth speaker — see BT Audio section below

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Phone (Flutter app — yt_display_app)                       │
│  Scans BLE → connects to board → writes URL + commands      │
│  Receives BT scan results + device status via BLE notify    │
└─────────────────────┬───────────────────────────────────────┘
                      │ BLE (GATT Write + Notify)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Arduino UNO Q — MPU (QRB2210, Debian Linux)                │
│                                                             │
│  App Lab (Docker)                                           │
│  ├── main.py           — WebUI events + BLE command handler │
│  ├── ble_gatt_serve.py — BLE peripheral GATT server (v1.2)  │
│  │   ├── CMD char      — receives commands from phone       │
│  │   └── EVT char      — pushes events/results to phone     │
│  └── WebUI brick       — Socket.IO server at port 7000      │
│                                                             │
│  Host system                                                │
│  ├── launcher.sh       — Chromium kiosk + BT file bridge    │
│  ├── bt-autoconnect    — auto-connects trusted BT on boot   │
│  ├── PipeWire          — audio routing to BT speaker        │
│  ├── unclutter         — hides mouse cursor on display      │
│  ├── dbus-bridge       — D-Bus socket bridge for BLE        │
│  └── Xorg / XFCE       — display server                     │
└─────────────────────┬───────────────────────────────────────┘
                      │ cmd.txt file bridge
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  Chromium (kiosk mode)                                      │
│  ├── splash.html       — home screen with clock             │
│  └── player.html       — YouTube IFrame player              │
│       └── YouTube CDN  — streams video                      │
└─────────────────────┬───────────────────────────────────────┘
                      │ MIPI-DSI → ANX7625 → USB-C → DisplayPort
                      ▼
               External LCD Display

               PipeWire → A2DP → Bluetooth Speaker
```

---

## BLE Architecture (v1.2)

```
Board = Peripheral (advertises as YT-Display, hosts characteristics)
Phone = Central (scans, connects, writes commands, receives notifications)
```

**Service UUID:** `a01c0000-0000-0000-0000-000000000000`
**CMD Characteristic:** `a01c0001-0000-0000-0000-000000000000` — WRITE
**EVT Characteristic:** `a01c0002-0000-0000-0000-000000000000` — NOTIFY

**CMD write protocol:**

| What phone sends | Board action |
|---|---|
| Raw YouTube URL | Extract video ID, play on LCD |
| `CMD:PAUSE` | Pause video |
| `CMD:RESUME` | Resume video |
| `CMD:STOP` | Stop video, return to home screen |
| `CMD:VOL_UP` | Volume +10 |
| `CMD:VOL_DOWN` | Volume -10 |
| `CMD:BT_SCAN_START` | Start BLE scan, push results via EVT notify |
| `CMD:BT_SCAN_STOP` | Stop scan |
| `CMD:BT_LIST` | Push trusted devices list via EVT notify |
| `CMD:BT_PAIR:<mac>` | Pair + trust device |
| `CMD:BT_CONNECT:<mac>` | Connect + set as default audio sink |
| `CMD:BT_DISCONNECT:<mac>` | Disconnect device |
| `CMD:BT_FORGET:<mac>` | Unpair + remove trust |

**EVT notify events (JSON pushed to phone):**

| Event | Meaning |
|---|---|
| `bt_trusted` | List of trusted devices with connected status |
| `bt_scan_results` | Nearby BLE devices with RSSI signal strength |
| `bt_scan_status` | Scanning true/false |
| `bt_connected` | Device connected confirmation |
| `bt_disconnected` | Device disconnected confirmation |
| `bt_error` | Error message |

---

## Bluetooth Audio

### Setup (one time per board)

```bash
bash setup_for_bt_audio.sh
```

Then pair your speaker once:

```bash
bluetoothctl
scan on
# wait for your speaker name
scan off
pair <MAC>
trust <MAC>
connect <MAC>
exit
```

After pairing once, speaker auto-connects on every reboot via `bt-autoconnect.service`.

### Managing speakers from the app

The Flutter app BT AUDIO section lets you scan for nearby speakers, pair new ones,
and connect/disconnect from the PAIRED list — no SSH needed.

### BT Compatibility — Important

The board scans **BLE only** (`le` transport). This means:

**Visible in app scan:** Modern Bluetooth speakers that advertise over BLE
(FUZO Groove, JBL Flip 6, Sony SRS-XB series, most speakers made after 2018).

**NOT visible in app scan:** Devices that only advertise Classic Bluetooth
(some budget earbuds like Airdopes Joy). These must be paired manually:

```bash
bluetoothctl pair <MAC>
bluetoothctl trust <MAC>
```

Once trusted they auto-connect on reboot and audio works normally.

**Why not scan Classic BT?** Using `auto` transport (Classic + BLE) on the
QRB2210 causes the Bluetooth adapter to power off, breaking the BLE connection
with the phone. This is a confirmed hardware/driver limitation on this board.
Classic BT pairing from the app is planned for v1.4.

**Recovery if BT adapter powers off:**
```bash
sudo systemctl restart bluetooth && sleep 3 && bluetoothctl power on
# if that fails:
sudo reboot
```

### Audio routing

PipeWire manages audio. When a BT speaker connects it becomes the default sink.
When it disconnects PipeWire falls back to Dummy Output (no sound).
bt-autoconnect.service reconnects trusted speakers at boot automatically.

HDMI/DisplayPort audio is not available — the QRB2210 driver has an ELD version
mismatch with most displays. Bluetooth is the only audio path on this board.

---

## Project File Structure

```
youtube-display/
├── setup.sh                  ← run once per board
├── setup_for_bt_audio.sh     ← run once for BT audio setup
├── deploy.sh                 ← run to start/restart app
├── bt-autoconnect.py         ← boot-time BT auto-connect script
├── launcher.sh               ← Chromium kiosk + BT command file bridge
├── README.md                 ← this file
├── app.yaml                  ← App Lab config (network_mode: host required)
├── python/
│   ├── main.py               ← Python entry point
│   ├── ble_gatt_serve.py     ← BLE peripheral GATT server (v1.2)
│   ├── ble_central.py        ← legacy BLE scanner (replaced in v1.2)
│   └── requirements.txt      ← Python wheel dependencies
├── sketch/
│   ├── sketch.ino            ← MCU sketch (minimal Bridge only)
│   └── sketch.yaml           ← Arduino Zephyr profile
├── assets/
│   ├── index.html            ← phone controller UI (WiFi legacy)
│   ├── splash.html           ← LCD home screen (clock)
│   ├── player.html           ← YouTube IFrame player
│   ├── admin.html            ← developer backdoor panel
│   └── socket.io.min.js      ← Socket.IO client (local — CDN blocked in App Lab)
├── wheels/                   ← pre-built Python wheels + .so libs (BLE)
└── typelibs/                 ← GObject introspection typelibs (BLE)
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

Takes 2-5 minutes. Installs dependencies, configures auto-login, dbus-bridge,
launcher autostart, timezone, shell aliases.

### Step 3 — Run BT audio setup (once per board)

```bash
bash setup_for_bt_audio.sh
```

Then pair your Bluetooth speaker (see BT Audio section above).

### Step 4 — Reboot

```bash
sudo reboot
```

### Step 5 — Deploy app

```bash
bash deploy.sh
```

### Step 6 — Install Flutter app on phone

```bash
# Windows PowerShell
cd C:\Users\mahes\yt_display_app_fresh
flutter build apk --debug
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### Step 7 — Use it

Open app, tap **SCAN**, connect to **YT-Display**, paste a YouTube URL and send.

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

debug-mode    # kill kiosk Chromium, show desktop
kiosk-mode    # return to splash screen
yt-logs       # view live app logs
yt-restart    # stop, clear cache, restart app
```

### Admin panel

```
http://BOARD_IP:7000/admin.html
```

### Manual video trigger

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
| bt-autoconnect service | `~/.config/systemd/user/` | Auto-connects BT speaker on boot |
| WirePlumber A2DP rule | `/etc/pipewire/wireplumber.conf.d/` | Auto-uses A2DP for BT audio |

---

## Boot Sequence

```
Power on
  → Linux boots (~45 seconds)
  → LightDM auto-logs in as arduino
  → XFCE desktop starts
  → bt-autoconnect.service runs → connects trusted BT speaker
  → youtube-display App starts automatically
  → dbus-bridge socket ready
  → XFCE autostart fires launcher.sh
  → unclutter hides cursor
  → launcher.sh waits for port 7000
  → WebUI brick ready
  → Chromium opens splash.html (home screen with clock)
  → Board advertises as YT-Display over BLE
  → Board ready for use (~90 seconds total)
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Black screen on boot | LightDM auto-login not configured | `bash setup.sh` |
| App Lab GUI appears on screen | ArduinoAppLab.desktop not disabled | `bash setup.sh` |
| Cursor visible on screen | unclutter not installed | `sudo apt install unclutter` |
| BLE D-Bus failed | dbus-bridge not running | `sudo systemctl restart dbus-bridge` |
| Phone can't find board | Board not advertising | Check logs for `[BLE] Advertising as YT-Display` |
| URL characteristic not found | Wrong UUID in phone app | Must be `a01c0001-0000-0000-0000-000000000000` |
| Video shows thumbnail only | Chromium reused existing session | `bash deploy.sh` |
| Clock shows wrong time | Timezone not set | `sudo timedatectl set-timezone Asia/Kolkata` |
| No audio from BT speaker | Speaker disconnected or wrong sink | `bluetoothctl connect <MAC>` or reboot |
| BT speaker not in app scan | Classic BT only device | Pair manually: `bluetoothctl pair <MAC>` |
| BT adapter powered off | Classic BT scan triggered (bug) | `sudo systemctl restart bluetooth && bluetoothctl power on` |
| Audio stops when app opens | Old bug — fixed in v1.2 | Ensure latest ble_gatt_serve.py is deployed |
| App status: failed on boot | Race condition on startup | `bash deploy.sh` manually |

---

## Roadmap

| Version | Feature | Status |
|---|---|---|
| v1.0 | WiFi URL → IFrame YouTube → LCD | Done |
| v1.1 | Smooth transitions, no flash | Partial |
| v1.2 | Flutter BLE app + BT audio manager | Done |
| v1.3 | Parent queue + kid viewing schedule | Next |
| v1.4 | Classic BT pairing from app (earbuds etc.) | Planned |
| v2.1 | QR code pairing — exclusive board-phone bond | Planned |
| v3.0 | Stream any internet video URL | Planned |
| v4.0 | Offline USB video playback | Planned |

---

## Dependencies

### System packages
- `socat` — D-Bus socket bridge
- `unclutter` — hide mouse cursor on display
- `libcairo2-dev`, `libgirepository-2.0-dev` — GObject/dbus Python bindings
- `curl` — port readiness check in launcher
- `pipewire`, `pipewire-pulse`, `wireplumber` — audio routing
- `libspa-0.2-bluetooth` — PipeWire Bluetooth audio plugin
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
- Classic BT only devices (some earbuds) must be paired manually via SSH

---

*Arduino UNO Q — QRB2210 MPU (Debian Linux) + STM32U585 MCU (Zephyr RTOS)*
