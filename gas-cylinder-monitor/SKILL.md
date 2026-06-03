# SKILL.md — gas-cylinder-monitor
# Merged from: experiments/SKILL.md + home-hub/SKILL.md + home-hub/SKILLS.md
# Last updated: 2026-06-03
# Read this before generating any code or modifying any file in this project.

---

## Board Architecture

```
SSH → MPU (QRB2210, Debian Linux, 4GB RAM)
         ↓ Bridge RPC (Arduino_RouterBridge, LPUART1 9600 baud MSGPACK)
      MCU (STM32U585, Zephyr RTOS @ 160MHz)

App Lab = Docker container on MPU
Python runs INSIDE Docker
/app inside container = ~/ArduinoApps/<APP_NAME>/ on host
```

---

## HX711 Hard Constraints (never deviate)

| Item | Value |
|------|-------|
| DT pin | D7 ONLY |
| SCK pin | D6 ONLY |
| Forbidden pins | D2 (TIM2_CH2), D3 (TIM3_CH3), D4, D5 — timer conflicts → 0x7FFFFF/0x800000 |
| Library | NONE — raw bit-bang only, no external library |
| delayMicroseconds | 1μs after EVERY GPIO edge — HIGH and LOW, data bits AND gain pulse |
| DOUT pullup | INPUT_PULLUP — HX711 DOUT is open-drain |
| VCC | 5V — green PCB clone modules need 5V AVDD (not 3.3V) |

---

## The Working Bit-Bang (copy verbatim — never change timing)

```cpp
#define HX711_DT_PIN   7   // D7 — NEVER change
#define HX711_SCK_PIN  6   // D6 — NEVER change

static long hx711_read_raw() {
    if (!hx711_wait_ready(400)) return LONG_MIN;  // 400ms — tuned for AQ3 under Bridge load
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 25th pulse: sets gain 128 (Channel A) for next conversion
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;  // sign extend 24-bit → 32-bit
    return value;
}
```

---

## Corrupt Value Filters (all four required — every read path)

```cpp
if (r == LONG_MIN)              continue;  // wait_ready timeout
if (r == -1)                    continue;  // 0xFFFFFF — all bits HIGH, not ready
if (r == 0x7FFFFF)              continue;  // positive saturation — pin/timer conflict
if (r < -5000000L || r > 5000000L) continue;  // out of physical range

// After gram conversion (adjust range to measurement context):
float g = (float)(r - tare_raw) / cal_factor;
if (g < -50.0f || g > 50.0f)   continue;  // outside physical range for empty scale
```

---

## Bridge.notify() Pattern (MCU → Python)

```cpp
// In loop() — millis() pacing at TOP, never inside state cases
void loop() {
    static uint32_t last_push = 0;
    if (millis() - last_push < PUSH_INTERVAL_MS) return;
    last_push = millis();

    long raw = hx711_read_raw();
    // filter corrupt reads...
    float grams = (float)(raw - tare_raw) / cal_factor;

    char buf[64];
    snprintf(buf, sizeof(buf), "{\"grams\":%.2f,\"sensor_ok\":true}", grams);
    Bridge.notify("weight_event", String(buf));
}
```

```python
# Python — Bridge.provide(), NOT Bridge.on() (does not exist)
def on_weight(data):
    print(str(data), flush=True)

Bridge.provide("weight_event", on_weight)
App.run()
```

---

## One Sample Per loop() Iteration (anti-pattern to avoid)

```cpp
// WRONG — blocking while inside state case
case STATE_MEASURE: {
    while (count < N) {
        long r = hx711_read_raw();
        count++;
    }
}

// CORRECT — one sample per loop() call
case STATE_MEASURE: {
    long r = hx711_read_raw();
    if (/* corrupt */) break;
    samples[count++] = r;
    if (count < N) break;  // yield back to loop() and return next call
    // compute stats here — only runs when count == N
}
```

---

## setup() Pattern

```cpp
void setup() {
    delay(3000);               // wait for Python container to start
    Bridge.begin();
    // Bridge.provide_safe() registrations here if needed
    Bridge.notify("log", String("MCU ready."));
}
```

**Never call Monitor.begin()** — makes synchronous RPC to Python; if no handler registered, MCU hangs forever.

---

## App Structure

```
<app-name>/
├── app.yaml
├── sketch/
│   ├── sketch.ino
│   └── sketch.yaml       ← Arduino_RouterBridge only; no library list needed
└── python/
    └── main.py           ← always required; minimum: Bridge.provide + App.run()
```

`sketch.yaml` for any HX711 app:
```yaml
profiles:
  default:
    platforms:
      - platform: arduino:zephyr
    libraries:
default_profile: default
```

---

## deploy.sh APP_NAME Rule

```bash
# Set APP_NAME explicitly — never use basename (nested paths give "app")
APP_NAME="gas-cylinder-monitor"
```

---

## Symlink Rule (arduino-app-cli lookup)

`arduino-app-cli` only looks one level deep under `~/ArduinoApps/`. Create a symlink:

```bash
ln -s ~/ArduinoApps/gas-cylinder-monitor/app ~/ArduinoApps/gas-cylinder-monitor
```

---

## Python Patterns

### Socket.IO (WebUI push)

```python
ui.send_message("weight_update",  {"weight_kg": 1.234, "weight_g": 1234.0})
ui.send_message("gas_prediction", {"days_left": 12.5, "low_confidence": False})
```

### push_evt() (BLE + Socket.IO)

```python
def push_evt(data):
    try:
        ble.push_evt(data)
    except Exception:
        pass
    ui.send_message(data.get("event", "evt"), data)
```

### BLE D-Bus Initialization (EXACT — must run before `import dbus`)

```python
import os, sys, ctypes

os.environ['GI_TYPELIB_PATH']         = '/app/typelibs'
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = 'unix:path=/app/dbus.sock'

for lib in ['libm.so.6','libcap.so.2','libpcre2-8.so.0','libselinux.so.1',
            'libaudit.so.1','libcap-ng.so.0','libexpat.so.1','libdbus-1.so.3',
            'libapparmor.so.1','libsystemd.so.0','libgirepository-2.0.so.0']:
    try:
        ctypes.CDLL(f'/app/wheels/{lib}')
    except Exception as e:
        print(f'[BLE] {lib}: {e}', flush=True)

sys.path.insert(0, '/usr/lib/python3/dist-packages')
import dbus, dbus.mainloop.glib
from gi.repository import GLib
```

Wheels live at `~/ArduinoApps/home-hub/wheels/` — one `cp` away. Do NOT duplicate into this repo.

---

## HX711 Calibration

```
grams = (raw_value - TARE) / CAL_FACTOR
```

- **TARE**: re-derive every boot. Never load from file. Range on AQ3: -12799 to -13737.
- **CAL_FACTOR**: derive once, store to `config.json`, load every boot. Range on AQ3: 100–107 raw/g.

```python
# Derive cal_factor
cal_factor = (raw_with_known_weight - tare_raw) / known_weight_g
```

---

## Per-Unit Calibration Rule

Every physical machine must be calibrated independently. Never copy `cal_factor` between units even if same model/wiring/code. Manufacturing tolerance ±0.5% + mounting geometry = 1–3% variation per unit.

---

## BLE UUIDs (never change — hardcoded in Flutter app)

```
Service:  a01c0000-0000-0000-0000-000000000000
CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)
```

---

## Critical Rules

| Rule | Detail |
|------|--------|
| DT=D7, SCK=D6 | Never change. D2–D5 have STM32U585 timer conflicts. |
| No external HX711 library | Raw bit-bang only. Copy from reference-code/hx711-modular/. |
| All four corrupt filters | LONG_MIN, -1, 0x7FFFFF, grams-range — all required. |
| millis() pacing at TOP of loop() | Never inside state cases. |
| One sample per loop() iteration | Never blocking while loops in state cases. |
| float only — never double | double arithmetic broken on STM32U585 (sum=0 bug). |
| Bridge.provide() not Bridge.on() | Bridge.on() does not exist in App Lab Python API. |
| Never Monitor.begin() | Hangs MCU if Python handler missing. |
| BLE transport = le only | auto kills WCBN3536A adapter, sudo reboot only recovery. |
| Never sockets: in app.yaml | Does not work — use socat bridge at /app/dbus.sock. |
| JCTL = 1.8V only | 3.3V on JCTL = hardware damage. |
| snprintf not String+= | String+= causes heap fragmentation on long-running MCU. |
| sketch.yaml required | Without it, arduino-app-cli uses wrong platform. |
| Read before edit | Always read full file before any Python edit. |

---

## Corruption Pattern Reference

| Pattern | Meaning | Cause | Fix |
|---------|---------|-------|-----|
| raw = 0x7FFFFF | ADC positive saturation | Wrong pin (timer conflict) | Move to D7/D6 |
| raw = 0x800000 | ADC negative saturation | Wrong pin | Move to D7/D6 |
| raw = -1 | All bits HIGH = not ready | Read while HX711 mid-conversion | Check wait_ready() |
| Constant value regardless of weight | Load cell not responding | A+/A- not connected | Check wiring |

---

## Deploy Reference

```bash
# Deploy
cd ~/ArduinoApps/gas-cylinder-monitor && bash deploy.sh

# Force recompile
rm -rf .cache && rm -rf ~/.arduino15/internal && bash deploy.sh

# Logs
arduino-app-cli app logs user:gas-cylinder-monitor --follow

# Docker fallback if logs empty
sudo docker logs $(sudo docker ps | grep gas-cylinder-monitor | awk '{print $1}') 2>&1 | tail -50
```
