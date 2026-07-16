# BLE Hub App

A Flutter mobile app that controls the **Arduino UNO Q BLE Hub** over Bluetooth Low Energy.

Works on **Android and iOS**. No WiFi required on the phone — everything goes over BLE.

---

## What It Does

- Sends YouTube URLs to the board → video plays on the connected HDMI display
- Controls the player (pause, resume, stop, mute)
- Switches display modes (idle, YouTube, clock)
- Toggles the MCU LED
- Manages BLE devices connected to the board (scan, connect, disconnect, trust)
- Receives live state updates from the board via BLE notify
- Full event log

---

## Requirements

- Flutter 3.27+
- Android 6.0+ or iOS 12+
- Arduino UNO Q running the [ble-display](https://github.com/<your-username>/ble-display) project

---

## Setup

```bash
git clone https://github.com/<your-username>/ble-hub-app.git
cd ble-hub-app
flutter pub get
flutter run
```

---

## BLE Protocol

The app connects to the board advertising as `BLE-Hub` with service UUID:

```
a00b0000-0000-0000-0000-000000000000
```

| Characteristic | UUID | Direction | Purpose |
|---|---|---|---|
| Command | `a00b0002-...` | Phone → Board | Send commands |
| Event | `a00b0003-...` | Board → Phone | Receive state updates |

### Commands sent by the app

```
YT:<url>              Play a YouTube URL
CMD:LED_TOGGLE        Toggle MCU LED
CMD:LED_ON            Turn LED on
CMD:LED_OFF           Turn LED off
CMD:MODE_IDLE         Switch display to idle
CMD:MODE_YOUTUBE      Switch display to YouTube
CMD:MODE_CLOCK        Switch display to clock
CMD:PLAYER_PAUSE      Pause video
CMD:PLAYER_RESUME     Resume video
CMD:PLAYER_STOP       Stop video
CMD:PLAYER_MUTE       Mute
CMD:PLAYER_UNMUTE     Unmute
CMD:SCAN_START        Start BLE scan on board
CMD:SCAN_STOP         Stop BLE scan
CMD:CONNECT:<mac>     Connect to BLE device
CMD:DISCONNECT:<mac>  Disconnect BLE device
CMD:FORGET:<mac>      Remove trusted device
CMD:GET_STATUS        Request full board state
```

---

## Project Structure

```
lib/
├── main.dart                   # Entry point
├── models/
│   └── board_event.dart        # Data models for board events
├── services/
│   ├── ble_service.dart        # BLE central logic (scan, connect, write, notify)
│   └── board_state.dart        # State management (ChangeNotifier)
├── screens/
│   └── hub_screen.dart         # Main dashboard screen
└── widgets/
    ├── connection_bar.dart     # BLE connection status + scan/disconnect
    ├── led_mode_bar.dart       # LED toggle + display mode buttons
    ├── youtube_section.dart    # YouTube URL input + history
    ├── player_controls.dart    # Pause/resume/stop/mute controls
    ├── ble_devices_panel.dart  # BLE device scanner and manager
    └── log_console.dart        # Live event log
```

---

## Android Permissions

The app requires these permissions (already in `AndroidManifest.xml`):

```
BLUETOOTH
BLUETOOTH_ADMIN
BLUETOOTH_SCAN
BLUETOOTH_CONNECT
ACCESS_FINE_LOCATION
```

On Android 12+ the user will be prompted to grant Bluetooth permissions on first launch.

## iOS Permissions

Add to `Info.plist` (already included):

```
NSBluetoothAlwaysUsageDescription
NSBluetoothPeripheralUsageDescription
```

---

## How It Works

1. Open app → tap **Scan** → app scans for `a00b0000` service UUID
2. Finds `BLE-Hub` → connects automatically
3. Discovers characteristics → subscribes to event notify on `a00b0003`
4. Board pushes full status on connect → UI populates
5. All controls write commands to `a00b0002` as UTF-8 strings
6. Board pushes state changes back via notify → UI updates in real time

---

## Companion Project

This app requires the **ble-display** board project:
[https://github.com/<your-username>/ble-display](https://github.com/<your-username>/ble-display)
