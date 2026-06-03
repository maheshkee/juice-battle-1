# gas-cylinder-monitor

A weight-based LPG gas level monitor for Indian households. A load cell permanently mounted under the cylinder continuously measures total weight. The MCU reads the HX711 ADC, detects weight changes, and pushes events to the Linux side via Bridge RPC. The Linux MPU stores snapshots to SQLite, predicts days until refill, and surfaces a live display and BLE alert to the phone.

**Development phase uses water in a container, not a gas cylinder.** Weight is weight. No code may hard-code "gas" semantics.

---

> **VOLTAGE WARNING**
>
> The Arduino UNO Q has two different voltage domains on its headers.
>
> - MCU Arduino headers (JDIGITAL, JANALOG): **3.3V logic** — except A0/A1 which are 3.3V max, NOT 5V tolerant.
> - **JCTL and JMISC (MPU-side pins): 1.8V ONLY.** Applying 3.3V to any JCTL or JMISC pin causes **immediate hardware damage**. No exceptions.
>
> The HX711 module (green PCB clone) requires **5V AVDD**. Connect to the 5V pin on JDIGITAL, NOT to 3.3V. The HX711 data and clock lines (D7, D6) are driven at 3.3V MCU logic — this is fine.

---

## Hardware List

| Component | Model | Notes |
|-----------|-------|-------|
| Board | Arduino UNO Q (AQ3) | MPU: QRB2210 Linux + MCU: STM32U585 Zephyr |
| Load cell | YZC-161A 20kg | ±0.05% accuracy, aluminum alloy, compression type |
| ADC | HX711 module (green PCB) | 24-bit, gain 128, requires 5V VCC |
| Cable | 4-wire load cell cable | Red→E+, Black→E-, Green→A+, White→A- |

### Critical Wiring

```
HX711 DT  → D7  (ONLY valid INPUT pin — D2/D3/D4/D5 have timer conflicts)
HX711 SCK → D6  (ONLY valid OUTPUT pin)
HX711 VCC → 5V  (NOT 3.3V — green PCB clones require 5V AVDD)
HX711 GND → GND

Load cell:
  Red   → E+
  Black → E-
  Green → A+
  White → A-
```

### Load Cell Mounting Rule

One end **FIXED** (clamped/screwed to rigid surface). Other end **FREE** (hangs over edge, nothing touching it). Weight placed on free end only. If both ends rest on a surface → corrupt cycling readings.

---

## Folder Tree

```
gas-cylinder-monitor/
├── CLAUDE.md               ← Read before every CLI session. Locked constants, rules, current state.
├── README.md               ← This file. Onboarding and orientation.
├── SKILL.md                ← HX711/Bridge/Python patterns, rules, anti-patterns.
├── .gitignore
│
├── docs/
│   ├── PLAN.md             ← Master plan: phases, chunks, acceptance criteria.
│   ├── PROJECT_CONTEXT.md  ← Problem statement, target user, version roadmap, India-specific facts.
│   ├── RESEARCH.md         ← First-principles derivations, design decisions, open questions.
│   ├── LEARNINGS.md        ← Permanent platform bug record. Read before touching HX711 code.
│   ├── HANDOFF.md          ← Session state — what was done, what's next.
│   │
│   ├── reference/
│   │   ├── SENSOR_CHARACTERISATION.md  ← Self-characterisation philosophy. Locked derived constants.
│   │   ├── HX711_CALIBRATION_ARCHITECTURE.md  ← TARE vs CAL_FACTOR model. Stability checks.
│   │   ├── HARDWARE.md                 ← Pin constraints, voltage domains, wiring reference.
│   │   ├── INTERFACE_CONTRACTS.md      ← Bridge RPC, BLE, Socket.IO, SQLite contracts.
│   │   ├── ARCHITECTURE.md             ← System data flow, MCU/Linux responsibilities, failure modes.
│   │   ├── SPEC.md                     ← Technical spec: hardware, measurement cycle, accuracy targets.
│   │   └── EXPERIMENT_HISTORY.md       ← One-table summary of experiments 001–007 and their findings.
│   │
│   ├── datasheets/
│   │   ├── ABX00162fullpinout.pdf
│   │   ├── ABX00162schematics.pdf
│   │   ├── SKUABX00162ABX00173datasheet.pdf
│   │   ├── hx711_english.pdf
│   │   ├── load_cell_hx711_mcu.docx
│   │   └── loadcell_hx711_mcu_reference.docx
│   │
│   └── platform/           ← Arduino UNO Q learning guides (4 parts)
│       ├── UNO_Q_Part1_Hardware_Architecture.md
│       ├── UNO_Q_Part2_AppLab_Bridge.md
│       ├── UNO_Q_Part3_Linux_BLE_Advanced.md
│       └── UNO_Q_Part4_Projects_Reference.md
│
├── reference-code/
│   └── hx711-modular/      ← Modular HX711 sketch from experiment 004. Reference only — copy, don't modify.
│       ├── hx711.cpp / .h
│       ├── tare.cpp / .h
│       ├── cal.cpp / .h
│       ├── noise.cpp / .h
│       ├── delta.cpp / .h
│       ├── sketch.ino
│       └── sketch.yaml
│
└── app/                    ← (empty — App Lab app goes here when Phase 1 is designed in chat)
```

---

## Where to Start

If you are a new engineer picking this up, do these steps in order:

1. **SSH to the board:** `ssh arduino@192.168.1.161`
2. **Navigate to this folder:** `cd ~/ArduinoApps/gas-cylinder-monitor`
3. **Read CLAUDE.md** — locked constants, rules, current state, what never to do
4. **Read docs/PLAN.md** — where Phase 1 begins and what needs designing
5. **Read docs/PROJECT_CONTEXT.md** — what the product is and why it exists
6. **Read docs/HANDOFF.md** — what was done last session and what comes next
7. **Open Claude.ai chat** (not CLI) to design the next phase from first principles
8. Chat produces a precise CLI prompt. Execute that prompt in Claude Code CLI.

**Do not write any product code before completing steps 1–7.**

---

## The Working Rule

```
PLANNING / RESEARCH / BRAINSTORMING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION       → Claude Code CLI only.
```

These two modes never mix. See `~/ArduinoApps/WORKING_MODE.md` for the full contract.

---

## Key Locked Values (quick reference)

```
DT=D7, SCK=D6               ← never change
HX711 VCC = 5V              ← never change
CAL_FACTOR = 100–107 raw/g  ← self-compute every deployment
TARE = -12799 to -13737 raw ← self-compute every boot
NOISE STD = 1.33–2.36g      ← self-compute every boot
THRESHOLD = 2.38–4.23g      ← derived from STD × formula
FALLBACK threshold = 8.0g   ← if characterisation fails
millis() pacing = 120ms     ← at TOP of loop() only
wait_ready timeout = 400ms  ← tuned for AQ3 under Bridge load
```

Full derivation and proof in `docs/reference/SENSOR_CHARACTERISATION.md`.
Full experiment history in `docs/reference/EXPERIMENT_HISTORY.md`.
