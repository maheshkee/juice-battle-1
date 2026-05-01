# CLAUDE.md — home-hub + digital-scale | AQ3
# Board: Arduino UNO Q AQ3 (4GB) | IP: 192.168.1.161
# Last updated: 2026-04-30 | Read this fully before doing ANYTHING

---

## Board Architecture

```
SSH → MPU (QRB2210, Debian Linux) — Python, BLE, WebUI, App Lab Docker
         ↓ Bridge RPC (Arduino_RouterBridge)
      MCU (STM32U585, Zephyr @ 160MHz) — sketch.ino, GPIO, HX711
```

---

## HX711 — THE CONFIRMED WORKING CONFIGURATION

These facts were proven after a full day of R&D. Never deviate.

| Parameter     | Value       | Why                                              |
|---------------|-------------|--------------------------------------------------|
| DT pin        | D7          | Conflict-free. D2/D3/D4/D5 have timer mux issues |
| SCK pin       | D6          | Conflict-free. All others produced corrupt reads  |
| Library       | NONE        | Raw bit-bang in sketch.ino. No external lib.     |
| Bridge pattern| notify()    | MCU pushes every 500ms. NOT provide_safe+polling  |
| Cal factor    | 420.0f      | Starting point. Tune with known weight.           |
| Power         | 5V          | Green PCB HX711 clones need 5V AVDD              |
| DOUT pullup   | INPUT_PULLUP| Required — HX711 DOUT is open-drain              |

### The Working Bit-Bang Recipe (copy verbatim, never change timing)

```cpp
static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 1 gain pulse = gain 128 (Channel A)
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}
```

### Bridge.notify() Pattern (NOT provide_safe + Python polling)

```cpp
// In loop() — MCU pushes every PUSH_INTERVAL_MS
void loop() {
    static uint32_t last_push = 0;
    if (millis() - last_push < PUSH_INTERVAL_MS) return;
    last_push = millis();
    long raw = hx711_read_average(SAMPLE_COUNT);
    if (raw == LONG_MIN) {
        Bridge.notify("weight_event", String("{\"sensor_ok\":false}"));
        return;
    }
    float grams = (float)(raw - g_tare_offset) / CALIBRATION_FACTOR;
    // ... build JSON ...
    Bridge.notify("weight_event", json);
}
```

```python
# In Python main.py — listen, don't poll
@Bridge.on('weight_event')
def on_weight(data):
    ui.send_message('weight_update', data)
```

---

## Reference App — digital-scale (WORKING, DO NOT BREAK)

```
~/ArduinoApps/digital-scale/
├── sketch/sketch.ino      ← THE reference. DT=7, SCK=6, Bridge.notify()
├── sketch/sketch.yaml     ← Arduino_RouterBridge only
├── python/main.py         ← Bridge.on('weight_event') listener
├── assets/index.html      ← WebUI: kg, g, STABLE, TARE button
└── assets/socket.io.min.js
```

When in doubt about HX711 implementation — copy from digital-scale sketch verbatim.

---

## App Status

| App | Status | Notes |
|-----|--------|-------|
| digital-scale | ✅ WORKING | Live weight, tare, stable detection |
| home-hub BLE | ✅ WORKING | Advertising as YT-Display |
| home-hub YouTube | ✅ WORKING | Flutter app control |
| home-hub weight widget | ⚠ NEEDS UPDATE | Must use D7/D6 + Bridge.notify() |
| home-hub gas monitor | ❌ DEFERRED | 6hr cycles not active |
| home-hub BT speaker | ❌ STUB | bt_manager.py all no-ops |

---

## home-hub File Map

```
~/ArduinoApps/home-hub/
├── CLAUDE.md                    ← this file
├── deploy.sh                    ← always use this
├── python/
│   ├── main.py                  ← weight_poll_loop here (NEEDS UPDATE to Bridge.on)
│   ├── config.py                ← REFILL_THRESHOLD_KG=8.0, GAS_DB_PATH
│   ├── bt_manager.py            ← STUB — do not delete
│   ├── ble_gatt_serve.py        ← DO NOT TOUCH
│   ├── queue_engine.py          ← DO NOT TOUCH
│   ├── local_engine.py          ← DO NOT TOUCH
│   └── services/gas_monitor.py  ← implemented, deferred
├── sketch/
│   ├── sketch.ino               ← NEEDS UPDATE: DT=7 SCK=6 + Bridge.notify()
│   ├── ScaleHX711.cpp/.h        ← CAN BE DELETED after migration
│   └── sketch.yaml
└── assets/
    └── splash.html              ← weight widget in #home div
```

---

## Critical Rules — Never Violate

1. HX711 DT = D7 ONLY. SCK = D6 ONLY. Any other pin = corrupt/no reads.
2. Bridge.notify() from loop() for weight. NOT Bridge.provide_safe() + Python polling.
3. No external HX711 library. Raw bit-bang only. digital-scale proves this.
4. BLE scan = le transport ONLY. Auto transport kills BT adapter on QRB2210.
5. Never add sockets: to app.yaml.
6. bt_manager.py EXISTS as stub — do not delete, do not recreate from scratch.
7. Never use sed/regex to edit Python files — use python3 read/replace/write.
8. JCTL = 1.8V ONLY. 3.3V on JCTL = hardware damage.
9. No hardcoded paths, usernames, hostnames in any script.
10. delayMicroseconds(1) after EVERY GPIO edge in HX711 bit-bang. Both HIGH and LOW.

---

## BLE UUIDs (never change)

- Service:  a01c0000-0000-0000-0000-000000000000
- CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
- EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)

---

## Deploy Commands

```bash
# Normal deploy
cd ~/ArduinoApps/home-hub && bash deploy.sh
cd ~/ArduinoApps/digital-scale && bash deploy.sh

# Force full recompile
rm -rf .cache && rm -rf ~/.arduino15/internal && bash deploy.sh

# Watch logs
arduino-app-cli app logs user:home-hub --follow
arduino-app-cli app logs user:digital-scale --follow

# Docker fallback (if app-cli logs empty)
sudo docker logs $(sudo docker ps | grep home-hub | awk '{print $1}') 2>&1 | tail -50
```

---

## Next Session Priorities

1. Calibrate digital-scale with known weight → get real CALIBRATION_FACTOR
2. Migrate home-hub sketch to D7/D6 + Bridge.notify() from digital-scale
3. Update home-hub Python to Bridge.on() listener pattern
4. BT speaker real implementation (D-Bus A2DP, never bluetoothctl)
5. Gas monitor 6hr cycles re-enable
6. Gas dashboard UI in splash.html

---

## Things to Revert Before Production

| File | Current | Should be |
|------|---------|-----------|
| home-hub python/main.py | time.sleep(30) gas cycle | time.sleep(21600) |
| home-hub sketch/sketch.ino | DT=4, SCK=3 (old) | DT=7, SCK=6 |

---

## Git State

Repo: git@github.com:gratiantechnologies/project13.git  
Branch: main  
Uncommitted: home-hub sketch changes, digital-scale new app  

```bash
git add -A
git commit -m "feat: digital-scale working, DT=D7 SCK=D6, Bridge.notify architecture"
git push
```
