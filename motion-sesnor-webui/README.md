# 😀 motion-sesnor-webui

# 🟢 motion-sesnor-webui

**Version 1.0 — PIR Motion Detector with Live Web Dashboard**  
Built on Arduino UNO Q · SR602 PIR sensor · Arduino App Lab

---

## What this does

Detects human presence using a miniature SR602 PIR sensor wired to the Arduino UNO Q's microcontroller. When motion is detected, a live web dashboard updates in real time — the status circle turns orange with a timestamp log of every event. No page refresh needed.

---

## How it works — the full chain

```
SR602 PIR sensor
      ↓  digital HIGH/LOW on D2
STM32U585 MCU  (Arduino sketch — Zephyr OS)
      ↓  Bridge RPC call → "motion_event"
QRB2210 MPU  (Python app — Debian Linux)
      ↓  Socket.IO → WebUI Brick
Browser dashboard  (http://192.168.1.154:7000)
```

The UNO Q runs two processors simultaneously. The MCU handles real-time sensor reading with edge detection. The MPU runs the web server and pushes events to the browser over WebSocket. They communicate via the Arduino Bridge RPC layer.

---

## Hardware

| Component | Details |
|---|---|
| Board | Arduino UNO Q (QRB2210 + STM32U585) |
| Sensor | SR602 / HW-438 miniature PIR module |
| Connection | 3 jumper wires |

### Wiring

| SR602 pin | UNO Q header | Pin | Wire color |
|---|---|---|---|
| + (power) | JANALOG | Pin 4 — +3V3 | Red |
| − (ground) | JANALOG | Pin 6 — GND | Black |
| O (signal) | JDIGITAL | Pin 3 — D2 | Any |

> **Voltage:** SR602 powered at 3.3V. Output signal is 3.3V — direct connection to MCU pin is safe. No level shifting required.

---

## Software structure

```
motion-sesnor-webui/
├── assets/
│   ├── index.html          ← Web dashboard (served by WebUI Brick)
│   └── libs/
│       └── socket.io.min.js  ← Socket.IO client (local copy)
├── python/
│   └── main.py             ← Bridge listener + Socket.IO emitter
├── sketch/
│   ├── sketch.ino          ← PIR reader with edge detection
│   └── sketch.yaml         ← Library dependencies
└── app.yaml
```

---

## Key implementation details

### Edge detection (sketch.ino)
The sketch does not fire on every loop tick. It only calls `Bridge.call()` on state *change* — LOW→HIGH when motion starts, HIGH→LOW when it ends. This prevents flooding the Bridge channel.

```cpp
if (currentState != lastPirState) {
    lastPirState = currentState;
    Bridge.call("motion_event", currentState);
}
```

### PIR warmup (sketch.ino)
The SR602 needs 60 seconds after power-on to stabilise its thermal reference. The sketch waits silently during this period before reading the pin.

```cpp
delay(60000);  // PIR warm-up — ignore first 60s of random signals
```

### Bridge direction (main.py)
Unlike the typical Blink example where Python calls the MCU, here the MCU calls Python. Python registers itself as the receiver:

```python
Bridge.provide("motion_event", on_motion_event)
```

### New client state sync (main.py)
When a new browser tab connects, it immediately receives the current motion state — so late-joining clients are never shown stale data.

---

## Running

1. Open **Arduino App Lab**
2. Open the `motion-sesnor-webui` app
3. Click **Run** — sketch compiles and Python starts (~60 seconds)
4. Open browser: `http://192.168.1.154:7000`
5. Wait 60 seconds for PIR warmup
6. Wave hand in front of SR602 dome

---

## Dependencies

### Sketch libraries (sketch.yaml)
- `Arduino_RouterBridge (0.3.0)`
- `Arduino_RPClite (0.2.1)`
- `ArxContainer (0.7.0)`
- `ArxTypeTraits (0.3.2)`
- `DebugLog (0.8.4)`
- `MsgPack (0.4.2)`

### Python
- `arduino.app_utils` — App + Bridge (provided by App Lab)
- `arduino.app_bricks.web_ui` — WebUI Brick (Socket.IO + FastAPI)

---

## Version roadmap

| Version | Status | Features |
|---|---|---|
| v1.0 | ✅ Complete | PIR detection · Live web dashboard · Event log |
| v2.0 | 🔲 Planned | Alert messages — email / Telegram / webhook |

---

## Learnings from building this

- The UNO Q is a dual-processor board — MCU handles real-time, MPU handles networking. Never conflate them.
- PIR sensors detect *change* in infrared — a still person goes undetected after a while.
- The Bridge RPC layer is symmetric — either side can `provide()` or `call()`.
- `socket.io.min.js` must be bundled locally in `assets/libs/` — the WebUI Brick does not serve it automatically from a URL path.
- JANALOG holds the power pins (+3V3, GND). JDIGITAL holds the digital I/O pins (D0–D21). They are on opposite sides of the board.

---

*Built with Arduino App Lab 0.6.0 · April 2026*


