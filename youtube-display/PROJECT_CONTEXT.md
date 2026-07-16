# PROJECT CONTEXT — YouTube Display on Arduino UNO Q
> Paste this at the start of every new Claude session.
> Last updated: April 24, 2026 — End of Session (v1.2 BT Audio complete)

---

## CRITICAL INSTRUCTIONS FOR CLAUDE

1. Read this entire file before responding to anything.
2. Never suggest things already tried and failed — check known issues section.
3. First principles always — explain WHY before HOW.
4. No rabbit holes — stay on critical path.
5. Ask all clarifying questions BEFORE writing any code.
6. Read current file contents with cat before modifying anything.

---

## WHO IS MAHESH

- Embedded systems learner on a structured mastery journey
- Learning style: first principles, hands-on lab-based, visual learning
- Windows laptop → SSH → Arduino UNO Q board (AQ2) at 192.168.1.154
- Windows username: mahes (not mahesh)
- Board MAC (BLE): 14:B5:CD:0A:87:F1

---

## HARDWARE

### Board: Arduino UNO Q (AQ2)
- MPU: Qualcomm QRB2210 — Debian Linux, 1.8V domain
- MCU: STM32U585 — Zephyr RTOS + Arduino Core, 3.3V domain
- RAM: 1.7Gi total (~1.3Gi used during operation)
- Storage: 16GB eMMC
- Wireless: WCBN3536A — WiFi 5 + Bluetooth 5.1
- Display: ANX7625 DSI-to-DP bridge → USB-C → external LCD (1920x1080, DP-1)
- SSH: ssh arduino@192.168.1.154
- Git repo: github.com:gratiantechnologies/project13 (branch: main)
- App dir: ~/ArduinoApps/youtube-display/

### Audio
- HDMI/DP audio: BROKEN — ELD version 0 error, driver limitation on QRB2210
- Headphone jack: Works (Arduino-Imola-HPH-LOUT) but LCD has no AUX input
- Bluetooth audio: WORKS via PipeWire + libspa-bluez5 + A2DP
- Audio server: PipeWire 1.4.2 + WirePlumber (user session)
- BT speaker: FUZO Groove (MAC: 41:42:5B:F4:65:27) — trusted, auto-connects on boot

### Development Machine (Windows laptop)
- Flutter SDK: C:\flutter (v3.41.7, stable)
- Android SDK: C:\Android (SDK 36.0.0)
- Java: OpenJDK 17 (Temurin-17.0.18+8)
- Phone: OnePlus Nord CE5 (CPH2717)
- Flutter app path: C:\Users\mahes\yt_display_app_fresh\

PATH must be set each PowerShell session:
  $env:Path += ";C:\flutter\bin;C:\Android\cmdline-tools\latest\bin;C:\Android\platform-tools"
  $env:ANDROID_HOME = "C:\Android"

---

## PROJECT: youtube-display

### What It Does
User powers on board → LCD shows home screen (clock + welcome) → User opens Flutter app
→ taps SCAN → connects to board via BLE → pastes YouTube URL → sends → video streams
fullscreen on LCD → audio plays via Bluetooth speaker → user controls playback from phone
→ BT AUDIO section lets user manage Bluetooth speakers entirely from the app.

### Architecture
```
Flutter app (phone) → BLE GATT Write → board (peripheral)
  → ble_gatt_serve.py receives URL/CMD
  → main.py handles it
  → writes video_id to /app/cmd.txt on host
  → launcher.sh reads cmd.txt → launches Chromium kiosk
  → player.html → YouTube IFrame API → streams video
  → PipeWire → BT speaker (A2DP) → audio

BT audio management (two paths):
  BT_LIST / BT_SCAN  → BlueZ D-Bus direct inside container (no bluetoothctl, no audio disruption)
  BT_CONNECT / DISCONNECT / PAIR / FORGET → file bridge → launcher.sh → bluetoothctl + wpctl on host
  Results → pushed back to phone via EVT notify characteristic
```

### BLE Protocol (v1.2)
Board advertises as: YT-Display
Service UUID:  a01c0000-0000-0000-0000-000000000000
CMD Char UUID: a01c0001-0000-0000-0000-000000000000  (WRITE)
EVT Char UUID: a01c0002-0000-0000-0000-000000000000  (NOTIFY)

CMD commands:
  Raw YouTube URL         play video
  CMD:PAUSE               pause
  CMD:RESUME              resume
  CMD:STOP                stop, return to home screen
  CMD:VOL_UP              volume up
  CMD:VOL_DOWN            volume down
  CMD:BT_SCAN_START       start BLE scan, push results via EVT notify
  CMD:BT_SCAN_STOP        stop scan
  CMD:BT_LIST             push trusted devices list via EVT notify
  CMD:BT_PAIR:<mac>       pair + trust device (file bridge)
  CMD:BT_CONNECT:<mac>    connect + set as default PipeWire sink (file bridge)
  CMD:BT_DISCONNECT:<mac> disconnect device (file bridge)
  CMD:BT_FORGET:<mac>     unpair + remove trust (file bridge)

EVT events (JSON pushed to phone):
  bt_trusted      list of trusted devices with connected status
  bt_scan_results list of available nearby BLE devices with RSSI
  bt_scan_status  scanning true/false
  bt_connected    device connected confirmation
  bt_disconnected device disconnected confirmation
  bt_error        error message

---

## FILE STRUCTURE

Board:
  ~/ArduinoApps/youtube-display/
  ├── app.yaml                    network_mode: host REQUIRED for BLE
  ├── deploy.sh                   stop + clear cache + restart
  ├── setup.sh                    one-time board setup
  ├── setup_for_bt_audio.sh       one-time BT audio setup
  ├── bt-autoconnect.py           copied to /usr/local/bin/ by setup_for_bt_audio.sh
  ├── launcher.sh                 Chromium kiosk + cmd.txt watcher + BT file bridge
  ├── README.md
  ├── python/
  │   ├── main.py                 URL handling, Socket.IO, Bridge to MCU
  │   └── ble_gatt_serve.py       BLE GATT server (CMD write + EVT notify)
  ├── assets/
  │   ├── splash.html             LCD home screen with clock
  │   ├── player.html             YouTube IFrame fullscreen kiosk
  │   ├── index.html              WebUI dashboard (legacy WiFi control)
  │   ├── admin.html              developer backdoor
  │   └── socket.io.min.js        local copy — CDN does NOT work in App Lab
  ├── sketch/sketch.ino           MCU LED control via Bridge
  ├── typelibs/                   GObject typelibs for dbus-python
  └── wheels/                     Pre-built Python wheels ARM64 + shared libs

Flutter app (Windows):
  C:\Users\mahes\yt_display_app_fresh\lib\
  ├── main.dart
  ├── models/board_event.dart         BtDevice model (mac, name, rssi, connected)
  ├── services/ble_service.dart       BLE central, all commands, EVT handler
  ├── services/board_state.dart       ChangeNotifier state store
  ├── screens/home_screen.dart        main dashboard
  └── widgets/
      ├── connect_section.dart
      ├── youtube_section.dart
      ├── player_controls.dart
      └── bt_audio_section.dart       BT speaker management UI

---

## SYSTEMD SERVICES

dbus-bridge.service (system)
  socat proxy: /app/dbus.sock → /run/dbus/system_bus_socket
  Allows App Lab Docker container to access BlueZ via D-Bus

bt-autoconnect.service (user)
  Runs once at boot after BlueZ + PipeWire ready
  Connects all trusted BT devices, sets first as default PipeWire sink
  Script: /usr/local/bin/bt-autoconnect.py

WirePlumber config
  /etc/pipewire/wireplumber.conf.d/51-bt-autoconnect.conf
  Auto-connects any BT audio device using A2DP profile

XFCE Autostart
  ~/.config/autostart/youtube-display-launcher.desktop
  Starts launcher.sh after desktop login

---

## BT AUDIO — CRITICAL ARCHITECTURE DECISIONS

### Why two paths (D-Bus direct vs file bridge)?
- BT_LIST and BT_SCAN use D-Bus direct INSIDE the container
  Zero audio disruption — never calls bluetoothctl
  Previously bt_list_trusted() used file bridge → bluetoothctl → interrupted A2DP stream → FUZO disconnected
- BT_CONNECT/DISCONNECT/PAIR/FORGET use file bridge to host
  Because wpctl (PipeWire control) only runs on host, not in container
  Container cannot run wpctl or set PipeWire sinks directly

### BLE vs Classic BT — important limitation
The board scans BLE (le transport) only.
  BLE devices: show up in scan — phones, JioSTB, some modern speakers
  Classic BT only devices (e.g. Airdopes Joy earbuds): do NOT show up in BLE scan

NEVER use auto transport for scan on this board.
  Using auto transport triggers Classic BT inquiry which powers off the BT adapter on QRB2210.
  Confirmed bug — sudo reboot is the only recovery.
  The le transport filter is intentional and must stay.

Classic BT pairing is v1.4 planned feature requiring:
  1. Persistent pairing agent as systemd service on host
  2. Two-phase scan (BLE first, then Classic with safe delay)
  3. Careful timing to avoid killing BLE advertisement

### One speaker at a time
PipeWire handles one default audio sink. Connecting a new speaker automatically
becomes the new default. Disconnect → PipeWire falls back to Dummy Output.
bt-autoconnect.service reconnects trusted speakers on next reboot.

---

## KNOWN ISSUES AND LESSONS LEARNED

HDMI/DP audio broken — ELD version 0, QRB2210 driver limitation, use BT speaker
BT scan auto transport kills adapter — confirmed on QRB2210, use le only
bluetoothctl not in Docker container — use D-Bus direct for reads, file bridge for writes
bt_list_trusted caused audio drop — fixed by using D-Bus direct instead of file bridge
FUZO dropped when app opened — fixed by removing bluetoothctl from bt_list_trusted
Chromium --load-extension= bug — fixed, only add flag when extensions exist
Video invisible thumbnail only — fixed with --user-data-dir per instance
launcher.sh killed itself — fixed by renaming from launch_chromium.sh
socket.io CDN fails in App Lab — must be local in assets/
dbus.sock wrong path after rename — use basename $PROJECT_DIR dynamically
BT adapter off after crash — sudo systemctl restart bluetooth && bluetoothctl power on

---

## VERSION ROADMAP

v1.0  WiFi URL → IFrame YouTube → LCD                     Done
v1.1  Smooth transitions                                   Partial
v1.2  Flutter BLE phone app + BT audio manager            Done
v1.3  Parent queue + kid viewing schedule                  Next session
v1.4  Classic BT pairing from app (earbuds etc.)          Planned
v2.1  QR code pairing — exclusive board-phone bond        Planned
v3.0  Stream any internet video URL                        Planned
v4.0  Offline USB video playback                          Planned

---

## v1.3 QUEUE FEATURE SPEC (next session)

Parent builds video queue per day, sends to board via BLE.
Board plays automatically. Parent controls all. Kids only watch.

Confirmed decisions:
  Play only when parent taps PLAY — no auto-scheduled time trigger
  Queue is day-tagged (date only, no time window)
  Auto-advance: video ends → next video plays automatically
  Replay: parent taps REPLAY → current video replays → continues
  Jump: CMD:QUEUE_GOTO:N → jump to video N
  Queue stored on board in queue.json (survives app close)
  History: logs completion % + replay count per video
  YouTube IFrame only — no yt-dlp, no mpv
  Multiple children = future scope
  Time windows = future scope

New commands needed:
  CMD:QUEUE_PLAY       start queue
  CMD:QUEUE_REPLAY     replay current video
  CMD:QUEUE_SKIP       skip to next
  CMD:QUEUE_GOTO:N     jump to video N
  CMD:QUEUE_PAUSE      pause queue (vacation mode)
  CMD:QUEUE_RESUME     resume queue
  CMD:QUEUE_SET:<json> send full queue to board
  CMD:QUEUE_GET        board sends current queue + history

Build order:
  1. Board: queue.json storage
  2. Board: BLE parser for CMD:QUEUE_* commands
  3. Board: queue engine (play, advance, replay)
  4. Board: history logging
  5. Phone: Queue Builder UI
  6. Phone: Queue Controls widget
  7. Phone: History screen

---

## QUICK REFERENCE

Deploy:         bash ~/ArduinoApps/youtube-display/deploy.sh
Logs:           arduino-app-cli app logs user:youtube-display 2>/dev/null | tail -30
BT status:      wpctl status && bluetoothctl devices Trusted
BT fix:         sudo systemctl restart bluetooth && sleep 3 && bluetoothctl power on
Audio test:     pw-play /usr/share/sounds/alsa/Front_Left.wav
Flutter build:  flutter build apk --debug
Flutter install: adb install -r build\app\outputs\flutter-apk\app-debug.apk
Flutter clean:  flutter clean
Gradle clean:   Remove-Item -Recurse -Force C:\Users\mahes\.gradle\caches
