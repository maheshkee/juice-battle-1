---
name: arduino-uno-q-home-hub
description: Use this skill when working on home-hub, digital-scale, or gas-cylinder-monitor projects on the Arduino UNO Q AQ3 board. Covers HX711 load cell integration, Bridge RPC patterns, BLE D-Bus setup, WebUI Socket.IO, App Lab Docker architecture, and all confirmed working configurations. Always check project knowledge files first. Critical: HX711 DT=D7 SCK=D6 ONLY, Bridge.notify() pattern ONLY, raw bit-bang NO external library.
---

## Project Knowledge Files (check these first, always)

- `UNO_Q_Part1_Hardware_Architecture.md` — board hardware, pinouts, voltage domains
- `UNO_Q_Part2_AppLab_Bridge.md` — App Lab, Docker, Bridge RPC, bricks
- `UNO_Q_Part3_Linux_BLE_Advanced.md` — BLE, D-Bus, BlueZ, socat bridge
- `UNO_Q_Part4_Projects_Reference.md` — examples, troubleshooting guide
- CLAUDE.md on board at ~/ArduinoApps/home-hub/CLAUDE.md — latest session state

---

## Board Architecture

```
SSH → MPU (QRB2210, Debian Linux, 4GB RAM)
         ↓ Bridge RPC (Arduino_RouterBridge)
      MCU (STM32U585, Zephyr @ 160MHz)

App Lab = Docker container on MPU
Python runs INSIDE Docker
/app inside container = ~/ArduinoApps/APP_NAME/ on host
```

---

## HX711 — CONFIRMED WORKING FACTS (proven 2026-04-30, never deviate)

```
DT pin  = D7  (PA GPIO, no timer conflict)
SCK pin = D6  (PA GPIO, no timer conflict)
Power   = 5V  (green PCB clones NEED 5V AVDD)
Library = NONE (raw bit-bang only, no external library)
Pattern = Bridge.notify() from loop() every 500ms
```

### Why NOT other pins

```
D2 (PA10) — PWM timer conflict, always reads HIGH
D3 (PB0)  — Timer conflict, SCK bit-bang fails
D4 (PA12) — Used DT, unstable with wrong SCK
D5        — Same corrupt pattern as D3
```

### Why Bridge.notify() NOT provide_safe()

```
provide_safe() = Python calls MCU on demand
  → Race conditions with HX711 timing
  → Python thread contention
  → 2s poll too slow for weight

Bridge.notify() = MCU pushes when ready
  → No race conditions
  → MCU controls timing naturally
  → 500ms push rate perfect for weight scale
```

### The Working Bit-Bang (copy verbatim)

```cpp
#define HX711_DT_PIN   7   // D7 — NEVER change
#define HX711_SCK_PIN  6   // D6 — NEVER change

static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);          // REQUIRED — 160MHz MCU too fast
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);          // REQUIRED — both edges
    }
    digitalWrite(HX711_SCK_PIN, HIGH); // gain pulse = gain 128
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000; // sign extend
    return value;
}
```

### Python Listener (NOT polling)

```python
@Bridge.on('weight_event')
def on_weight(data):
    ui.send_message('weight_update', data)
```

---

## Reference Implementation — digital-scale

The canonical working app. When implementing weight in any new project, copy from here.

```
~/ArduinoApps/digital-scale/
├── sketch/sketch.ino      ← reference implementation
├── sketch/sketch.yaml     ← Arduino_RouterBridge only, no other libs
├── python/main.py         ← Bridge.on listener pattern
└── assets/index.html      ← WebUI with TARE button
```

sketch.yaml for any HX711 app:
```yaml
profiles:
  default:
    platforms:
      - platform: arduino:zephyr
    libraries:
default_profile: default
```
Note: No libraries listed — Arduino_RouterBridge is bundled with Zephyr platform.

---

## Critical Rules — Never Violate

1. HX711 DT=D7, SCK=D6. NO OTHER PINS.
2. Bridge.notify() for sensor data. Never Bridge.provide_safe() + Python polling.
3. No external HX711 library. Raw bit-bang only.
4. delayMicroseconds(1) after EVERY GPIO edge — HIGH and LOW, data bits AND gain pulse.
5. INPUT_PULLUP on DT pin — HX711 DOUT is open-drain.
6. BLE scan = le transport ONLY — auto transport kills BT adapter on QRB2210.
7. Never add sockets: to app.yaml.
8. Never use sed/regex to edit Python files — python3 read/replace/write only.
9. bt_manager.py is stub — never delete, never recreate from scratch.
10. JCTL = 1.8V ONLY. 3.3V = hardware damage.
11. No hardcoded paths, usernames, hostnames in any script.

---

## Corruption Patterns and Their Causes

| Pattern | Meaning | Cause | Fix |
|---------|---------|-------|-----|
| raw=8388607 (0x7FFFFF) | ADC positive saturation | Wrong pin (timer conflict) or loose wire | Move to D7/D6 |
| raw=-8388608 (0x800000) | ADC negative saturation | Same as above | Move to D7/D6 |
| raw=-1 (0xFFFFFF) | All bits HIGH = not ready | Read while HX711 mid-conversion | Check wait_ready() |
| Constant value regardless of weight | Load cell not responding | A+/A- not connected or broken cell | Check wiring |

---

## App Lab Docker Rules

```
D-Bus inside Docker requires socat socket forwarding
Socket path: /app/dbus.sock (only path Docker can reach)
Never add sockets: to app.yaml — confirmed broken
Python wheels for dbus: /app/wheels/
```

---

## Bridge RPC Rules

```
Bridge.begin()        — must be first in setup()
Monitor.begin()       — second in setup()
Bridge.provide_safe() — use only for commands (tare, config)
Bridge.notify()       — use for continuous sensor data from loop()
Bridge.call()         — use from Python to trigger MCU actions
```

---

## BLE UUIDs (home-hub, never change)

```
Service:  a01c0000-0000-0000-0000-000000000000
CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)
```

---

## Calibration Formula

```
new_cal = current_cal × (displayed_g / actual_g)

Starting point: 420.0f
For gas cylinder range (5-14kg): calibrate with 1kg+ reference weight
```

---

## LED Conventions (home-hub)

```
LED3_R (PH10) — active LOW — RED on during tare
LED3_G (PH11) — active LOW — GREEN on when ready, blinks on each read
Both active LOW: digitalWrite(LED, LOW) = ON, HIGH = OFF
```

---

## Deploy Pattern

```bash
cd ~/ArduinoApps/APP_NAME && bash deploy.sh
# Force recompile:
rm -rf .cache && rm -rf ~/.arduino15/internal && bash deploy.sh
# Logs:
arduino-app-cli app logs user:APP_NAME --follow
```

---

## HX711 Load Cell Skill (confirmed 2026-05-01)

### What Works
- Raw bit-bang on D7/D6 with delayMicroseconds(1) per edge
- Bridge.notify() push architecture (NOT Bridge.call() polling)
- Bridge.provide() on Python side to receive MCU notifications
- CALIBRATION_FACTOR = 100.0f for this specific 20kg load cell + HX711 module
- Filtering: skip RAW==-1, RAW==0x7FFFFF, RAW==0x800000 in hx711_read_average()

### What Fails
- Bridge.on() does not exist in App Lab Python API — use Bridge.provide()
- D2/D3/D4/D5 for HX711 — timer conflicts on STM32U585
- External HX711 library (ScaleHX711, HX711Zephyr) — causes issues
- Both ends of load cell resting on surface — beam cannot flex
- HX711 VCC from 3.3V on green PCB clone modules — use 5V

### Calibration Math
cal_factor = net_raw_units / actual_grams
where net_raw_units = RAW_with_weight - RAW_empty (both after tare)
