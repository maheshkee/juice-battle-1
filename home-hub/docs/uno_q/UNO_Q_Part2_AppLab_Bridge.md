# Arduino UNO Q — Complete Learning Guide
## Part 2: Arduino App Lab, Bridge RPC & Development Workflow

> Sources: Official Getting Started guide (Feb 2026), User Manual (Mar 2026), App Lab Release Notes (v0.6.0), DroneBot Workshop field notes, Community testing notes.

---

## 1. What Is Arduino App Lab?

Arduino App Lab is the **unified development environment** designed exclusively for the UNO Q. It is fundamentally different from the classic Arduino IDE because it must manage **two processors simultaneously** — something no existing IDE was built for.

### What App Lab Manages

```
App Lab (running on PC or on the UNO Q itself)
│
├── Editor
│   ├── main.py        ← Python — compiles and deploys to Linux/MPU
│   ├── sketch.ino     ← C++ Arduino — compiles for STM32U585 MCU
│   └── assets/        ← HTML/CSS/JS for web UIs (optional)
│
├── Build & Deploy System
│   ├── Compiles sketch.ino for STM32U585 (ARM Cortex-M33, Zephyr toolchain)
│   ├── Creates Python virtual environment on the board
│   ├── Flashes MCU sketch over USB or WiFi
│   └── Deploys Python app + Bricks to Linux filesystem
│
├── Console (3 tabs)
│   ├── Start-up      ← Launch logs, compilation results, Brick deployment
│   ├── Main (Python) ← print() output from main.py
│   └── Sketch (MCU)  ← Monitor.println() output from sketch.ino
│
└── Resource Management
    ├── Library Manager  ← C++ sketch libraries
    ├── Brick Manager    ← modular pre-built service blocks
    └── Board Settings   ← update, flash, rename board
```

### App Lab Versions

| Version | Date | Key Changes |
|---|---|---|
| 0.3.2 | Jan 2026 | Early beta — limited editor, no find/replace, sluggish |
| 0.4.0 | Feb 6 2026 | Flasher tool integrated, syntax highlighting for web files |
| 0.5.0 | Feb 27 2026 | Edge Impulse + Arduino Cloud integration, mobile camera |
| **0.6.0** | **Mar 18 2026** | **Board settings page, new Bricks, Edge Impulse model update** |

---

## 2. Three Operating Modes

### Mode 1: Desktop (PC-Hosted) Mode — USB or WiFi

App Lab runs on your PC. The UNO Q connects via USB-C cable (first setup) or WiFi SSH (after WiFi is configured).

```
Your PC  ←─USB-C or WiFi SSH──►  UNO Q
App Lab                           Board runs the App
```

- **First connection requires USB-C** (for WiFi configuration)
- After WiFi setup, you can switch to Network/WiFi mode
- Only one connection active at a time (USB or WiFi, not both)

### Mode 2: Network Mode (WiFi)

Board connects to your WiFi. App Lab on your PC discovers it via mDNS on the local network.

```
App Lab (PC)  ←─WiFi/LAN──►  UNO Q
```

- Requires first setup to be completed over USB
- Both devices must be on the same local network
- Board appears in App Lab with "Network" tag
- Uses local network discovery (mDNS) — some corporate/guest WiFi networks block this
- **Windows:** Allow `mdns-discovery.exe` through firewall; ensure UDP port 5353 is open
- Does NOT require USB cable after initial setup

### Mode 3: Single-Board Computer (SBC) Mode

The UNO Q acts as a standalone Linux desktop. App Lab runs directly on the board.

```
USB-C Dongle ─── Monitor (HDMI)
              ├── Keyboard (USB)
              ├── Mouse (USB)
              └── External 5V/3A power supply
                  └── UNO Q (standalone)
```

- 4 GB RAM variant strongly recommended for SBC mode
- Log in with Linux credentials (default: `arduino` / your password)
- App Lab launches automatically on boot
- Requires USB-C dongle with **external power delivery** — do not use Apple dongles

---

## 3. First-Time Setup Sequence

```
Step 1: Install App Lab on your PC (or power UNO Q for SBC mode)
        ├── Windows: run .exe installer
        ├── macOS: drag .dmg to Applications
        └── Linux: extract .tar.gz, run AppImage
                   (requires: libwebkit2gtk-4.1-0)

Step 2: Connect UNO Q via USB-C data cable

Step 3: App Lab discovers the board (may take up to 60 seconds)
        └── LED matrix shows Arduino logo → pulsing heart when connected

Step 4: Select the board to connect

Step 5: App Lab scans for WiFi networks → choose network → enter password

Step 6: App Lab checks for updates → INSTALL ALL UPDATES

Step 7: Restart App Lab after updates complete

Step 8: Set device name and password (default user: arduino)

Step 9: Choose USB or WiFi connection going forward

Step 10: Run "Blink LED" example to verify setup ✓
```

> **Important:** The first boot takes **20–30 seconds** while Linux starts. The LED matrix animation indicates this. If App Lab shows the board but the animation is still running, wait for it to complete before running Apps.

### Linux Host Setup (Linux PC Users Only)

Linux blocks USB access by default. You must install udev rules before App Lab can connect:

```bash
echo \
'# Operating mode
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0078", MODE="0660", TAG+="uaccess"
# EDL mode (for flashing)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9008", MODE="0660", TAG+="uaccess"' \
| sudo tee "/etc/udev/rules.d/60-Arduino-UNO-Q.rules" \
&& sudo udevadm control --reload-rules \
&& sudo udevadm trigger
```

Then **unplug and reconnect** the board. Verify with:
```bash
lsusb | grep -E "2341:0078|05c6:9008"
adb devices
```

Alternative: run the official post-install script:
```bash
wget https://raw.githubusercontent.com/arduino/ArduinoCore-zephyr/main/post_install.sh
chmod +x post_install.sh && sudo ./post_install.sh
```

---

## 4. Apps — Complete Anatomy

An App is a **self-contained project** stored on the UNO Q at `/home/arduino/ArduinoApps/<AppName>/`.

> **Key fact:** App files live ON THE BOARD, not on your PC. App Lab edits files directly on the board via USB or network. Even in PC-hosted mode, your code exists on the UNO Q's filesystem.

### App File Structure

```
MyApp/
├── app.yaml          ← App metadata, Brick config, port declarations
├── README.md         ← Documentation (feeds App Lab's "Learn" tab)
├── python/
│   └── main.py       ← Python entry point — runs on Linux/MPU
├── sketch/
│   ├── sketch.ino    ← Arduino C++ sketch — runs on MCU
│   └── sketch.yaml   ← Sketch metadata, library declarations
└── assets/           ← Optional: HTML/CSS/JS for WebUI
    ├── index.html
    ├── app.js
    └── style.css
```

### app.yaml

```yaml
name: my_app
description: "What this app does"
ports: [7000]          # exposed network ports (e.g., for web UI)
bricks:
  - arduino:web_ui: {}   # Bricks used by this app
icon: 🚀
network_mode: "host"   # optional: give Docker access to host network
sockets:               # optional: mount host sockets into Docker
  - "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
```

### main.py Template

```python
from arduino.app_utils import App, Bridge

# Runs when Python side starts up
print("App starting...")

# Define functions the MCU can call (provide to Bridge)
def handle_sensor_data(value: int):
    print(f"Sensor reading: {value}")

Bridge.provide("sensor_data", handle_sensor_data)

# Optional: run loop function
def loop():
    # Called repeatedly by App.run()
    pass

# ALWAYS at the end of main.py — launches Bridge and all Bricks
App.run(user_loop=loop)
```

> **Rule:** `App.run()` MUST be the **last line** of `main.py`. Any code after it will not execute properly. It starts the Bridge, launches all configured Bricks, and enters the event loop.

### sketch.ino Template

```cpp
#include <Arduino_RouterBridge.h>  // REQUIRED for Bridge + Monitor

void setup() {
    Bridge.begin();               // Initialize Bridge communication
    Monitor.begin();              // Initialize console output (not Serial!)
    
    // Expose local MCU functions to Linux/Python
    Bridge.provide("set_led", set_led);
    Bridge.provide("read_adc", read_adc);
    
    Monitor.println("MCU ready");
}

void loop() {
    // Bridge handles communication in background threads
    // Keep loop() free or use it for non-Bridge real-time tasks
}

void set_led(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);  // active-low
}

int read_adc() {
    return analogRead(A0);
}
```

---

## 5. Bridge RPC — The Heart of the UNO Q

### The Problem Bridge Solves

Two processors, no shared memory, different operating systems, different languages. How do they coordinate? They need a protocol that:
- Is type-safe (no mis-matched data types across the language boundary)
- Supports synchronous calls (request → wait → response)
- Supports asynchronous push (fire-and-forget notifications)
- Is transport-agnostic (can work over UART, USB, or SPI)

That protocol is **Bridge** — implemented as Arduino's RPC (Remote Procedure Call) layer.

### The Three Bridge Primitives

```
Bridge.provide(name, function)   ← Register a local function for remote calling
Bridge.call(name, args...)       ← Call a remote function and WAIT for response
Bridge.notify(name, args...)     ← Call a remote function WITHOUT waiting (fire-and-forget)
```

**On the MCU (C++):**
```cpp
Bridge.provide("set_led", set_led);       // MCU exposes set_led to Python
int val = Bridge.call("get_data");        // MCU calls Python's get_data function
Bridge.notify("sensor_reading", 42);      // MCU pushes data to Python without waiting
```

**On the MPU (Python):**
```python
Bridge.provide("get_data", get_data_fn)   # Python exposes get_data to MCU
Bridge.call("set_led", True)              # Python calls MCU's set_led function
Bridge.notify("command", "start")         # Python pushes command to MCU
```

### The Arduino Router — Infrastructure Behind Bridge

Under the hood, Bridge uses a background Linux service called `arduino-router`:

```
┌─────────────────────────────────────────────────────────────────┐
│                   arduino-router (Star Topology)                  │
│                                                                   │
│  Python App ──────────────────────────────────────────────┐      │
│  Another Python Script ───────────────────────────────────┤      │
│  C++ App ─────────────────────────────────────────────────┤  ←→  MCU │
│  Any Linux process ────────────────────────────────────────┘      │
│                                                                   │
│  Unix socket: /var/run/arduino-router.sock                        │
│  Serial link to MCU: /dev/ttyHS1 @ 115200 baud                   │
└─────────────────────────────────────────────────────────────────┘
```

**Key architecture fact:** The Router uses a **Star Topology** with MessagePack RPC. Multiple Linux processes can communicate with the MCU simultaneously — or with each other, without involving the MCU at all.

**Managing the Router:**
```bash
systemctl status arduino-router        # check if running
sudo systemctl restart arduino-router  # restart if stuck
journalctl -u arduino-router -f       # view live logs
```

**Enable verbose logging for debugging:**
```bash
sudo systemctl edit --full arduino-router.service
# Add --verbose to ExecStart line
sudo systemctl daemon-reload && sudo systemctl restart arduino-router
journalctl -u arduino-router -f
```

### Bridge Safety Rules

```
⚠️  Do NOT call Bridge.call() or Monitor.print() inside a provide() callback.
    Initiating a new RPC while responding to one causes DEADLOCKS.

⚠️  Bridge.provide() executes in a HIGH-PRIORITY background RPC thread.
    Keep provide() callbacks SHORT and thread-safe.

⚠️  Use Bridge.provide_safe() instead if your callback calls Arduino APIs
    (digitalWrite, analogRead, etc.) — this ensures it runs in the main loop context.
```

### provide() vs provide_safe()

```cpp
// Use provide() for fast, thread-safe operations only:
Bridge.provide("set_value", [](int v) { shared_var = v; });

// Use provide_safe() when your callback calls Arduino hardware APIs:
Bridge.provide_safe("read_sensor", []() {
    return analogRead(A0);  // analogRead not safe from RPC thread
});
```

### Complete Bridge Example

**main.py (Python, runs on Linux/MPU):**
```python
from arduino.app_utils import App, Bridge
import time

led_state = False

def loop():
    global led_state
    time.sleep(1)
    led_state = not led_state
    Bridge.call("set_led_state", led_state)  # Call MCU function every second

App.run(user_loop=loop)
```

**sketch.ino (C++, runs on MCU):**
```cpp
#include "Arduino_RouterBridge.h"

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
}

void loop() {}

void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);  // active-low
}
```

---

## 6. Monitor vs Serial — Important Distinction

```
Serial.println("hello")  →  Goes to UART pins D0/D1 (physical TX/RX)
                             NOT visible in App Lab console

Monitor.println("hello") →  Goes to App Lab console via Bridge RPC
                             Visible in "Sketch (Microcontroller)" tab
```

```cpp
// WRONG for App Lab debugging:
void setup() { Serial.begin(115200); }
void loop()  { Serial.println("data"); }

// CORRECT for App Lab debugging:
#include <Arduino_RouterBridge.h>
void setup() { Monitor.begin(); }
void loop()  { Monitor.println("data"); }
```

`Serial` still works for UART communication with external devices — it just doesn't route to the App Lab console.

---

## 7. Running Apps

### From App Lab UI

1. Select an example (Examples tab) or your own app (Apps tab)
2. Click the **Run** button (top right)
3. Watch the Start-up console tab for compilation and deployment
4. Check the Python and Sketch tabs for runtime output

**Compilation time:** First run can take up to 60 seconds (MCU compilation + Python environment setup). Subsequent runs with unchanged sketch code are faster.

### Run at Startup (Standalone Deployment)

To run an App automatically every time the board boots:

1. Open your custom App (NOT a built-in example — must copy it first)
2. Click the **▼** arrow next to the Run button
3. Toggle **Run at startup** to ON
4. A **DEFAULT** badge appears next to the App name

Via CLI:
```bash
arduino-app-cli properties set default user:<APP_NAME>
```

### From Command Line (arduino-app-cli)

```bash
# List all available apps and their status
arduino-app-cli app list

# Start an app
arduino-app-cli app start user:my-app
arduino-app-cli app start examples:blink

# Stop an app
arduino-app-cli app stop user:my-app

# View logs
arduino-app-cli app logs /home/arduino/ArduinoApps/my-app --all

# Create a new app
arduino-app-cli app new "my-new-app"

# System management
arduino-app-cli system update              # check and install updates
arduino-app-cli system set-name "my-board" # rename board
arduino-app-cli system network enable      # enable SSH/network mode
arduino-app-cli system cleanup             # free Docker container storage

# Brick management
arduino-app-cli brick list                 # list installed Bricks
arduino-app-cli brick details arduino:<brick>
```

---

## 8. Console Tabs — Debugging Guide

| Tab | Content | When to Check |
|---|---|---|
| **Start-up** | MCU compilation output, Python deployment, Brick container launch | When app fails to launch |
| **Main (Python)** | `print()` output from main.py | Python logic errors, data flow |
| **Sketch (MCU)** | `Monitor.println()` output from sketch.ino | MCU errors, sensor readings |

> **Critical insight:** An app can launch successfully (Start-up tab shows no errors) yet still have runtime failures. Always check BOTH Python and Sketch tabs after pressing Run.

If a **sketch compilation error** occurs, launch is immediately aborted. If a **Python runtime error** occurs, the MCU sketch may still be running while Python fails silently.

---

## 9. Bricks — Modular Building Blocks

### What is a Brick?

A Brick is a **pre-packaged service** that runs alongside your App on the Linux side. Think of it as a ready-made backend component that eliminates writing infrastructure code from scratch.

```
Your App
├── main.py              ← your logic
├── sketch.ino           ← MCU code
└── Bricks (configured in app.yaml, deployed by App Lab):
    ├── WebUI Brick      ← web server at board_ip:7000 (uses assets/ folder)
    ├── Database Brick   ← time-series or SQL storage
    └── AI Model Bricks  ← object detection, audio classification, etc.
```

### How Bricks Work Internally

- **Simple Bricks** (e.g., WebUI, weather_forecast): Run as Python processes, imported directly into `main.py`
- **AI/Complex Bricks**: Run as **Docker containers** launched in parallel with your app

```bash
# Check which Docker containers are running:
docker ps
# Output shows: container ID, image, command, uptime, ports, name
```

> **Storage warning:** AI Bricks use Docker images that consume significant space in the `/` partition. The `/` partition starts at ~68% full on a fresh board. Monitor with `df -h` before deploying large AI Bricks.

### Adding a Brick to Your App

**Step 1:** In App Lab, click "Add Bricks" button in your App and select the Brick.

**Step 2:** This updates `app.yaml`:
```yaml
bricks:
  - arduino:web_ui: {}
  - arduino:motion_detection: {}
```

**Step 3:** Import and initialize in `main.py`:
```python
from arduino.app_bricks.web_ui import WebUI
from arduino.app_bricks.motion_detection import MotionDetection

ui = WebUI()  # serves web UI at board_ip:7000
detection = MotionDetection(confidence=0.7)

# Register callback for when motion is detected
def on_motion(data):
    print(f"Motion detected: {data}")
detection.on_detect(on_motion)

App.run()
```

### Complete Brick Categories & Available Bricks

**AI — Computer Vision:**
- `object_detection` — YoloX Nano model, detects 80+ object classes
- `image_classification` — classify objects in a static image
- `visual_anomaly_detection` — detect cracks/defects in concrete surfaces
- `video_objectdetection` — real-time object detection on live camera feed
- `video_imageclassification` — classify objects in video stream
- `video_person_classification` — detect/classify people in video
- `camera_code_detection` — QR code and barcode detection

**AI — Audio:**
- `audio_classification` — classify audio files by sound type
- `keyword_spotting` — detect spoken keywords ("Hey Arduino")
- `automatic_speech_recognition` (cloud) — cloud ASR

**AI — Sensor Data:**
- `motion_detection` — accelerometer-based motion pattern recognition (Edge Impulse)
- `vibration_anomaly_detection` — industrial vibration monitoring

**IoT/Cloud:**
- `arduino_cloud` — connect to Arduino Cloud IoT
- `telegram_bot` (new in 0.6.0) — Telegram Bot integration

**Storage:**
- `dbstorage_tsstore` — time-series database with retention and aggregation
- `dbstorage_sqlstore` — SQL storage for structured data

**Web/UI:**
- `web_ui` — web server at port 7000, with WebSocket for real-time updates

**Media:**
- `wave_generator` — audio synthesis and streaming
- `sound_generator` (new in 0.6.0) — sound generation

**LLM/AI:**
- `cloud_llm` — interface with cloud LLMs (Google Gemini, OpenAI GPT, Anthropic Claude)

### WebUI Brick — Detailed Guide

The WebUI Brick is the most commonly used. It serves your `assets/` folder as a web app at `http://board_ip:7000` (or `http://boardname.local:7000`).

**Python side:**
```python
from arduino.app_utils import App
from arduino.app_bricks.web_ui import WebUI

ui = WebUI()

# Send data to browser
def send_sensor_data(value):
    ui.send_message('sensor_update', {'value': value, 'time': '12:00:00'})

# Receive commands from browser
def on_toggle(client, data):
    Bridge.call("set_led_state", data.get('state', False))

ui.on_message('toggle', on_toggle)
ui.on_connect(lambda sid: send_sensor_data(0))  # send initial state on connect

App.run()
```

**JavaScript side (assets/app.js):**
```javascript
const socket = io(`http://${window.location.host}`);

socket.on('connect', () => {
    socket.emit('get_initial_state', {});
});

socket.on('sensor_update', (data) => {
    document.getElementById('value').textContent = data.value;
});

function toggleLed(state) {
    socket.emit('toggle', { state: state });
}
```

**HTTPS for WebUI (optional security hardening):**
```python
ui = WebUI(use_ssl=True)
```
Place `cert.pem` and `key.pem` in `assets/certs/` directory of your app. Use `mkcert` to generate certificates.

---

## 10. Arduino IDE Integration (Beta)

The classic Arduino IDE can be used to program **only the MCU side** (STM32U585). The MPU (Linux/Python) side requires App Lab.

### Setup

1. Open Arduino IDE
2. Go to **File → Preferences → Additional Board URLs**, add:
   ```
   https://downloads.arduino.cc/packages/package_zephyr_index.json
   ```
3. Go to **Tools → Board → Boards Manager**, search "UNO Q", install **Arduino UNO Q Zephyr Core**
4. In **Library Manager**, install **Arduino_RouterBridge** with all dependencies
5. Select board: **Tools → Board → Arduino UNO Q**
6. Select port: **Tools → Port → (UNO Q port)**
7. Upload normally with the Upload button

> **Important:** When using Arduino IDE, it uploads ONLY to the STM32U585 MCU. The Python side (main.py) will NOT run unless deployed via App Lab.

---

## 11. Alternative Editors & Recommended Workflow

App Lab's built-in editor (especially in early versions) has limitations. Professional workflow:

### Recommended Setup

```
Code Development  →  VS Code (or PyCharm/Vim) editing files on the board
File Access       →  SSH mount (sshfs) or VS Code Remote-SSH
Deployment        →  App Lab (Run button) or arduino-app-cli
Monitoring        →  App Lab console OR arduino-app-cli logs
```

### SSHFS Mount (Linux/macOS)

```bash
# Mount board filesystem locally
sshfs arduino@boardname.local:/home/arduino/ArduinoApps ~/arduino_apps

# Edit files locally with any editor
code ~/arduino_apps/my-app

# Changes are live on the board — just press Run in App Lab
```

### SCP File Transfer

```bash
# Push file to board
scp my_script.py arduino@boardname.local:/home/arduino/ArduinoApps/my-app/python/

# Push entire folder
scp -rp my-app/ arduino@boardname.local:/home/arduino/ArduinoApps/

# Pull folder from board
scp -rp arduino@boardname.local:/home/arduino/ArduinoApps/my-app/ ./
```

### ADB File Transfer

```bash
# Pull files from board
adb pull /home/arduino/ArduinoApps /path/to/local/folder

# Push files to board
adb push /path/to/local/folder /home/arduino/ArduinoApps
adb shell chown -R arduino:arduino /home/arduino/ArduinoApps
```

---

## 12. Example Apps — Complete Catalog

### Apps Without Additional Hardware

| App | Bricks Used | What It Demonstrates |
|---|---|---|
| **Blink LED** | None (Bridge only) | Basic Bridge: Python timing + MCU LED |
| **Blink LED with UI** | web_ui | Browser toggle switch controlling MCU LED |
| **Weather Forecast on LED Matrix** | weather_forecast | API data → Python → Bridge → MCU LED matrix |
| **Air Quality Monitoring** | None | AQICN API → LED matrix display |
| **UNO Q Pin Toggle** | web_ui | Interactive web dashboard controlling all pins |
| **Linux Blink with UI** | web_ui | WebSocket event handling basics |
| **System Resources Logger** | dbstorage_tsstore, web_ui | CPU/RAM monitoring + historical charting |
| **Mascot Jump Game** | web_ui | Real-time game physics: browser + LED matrix sync |
| **Bedtime Story Teller** | cloud_llm, web_ui | Streaming LLM responses to browser |
| **Image Classification** | image_classification, web_ui | Upload image → AI model → results |
| **Object Detection** | object_detection, web_ui | Upload image → bounding boxes |
| **Glass Breaking Sensor** | audio_classification, web_ui | Audio file → sound classification |
| **Concrete Crack Detector** | visual_anomaly_detection, web_ui | Structural defect detection |
| **Blinking LED from Arduino Cloud** | arduino_cloud | Cloud dashboard → Bridge → MCU LED |
| **Music Composer** (new 0.6.0) | wave_generator, web_ui | AI music generation |
| **Cloud AI Assistant** (new 0.6.0) | cloud_llm, web_ui | Conversational AI interface |
| **Telegram Bot** (new 0.6.0) | telegram_bot | Bot-controlled hardware |

### Apps Requiring Additional Hardware

| App | Hardware Needed | Bricks | What It Demonstrates |
|---|---|---|---|
| **Home Climate Monitoring** | Modulino Thermo (Qwiic) | dbstorage_tsstore, web_ui | I²C sensor → time-series DB → live dashboard |
| **Real-Time Accelerometer** | Modulino Movement (Qwiic) | motion_detection, web_ui | Motion ML + live data streaming |
| **Vibration Anomaly Detection** | Modulino Movement (Qwiic) | vibration_anomaly_detection, web_ui | Industrial vibration monitoring |
| **Hey Arduino!** | USB Microphone + hub | keyword_spotting | Wake word → LED matrix animation |
| **Code Detector** | USB camera + hub | camera_code_detection, dbstorage_sqlstore, web_ui | QR/barcode scanning + storage |
| **Detect Objects on Camera** | USB camera + hub | video_objectdetection, web_ui | Live object detection |
| **Face Detector on Camera** | USB camera + hub | video_objectdetection, web_ui | Live face detection |
| **Person Classifier on Camera** | USB camera + hub | video_imageclassification, web_ui | Person detection |
| **Object Hunting Game** | USB camera + hub | video_objectdetection, web_ui | AI scavenger hunt game |
| **Theremin Simulator** | USB audio device + hub | web_ui, wave_generator | Motion-controlled audio synthesis |
| **Mobile Video Object Detection** | Smartphone (IoT Remote app) | video_objectdetection, web_ui | Phone as wireless camera |
| **Color Your LEDs** | None (uses built-in LEDs) | web_ui | Control all 4 RGB LEDs from browser |

### Field-Tested App: Home Climate + Proximity

A real custom app built from the Home Climate example:

```
Architecture:
├── Modulino Thermo (I²C, Qwiic) ─────────────────────────────────┐
├── Modulino Distance (I²C, Qwiic, ToF proximity sensor) ──────── sketch.ino (MCU)
│                                                                   │ Bridge RPC
└── Display temperature on LED matrix ONLY when                    ▼
    person detected within 500mm ──────────────────────────── main.py (Python)
                                                                    │
                                                              Database Brick
                                                              WebUI Brick → browser:7000
```

**Known issue with read-only examples:** Official example Apps are read-only in the filesystem. If you get a Zephyr compilation/linking error, **duplicate the example** (click "Copy and edit app"). The copy has write permissions and compiles correctly even without changing any code.

---

## 13. Flashing a New Image (OS Reset)

Use the **Arduino Flasher CLI** to wipe and re-flash the Linux OS. Use this for:
- Hard reset after corruption
- Starting fresh
- Updating to a major new OS version

> **⚠️ WARNING: This wipes EVERYTHING on the board.** All files, apps, and configurations are destroyed.

### Requirements

- Arduino Flasher CLI (download from arduino.cc/en/software)
- Female-to-female jumper wire
- At least 10 GB free disk space on your PC
- Stable internet connection (image is >1 GB)

### Steps

**Step 1: Prepare hardware for flashing**
- Disconnect board from computer
- Short the two end pins of the JCTL connector (pins 2 & 9 = USB_BOOT to +1V8... actually pin 2 = USB_BOOT to GND) using a jumper wire
- Connect to computer via USB-C

**Step 2: Verify Flasher CLI works**
```bash
./arduino-flasher-cli        # macOS/Linux
arduino-flasher-cli.exe      # Windows
```

**Step 3: Flash**
```bash
./arduino-flasher-cli flash latest
# Downloads image (>1 GB) then flashes — takes several minutes
# DO NOT disconnect USB during this process
```

**Step 4: After success**
- Remove the jumper wire from JCTL
- Unplug and reconnect the board
- Wait for Linux to boot (LED matrix animation)

**Linux-specific:** The board enters EDL mode (USB VID 05C6 PID 9008) during flashing. Install the udev rules shown in Section 3 to grant access to both operating modes.

**Linux-specific issue — qcserial kernel module:**
```bash
lsmod | grep qcse   # check if loaded
# If present, blacklist it:
sudo nano /etc/modprobe.d/blacklist-modem.conf
# Add: blacklist qcserial
# Save and reboot
```

---

## 14. SSH Access

### Prerequisites

- First setup completed in App Lab (enables SSH and sets board password)
- Both computer and board on same WiFi network

### Connect

```bash
ssh arduino@<boardname>.local
# or by IP address:
ssh arduino@192.168.x.x
```

### Troubleshooting SSH

```bash
# Find board's IP address (run on board via ADB or SBC terminal):
hostname -I

# If known_hosts has stale entry after reflashing:
ssh-keygen -R boardname.local
ssh-keygen -R 192.168.x.x

# mDNS not working? Add to /etc/hosts on your PC:
sudo nano /etc/hosts
# Add: 192.168.x.x  boardname.local
```

---

## 15. ADB Access

Android Debug Bridge (ADB) gives shell access over USB without needing WiFi or SSH.

### Install ADB

```bash
# macOS
brew install android-platform-tools

# Windows
winget install Google.PlatformTools

# Linux (Debian/Ubuntu)
sudo apt-get install android-sdk-platform-tools
```

### Use ADB

```bash
adb devices          # list connected boards
adb shell            # enter board's shell (default password: arduino)
exit                 # leave shell

# Pull/push files
adb pull /home/arduino/ArduinoApps /local/path
adb push /local/path /home/arduino/ArduinoApps
adb shell chown -R arduino:arduino /home/arduino/ArduinoApps
```

### ADB for Network Recovery

If you configured a broken WiFi network and can't reach the board:
```bash
adb shell nmcli connection show           # list saved networks
adb shell nmcli connection delete "BrokenNetwork"
```

---

## 16. Custom AI Models with Edge Impulse

App Lab v0.5.0+ integrates directly with Edge Impulse for training custom AI models.

### Workflow

```
Step 1: In App Lab, navigate to a Brick's "AI models" tab
Step 2: Click "Train new AI model" → links to your Arduino account
Step 3: You're redirected to Edge Impulse Studio
Step 4: Collect data (image or audio samples)
Step 5: Label data, design Impulse, train model
Step 6: Export for UNO Q → .eim file
Step 7: Return to App Lab → model appears in Brick's model list
Step 8: Click "Install" → model is built and installed on the board
Step 9: Configure Brick to use your custom model
```

### Supported Model Types

| Type | Edge Impulse Block | Notes |
|---|---|---|
| Image object detection | MobileNetV2 SSD FPN-Lite 320x320 | ~370ms inference, 11MB Flash |
| Fast image detection | FOMO MobileNetV2 0.35 | ~3ms inference, 102KB Flash |
| Audio classification | MFCC + Neural Network | Fast inference |
| Accelerometer / motion | Spectral features + NN | Low latency |

### Custom Model Export Format

Edge Impulse exports a `.eim` (Edge Impulse Model) file — a container holding trained parameters and inference logic, optimized for the UNO Q's architecture.

---

## 17. IoT Remote App — Mobile Camera Integration

The Arduino IoT Remote app (iOS/Android) can stream your phone's camera to the UNO Q for AI vision projects without a USB webcam.

### How It Works

```
QR code generated by App on board
         │ scan with phone camera
         ▼
IoT Remote app opens → authenticates via OTP
         │ secure WebSocket handshake
         ▼
Phone streams video over HTTP (port 4912) → UNO Q
         │
         ▼ video frames fed to object detection Brick
         ▼
Results displayed in web browser at board_ip:7000
```

### Security Model

- One-time password (OTP) generated per session
- Direct WiFi connection — no video goes to cloud
- WebSocket control channel + HTTP video channel (port 4912)

### Integration Code

**main.py:**
```python
import secrets, string
from arduino.app_peripherals.camera import WebSocketCamera

def generate_secret():
    return ''.join(secrets.choice(string.digits) for _ in range(6))

secret = generate_secret()
resolution = (480, 640)  # portrait for mobile
camera = WebSocketCamera(resolution=resolution, secret=secret, encrypt=True)

ui.on_connect(lambda sid: ui.send_message("welcome", {
    "client_name": camera.name, "secret": secret,
    "status": camera.status, "protocol": camera.protocol,
    "ip": camera.ip, "port": camera.port
}))
```

**app.js:**
```javascript
socket.on('welcome', async (message) => {
    if (message.status !== "connected") {
        const url = `https://cloud.arduino.cc/installmobileapp?otp=${message.secret}&protocol=${message.protocol}&ip=${message.ip}&port=${message.port}`;
        new QRCode(document.getElementById('qrCodeContainer'), { text: url });
    }
});

// Display video stream
const streamUrl = `http://${window.location.hostname}:4912/embed`;
document.getElementById('videoIframe').src = streamUrl;
```

---

## 18. First-Principles Challenge Questions (Part 2)

**Q1 — Bridge architecture:** Bridge uses a "Star Topology" via the arduino-router. What is a star topology and why is it better for multi-process communication than point-to-point serial? What breaks if the router crashes?

**Q2 — provide() vs provide_safe():** Why is calling `analogRead()` inside a `Bridge.provide()` callback dangerous? What specific threading scenario causes this to fail?

**Q3 — App.run() position:** Why must `App.run()` be the LAST line of `main.py`? What happens to Bricks if you put code after it?

**Q4 — Bricks and Docker:** Some Bricks run in Docker containers. Why use Docker instead of running directly on the Linux system? What does containerization give you that a plain Python process doesn't?

**Q5 — Console tabs:** An App launches successfully (Start-up tab shows no errors), but the LED isn't blinking as expected. What specifically would you look for in each of the three console tabs, and in what order?

**Q6 — File storage:** You're editing `main.py` in App Lab on your PC while in Network mode. The board's WiFi drops for 5 seconds. You keep typing. What happens to your edits? Where do the files actually live?

---

*End of Part 2. Continue to Part 3: Debian Linux, System Administration & Board Access.*
