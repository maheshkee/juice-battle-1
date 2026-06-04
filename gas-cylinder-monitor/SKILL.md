# SKILL.md — gas-cylinder-monitor
# Last updated: 2026-06-04 (ESP32 pivot — split into node + hub contexts)
# Read this before generating any code or modifying any file in this project.

---

## Two Contexts — Read the Right Section

This project has two code contexts that MUST NOT be blurred.
Read only the section that applies to the current task.

---

## NODE CONTEXT — ESP32-C3 (node/ directory)

Firmware for the ESP32-C3 sensor node. Arduino IDE or PlatformIO.
NOT App Lab, NOT Bridge, NOT Bridge.notify.

### HX711 Bit-Bang Pattern (port from reference-code/stm32-hx711-modular/)

Port the LOGIC, not the code. The STM32 pin numbers (D7/D6) and call conventions
(Bridge.notify) do NOT carry. The bit-bang timing does.

```cpp
// Pin constants — TBD at E-000. Any two ESP32-C3 GPIO work.
// #define HX711_DT_PIN  <chosen at bring-up>
// #define HX711_SCK_PIN <chosen at bring-up>

static long hx711_read_raw() {
    if (!hx711_wait_ready(200)) return LONG_MIN; // timeout — re-tune on ESP32
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
    if (value & 0x800000) value |= 0xFF000000; // sign extend 24-bit → 32-bit
    return value;
}
```

**wait_ready timeout:** was 400ms on STM32 (tuned for Bridge load). Re-tune on ESP32.
Start with 200ms; adjust based on observed DOUT behaviour.

### Corrupt-Value Filters (all three required — every read path)

```cpp
if (r == LONG_MIN)                   continue;  // wait_ready timeout
if (r == -1)                         continue;  // 0xFFFFFF — not ready
if (r == 0x7FFFFF)                   continue;  // positive saturation
// After gram conversion:
float g = (float)(r - tare_raw) / cal_factor;
if (g < -500.0f || g > 35000.0f)     continue;  // outside physical range
```

### Node WiFi Send Pattern

```cpp
// In loop() — millis() pacing at TOP, never inside state cases
void loop() {
    static uint32_t last_send = 0;
    if (millis() - last_send < SEND_INTERVAL_MS) return;
    last_send = millis();

    long raw = hx711_read_raw();
    // filter corrupt reads...
    float grams = (float)(raw - tare_raw) / cal_factor;

    char buf[96];
    snprintf(buf, sizeof(buf),
        "{\"grams\":%.1f,\"quality\":\"GOOD\",\"sigma\":%.2f}",
        grams, current_sigma);
    // send via WiFi (MQTT publish or HTTP POST)
}
```

No Bridge.notify here. No Bridge.provide. No App.run.

### One Sample Per loop() Iteration (anti-pattern to avoid)

```cpp
// WRONG — blocks while inside state case
case STATE_NOISE: {
    while (count < N) { long r = hx711_read_raw(); count++; }
}

// CORRECT — one sample per loop() call, yield by returning
case STATE_NOISE: {
    long r = hx711_read_raw();
    if (/* corrupt */) break;
    samples[count++] = r;
    if (count < N) break;  // yield; comes back next loop()
    // compute stats only when count == N
}
```

### Node setup() Pattern

```cpp
void setup() {
    Serial.begin(115200);
    pinMode(HX711_DT_PIN, INPUT_PULLUP);
    pinMode(HX711_SCK_PIN, OUTPUT);
    // WiFi connect...
    // NO Bridge.begin(). NO delay(3000). NO Monitor.begin().
}
```

### Node Calibration Rules

```
grams = (raw_reading - tare_raw) / cal_factor

tare_raw : self-computed at setup, never hardcoded. Re-compute on every cylinder removal.
cal_factor: self-computed at setup, stored to config.json, loaded at boot. NEVER 106.7 — that was STM32.
sigma    : measured every boot (N=200 lab, N=50 production). Never hardcoded.
```

**float vs double:** the double-broken bug was STM32U585-specific. Re-verify on ESP32-C3
at E-001. Use float as safe default until verified.

### Node Module Contract

Every node module returns:
```cpp
struct ModuleResult {
    float value;
    enum Quality { GOOD, DEGRADED, FAILED } quality;
    char  diagnosis[64];
};
```

State machine reads quality and routes. Never inspects module internals.

### Node Safety Rules

| Rule | Detail |
|------|--------|
| DOUT pullup | `INPUT_PULLUP` — HX711 DOUT is open-drain |
| HX711 VCC | 5V (not 3.3V) — green PCB clones need 5V AVDD |
| Logic-level check | Verify ESP32 GPIO vs HX711 5V DOUT BEFORE powering (E-000 gate) |
| No external HX711 library | Raw bit-bang only. Port from stm32-hx711-modular/. |
| snprintf not String+= | Heap fragmentation on long-running MCU |
| No delay() in setup | Corrupts HX711 reads; use millis() pacing |

---

## HUB CONTEXT — UNO Q Python (hub/ directory)

Python on QRB2210 Linux, running inside App Lab Docker container.
`/app` inside container = hub/ directory on host.

### Hub Receive Pattern

```python
# Hub receives grams from node via WiFi (MQTT callback or HTTP endpoint)
def on_weight_received(payload):
    import json, datetime
    data = json.loads(payload)
    grams  = data["grams"]
    quality = data["quality"]
    sigma  = data["sigma"]
    ts     = datetime.datetime.now().isoformat()  # hub stamps timestamp — node has no RTC
    store_reading(ts, grams, quality)
    compute_gas_pct(grams)
```

Hub never receives raw ADC counts. Hub never calls Bridge.call for sensor data.
The ESP32-C3 handles all sensing.

### Hub Gas Calculation

```python
# steel derived once per cylinder at install anchor event
# config.json: { "cylinder": { "tare_kg": 15.3, ... } }

CAPACITY_KG = 14.2  # BIS IS 3196 — fixed constant, NOT a runtime config value

def compute_gas(gross_kg, steel_kg):
    gas_kg  = gross_kg - steel_kg
    gas_pct = (gas_kg / CAPACITY_KG) * 100.0
    return gas_kg, gas_pct
```

### Hub Steel Derivation (Anchor Event)

```python
def on_install_event(gross_kg):
    # Install: gross = steel + gas; gas = CAPACITY_KG (full cylinder, BIS law)
    steel_kg = gross_kg - CAPACITY_KG
    save_to_config("cylinder.tare_kg", steel_kg)
    return steel_kg
```

### Hub SQLite Patterns

```python
import sqlite3

conn = sqlite3.connect("data/gas_monitor.db")

# Heartbeat write (every 15 min)
conn.execute("""
    INSERT INTO readings (ts, gross_kg, gas_kg, gas_pct)
    VALUES (?, ?, ?, ?)
""", (ts, gross_kg, gas_kg, gas_pct))
conn.commit()

# Burn rate query
rows = conn.execute("""
    SELECT ts, gas_kg FROM readings
    WHERE ts >= datetime('now', '-7 days')
    ORDER BY ts ASC
""").fetchall()
```

### Hub App Lab Patterns

```python
# App Lab entry point
from arduino_lab import App, Bridge

def on_weight_event(data):
    print(str(data), flush=True)

# Hub may still use Bridge.provide for other UNO Q MCU data (not HX711 — that's ESP32 now)
# Bridge.provide("some_other_event", handler)

App.run()
```

### Hub Socket.IO Push

```python
ui.send_message("weight_update", {
    "grams": grams,
    "gas_kg": gas_kg,
    "gas_pct": gas_pct,
    "quality": quality,
    "ts": ts,
})
```

### Hub Wheels/TypeLibs (BLE — when needed)

```bash
# Copy from home-hub when WebUI phase (Group 7) begins
cp -r ~/ArduinoApps/home-hub/wheels/    hub/wheels/
cp -r ~/ArduinoApps/home-hub/typelibs/  hub/typelibs/
cp ~/ArduinoApps/home-hub/assets/socket.io.min.js  hub/assets/
```

Do NOT copy or commit now. Do NOT duplicate into this repo prematurely.

### Hub BLE Transport (parked — read before using)

BLE transport is parked for v1.x. If you add it:
- BLE scan must use `le` transport ONLY. `auto` kills the WCBN3536A adapter (hardware bug).
- D-Bus via socat at /app/dbus.sock. `sockets:` in app.yaml does NOT work.
- BLE UUIDs (if shared with home-hub): Service a01c0000, CMD a01c0001, EVT a01c0002.

---

## Critical Rules (Both Contexts)

| Rule | Detail |
|------|--------|
| No external HX711 library | Raw bit-bang only. Port from stm32-hx711-modular/. |
| No hardcoded cal_factor | Derive at boot, store config.json. Old 106.7 is VOID on ESP32. |
| No hardcoded threshold_g | Derive from noise characterisation. Fallback = 8.0g. |
| No hardcoded steel/tare | Derive from anchor event. Never assume brand. |
| All three corrupt filters | LONG_MIN, -1, 0x7FFFFF — all required on every read path. |
| millis() pacing at TOP | Never guard pacing inside a state case. |
| One sample per loop() | No blocking while loops in state cases (node only). |
| snprintf not String+= | Heap fragmentation on long-running MCU (node only). |
| Read before edit | Always read full file before any Python edit. |
| JCTL = 1.8V only | 3.3V on JCTL = hardware damage (hub board). |
| ESP32-C3 is 3.3V | Check logic-level before powering HX711 at 5V. |

---

## Corruption Pattern Reference (node)

| Pattern | Meaning | Cause | Fix |
|---------|---------|-------|-----|
| raw = 0x7FFFFF | ADC positive saturation | Wait not ready, wrong pin, timer conflict | Check wait_ready; try different GPIO |
| raw = 0x800000 | ADC negative saturation | Wrong pin | Try different GPIO |
| raw = -1 | All bits HIGH = not ready | Read mid-conversion | Check wait_ready() |
| Constant value regardless of weight | Load cell not responding | A+/A- not connected | Check wiring |
| High sigma, rock-solid tare | Analog path noise (jumper wires) | mV signal amplified 128× | Solder/shorten connections |

---

## Hub Deploy Reference

```bash
# Deploy hub
cd ~/ArduinoApps/gas-cylinder-monitor/hub && bash deploy.sh

# Logs
arduino-app-cli app logs user:gas-cylinder-monitor --follow

# Docker fallback
sudo docker logs $(sudo docker ps | grep gas-cylinder-monitor | awk '{print $1}') 2>&1 | tail -50
```
