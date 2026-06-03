# Arduino UNO Q — Complete Learning Guide
## Part 4: Complete Projects, Troubleshooting & Quick Reference

> Sources: All previous source material synthesized into practical reference.

---

## 1. Complete Working Projects

### Project 1: Blink LED (Hello World — Full Stack)

The canonical first project. Demonstrates the complete MPU↔MCU architecture.

**sketch.ino:**
```cpp
#include <Arduino_RouterBridge.h>

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, HIGH);  // HIGH = OFF (active-low LED)
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
    Monitor.begin();
    Monitor.println("MCU: Ready");
}

void loop() {
    // Bridge handles communication in background threads
}

void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
    Monitor.print("LED: ");
    Monitor.println(state ? "ON" : "OFF");
}
```

**main.py:**
```python
from arduino.app_utils import App, Bridge
import time

led_state = False

def loop():
    global led_state
    time.sleep(1)
    led_state = not led_state
    Bridge.call("set_led_state", led_state)
    print(f"Python: toggled LED to {'ON' if led_state else 'OFF'}")

App.run(user_loop=loop)
```

**What to observe:**
- Start-up tab: MCU compilation success, Python deployment
- Sketch tab: "MCU: Ready" then "LED: ON/OFF" alternating
- Python tab: "Python: toggled LED to ON/OFF" alternating
- Built-in LED (LED_BUILTIN = LED3_R = red channel of RGB LED 3) blinks at 1Hz

---

### Project 2: Potentiometer → Variable LED Blink Rate

Demonstrates ADC reading on MCU and Bridge bidirectional communication.

**Hardware:** Potentiometer with center wiper → A0, outer pins → 3.3V and GND.

**sketch.ino:**
```cpp
#include <Arduino_RouterBridge.h>

const int potPin = A0;
const int ledPin = D9;  // PWM-capable
volatile int blinkDelay = 1000;
unsigned long prevMillis = 0;
int ledState = LOW;

int get_pot_value() {
    return analogRead(potPin);  // 0–16383 (14-bit ADC)
}

void set_blink_rate(int rate) {
    blinkDelay = constrain(rate, 50, 2000);
}

void setup() {
    analogReadResolution(14);  // 14-bit = 0 to 16383
    pinMode(ledPin, OUTPUT);
    Bridge.begin();
    Monitor.begin();
    Bridge.provide("get_pot_value", get_pot_value);
    Bridge.provide("set_blink_rate", set_blink_rate);
}

void loop() {
    unsigned long now = millis();
    if (now - prevMillis >= blinkDelay) {
        prevMillis = now;
        ledState = (ledState == LOW) ? HIGH : LOW;
        digitalWrite(ledPin, ledState);
    }
}
```

**main.py:**
```python
from arduino.app_utils import App, Bridge
import time

def loop():
    try:
        raw_val = int(Bridge.call("get_pot_value"))           # 0–16383
        new_delay = int((raw_val / 16383) * 1950) + 50        # map to 50–2000ms
        Bridge.call("set_blink_rate", new_delay)
        print(f"Pot: {raw_val} → Delay: {new_delay}ms")
    except Exception as e:
        print(f"Bridge error: {e}")
    time.sleep(0.05)  # 20Hz polling

App.run(user_loop=loop)
```

---

### Project 3: LED Matrix Weather Display

Demonstrates API data fetching on Linux + Bridge to MCU display.

**main.py:**
```python
from arduino.app_utils import App, Bridge
from arduino.app_bricks.weather_forecast import WeatherForecast
import time

weather = WeatherForecast()

def loop():
    try:
        data = weather.get_current()
        condition = data.get("condition", "unknown")
        # Map condition to LED matrix pattern (0=off, 1=on, 104 pixels)
        pattern = get_pattern_for_condition(condition)
        Bridge.call("display_pattern", pattern)
        print(f"Weather: {condition}")
    except Exception as e:
        print(f"Error: {e}")
    time.sleep(300)  # update every 5 minutes

def get_pattern_for_condition(condition):
    # Return 104-element list based on weather
    if "sun" in condition.lower():
        return [0]*104  # sunny pattern
    return [1]*104      # default: all on

App.run(user_loop=loop)
```

**sketch.ino:**
```cpp
#include <Arduino_RouterBridge.h>
#include <Arduino_LED_Matrix.h>

Arduino_LED_Matrix matrix;
uint8_t currentPattern[104];

void display_pattern(uint8_t pattern[], int size) {
    for (int i = 0; i < min(size, 104); i++) {
        currentPattern[i] = pattern[i];
    }
    matrix.draw(currentPattern);
}

void setup() {
    matrix.begin();
    matrix.setGrayscaleBits(1);
    Bridge.begin();
    Bridge.provide("display_pattern", display_pattern);
}

void loop() {}
```

---

### Project 4: BLE GATT + Web Dashboard + MCU LED (Complete)

Full-stack app: BLE peripheral running on Linux, web UI, MCU LED control via Bridge.

> See Part 3 Section 8 for the complete BLE implementation. Below is the integration summary.

**Architecture:**
```
Phone (nRF Connect) ←─ BLE ─→ BlueZ/D-Bus (Linux/MPU)
                                     │
                               Python BLE server
                                     │ Bridge.call()
                                     ▼
                              STM32U585 (MCU)
                              LED_BUILTIN control
                                     
Browser ←─ HTTP/WebSocket ─→ WebUI Brick (port 7000)
                                     │
                              Python BLE server
                              (controls advertising,
                               shows BLE events in log)
```

**app.yaml:**
```yaml
name: ble_gatt_dashboard
description: "BLE GATT Server with web UI and MCU LED control"
ports: [7000]
bricks:
  - arduino:web_ui: {}
network_mode: "host"
sockets:
  - "/run/dbus/system_bus_socket:/run/dbus/system_bus_socket"
```

---

### Project 5: Home Climate Monitor (Modulino)

**Hardware:** Modulino Thermo (I²C, Qwiic connector) + optionally Modulino Distance.

**sketch.ino:**
```cpp
#include <Arduino_RouterBridge.h>
#include <Modulino.h>

ModulinoThermo thermo;

float get_temperature() { return thermo.getTemperature(); }
float get_humidity()    { return thermo.getHumidity(); }

void setup() {
    ModulinoI2C.begin();  // Wire1 (Qwiic connector)
    thermo.begin();
    Bridge.begin();
    Bridge.provide("get_temperature", get_temperature);
    Bridge.provide("get_humidity", get_humidity);
}

void loop() {}
```

**main.py:**
```python
from arduino.app_utils import App, Bridge
from arduino.app_bricks.web_ui import WebUI
from arduino.app_bricks.dbstorage_tsstore import DBStorageTSStore
import time, datetime

ui = WebUI()
db = DBStorageTSStore()

def loop():
    temp = float(Bridge.call("get_temperature"))
    hum  = float(Bridge.call("get_humidity"))
    ts   = datetime.datetime.now().isoformat()
    
    db.insert("climate", {"temperature": temp, "humidity": hum, "timestamp": ts})
    ui.send_message('data_update', {"temp": temp, "humidity": hum, "time": ts})
    print(f"T={temp:.1f}°C  H={hum:.1f}%")
    time.sleep(5)

App.run(user_loop=loop)
```

> **Known issue:** If this is a read-only example app, duplicate it first before running. Zephyr needs write access to the sketch directory during compilation.

---

### Project 6: DAC Sine Wave Generator

Demonstrates hardware DAC output — 60 Hz sine wave on A0/DAC0 pin.

**sketch.ino:**
```cpp
// No Bridge needed for this pure hardware example
const float freq = 60.0f;
const int   N    = 256;
const uint32_t Ts_us = (uint32_t)llroundf(1e6f / (freq * N));
uint16_t lut[N];

void setup() {
    analogWriteResolution(12);  // 12-bit DAC = 0 to 4095
    for (int i = 0; i < N; ++i) {
        lut[i] = 2048 + (int)(1000.0 * sin(2 * PI * i / N));
    }
}

void loop() {
    static uint32_t t_next = micros();
    for (int i = 0; i < N; ++i) {
        analogWrite(DAC0, lut[i]);
        t_next += Ts_us;
        while ((int32_t)(micros() - t_next) < 0) { /* spin wait */ }
    }
}
```

Measure A0 (PA4) pin with oscilloscope or logic analyzer → should show 60 Hz sine wave, amplitude ≈ ±1V around 1.65V midpoint.

---

## 2. Troubleshooting Guide

### App Won't Launch

| Symptom | Likely Cause | Fix |
|---|---|---|
| Compilation error in Start-up tab | Syntax error in sketch.ino, or missing library | Read error message, check library is installed |
| Zephyr linking error | Example app is read-only; Zephyr needs write access | Duplicate the example first, then run the copy |
| Python import error in Main tab | Missing dependency, wrong Brick configuration | Check `app.yaml` Brick list, ensure Brick is added in UI |
| App starts but MCU doesn't respond | Bridge not initialized | Check `Bridge.begin()` is in `setup()` |
| Timeout waiting for response | Function not registered with `Bridge.provide()` | Verify function name matches exactly (case-sensitive) |

### Connection Issues

| Symptom | Cause | Fix |
|---|---|---|
| Board not found in App Lab | Too early — still booting | Wait for LED matrix animation to complete |
| Network mode not discovering board | mDNS blocked | Allow UDP port 5353, or connect by IP address |
| SSH connection refused | First setup not completed (SSH not enabled) | Connect via USB first, complete setup |
| ADB: insufficient permissions | udev rules not installed (Linux) | Install udev rules (Section 3, Part 2) |
| App Lab can't connect after WiFi change | Board on different network | Connect via USB, reconfigure WiFi in App Lab |

### Performance & Storage

| Symptom | Cause | Fix |
|---|---|---|
| / partition nearly full | Docker images from AI Bricks | `arduino-app-cli system cleanup` to remove unused containers |
| App runs slowly | Too many heavy Bricks | Use lightweight Bricks, check CPU usage with `top` |
| Bridge timeouts | Router crashed or serial link issue | `sudo systemctl restart arduino-router` |
| Compilation takes very long | First compile after MCU firmware update | Normal — subsequent compiles are faster |

### BLE Issues

| Symptom | Cause | Fix |
|---|---|---|
| "Connection failed" for D-Bus | dbus-bridge service not running | `sudo systemctl start dbus-bridge.service` |
| BLE device not visible | Advertising not started | Check for errors in advertising registration |
| Connect then immediately disconnect | BLE stack issue | Restart bluetooth: `sudo systemctl restart bluetooth` |
| BlueZ adapter not found | Bluetooth powered off | `bluetoothctl power on` or check WCBN3536A status |

### Voltage & Hardware Issues

| Symptom | Cause | Fix |
|---|---|---|
| Board won't boot after connecting external sensor | Voltage too high on MPU pin | Check: was it connected to JCTL? Those are 1.8V only |
| ADC reading always at maximum | A0/A1 connected to 5V | Only use 0-3.3V on A0/A1; they are NOT 5V tolerant |
| SPI device not responding | JSPI and JDIGITAL SPI conflict | Cannot use JSPI and D10-D13 SPI simultaneously |
| LED3/LED4 won't turn on | Active-low confusion | Use LOW to turn on, HIGH to turn off |
| I²C Modulino not detected | Wrong Wire object | Qwiic uses Wire1.begin(), not Wire.begin() |

---

## 3. Arduino App CLI — Complete Command Reference

```bash
# App management
arduino-app-cli app list                           # list all apps + status
arduino-app-cli app new "app-name"                 # create new app
arduino-app-cli app start user:my-app              # start user app
arduino-app-cli app start examples:blink           # start example
arduino-app-cli app stop user:my-app               # stop app
arduino-app-cli app logs user:my-app --all         # view all logs
arduino-app-cli app logs user:my-app               # view recent logs

# System
arduino-app-cli system update                      # check + install updates
arduino-app-cli system set-name "my-board"         # rename board
arduino-app-cli system network-mode enable          # enable SSH/network
arduino-app-cli system network-mode disable         # disable SSH/network
arduino-app-cli system network-mode status          # check status
arduino-app-cli system cleanup                     # remove unused Docker data
arduino-app-cli properties set default user:app    # set startup app

# Bricks
arduino-app-cli brick list                         # list installed Bricks
arduino-app-cli brick details arduino:web_ui       # details for specific Brick
```

---

## 4. Communication Protocols — Quick Setup

### I²C (Wire / Wire1)

```cpp
#include <Wire.h>

// Primary I²C (UNO headers: D20=SDA/PB11, D21=SCL/PB10)
Wire.begin();
Wire.beginTransmission(0x35);  // device address
Wire.write(0x00);              // register
Wire.write(0xFA);              // value
Wire.endTransmission();

// Secondary I²C (Qwiic: PD13=SDA, PD12=SCL) — for Modulino modules
Wire1.begin();
// Use Wire1.beginTransmission() etc. for Qwiic devices
```

### SPI

```cpp
#include <SPI.h>
#define SS D10  // Chip Select

void setup() {
    pinMode(SS, OUTPUT);
    digitalWrite(SS, HIGH);  // deselect
    SPI.begin();             // SCK=D13, MOSI=D11, MISO=D12
}

void loop() {
    digitalWrite(SS, LOW);      // select device
    SPI.transfer(0x35);         // send address byte
    byte result = SPI.transfer(0x00);  // receive data
    digitalWrite(SS, HIGH);     // deselect
}
```

### UART (Serial → external devices, not App Lab console)

```cpp
void setup() {
    Serial.begin(115200);  // D0=RX(PB7), D1=TX(PB6)
}

void loop() {
    Serial.println("Hello from MCU UART");  // NOT visible in App Lab console
    
    while (Serial.available()) {
        char c = Serial.read();
        Serial.print(c);  // echo received data
    }
}
```

### TCP over WiFi (Bridge-tunneled to MCU)

```cpp
#include <Arduino_RouterBridge.h>
BridgeTCPClient<> client(Bridge);

void setup() { Bridge.begin(); Monitor.begin(); }

void loop() {
    if (client.connect("api.example.com", 80)) {
        client.println("GET /data HTTP/1.0");
        client.println("Host: api.example.com");
        client.println();
        while (client.available()) {
            char c = client.read();
            Monitor.print(c);
        }
        client.stop();
    }
    delay(10000);
}
```

---

## 5. ADC Reference — All Configuration Options

```cpp
// Resolution options:
analogReadResolution(14);  // 14-bit: 0 to 16383 (DEFAULT, highest quality)
analogReadResolution(12);  // 12-bit: 0 to 4095
analogReadResolution(10);  // 10-bit: 0 to 1023
analogReadResolution(8);   // 8-bit:  0 to 255

// Voltage reference options:
analogReference(AR_DEFAULT);        // 3.3V (VREF+ = PWR_3P3V)
analogReference(AR_INTERNAL1V5);    // 1.5V internal
analogReference(AR_INTERNAL1V8);    // 1.8V internal
analogReference(AR_INTERNAL2V05);   // 2.048V internal
analogReference(AR_INTERNAL2V5);    // 2.5V internal
analogReference(AR_EXTERNAL);       // External via AREF pin

// Reading:
int raw = analogRead(A0);           // returns 0 to (2^resolution - 1)
float voltage = (raw / 16383.0) * 3.3;  // convert to volts (14-bit, 3.3V ref)

// DAC output (A0=DAC0, A1=DAC1):
analogWriteResolution(12);          // 12-bit DAC: 0 to 4095
analogWrite(DAC0, 2048);           // ~1.65V output (midpoint)
```

---

## 6. Bridge API — Complete Reference

### MCU (C++) Side

```cpp
#include <Arduino_RouterBridge.h>

// Initialization (must be in setup())
Bridge.begin();
Monitor.begin();  // for App Lab console output

// Register functions for Python to call
Bridge.provide("function_name", function_pointer);
Bridge.provide_safe("hardware_function", function_pointer);  // runs in main loop context

// Call Python functions from MCU
auto result = Bridge.call("python_function");                   // returns RpcCall
auto result = Bridge.call("python_function", arg1, arg2);      // with arguments
int value = result;                                             // implicit conversion

// Fire-and-forget to Python
Bridge.notify("python_function", data);

// Console output (appears in App Lab "Sketch" tab)
Monitor.print("value: ");
Monitor.println(42);
Monitor.println("message");
```

### Python Side

```python
from arduino.app_utils import App, Bridge

# Call MCU function and get result
result = Bridge.call("mcu_function")
result = Bridge.call("mcu_function", arg1, arg2)

# Fire-and-forget to MCU
Bridge.notify("mcu_function", data)

# Register Python function for MCU to call
def my_handler(value: int):
    print(f"MCU called with: {value}")

Bridge.provide("python_function", my_handler)

# Launch everything (must be LAST LINE)
App.run()
App.run(user_loop=my_loop_function)  # with periodic loop
```

---

## 7. Key GPIO Pin Mappings — Quick Reference

| Arduino Label | MCU Pin | Digital | PWM | ADC | DAC | Special |
|---|---|---|---|---|---|---|
| D0 / RX | PB7 | ✓ | — | — | — | USART1_RX |
| D1 / TX | PB6 | ✓ | — | — | — | USART1_TX |
| D2 | PB3 | ✓ | — | — | — | — |
| ~D3 | PB0 | ✓ | ✓ | — | — | OPAMP2_OUT |
| D4 | PA12 | ✓ | — | — | — | FDCAN1_TX |
| ~D5 | PA11 | ✓ | ✓ | — | — | FDCAN1_RX |
| ~D6 | PB1 | ✓ | ✓ | — | — | — |
| D7 | PB2 | ✓ | — | — | — | — |
| D8 | PB4 | ✓ | — | — | — | — |
| ~D9 | PB8 | ✓ | ✓ | — | — | — |
| ~D10 / SS | PB9 | ✓ | ✓ | — | — | SPI2_SS |
| ~D11 / MOSI | PB15 | ✓ | ✓ | — | — | SPI2_MOSI |
| D12 / MISO | PB14 | ✓ | — | — | — | SPI2_MISO |
| D13 / SCK | PB13 | ✓ | — | — | — | SPI2_SCK |
| D20 / SDA | PB11 | ✓ | — | — | — | I2C2_SDA (Wire) |
| D21 / SCL | PB10 | ✓ | — | — | — | I2C2_SCL (Wire) |
| A0 / D14 | PA4 | ✓* | — | ✓ | ✓(DAC0) | ⚠️ NOT 5V tolerant |
| A1 / D15 | PA5 | ✓* | — | ✓ | ✓(DAC1) | ⚠️ NOT 5V tolerant |
| A2 / D16 | PA6 | ✓* | — | ✓ | — | OPAMP2_IN+ |
| A3 / D17 | PA7 | ✓* | — | ✓ | — | OPAMP2_IN− |
| A4 / D18 | PC1 | ✓ | — | ✓ | — | I2C3_SDA (Wire, A4/A5 mode) |
| A5 / D19 | PC0 | ✓ | — | ✓ | — | I2C3_SCL (Wire, A4/A5 mode) |

*5V tolerant in digital mode ONLY — not when configured as ADC

**MCU-controlled LEDs:**
- LED3_R = PH10, LED3_G = PH11, LED3_B = PH12
- LED4_R = PH13, LED4_G = PH14, LED4_B = PH15
- LED_BUILTIN = LED3_R (red channel of RGB LED 3)
- All active-LOW: `LOW` = ON, `HIGH` = OFF

---

## 8. Modulino Ecosystem — Quick Reference

Modulino modules connect via Qwiic (I²C at 3.3V). Use `Wire1` in sketches.

```cpp
#include <Modulino.h>

ModulinoThermo thermo;     // temperature + humidity
ModulinoDistance distance;  // time-of-flight proximity
ModulinoMovement movement;  // accelerometer (IMU)
ModulinoPixels pixels;      // 8-LED RGB strip
ModulinoKnob knob;          // rotary encoder
ModulinoBuzzer buzzer;      // speaker/buzzer
ModulinoButtons buttons;    // 3-button panel

void setup() {
    ModulinoI2C.begin();    // initialize Wire1 for Qwiic
    thermo.begin();
    distance.begin();
    // ... etc
}

void loop() {
    float temp = thermo.getTemperature();   // °C
    float hum  = thermo.getHumidity();     // %RH
    int   dist = distance.get();           // mm
    int   knobPos = knob.get();            // encoder position
}
```

---

## 9. App Release Notes Summary

| Version | Date | Key Additions |
|---|---|---|
| 0.6.0 | Mar 18 2026 | Board settings page, Edge Impulse model updates, Sound Generator Brick, Telegram Bot Brick, Cloud AI Assistant example, Music Composer example |
| 0.5.0 | Feb 27 2026 | Edge Impulse integration, Arduino Cloud Brick, mobile camera (IoT Remote), Color Your LEDs example, mobile video detection |
| 0.4.0 | Feb 6 2026 | Flasher integrated, web code syntax highlighting, analytics, editor improvements |
| 0.3.2 | Jan 2026 | Early beta — functional but limited editor |

**Current version (as of Apr 2026):** 0.6.0

---

## 10. Board File System Layout

```
/                              # Root partition (~68% full on fresh board)
├── etc/                       # System configuration
│   ├── systemd/system/        # Service definitions (arduino-router, adbd, etc.)
│   └── udev/rules.d/          # USB permission rules
├── var/run/
│   └── arduino-router.sock    # Bridge RPC Unix socket
├── dev/
│   ├── ttyHS1                 # MPU↔MCU UART (DO NOT OPEN)
│   └── video*                 # USB cameras
└── sys/class/leds/            # MPU RGB LED sysfs interface

/home/arduino/                 # USER PARTITION (survives reflash!)
├── ArduinoApps/               # All App Lab projects
│   └── <AppName>/
│       ├── app.yaml
│       ├── python/main.py
│       ├── sketch/sketch.ino
│       ├── assets/            # HTML/CSS/JS (optional)
│       ├── .cache/            # Python venv, build artifacts
│       └── data/              # App persistent data
└── .local/share/mkcert/       # TLS certificates (if using mkcert)

/boot/efi/                     # Boot partition
```

---

## 11. Power Budget Planning

**Observed real-world consumption:**
- Idle + WiFi connected: ~100-200mA from 5V USB-C
- Idle + WiFi + 2 Apps running: ~400-500mA
- Peak during boot animation: <200mA
- **All well within USB3 port limit (900mA)**

**For external peripherals (budget from 3.3V rail):**
- Modulino Thermo: ~0.5mA
- Modulino Distance: ~10mA
- USB camera (via dongle): ~200-500mA from 5V_USB_VBUS
- USB microphone: ~50-100mA

**Remember:** 5V_USB_VBUS on headers (JANALOG pin 5, JSPI pin 2, JMISC pins 54/56) is shared with board consumption. Total draw from USB-C source must stay under 3A.

---

## 12. Quick Reference Card

### UNO Q Architecture in One Sentence
> QRB2210 MPU (Linux/Python, 1.8V I/O) + STM32U585 MCU (Zephyr+Arduino/C++, 3.3V I/O) communicate via Bridge RPC over a dedicated UART link, managed by the arduino-router service.

### Voltage Rules in One Sentence
> JDIGITAL/JANALOG/JSPI/QWIIC = 3.3V; JCTL/JMEDIA/JMISC-MPU-pins = 1.8V; A0&A1 are NOT 5V tolerant in any mode.

### Console in One Sentence
> Use `Monitor.println()` (not `Serial.println()`) for App Lab console; `Serial` goes to physical UART pins D0/D1.

### Bridge in Three Lines
> MCU: `Bridge.provide("name", fn)` + `Bridge.begin()`; `Bridge.call("name")`; `Bridge.notify("name", val)`.
> Python: `Bridge.call("name", args)` → returns value; `Bridge.notify("name", args)` → fire-and-forget.
> `App.run()` must be the LAST line of main.py.

### File Location in One Line
> App files live on the BOARD at `/home/arduino/ArduinoApps/<AppName>/` — not on your PC.

### SPI Conflict Warning
> JSPI (A5 connector) and JDIGITAL D10-D13 share SPI2 — never use both simultaneously.

### BLE is Linux-side
> BLE GATT runs via BlueZ/D-Bus on the QRB2210 MPU (Python), not on the STM32U585 MCU.

---

## 13. Final First-Principles Challenge Questions

**Q1 — System integration:** Trace the complete data path for this scenario: "A temperature reading from a Modulino Thermo module appears in a web browser." Name every protocol, every software component, and every hardware bus involved in order.

**Q2 — Brick architecture:** Why do AI Bricks use Docker containers while simpler Bricks (like `web_ui`) don't? What specific property of AI inference workloads makes containerization beneficial?

**Q3 — Bridge timeout:** You call `Bridge.call("get_temperature")` from Python, but it times out after 5 seconds. List five different reasons this could happen, ordered from most likely to least likely, and how you'd diagnose each.

**Q4 — Active-low LEDs:** The schematic shows all four RGB LEDs are connected between their MCU/MPU GPIO pins and the 3.3V rail (not to GND). Why would a designer connect LEDs to the power rail instead of ground? What circuit topology is this, and what does it imply for the logic level to turn them on?

**Q5 — Boot sequence:** When you press "Run" in App Lab, sketch compilation starts. But the App Lab runs on your PC while the MCU is on the board. Where exactly does compilation happen? On your PC, on the board's Linux system, or somewhere else? Trace the full build → flash → run sequence.

**Q6 — Docker and disk space:** An AI Brick downloads a Docker image that's 800MB. Where does this go on the UNO Q's storage? If you run three different AI Bricks, do they share base image layers or duplicate storage? How do you reclaim this space?

---

## 14. Glossary

| Term | Definition |
|---|---|
| **MPU** | Microprocessor Unit — the QRB2210, runs Debian Linux |
| **MCU** | Microcontroller Unit — the STM32U585, runs Zephyr + Arduino Core |
| **Bridge** | Arduino's RPC layer connecting MPU ↔ MCU communication |
| **arduino-router** | Linux background service managing Bridge traffic (star topology) |
| **App** | Complete project in App Lab: Python + sketch + optional Bricks |
| **Brick** | Pre-packaged service (web server, AI model, database, API client) |
| **GATT** | Generic Attribute Profile — BLE service/characteristic structure |
| **BlueZ** | Linux Bluetooth protocol stack |
| **D-Bus** | Linux IPC mechanism used by BlueZ |
| **Qwiic** | SparkFun I²C connector ecosystem, 3.3V, used for Modulino modules |
| **Modulino** | Arduino's plug-and-play sensor/actuator modules (Qwiic-compatible) |
| **eMMC** | Embedded Multi-Media Card — the board's built-in storage |
| **LPDDR4X** | Low-Power Double Data Rate 4X — the board's RAM type |
| **PMIC** | Power Management IC — the PM4125 that generates the 1.8V rail |
| **mDNS** | Multicast DNS — protocol for discovering boards by name on local network |
| **ADB** | Android Debug Bridge — USB shell access tool |
| **EDL** | Emergency Download Mode — mode for firmware flashing (USB VID 05C6) |
| **udev** | Linux kernel device manager — handles USB permission rules |
| **socat** | Network/socket relay tool — used to bridge D-Bus into Docker |
| **Wire1** | Secondary I²C bus object in Arduino — maps to Qwiic connector |
| **Monitor** | Bridge-tunneled console output — replaces Serial for App Lab debugging |
| **provide_safe** | Bridge variant that runs callback in main loop context (thread-safe for Arduino APIs) |
| **Star Topology** | Network where all clients connect to a central router, not directly to each other |
| **MessagePack** | Binary serialization format used by arduino-router RPC protocol |
| **PWR_3P3V** | 3.3V system rail powering MCU and maker headers |
| **VREG_L15A_1P8V** | 1.8V rail from PM4125 PMIC powering MPU I/O |
| **5V_SYS** | System 5V bus — Schottky OR of USB-C VBUS and VIN buck output |
| **Diode-OR** | Circuit where two power sources feed through diodes so only the higher voltage wins |

---

*This concludes the Arduino UNO Q Complete Learning Guide (4 parts).*
*Parts: 1=Hardware Architecture, 2=App Lab & Bridge, 3=Linux & BLE, 4=Projects & Reference*
*All content sourced from official Arduino documentation (2025-2026) + community field notes.*
