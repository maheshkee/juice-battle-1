# Brainstorm Learnings — MCU Transport & IoT Product Architecture
**Source**: Brainstorming session transcript  
**Context**: Gas Cylinder Monitor — ESP32-C3 sensor node → Arduino UNO Q hub  
**Principle applied throughout**: WHY before HOW. Nothing floats in isolation.

---

## Table of Contents

1. [The Fundamental Problem — What Is Communication?](#1-the-fundamental-problem)
2. [What Is Data, Really?](#2-what-is-data-really)
3. [Physical Layer — How Bits Travel as Voltage](#3-physical-layer)
4. [Communication Protocols — The Big Three](#4-communication-protocols)
5. [Voltage Discipline — The Danger Hiding in Plain Sight](#5-voltage-discipline)
6. [From Communication to Product Architecture](#6-from-communication-to-product-architecture)
7. [Responsibility Assignment — Who Owns What](#7-responsibility-assignment)
8. [The Golden Rule — Raw Data vs State vs Information](#8-the-golden-rule)
9. [Device State Model](#9-device-state-model)
10. [Event Model](#10-event-model)
11. [BLE GATT Service Design — From State to Schema](#11-ble-gatt-service-design)
12. [Ownership Model — ESP32 vs UNO Q](#12-ownership-model)
13. [Communication Patterns — Three Are Better Than One](#13-communication-patterns)
14. [Resilience by Design — Reconnection Strategy](#14-resilience-by-design)
15. [Scalability — Why Good Architecture Survives V2](#15-scalability)
16. [What to Design Before Writing Any Code](#16-what-to-design-before-writing-any-code)
17. [Locked Decisions in This Project](#17-locked-decisions-in-this-project)

---

## 1. The Fundamental Problem

When two MCUs need to exchange data, the first question is not *"which protocol do I use?"*

The first question is:

> **How will bits physically travel from one MCU to the other?**

This matters because inside any MCU, everything is 0s and 1s. The challenge is:  
*How can the receiving MCU reconstruct those same bits correctly?*

That is what communication protocols solve. They are not magic — they are an agreed set of rules for encoding bits as electrical signals and decoding them back.

---

## 2. What Is Data, Really?

Suppose an MCU wants to send the number `25`.

Internally it becomes: `00011001`

On the wire, it travels as changing voltages:

- For a 3.3V system: `3.3V = Logic 1`, `0V = Logic 0`
- The receiver samples those voltage levels and reconstructs the byte

**Key insight**: Data is not moving as numbers or letters. It is moving as changing voltages on a wire. The protocol is simply the agreed-upon rules for how fast those voltages change and what each transition means.

---

## 3. Physical Layer

### Why Common Ground Is Non-Negotiable

Every communication protocol requires a shared GND between devices.

Without a common ground, voltage measurements have no reference. `3.3V` is meaningless unless both devices agree on what `0V` is. This is not optional — it is physics.

### How UART Bits Look on a Wire

Sending character `A` (ASCII 65 = `01000001`):

```
3.3V ─────┐     ┌─┐           ┌──
          │     │ │           │
0V        └─────┘ └───────────┘
          S  7  6  5  4  3  2  1  0  Stop
```

The wire voltage literally toggles between 0V and 3.3V. The receiver samples at each bit period and reconstructs the byte. Nothing more is happening electrically.

---

## 4. Communication Protocols — The Big Three

### UART — Universal Asynchronous Receiver Transmitter

**Why it exists**: Simplest point-to-point protocol. No shared clock needed.

**How it works**: Sender and receiver agree on a baud rate (e.g., 9600 bps). At that rate, both sides count time independently ("asynchronous") and sample bits accordingly.

**Why baud rate matters**: Without agreement on speed, bits arrive too fast or too slow. The receiver samples at the wrong moment and gets garbage. This is why both sides must be configured identically.

```
Arduino TX ──────────────> ESP32 RX
Arduino RX <────────────── ESP32 TX
GND ──────────────────────── GND   ← MANDATORY
```

**When to use**: Point-to-point, simplest wiring, easiest debugging, beginner-friendly. Perfect for initial learning.

---

### I2C — Inter-Integrated Circuit

**Why it exists**: Multiple devices need to share a two-wire bus. UART cannot address multiple receivers.

**How it works**: Two wires — `SDA` (data) and `SCL` (clock). The clock is shared, so devices don't need independent timing. Every device has a unique address (e.g., `0x27`, `0x68`). The master sends an address first; only the device with that address responds.

**Why a shared clock helps**: UART is "trust the timer." I2C is "sample when I say sample." This makes it more reliable across mixed-speed devices.

```
ESP32 (Master)
      │
      ├── SDA ──── Sensor (0x68)
      │            Display (0x27)
      └── SCL ──── Arduino  (0x48)
```

**When to use**: Multiple sensors on one bus, short distances, medium speed.

---

### SPI — Serial Peripheral Interface

**Why it exists**: Speed. I2C is limited by open-drain bus physics. SPI uses dedicated push-pull lines for each direction, enabling much higher data rates.

**How it works**: Four wires — `MOSI` (master→slave data), `MISO` (slave→master data), `SCLK` (clock), `CS` (chip select). `CS` goes LOW to select a specific device.

**When to use**: SD cards, displays, high-speed sensors. When speed matters more than wire count.

---

### Comparison Table

| Feature | UART | I2C | SPI |
|---------|------|-----|-----|
| Wires | 2 + GND | 2 + GND | 4 + GND |
| Speed | Medium | Medium | High |
| Multiple devices | Difficult | Easy (addressing) | Possible (one CS per device) |
| Shared clock | No (asynchronous) | Yes | Yes |
| Complexity | Low | Medium | Medium |
| Best for | Point-to-point | Multi-sensor buses | High-speed transfers |

---

## 5. Voltage Discipline

**This is a hardware damage risk, not just a preference.**

| Platform | Logic Level |
|----------|-------------|
| Classic Arduino Uno | 5V |
| ESP32 | 3.3V |
| UNO Q MCU headers | 3.3V (5V tolerant except A0, A1) |
| UNO Q JCTL/MPU headers | **1.8V ONLY — 3.3V = hardware damage** |

### Why This Matters

If a classic Arduino (5V TX) sends a signal to an ESP32 RX pin directly:
- The ESP32 RX sees 5V
- ESP32 I/O is rated for 3.3V
- Result: potential damage to the ESP32

**Solution**: A logic level shifter between 5V and 3.3V systems. Never connect them directly.

**UNO Q JCTL warning**: JCTL pins are 1.8V. Connecting 3.3V here destroys the MPU. Always verify the header type before wiring.

---

## 6. From Communication to Product Architecture

### The Engineering Principle That Changes Everything

> **Users don't buy BLE. Users don't buy ESP32. Users buy a working LPG monitoring system.**

Everything else — protocols, voltage levels, calibration — is supporting infrastructure for that goal.

Once this is understood, architecture decisions become clearer. You don't choose UART vs I2C because of a feature list. You choose based on what the product actually needs.

### V1 Product Pipeline

```
Cylinder
    ↓
Load Cell (force → tiny voltage)
    ↓
HX711 (tiny voltage → 24-bit digital counts)
    ↓
ESP32-C3 (counts → grams → state → BLE)
    ↓ BLE
UNO Q Hub (system brain — aggregation, storage, intelligence, UI)
```

Every arrow represents a transformation with a clear contract. Nothing bleeds across boundaries.

---

## 7. Responsibility Assignment — Who Owns What

### Load Cell

**Single responsibility**: Convert force (cylinder weight) into a tiny differential voltage.

It does NOT know: weight, gas %, BLE, LPG, anything.

### HX711

**Single responsibility**: Amplify and digitise that tiny voltage into 24-bit counts.

It does NOT know: weight units, calibration, gas %, BLE.

### ESP32-C3 — The Sensor Brain

**Owns**: Sensor reading, filtering, tare, calibration, weight calculation, gas event detection, BLE service, node state.

**Does NOT own**: Prediction, historical storage, business logic, user interface.

The key insight: **calibration belongs as close to measurement as possible.** The hub should never see raw HX711 counts. It should receive physical units (grams). The ESP32 does that conversion.

### UNO Q — The System Brain

**Owns**: Connection management, data aggregation, local intelligence, cloud sync (future), user interface, configuration, multi-node coordination.

**Does NOT own**: Raw sensor data, calibration math.

A common mistake: making the hub do sensor intelligence. Don't. Let the sensor brain be a sensor brain. The hub gets trustworthy measurements and focuses on what to do with them.

---

## 8. The Golden Rule — Raw Data vs State vs Information

```
Raw Data          → Information         → State
14.201, 14.203    → Weight = 14.20 kg   → Gas = 82%, Status = Healthy
thousands of ADC  → Calibrated grams    → System truth snapshot
samples
```

**State is the distilled truth.** It is what you would answer if someone asked:

> "Tell me everything important about the cylinder right now."

### Why State Matters for Reconnection

If UNO Q disconnects and reconnects, instead of asking multiple questions:

```
Weight? Gas? Battery? Health? Status?
```

It asks one:

```
Current State?
```

And receives a coherent snapshot. This is the difference between a collection of readings and a real product.

### Module Result Contract

Every module in the system should return not just a value, but a quality assessment:

```
{
    value:     float       — the measurement
    quality:   GOOD | DEGRADED | FAILED
    diagnosis: string      — human-readable reason for degradation/failure
}
```

Never return just a boolean. A `FAILED` state with a diagnosis tells you *why* it failed. A bare `false` tells you nothing.

---

## 9. Device State Model

The state model answers: *"If the hub asks for everything right now, what should exist?"*

### Structure

```
Device State
│
├── Device Info
│   ├── Device ID          (e.g., cylinder_node_001)
│   ├── Firmware Version
│   ├── Hardware Version
│   └── Node Type
│
├── Sensor State
│   ├── Current Weight (filtered)
│   ├── Raw Weight
│   └── Last Measurement Time
│
├── Cylinder State
│   ├── Gas Percentage
│   ├── Cylinder Present
│   ├── Cylinder Empty
│   └── Cylinder Replaced (flag)
│
├── Health State
│   ├── Load Cell: OK | FAULT
│   ├── HX711: OK | FAULT
│   ├── Battery: OK | LOW | CRITICAL
│   └── System Health: OK | DEGRADED | FAILED
│
├── Communication State
│   ├── BLE Connected
│   ├── Last Heartbeat
│   ├── Connection Count
│   └── Last Connection Time
│
└── Event State
    ├── Last Event Type
    ├── Last Event Time
    └── Event Counter
```

### Why Health State Is Critical

Many hobby projects expose `Weight = 0` when a sensor fails.

`Weight = 0` looks like an empty cylinder. That is wrong and misleading.

The correct design: expose `Health = FAULT`, so the hub knows the measurement is invalid — not that the cylinder is empty. These are completely different situations with completely different responses.

### Configuration State — Future-Proofing

The hub should be able to write thresholds to the ESP32:

```
Low Gas Threshold    = 20%
Critical Threshold   = 5%
Heartbeat Interval   = 15 min
```

This means behavior can be changed without flashing new firmware. The architecture stays static; the parameters change.

---

## 10. Event Model

Events are NOT measurements. They are **state transitions** — something that happened, that matters.

| Event | Trigger | Why It Matters |
|-------|---------|----------------|
| `CYLINDER_INSTALLED` | Weight jumps up >8kg | Refill detected, new anchor |
| `CYLINDER_REMOVED` | Weight drops to near zero | Maintenance window |
| `LOW_GAS` | Gas < 20% | Alert threshold crossed |
| `CRITICAL_GAS` | Gas < 5% | Urgent — order now |
| `SENSOR_FAULT` | Invalid/corrupt readings | System degraded |
| `RECOVERY` | Fault cleared | System restored |

Events are sparse. Measurements are continuous. The hub only needs to act on events — it does not need to re-examine every weight sample to detect that gas is low.

**Why events are pushed immediately**: Latency matters for alerts. A low-gas event that sits in a heartbeat queue for 15 minutes is not useful. Events bypass the heartbeat rhythm and are pushed as soon as they are detected.

---

## 11. BLE GATT Service Design — From State to Schema

Once the state model is defined, BLE service design becomes mechanical. You are not inventing characteristics — you are exposing the state model over BLE.

### Wrong Approach (random characteristics)

```
Weight
Battery
Temperature
SomeFlag
...
```

No structure. No clear ownership. No way to get a coherent snapshot.

### Right Approach (state-driven)

```
LPG Service (one UUID)
│
├── State Characteristic    — full state snapshot, readable + notifiable
├── Event Characteristic    — sparse events, notifiable (subscribe only)
├── Health Characteristic   — health state only
└── Config Characteristic   — hub writes thresholds here
```

Each characteristic maps to a section of the state model. Every request, notification, heartbeat, and future cloud sync is based on this same structure.

### Seam Contract (locked for this project)

```json
{
    "grams":   29420.5,
    "quality": "GOOD",
    "sigma":   2.3
}
```

`grams` = calibrated weight from ESP32  
`quality` = GOOD | DEGRADED | FAILED (module result contract)  
`sigma` = noise/spread of the measurement  
`timestamp` = stamped by hub on receipt (ESP32 has no RTC)

This contract is the seam between the sensor world and the system world. Everything on the ESP32 side is Group 1. Everything on the hub side is Group 2 and beyond. The contract never changes regardless of what either side does internally.

---

## 12. Ownership Model — ESP32 vs UNO Q

```
ESP32 owns:           UNO Q owns:
─────────────────     ────────────────────────────
Measurement truth     System truth
Raw→grams conv        Grams→gas% conversion
Calibration           Domain logic
Sensor health         Aggregation (multiple nodes)
BLE advertising       Storage
Node state            Intelligence / prediction
                      User-facing interface
                      Cloud sync (future)
```

**V2 Expansion**: Add more ESP32 nodes (water, temperature, solar). Nothing changes architecturally on the UNO Q side — it just handles more nodes. That is the sign of a correct design.

```
ESP32 #1 (LPG)
ESP32 #2 (Water)    ──→  UNO Q Hub
ESP32 #3 (Temperature)
```

---

## 13. Communication Patterns — Three Are Better Than One

No single pattern is sufficient for a real IoT product. Use all three together.

### Event-Driven (ESP32 pushes immediately)

```
Trigger: Low gas detected, Cylinder replaced, Sensor fault
ESP32 → Hub (immediate, no waiting)
```

Why: Latency-sensitive. A 15-minute delay on a fault is unacceptable.

### Request-Response (Hub pulls on demand)

```
Trigger: Hub reconnects, User opens dashboard
Hub → "Current State?" → ESP32 responds
```

Why: Hub gets fresh state on demand without ESP32 needing to remember to push.

### Heartbeat (scheduled, periodic)

```
Every 15 minutes:
ESP32 → Hub: "I am alive. Current: {grams, quality, sigma}"
```

Why: Creates an authoritative timeline. Hub knows the ESP32 is alive even when no events occur. Enables burn-rate calculations (consumption per interval). Proves liveness.

**Every heartbeat is a data point**. Even "nothing changed" is information — it tells you consumption rate for that interval.

---

## 14. Resilience by Design — Reconnection Strategy

**BLE failure should never affect measurement.**

This is non-negotiable. The sensor must continue operating regardless of transport state.

```
ESP32 continuous loop:
  Read HX711
  Filter
  Apply calibration
  Compute grams, quality, sigma
  Update internal state
  Detect events
  ↓
  If BLE connected → notify hub
  If BLE disconnected → discard reading, continue loop
```

The ESP32 never halts, never waits for BLE, never retries connection. It just keeps measuring.

**Hub owns all reconnection logic**:

```
Hub reconnect loop:
  BLE drops → detect immediately
  Start scan for ESP32 service UUID
  Find → connect → subscribe
  Target: reconnect within 30 seconds
  No user action ever required
```

**Why this division**: The ESP32 is a sensor node. It should be as simple as possible. Adding reconnection state machines to a sensor makes it harder to reason about. Put complexity where it is easiest to update: the hub (Python on Linux).

---

## 15. Scalability — Why Good Architecture Survives V2

A good architecture does not need redesign to support more nodes. It needs only configuration.

The test: if you add a second ESP32 tomorrow, does the hub architecture change?

With correct ownership model: No. The hub just handles another UUID, another state, another set of events.

With incorrect ownership model (e.g., hub knows too much about sensor internals): Yes. And that is how technical debt accumulates.

**Rule**: Keep the seam contract clean. As long as every node delivers `{grams, quality, sigma}`, the hub can handle any number of them identically.

---

## 16. What to Design Before Writing Any Code

From this brainstorm, the lesson is clear: **four documents before any code**.

1. **Complete Device State Model**  
   What exists? Who owns it? What is its type? What are its valid values?

2. **Event Catalogue**  
   What state transitions matter? What triggers them? What payload do they carry?

3. **BLE Service and Characteristic Schema**  
   UUIDs, properties (READ / WRITE / NOTIFY), payload format, direction.

4. **Reconnection and Heartbeat Rules**  
   Who reconnects? How fast? What happens to data during disconnect? Who stamps the timestamp?

These four documents will save more engineering time than hundreds of lines of code written prematurely.

**The most important**: the Device State Model. Every other design decision flows from it.

---

## 17. Locked Decisions in This Project

| Decision | Value | Why |
|----------|-------|-----|
| Transport | BLE only — no WiFi | WiFi needs credentials on headless ESP32. BLE needs zero provisioning. |
| Topology | Hub-initiated | ESP32 advertises. Hub connects. Hub owns all reconnect logic. |
| Delivery | Best-effort | Readings lost during disconnect are acceptable for V1. |
| Local storage on ESP32 | None | No flash writes, no buffering. Simplicity. |
| Timestamp ownership | Hub stamps on receipt | ESP32 has no RTC. |
| Reconnect target | 30 seconds | Automatic, silent, no user action. |
| Seam contract | `{grams, quality, sigma}` | Clean boundary. Hub handles everything downstream. |
| Sampling rhythm | 15-min heartbeat + event-driven push | Balances battery, data richness, and latency. |
| cal_factor | Never hardcoded — derived on boot | Hardware varies. Always measure, never assume. |

---

*Generated from brainstorm session. Cross-referenced against project knowledge: TRANSPORT_DECISION_BLE_ONLY.md, ARCHITECTURE_SPECIFICATION.md, TRANSPORT_SPECIFICATION.md, LPG_DOMAIN_SPECIFICATION.md.*
