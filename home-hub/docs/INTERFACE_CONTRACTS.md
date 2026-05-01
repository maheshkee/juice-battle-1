# Interface Contracts — Arduino UNO Q Products
# All products run on the same AQ2 board (QRB2210 MPU + STM32U585 MCU)

# Last updated: April 2026
# Active integrated app: home-hub (~/ArduinoApps/home-hub/)
# Planned future products to integrate: motion-sensor-webui, and more

---

## 1. Architecture Overview

All products on AQ2 share the same physical hardware layers.
Integration means wiring them together in one App Lab app with clean module boundaries.

```
┌─────────────────────────────────────────────────────────────────┐
│  Flutter App (Android)                                          │
│  - BLE CMD writes → triggers actions                           │
│  - BLE EVT notifications ← receives events from board         │
└────────────────────┬────────────────────────────────────────────┘
                     │ BLE (GATT over WCBN3536A)
┌────────────────────▼────────────────────────────────────────────┐
│  MPU — Debian Linux (QRB2210)   ~/ArduinoApps/home-hub/        │
│  Runs inside Docker (App Lab)                                   │
│                                                                 │
│  main.py          ← orchestrator, owns NO logic itself         │
│  ├── ble_gatt_serve.py  ← GATT server, routes CMD to modules  │
│  ├── queue_engine.py    ← YouTube queue state machine          │
│  ├── local_engine.py    ← local video file management          │
│  ├── bt_manager.py      ← Bluetooth audio (A2DP, D-Bus)       │
│  └── gas_monitor.py     ← gas sensor data, SQLite, prediction  │
│                                                                 │
│  WebUI Brick (port 7000) ← serves splash.html SPA             │
│  SQLite DB: data/gas_monitor.db                                │
└────────────────────┬────────────────────────────────────────────┘
                     │ Bridge RPC (LPUART1, 9600 baud, MSGPACK)
┌────────────────────▼────────────────────────────────────────────┐
│  MCU — Zephyr RTOS (STM32U585)   sketch/sketch.ino             │
│  - HX711 load cell reading (bit-bang GPIO)                     │
│  - Battery ADC                                                  │
│  - RTC periodic wake (6hr cycles)                              │
│  - LED indicators (RGB LED 3 = MCU-owned)                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. BLE Interface (Flutter ↔ MPU)

### Service & Characteristic UUIDs — DO NOT CHANGE

```
Service:       a01c0000-0000-0000-0000-000000000000
CMD char:      a01c0001-0000-0000-0000-000000000000  (WRITE, phone→board)
EVT char:      a01c0002-0000-0000-0000-000000000000  (NOTIFY, board→phone)
```

### CMD Format (Flutter → board, via CMD characteristic WRITE)

All commands are plain UTF-8 strings written to the CMD characteristic.

| Command string       | Handled by        | Action                                  |
|----------------------|-------------------|-----------------------------------------|
| `STOP`               | queue_engine      | Stop current YouTube playback           |
| `LOCAL:<filename>`   | local_engine      | Play local video file from assets/      |
| `<youtube_video_id>` | queue_engine      | Queue/play YouTube video by ID          |
| `BT_LIST`            | bt_manager        | List paired BT audio devices            |
| `BT_SCAN`            | bt_manager        | Scan for nearby BT devices              |
| `BT_CONNECT:<mac>`   | bt_manager        | Connect BT audio to device by MAC       |
| `GAS_STATUS`         | gas_monitor       | Request current gas reading (push EVT)  |
| `GAS_HISTORY:<n>`    | gas_monitor       | Request last n readings (push EVT)      |

> Routing is done in ble_gatt_serve.py. Each module exposes a `handle_cmd(cmd_str)` method.
> New products: add a new elif block in ble_gatt_serve.py — do NOT modify existing routing.

### EVT Format (board → Flutter, via EVT characteristic NOTIFY)

All events are JSON strings pushed via `push_evt(data)`.

```python
# push_evt() pattern — always use this, never push directly
def push_evt(data: dict):
    ble.push_evt(data)               # BLE NOTIFY to Flutter
    ui.send_message(data.get("event", "evt"), data)  # also Socket.IO to browser
```

#### EVT payloads by event type:

**YouTube / video events:**
```json
{ "event": "play_started",  "video_id": "abc123",    "title": "Video Title" }
{ "event": "play_stopped" }
{ "event": "queue_updated", "queue": ["id1", "id2"] }
{ "event": "local_playing", "filename": "promo.mp4" }
```

**Bluetooth audio events:**
```json
{ "event": "bt_list",    "devices": [{"mac": "AA:BB:CC", "name": "Speaker", "connected": true}] }
{ "event": "bt_scan",    "found":   [{"mac": "DD:EE:FF", "name": "JBL Flip"}] }
{ "event": "bt_status",  "mac": "AA:BB:CC", "connected": true }
```

**Gas monitor events:**
```json
{
  "event":       "gas_status",
  "weight_kg":   18.42,
  "gas_left_kg": 2.42,
  "gas_pct":     55,
  "days_left":   8,
  "battery_pct": 83,
  "sensor_ok":   true,
  "timestamp":   "2026-04-27T08:00:00"
}
{ "event": "gas_history", "readings": [ { ...same fields... }, ... ] }
{ "event": "gas_refill",  "detected_at": "2026-04-27T14:00:00", "new_weight_kg": 29.8 }
```

---

## 3. Bridge RPC Interface (MPU Python ↔ MCU C++)

### Communication channel
- Physical: LPUART1 on STM32U585 ↔ UART on QRB2210
- Baud rate: 9600
- Encoding: MSGPACK via Arduino RouterBridge library
- Use `Bridge.call()` when a return value is needed (blocks, 5s timeout)
- Use `Bridge.notify()` for fire-and-forget (no return value, faster)

### Functions provided by MCU (callable from Python)

```
Function name          Args                Returns         Notes
─────────────────────────────────────────────────────────────────────────
read_weight_packet     none                dict (see below) Stable average of 20 samples
read_battery_pct       none                int (0–100)     ADC-based estimation
set_led_red            state: bool         none            RGB LED3 red channel
set_led_green          state: bool         none            RGB LED3 green channel
set_led_blue           state: bool         none            RGB LED3 blue channel (future)
```

**`read_weight_packet` return structure:**
```python
{
    "weight_kg":  18.42,   # float, already tare-compensated if tare set
    "raw_kg":     34.52,   # float, raw HX711 reading before compensation
    "stable":     True,    # bool, False if reading variance too high
    "sensor_ok":  True,    # bool, False if HX711 not responding
    "timestamp":  "2026-04-27T08:00:00"  # ISO string from RTC
}
```

### Adding new MCU functions (rules)
1. Declare in sketch.ino using `Bridge.provide("function_name", handler_fn)`
2. Document here before implementing — contract first, code second
3. All thresholds in `#define` at top of sketch.ino, not magic numbers inline
4. Every UART read/write in the handler must have timeout + retry logic

---

## 4. WebUI / Socket.IO Interface (MPU Python ↔ Browser)

Port 7000 served by WebUI Brick. SPA entry point: `assets/splash.html`.

### Python → Browser (send_message)

```python
ui.send_message("event_name", { ...payload... })
```

| Event name            | Payload keys                              | Consumer (HTML view)   |
|-----------------------|-------------------------------------------|------------------------|
| `play_video_display`  | `video_id`                                | splash.html (YT div)   |
| `play_local_display`  | `filename`                                | splash.html (video div)|
| `player_control`      | `action: "stop"`                          | splash.html            |
| `data_update`         | `temp`, `humidity`, `time`               | (future: climate view) |
| `gas_update`          | same as gas_status EVT payload            | gas_dashboard.html     |
| `gas_history`         | `readings: [...]`                         | gas_dashboard.html     |

### Browser → Python (incoming WebSocket messages)
Currently all display control flows from BLE CMD → Python → Socket.IO to browser.
Browser does not push commands back to Python (no reverse Socket.IO handlers implemented yet).

---

## 5. Internal Python Module Contracts

Each module is independently testable. No module imports another module directly.
All cross-module coordination goes through `main.py`.

```
Module              Owns                                    Exposes
────────────────────────────────────────────────────────────────────────────────
queue_engine.py     YouTube queue state machine             handle_cmd(cmd: str)
                                                            on_start_cb / on_stop_cb hooks

local_engine.py     Local video file list + playback        handle_cmd(cmd: str)
                                                            list_videos() → list[str]

bt_manager.py       BT audio D-Bus (A2DP pairing/connect)  handle_cmd(cmd: str)
                    Never uses bluetoothctl (disrupts A2DP) get_connected_device() → str|None

ble_gatt_serve.py   GATT server lifecycle                   start(), stop()
                    CMD routing to above modules            push_evt(data: dict)
                    EVT notifications to Flutter

gas_monitor.py      HX711 readings via Bridge               start_service()
                    SQLite storage (gas_monitor.db)         get_current_status() → dict
                    Prediction engine (7-day rolling avg)   get_history(n: int) → list[dict]
                    Tare learning across refill cycles      handle_cmd(cmd: str)
```

**Rule:** If you find yourself importing `queue_engine` from `gas_monitor` or vice versa — stop. Add a hook/callback in `main.py` instead.

---

## 6. SQLite Schema (gas_monitor.db)

```sql
-- All weights in kg. Never grams. Never hardcoded tare.

CREATE TABLE readings (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp    TEXT NOT NULL,        -- ISO 8601
    weight_kg    REAL NOT NULL,        -- raw from MCU
    stable       INTEGER NOT NULL,     -- 1/0
    battery_pct  INTEGER,
    sensor_ok    INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE refill_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    detected_at     TEXT NOT NULL,
    weight_before   REAL,
    weight_after    REAL,
    tare_estimate   REAL               -- learned from previous cycle low point
);

CREATE TABLE predictions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    calculated_at   TEXT NOT NULL,
    gas_left_kg     REAL,
    days_left       REAL,
    avg_daily_use   REAL,
    confidence      REAL               -- 0.0–1.0
);

CREATE TABLE cylinder_templates (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    name         TEXT NOT NULL,        -- e.g. "Indane 14.2kg"
    tare_kg      REAL NOT NULL,        -- empty cylinder weight
    capacity_kg  REAL NOT NULL         -- usable gas weight
);
```

**Key rules:**
- Tare ONLY from `cylinder_templates` table. Never hardcode tare.
- Refill detection threshold: weight delta > 8 kg. Defined in `config.py`.
- Prediction uses 7-day rolling average. Defined in `config.py`.

---

## 7. Config (config.py) — All Thresholds Here

```python
# Gas monitor
REFILL_THRESHOLD_KG   = 8.0      # weight jump that signals cylinder replacement
PREDICTION_WINDOW_DAYS = 7       # rolling average window for daily use calculation
SENSOR_SAMPLE_COUNT    = 20      # HX711 samples averaged per reading
MEASUREMENT_INTERVAL_HR = 6      # MCU wake cycle

# Weight units — always kg internally, convert only at display layer
WEIGHT_UNIT = "kg"

# BLE
BLE_SERVICE_UUID = "a01c0000-0000-0000-0000-000000000000"
BLE_CMD_UUID     = "a01c0001-0000-0000-0000-000000000000"
BLE_EVT_UUID     = "a01c0002-0000-0000-0000-000000000000"

# Ports
WEBUI_PORT = 7000
```

---

## 8. Future Products — Placeholder Contracts

When motion-sensor-webui is integrated into home-hub, add its module here.
Template to follow:

```
Module              Owns                                    Exposes
────────────────────────────────────────────────────────────────────────────────
motion_monitor.py   SR602 PIR state via Bridge              start_service()
                    Motion event history                    get_last_event() → dict
                    Web dashboard data feed                 handle_cmd(cmd: str)
```

Planned BLE EVT additions:
```json
{ "event": "motion_detected", "timestamp": "...", "zone": "main" }
{ "event": "motion_cleared",  "timestamp": "..." }
```

Planned Bridge RPC additions:
```
read_pir_state     none    bool    Current PIR state (HIGH/LOW)
```

---

## 9. Critical Hardware Rules (applies to all products)

```
⚠️  MCU headers = 3.3V logic. EXCEPT A0, A1 — NOT 5V tolerant.
⚠️  JCTL (MPU debug header) = 1.8V ONLY. 3.3V = hardware damage.
⚠️  BLE scan: ALWAYS use le transport. Never auto. Auto kills adapter on QRB2210.
⚠️  HDMI audio = broken on QRB2210. BT speaker only.
⚠️  sockets: in app.yaml does NOT work. D-Bus via socat at /app/dbus.sock only.
⚠️  Do NOT open /dev/ttyHS1 directly. arduino-router owns it.
⚠️  Chromium: one instance only. Never kill/relaunch. Use Socket.IO show/hide.
```
