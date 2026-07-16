# gas-cylinder-monitor

LPG cylinder weight monitor for Indian households.

An **ESP32-C3 sensor node** reads a 20 kg load cell via HX711, computes gross weight in
grams, and sends `{grams, quality, sigma}` over WiFi to the **Arduino UNO Q hub**.
The hub stamps timestamps, derives cylinder steel via anchor events, computes gas %,
stores to SQLite, runs analytics + prediction, and serves a WebUI dashboard.

Development phase uses water in a container — not a gas cylinder. Weight is weight.

---

## The Node / Hub Split

This project has two distinct software contexts. Never blur them.

```
node/   ← ESP32-C3 firmware (Arduino IDE / PlatformIO)
        Owns: HX711 bit-bang, corrupt filters, cal_factor, grams output, WiFi send
        Does NOT: compute gas %, know steel, have a clock, use App Lab or Bridge

hub/    ← UNO Q Python (App Lab Docker / QRB2210 Linux)
        Owns: WiFi receive, timestamp, steel derivation, gas%, SQLite, analytics,
              prediction, WebUI
        Does NOT: touch a sensor pin, see raw ADC counts, or call Bridge.notify
```

**Payload across WiFi:** `{grams: float, quality: "GOOD"|"DEGRADED"|"FAILED", sigma: float}`
Hub stamps timestamp on receipt — ESP32-C3 has no RTC.

---

## Voltage Warning

```
⚠️  HX711 VCC = 5V required (green PCB clone — 3.3V gives degraded output)
⚠️  ESP32-C3 GPIO = 3.3V — check HX711 DOUT/SCK logic-level compatibility
    before applying power. Level-shift if needed. (E-000 safety gate)
⚠️  UNO Q JCTL header = 1.8V ONLY. 3.3V = immediate hardware damage.
⚠️  UNO Q STM32 MCU is IDLE in V1 — ESP32-C3 owns all sensing.
```

---

## Hardware

| Role | Board | Notes |
|------|-------|-------|
| Hub | Arduino UNO Q AQ3 (192.168.1.161) | App Lab / Python / SQLite / WebUI |
| Node | ESP32-C3 | Arduino IDE / PlatformIO. NOT App Lab. |
| Load cell | YZC-161A 20 kg | Red→E+, Black→E-, Green→A+, White→A- |
| ADC | HX711 (green PCB) | 24-bit, gain 128. VCC = 5V. |

---

## Folder Tree

```
gas-cylinder-monitor/
├── CLAUDE.md              ← Read FIRST every CLI session
├── SKILL.md               ← node (ESP32/HX711) vs hub (App Lab/Python) patterns
├── README.md              ← This file
│
├── node/                  ← ESP32-C3 firmware (empty — not yet written)
│   └── README.md
│
├── hub/                   ← UNO Q Python hub (empty — not yet written)
│   └── README.md
│
├── docs/
│   ├── PLAN.md            ← Chunk-groups 1–7, current position
│   ├── SCOPE.md           ← V1 locked scope, state machine, config values
│   ├── RESEARCH.md        ← First-principles findings (ESP32 era + STM32 archived)
│   ├── HANDOFF.md         ← Session handoffs
│   ├── PROJECT_CONTEXT.md ← One-screen current state
│   │
│   ├── reference/
│   │   ├── ARCHITECTURE.md          ← System design, node/hub, pipeline
│   │   ├── INTERFACE_CONTRACTS.md   ← Node↔hub seam + module result-struct contract
│   │   ├── HANDOFF_ESP32_PIVOT.md   ← Why we pivoted from STM32 to ESP32-C3
│   │   ├── HARDWARE.md              ← Load cell wiring, board pinouts
│   │   ├── SENSOR_CHARACTERISATION.md  ← (to be created at E-002)
│   │   └── specs/                   ← V1 subsystem specs (read per chunk-group)
│   │       ├── ARCHITECTURE_SPECIFICATION.md
│   │       ├── TRANSPORT_SPECIFICATION.md
│   │       ├── DATA_STORAGE_SPECIFICATION.md
│   │       ├── ANALYTICS_SPECIFICATION.md
│   │       ├── PREDICTION_SPECIFICATION.md
│   │       ├── LPG_DOMAIN_SPECIFICATION.md
│   │       ├── MEASUREMENT_AND_CALIBRATION.md
│   │       ├── EXPERIMENT_PROGRAM.md
│   │       └── _source/MDD_v2_full.md
│   │
│   └── datasheets/
│       ├── hx711_english.pdf
│       ├── esp32-c3_datasheet_en.pdf
│       └── ... (UNO Q docs)
│
└── reference-code/
    └── stm32-hx711-modular/   ← STM32 reference (port logic not code)
        └── PORTING_NOTE.md    ← What carries, what doesn't, safety gate
```

---

## Where to Start

1. `ssh arduino@192.168.1.161`
2. `cd ~/ArduinoApps/gas-cylinder-monitor`
3. Read `CLAUDE.md` — architecture, node/hub split, rules, never-do list
4. Read `docs/PLAN.md` — chunk-groups, current position
5. Read `docs/PROJECT_CONTEXT.md` — current state, open questions
6. Read `docs/HANDOFF.md` — what the last session left
7. **Design the next chunk in Claude.ai chat** — chat produces a CLI prompt
8. Execute that prompt in Claude Code CLI

**Do not write any product code before steps 1–7.**

---

## Working Rule

```
PLANNING / RESEARCH / BRAINSTORMING → Claude.ai chat only
CODE WRITING / IMPLEMENTATION       → Claude Code CLI only
```

See `~/ArduinoApps/WORKING_MODE.md` for the full contract.
