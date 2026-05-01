# Arduino UNO Q — Complete Learning Guide
## Part 3: Debian Linux System, BLE GATT Server & Advanced Topics

> Sources: UNO Q User Manual (Mar 2026), Debian Basics guide (Mar 2026), Security Hardening guide (Mar 2026), Remote Access guide (Apr 2026), Arduino Router RPC guide (Apr 2026), BLE App Lab project source code analysis.

---

## 1. Debian Linux on the UNO Q — Architecture

The QRB2210 MPU runs a full **Debian Linux** distribution (currently Debian "Trixie" / testing branch with Arduino's custom package repository overlaid).

```
┌─────────────────────────────────────────────┐
│            Debian Linux (QRB2210)            │
│                                              │
│  ┌─────────────┐    ┌────────────────────┐  │
│  │ App Lab      │    │ Your Python Apps   │  │
│  │ (Electron)   │    │ + Bricks (Docker)  │  │
│  └─────────────┘    └────────────────────┘  │
│         │                    │               │
│  ┌──────────────────────────────────────┐    │
│  │       arduino-router daemon           │    │
│  │  /var/run/arduino-router.sock        │    │
│  └────────────────┬─────────────────────┘    │
│                   │ /dev/ttyHS1 (UART)       │
└───────────────────┼──────────────────────────┘
                    │
        ┌───────────┴────────────┐
        │  STM32U585 (Zephyr)    │
        │  Arduino sketches      │
        └────────────────────────┘
```

**Key filesystem locations:**
```
/home/arduino/             # Your working directory (separate partition — survives reflash)
/home/arduino/ArduinoApps/ # All App Lab projects
/home/arduino/ArduinoApps/<AppName>/.cache/  # Python venv, build artifacts
/home/arduino/ArduinoApps/<AppName>/data/    # App persistent data
/var/run/arduino-router.sock                 # Router Unix socket
/dev/ttyHS1                                  # MPU↔MCU UART (DO NOT OPEN)
/sys/class/leds/                             # MPU-controlled LED sysfs interface
```

---

## 2. Accessing the Board Shell — 4 Methods

### Method 1: ADB (USB) — No Network Required

Best for: initial setup, debugging broken WiFi, quick access.

```bash
adb devices    # list connected boards
adb shell      # enter shell (password: arduino on first boot)
exit           # leave shell
```

### Method 2: SSH (Network) — Wireless

Best for: normal development, file transfer, remote management.

```bash
ssh arduino@<boardname>.local   # mDNS discovery
ssh arduino@192.168.x.x         # direct by IP (more reliable on some networks)
```

### Method 3: SBC Mode (Desktop) — Full Linux Desktop

Best for: running App Lab natively, USB camera/audio testing, full GUI.

Connect via USB-C hub with power delivery → monitor → keyboard → mouse → login with Linux credentials.

### Method 4: Hardware Debug UART — Low-Level Boot Logs

Best for: capturing early boot messages before network is available, diagnosing boot failures.

```
JCTL connector:
  Pin 4 (SOC_SE4_TX) → RX on your 1.8V USB-TTL adapter
  Pin 6 (SOC_SE4_RX) → TX on your 1.8V USB-TTL adapter
  Pin 1 or 7 (GND) → GND on adapter
  
Settings: 115200 baud, 8N1
⚠️ 1.8V logic ONLY — use a compatible adapter (e.g., DSD Tech SH-U09C5)
```

---

## 3. Essential Linux Commands for UNO Q

### Navigation

```bash
pwd                    # where am I?
cd ~/ArduinoApps       # go to Apps directory
ls -lah                # detailed listing including hidden files
find /home/arduino -name "*.py"     # find Python files
find /home/arduino -mtime -7        # files modified in last 7 days
grep -r "Bridge.call" ~/ArduinoApps  # search inside all files
```

### File Operations

```bash
cp source.txt dest.txt             # copy file
cp -r source_folder/ dest_folder/  # copy directory recursively
mv old.txt new.txt                 # rename file
mv file.txt /home/arduino/         # move file
rm file.txt                        # delete file (IRREVERSIBLE)
rm -rf folder/                     # delete directory (DANGEROUS — no confirmation)
mkdir -p projects/sub/dir          # create nested directories
nano myfile.txt                    # edit file (easy terminal editor)
cat myfile.txt                     # view file contents
less myfile.txt                    # scrollable view (q to quit)
head -n 20 logfile.txt             # first 20 lines
tail -f logfile.txt                # watch file grow in real-time
```

### Permissions

```bash
chmod +x script.sh        # make executable
chmod 755 script.sh       # owner: rwx, group+others: r-x
chmod -R 755 folder/      # apply recursively
sudo chown arduino:arduino /home/arduino/project/ -R  # fix ownership
```

### System Status

```bash
df -h                    # disk usage (check / partition for Docker space)
free -h                  # RAM usage
top                      # live process monitor (q to quit)
du -sh *                 # size of each item in current directory
uname -a                 # Linux kernel version
cat /etc/os-release      # Debian version info
lscpu                    # CPU information
```

### Package Management

```bash
sudo apt update                     # refresh package lists
sudo apt upgrade                    # upgrade all packages
sudo apt install <package>          # install software
sudo apt remove <package>           # uninstall (keep config)
sudo apt purge <package>            # uninstall + delete config
sudo apt autoremove                 # remove unused dependencies
apt search <keyword>                # find packages
```

### Network

```bash
ip addr                             # show IP addresses
nmcli device status                 # network device status
nmcli device wifi list              # scan for WiFi networks
nmcli device wifi connect "SSID" password "pass"  # connect to WiFi
nmcli device disconnect wlan0       # disconnect WiFi
nmcli connection show               # list saved connections
nmcli connection delete "SSID"      # forget network
ping google.com                     # test internet connectivity (Ctrl+C to stop)
hostname -I                         # show board's IP addresses (use LAN IP, not 172.x.x.x)
```

### System Logs

```bash
journalctl -f                       # live system log stream
journalctl -xe                      # recent logs with explanations
journalctl -u arduino-router -f    # router service logs
journalctl -u arduino-router -n 50  # last 50 router log entries
sudo journalctl -f                  # if you need root
sudo dmesg | less                   # kernel messages
```

### Process Management

```bash
systemctl status arduino-router     # check service status
sudo systemctl restart arduino-router   # restart service
sudo systemctl start/stop/enable/disable <service>  # manage services
ps aux | grep python                # find running Python processes
kill <PID>                          # terminate a process
```

---

## 4. Shutdown Behavior — Important UNO Q Specifics

The UNO Q has **auto-restart** behavior by design:

```
sudo shutdown now    →  clean shutdown, then AUTOMATIC RESTART ⚠️
sudo poweroff        →  clean shutdown, then AUTOMATIC RESTART ⚠️
sudo reboot          →  intentional restart (expected)
sudo halt            →  clean shutdown, stays OFF ✓ (recommended for power-down)
```

**Why the difference?** The board's power management system is designed for always-on IoT deployment. `shutdown` and `poweroff` bring Linux to a safe state but the hardware power controller restarts the board.

**To power off for storage or transport:**
```bash
sudo halt
# Wait for green power LED to turn off — then disconnect power
# (For USB-C powered: unplug USB-C immediately after LED goes off — timing matters)
```

---

## 5. MPU-Controlled LEDs — Python Control

### Direct Sysfs (Shell or Python)

```bash
# From shell:
echo 1 | tee /sys/class/leds/red:user/brightness     # LED 1 Red ON
echo 0 | tee /sys/class/leds/green:wlan/brightness   # LED 2 Green OFF
```

```python
# From Python (direct file I/O):
def set_led(led_file, value):
    with open(led_file, "w") as f:
        f.write(f"{value}\n")

# LED 1 channels
set_led("/sys/class/leds/red:user/brightness", 1)
set_led("/sys/class/leds/green:user/brightness", 0)
set_led("/sys/class/leds/blue:user/brightness", 0)

# LED 2 channels (system status — can be overridden)
set_led("/sys/class/leds/red:panic/brightness", 0)
set_led("/sys/class/leds/green:wlan/brightness", 1)
set_led("/sys/class/leds/blue:bt/brightness", 0)
```

### Using the Leds API (App Lab)

```python
from arduino.app_utils import App, Leds

def loop():
    Leds.set_led1_color(1, 0, 0)   # LED1 red (R=1, G=0, B=0)
    time.sleep(1)
    Leds.set_led1_color(0, 1, 0)   # LED1 green
    time.sleep(1)
    Leds.set_led2_color(0, 0, 1)   # LED2 blue (overrides system status)
    time.sleep(1)

App.run(user_loop=loop)
```

---

## 6. Remote Access Options

### 6.1 Tailscale + SSH (Access from Anywhere)

```bash
# Install Tailscale on UNO Q
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up    # authenticate via provided link

# Find Tailscale IP
tailscale ip -4

# SSH from anywhere
ssh arduino@<tailscale-ip>
```

### 6.2 xrdp — Remote Desktop (RDP Protocol)

Gives you a graphical desktop over the network.

```bash
# Install on UNO Q
sudo apt update
sudo apt install xrdp dbus-x11
sudo systemctl enable xrdp
sudo systemctl start xrdp
# Listens on port 3389
```

**Connect:** Windows = Remote Desktop Connection (built-in) | macOS = Windows App | Linux = Remmina

**Fix black screen on connect** (common issue):
```bash
sudo tee /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
if [ -r /etc/profile ]; then . /etc/profile; fi
exec dbus-run-session -- xfce4-session
EOF
sudo systemctl restart xrdp
```

**RDP over ADB (USB, no network needed):**
```bash
adb forward tcp:3389 tcp:3389
# Then connect RDP client to localhost:3389
adb forward --remove tcp:3389  # cleanup when done
```

**RDP over Tailscale VPN:**
```bash
# Get Tailscale IP
tailscale ip -4
# Connect RDP client to <tailscale-ip>:3389
```

### 6.3 RustDesk — Open-Source Remote Desktop

```bash
# On UNO Q - download aarch64.deb from github.com/rustdesk/rustdesk/releases
wget <PASTE_DOWNLOAD_LINK>
sudo dpkg -i rustdesk-*-aarch64.deb
sudo apt -f install

# Install dummy display driver (for headless use)
sudo apt install xserver-xorg-video-dummy
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-dummy.conf << 'EOF'
Section "Device"
  Identifier "DummyDevice"
  Driver "dummy"
  VideoRam 256000
  Option "IgnoreEDID" "true"
EndSection
Section "Monitor"
  Identifier "DummyMonitor"
  HorizSync 28.0-80.0
  VertRefresh 48.0-75.0
  Modeline "1920x1080" 148.50 1920 2008 2052 2200 1080 1084 1089 1125
EndSection
Section "Screen"
  Identifier "DummyScreen"
  Device "DummyDevice"
  Monitor "DummyMonitor"
  DefaultDepth 24
  SubSection "Display"
    Depth 24
    Modes "1920x1080"
  EndSubSection
EndSection
EOF

# Configure auto-login in LightDM
sudo tee -a /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=arduino
EOF

# Enable RustDesk and reboot
sudo systemctl enable rustdesk
sudo reboot

# After reboot, get your ID and set password via SSH
rustdesk --get-id
sudo rustdesk --password your_password
```

**Toggle between headless (RustDesk) and physical HDMI:**
```bash
sudo tee /usr/local/bin/toggle-display << 'EOF'
#!/bin/bash
CONF="/etc/X11/xorg.conf.d/10-dummy.conf"
BAK="${CONF}.bak"
if [ -f "$CONF" ]; then mv "$CONF" "$BAK"; echo "Switched to HDMI"
else mv "$BAK" "$CONF"; echo "Switched to headless/RustDesk"; fi
systemctl restart lightdm
EOF
sudo chmod +x /usr/local/bin/toggle-display
sudo toggle-display  # run to switch
```

---

## 7. Arduino Router RPC — Direct Access (Advanced)

You can communicate with the MCU from **any language** using the MessagePack RPC protocol directly over the Unix socket at `/var/run/arduino-router.sock`. This bypasses Arduino App Lab entirely.

### Protocol Specification

**Message Types:**

```
REQUEST  (type 0): [0, msgid, "method_name", [arg1, arg2, ...]]
RESPONSE (type 1): [1, msgid, error_or_nil, result_or_nil]
NOTIFY   (type 2): [2, "method_name", [arg1, arg2, ...]]
```

**Router Control Methods:**

```
[0, msgid, "$/register", ["method_name"]]   # register a function
[0, msgid, "$/reset", []]                   # unregister all your functions
```

### Python Direct Client

**Install:**
```bash
sudo apt install python3-msgpack
# or
pip3 install msgpack --break-system-packages
```

**Simple caller:**
```python
import socket, msgpack, sys

SOCKET_PATH = "/var/run/arduino-router.sock"
led_state = True  # or False

request = [0, 1, "set_led_state", [led_state]]
packed = msgpack.packb(request)

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
    client.connect(SOCKET_PATH)
    client.sendall(packed)
    response_data = client.recv(1024)
    response = msgpack.unpackb(response_data)
    print(f"Router Response: {response}")  # [1, 1, None, None] = success
```

**Reusable Python Bridge class** (from User Manual):
```python
import socket, msgpack, threading, time

class ArduinoBridge:
    def __init__(self, socket_path="/var/run/arduino-router.sock"):
        self.socket_path = socket_path
        self.sock = None
        self.msg_counter = 0
        self.pending_responses = {}
        self.running = False
        self.lock = threading.Lock()
        
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.socket_path)
        self.running = True
        t = threading.Thread(target=self._receive_loop, daemon=True)
        t.start()
        return True
    
    def call(self, method, *args, timeout=5):
        self.msg_counter += 1
        msgid = self.msg_counter
        event = threading.Event()
        with self.lock:
            self.pending_responses[msgid] = {"event": event, "result": None, "error": None}
        self.sock.sendall(msgpack.packb([0, msgid, method, list(args)]))
        if event.wait(timeout):
            with self.lock:
                r = self.pending_responses.pop(msgid)
            if r["error"]: raise Exception(r["error"])
            return r["result"]
        with self.lock:
            self.pending_responses.pop(msgid, None)
        raise TimeoutError(f"Timeout for {method}")
    
    def notify(self, method, *args):
        self.sock.sendall(msgpack.packb([2, method, list(args)]))
    
    def disconnect(self):
        self.running = False
        if self.sock: self.sock.close()
    
    def _receive_loop(self):
        unpacker = msgpack.Unpacker()
        while self.running:
            data = self.sock.recv(4096)
            if not data: break
            unpacker.feed(data)
            for msg in unpacker:
                if isinstance(msg, list) and len(msg) >= 4 and msg[0] == 1:
                    msgid = msg[1]
                    with self.lock:
                        if msgid in self.pending_responses:
                            self.pending_responses[msgid]["error"] = msg[2]
                            self.pending_responses[msgid]["result"] = msg[3]
                            self.pending_responses[msgid]["event"].set()
```

**Usage:**
```python
bridge = ArduinoBridge()
bridge.connect()

bridge.notify("set_led_state", True)   # fire-and-forget
value = bridge.call("read_sensor")      # wait for response
bridge.disconnect()
```

### C++ Direct Client

**Install:**
```bash
sudo apt install libmsgpack-cxx-dev
```

**Compile:**
```bash
g++ -std=c++17 my_app.cpp -pthread -o my_app
./my_app
```

**Key patterns:**
- Use `notify()` for `set_led_state` (no response needed — faster)
- Use `call()` for `read_sensor` (need the value back)
- Background thread receives all messages; mutex protects pending_responses map
- 5-second default timeout on `call()`

The full C++ `ArduinoBridge` class with template-based argument packing, async response tracking, and thread-safe access is in the User Manual's "Working with Arduino Router RPC" section.

---

## 8. BLE GATT Server on UNO Q — Complete Implementation

The BLE functionality runs on the Linux (MPU) side through BlueZ via D-Bus. App Lab apps can expose BLE GATT services.

### Why BLE on the MPU Side?

The WCBN3536A wireless module connects to the QRB2210 MPU — Bluetooth is handled by the Linux BlueZ stack, not the MCU. Your BLE code runs in Python on the MPU.

### D-Bus Access Challenge

BlueZ communicates via D-Bus, which normally requires access to the system D-Bus socket at `/run/dbus/system_bus_socket`. Docker containers (used by App Lab) don't have this by default. Solution: **socket forwarding via `socat`**.

### Complete BLE App Setup

**Step 1: Install system dependencies (run once)**
```bash
sudo apt update -qq
sudo apt install -y libcairo2-dev libgirepository-2.0-dev socat
```

**Step 2: Build Python wheels**
```bash
pip3 wheel dbus-python --wheel-dir ~/ArduinoApps/my_ble_app/wheels
pip3 wheel PyGObject --wheel-dir ~/ArduinoApps/my_ble_app/wheels
```

**Step 3: Copy required shared libraries**
```bash
for lib in \
    /lib/aarch64-linux-gnu/libdbus-1.so.3 \
    /lib/aarch64-linux-gnu/libapparmor.so.1 \
    /lib/aarch64-linux-gnu/libexpat.so.1 \
    /lib/aarch64-linux-gnu/libsystemd.so.0 \
    /usr/lib/aarch64-linux-gnu/libgirepository-2.0.so.0; do
    cp "$lib" ~/ArduinoApps/my_ble_app/wheels/
done
```

**Step 4: Copy GObject introspection typelibs**
```bash
mkdir -p ~/ArduinoApps/my_ble_app/typelibs
for typelib in GLib-2.0.typelib GLibUnix-2.0.typelib Gio-2.0.typelib GObject-2.0.typelib DBus-1.0.typelib; do
    cp "/usr/lib/aarch64-linux-gnu/girepository-1.0/$typelib" ~/ArduinoApps/my_ble_app/typelibs/
done
```

**Step 5: Create dbus-bridge systemd service**

This service creates a socket bridge from inside Docker to the system D-Bus:
```bash
sudo tee /etc/systemd/system/dbus-bridge.service > /dev/null << EOF
[Unit]
Description=DBus Unix Bridge for App Lab
After=network.target

[Service]
User=arduino
ExecStartPre=/bin/rm -f /home/arduino/ArduinoApps/my_ble_app/dbus.sock
ExecStart=/usr/bin/socat UNIX-LISTEN:/home/arduino/ArduinoApps/my_ble_app/dbus.sock,fork,reuseaddr,mode=0777,unlink-early UNIX-CONNECT:/run/dbus/system_bus_socket
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable dbus-bridge.service
sudo systemctl start dbus-bridge.service
```

**Step 6: Configure app.yaml**
```yaml
name: my_ble_app
description: "BLE GATT Server"
ports: [7000]
bricks:
  - arduino:web_ui: {}
network_mode: "host"
sockets:
  - "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
```

### BLE Python Code Structure

```python
import os, ctypes, sys

# Load shared libraries from bundled wheels
os.environ['GI_TYPELIB_PATH'] = '/app/typelibs'
for lib in ['libm.so.6', 'libdbus-1.so.3', 'libgirepository-2.0.so.0', ...]:
    ctypes.CDLL(f'/app/wheels/{lib}')

# Connect to D-Bus via the forwarded socket
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

# D-Bus interface names
BLUEZ_SERVICE_NAME = 'org.bluez'
GATT_MANAGER_IFACE = 'org.bluez.GattManager1'
GATT_SERVICE_IFACE = 'org.bluez.GattService1'
GATT_CHRC_IFACE    = 'org.bluez.GattCharacteristic1'
LE_ADVERTISEMENT_IFACE = 'org.bluez.LEAdvertisement1'
LE_ADVERTISING_MANAGER_IFACE = 'org.bluez.LEAdvertisingManager1'
DBUS_OM_IFACE = 'org.freedesktop.DBus.ObjectManager'
DBUS_PROP_IFACE = 'org.freedesktop.DBus.Properties'
```

### GATT Object Hierarchy

```
Application (root D-Bus object)
└── Service (GATT Service, with UUID)
    ├── Characteristic 1: RandomSensor (read-only)
    │   UUID: a00b0001-0000-0000-0000-000000000000
    │   Flags: ['read']
    │   Action: returns random 0-100 value when read
    │
    ├── Characteristic 2: TextCommand (write-only)
    │   UUID: a00b0002-0000-0000-0000-000000000000
    │   Flags: ['write', 'write-without-response']
    │   Action: receives UTF-8 text from phone
    │
    └── Characteristic 3: Timestamp (notify)
        UUID: a00b0003-0000-0000-0000-000000000000
        Flags: ['notify']
        Action: pushes HH:MM:SS string every 5 seconds when subscribed
```

### Advertisement Registration

```python
class Advertisement(dbus.service.Object):
    def __init__(self, bus, index):
        self.path = '/org/bluez/hci0/advertisement' + str(index)
        self.ad_type = 'peripheral'
        self.service_uuids = ['a00b0000-0000-0000-0000-000000000000']
        self.local_name = 'BLE'
        self.include_tx_power = True
        dbus.service.Object.__init__(self, bus, self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {
            'Type': dbus.String(self.ad_type),
            'ServiceUUIDs': dbus.Array(self.service_uuids, signature='s'),
            'LocalName': dbus.String(self.local_name),
            'IncludeTxPower': dbus.Boolean(self.include_tx_power),
            'Discoverable': dbus.Boolean(True)
        }
```

### Notify Characteristic Implementation

```python
class TimestampCharacteristic(Characteristic):
    def __init__(self, bus, index, service):
        super().__init__(bus, index, 'a00b0003-0000-0000-0000-000000000000',
                        ['notify'], service)
        self.notifier = None

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying: return
        self.notifying = True
        self.notifier = threading.Thread(target=self._send_timestamp, daemon=True)
        self.notifier.start()

    def _send_timestamp(self):
        while self.notifying:
            ts = datetime.datetime.now().strftime("%H:%M:%S")
            self.update_value(list(ts.encode('utf-8')))
            time.sleep(5)  # push every 5 seconds

    def update_value(self, value):
        self.value = dbus.Array(value, signature='y')
        self.PropertiesChanged(GATT_CHRC_IFACE, {'Value': self.value}, [])

    @dbus.service.signal(DBUS_PROP_IFACE, signature='sa{sv}as')
    def PropertiesChanged(self, interface, changed, invalidated):
        pass  # D-Bus signal emission happens automatically
```

### BLE + MCU Integration (via Bridge)

The BLE app also controls the MCU LED via Bridge RPC:

```python
# In BLE Python app:
from arduino.app_utils import Bridge

def on_toggle_led(client, data):
    global led_state
    led_state = not led_state
    Bridge.call("set_led_state", led_state)  # call MCU function
    ui.send_message('led_status', {'state': led_state, 'text': 'ON' if led_state else 'OFF'})
```

```cpp
// In MCU sketch:
#include <Arduino_RouterBridge.h>
bool led_state = false;

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, HIGH);  // HIGH = OFF (active-low)
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
    Bridge.provide("get_led_state", get_led_state);
}

void set_led_state(bool state) {
    led_state = state;
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}

bool get_led_state() { return led_state; }
```

### Device Connection Monitoring

```python
class DeviceMonitor:
    def __init__(self, bus):
        bus.add_signal_receiver(
            self.properties_changed,
            dbus_interface='org.freedesktop.DBus.Properties',
            signal_name='PropertiesChanged',
            arg0='org.bluez.Device1',
            path_keyword='path'
        )

    def properties_changed(self, interface, changed, invalidated, path):
        if interface != 'org.bluez.Device1': return
        # Extract connection state from D-Bus properties
        obj = self.bus.get_object('org.bluez', path)
        props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
        connected = bool(props.Get('org.bluez.Device1', 'Connected'))
        if connected:
            log('[BLE] Device connected')
        else:
            log('[BLE] Device disconnected')
```

### BLE Testing with nRF Connect

Use nRF Connect (iOS/Android) to test your GATT server:
1. Open nRF Connect → scan for "BLE" device
2. Connect → see all 3 characteristics listed by UUID
3. Tap on RandomSensor UUID → "Read" → see random 0-100 value
4. Tap on TextCommand UUID → "Write" → send text → see it in app log
5. Tap on Timestamp UUID → enable notifications → see HH:MM:SS pushed every 5 seconds

---

## 9. Arduino Cloud Integration

```python
# Brick configuration in app.yaml:
bricks:
  - arduino:arduino_cloud: {}

# In main.py:
from arduino.app_bricks.arduino_cloud import ArduinoCloud

cloud = ArduinoCloud(device_id="<YOUR_DEVICE_ID>", secret_key="<YOUR_SECRET>")

@cloud.on_change("led")
def led_changed(new_value):
    Bridge.call("set_led_state", new_value)  # sync cloud → MCU

App.run()
```

Setup flow: Arduino Cloud dashboard → Add Device → Arduino Uno Q → copy device_id + secret_key → paste into Brick Configuration in App Lab.

---

## 10. Security Hardening

### Default Credentials

The `arduino` user is the primary system user. First login requires setting a mandatory password.

**Strong password guidelines:** At least 12 characters with uppercase, lowercase, digits, and punctuation. Never reuse passwords.

### Audit Login History

```bash
last    # shows complete login/logout history + reboots from /var/log/wtmp
```

### Disable ADB (USB Access) for Production Deployment

```bash
sudo systemctl stop adbd     # stop now
sudo systemctl disable adbd  # don't start on boot
# Re-enable:
sudo systemctl enable adbd && sudo systemctl start adbd
```

### SSH Best Practices

By default, NO TCP ports are open on the network. SSH is enabled during first setup. For production:
- Use SSH key authentication (disable password auth)
- Restrict SSH to specific IP ranges via `iptables`
- Use SSH tunneling instead of exposing application ports directly

### SSH Tunneling to Protect a Service

```bash
# On UNO Q: block direct access to port 8900
sudo iptables -A INPUT -i lo -j ACCEPT            # allow localhost
sudo iptables -A INPUT -p tcp --dport 8900 -j DROP # block external

# On your PC: access via SSH tunnel
ssh -L 9999:127.0.0.1:8900 arduino@boardname.local
# Now access the service at localhost:9999 on your PC
```

### HTTPS for WebUI Brick

```bash
# Install mkcert on UNO Q
wget https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-arm64
chmod +x mkcert-v1.4.4-linux-arm64
sudo mv mkcert-v1.4.4-linux-arm64 /usr/local/bin/mkcert

# Generate certificates
cd ~/ArduinoApps/my-app
mkdir certs && cd certs
mkcert -install                    # install root CA
mkcert localhost 127.0.0.1 ::1    # generate cert for localhost
mv localhost+2.pem cert.pem
mv localhost+2-key.pem key.pem
```

```python
# In main.py:
ui = WebUI(use_ssl=True)  # enables HTTPS using certs/ directory
```

### Data Encryption at Rest

```bash
sudo apt install ecryptfs-utils
ecryptfs-setup-private   # creates encrypted ~/Private directory
# Files in ~/Private are encrypted; auto-mounted on login
# Store the passphrase safely!
ecryptfs-unwrap-passphrase ~/.ecryptfs/wrapped-passphrase  # retrieve passphrase
```

### System Monitoring (Production)

**Monitor disk space and send alerts:**
```bash
sudo apt install monit
sudo nano /etc/monit/monitrc
# Configure SMTP server for email alerts

sudo nano /etc/monit/conf.d/disk-check
# Add: check filesystem rootfs with path /
#       if space usage > 85% then alert
#       if inode usage > 85% then alert

sudo monit -t   # test config syntax
sudo systemctl reload monit
```

**Centralized log forwarding:**
```bash
sudo nano /etc/rsyslog.d/90-forward.conf
# Add:
# action(type="omfwd" target="<LOG_SERVER_IP>" port="514" protocol="tcp"
#   queue.type="linkedList" queue.filename="fwd_queue" queue.saveOnShutdown="on")
sudo systemctl restart rsyslog
```

---

## 11. USB Peripherals

```bash
lsusb                    # list all connected USB devices
lsusb -t                 # USB device tree
ls /dev/video*           # list video devices (cameras)
ls /dev/ttyUSB* /dev/ttyACM*  # list serial devices
lsblk                    # list storage devices

# Mount USB storage
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb
sudo umount /mnt/usb    # ALWAYS unmount before unplugging

# Test USB camera
sudo apt install cheese
cheese   # open camera viewer

# Camera in Python
import cv2
cap = cv2.VideoCapture(0)  # /dev/video0
ret, frame = cap.read()
```

---

## 12. First-Principles Challenge Questions (Part 3)

**Q1 — D-Bus and Docker:** The BLE app requires a `socat` bridge to forward the D-Bus socket into Docker containers. Why does Docker isolate the D-Bus socket by default? What security problem is D-Bus socket sharing solving, and what does forwarding it enable/risk?

**Q2 — BLE GATT model:** The GATT server exposes three characteristics: Read, Write, and Notify. What is fundamentally different between "Notify" and "Read" from the perspective of which side initiates the data transfer? Why does Notify require a background thread in the implementation shown?

**Q3 — sudo halt vs poweroff:** Both commands bring Linux to a clean state. Why does `poweroff` trigger an automatic restart on the UNO Q while `halt` doesn't? What hardware component controls this behavior?

**Q4 — MessagePack vs JSON:** The arduino-router uses MessagePack instead of JSON for RPC messages. What are the specific tradeoffs (size, speed, type safety, human-readability) between the two formats, and why does MessagePack win for this use case?

**Q5 — SSH tunnel security:** You've blocked port 8900 externally but allow access via SSH tunnel. Explain step-by-step how the tunnel works: which TCP connections exist, which machine initiates each, and why this is more secure than simply opening port 8900 in the firewall.

**Q6 — ecryptfs and ADB:** The documentation notes that `~/Private` (encrypted directory) is NOT automatically mounted when accessing the board via `adb shell`. Why not? What specific property of ADB access prevents the auto-mount from occurring?

---

*End of Part 3. Continue to Part 4: Real-World Projects, Troubleshooting & Reference.*
