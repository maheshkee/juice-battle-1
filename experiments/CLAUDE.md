# CLAUDE.md — experiments workspace | AQ3
# Board: Arduino UNO Q AQ3 | IP: 192.168.1.161
# Read this fully before doing anything in this directory

---

## What This Directory Is

This is the experiment lab — NOT production.

Code here is throwaway. Its only purpose is to prove or disprove a specific hardware or firmware hypothesis. Once proven, the learning graduates to `~/ArduinoApps/home-hub/` as production implementation.

Production apps live at `~/ArduinoApps/` alongside this directory — never touch them from here.

---

## Hardware Platform

```
Board: Arduino UNO Q (AQ3)

MPU: Qualcomm QRB2210
  OS: Debian Linux, aarch64
  Runtime: Python 3
  Connectivity: SSH, BLE, App Lab Docker

MCU: STM32U585
  OS: Zephyr RTOS + Arduino Core
  Language: C++
  Clock: 160 MHz

Bridge RPC: arduino-router at /var/run/arduino-router.sock
  MCU → MPU output: Monitor.println() → Bridge → MPU → app logs
  NOT Serial.println() — USB-C port is wired to MPU, not MCU
```

---

## Rules

- Production apps at `~/ArduinoApps/` — do not touch from here
- Golden reference: `~/ArduinoApps/digital-scale/` — never modify, copy from it
- Experiment apps deploy via `arduino-app-cli` — same mechanism as production
- Each experiment is self-contained in its own numbered subfolder
- Learnings graduate to `~/ArduinoApps/home-hub/`

See [SKILL.md](SKILL.md) for operating rules.
See [HARDWARE.md](HARDWARE.md) for pin constraints and voltage domains.
See [LEARNINGS.md](LEARNINGS.md) for hardware-verified constants — check before implementing any HX711 weight conversion.
See [STATUS.md](STATUS.md) for current experiment state and calibration values.

---

## Directory Structure

```
experiments/
├── CLAUDE.md          ← this file
├── SKILL.md           ← operating rules for Claude
├── PLAN.md            ← experiment queue
├── STATUS.md          ← current state snapshot
├── HARDWARE.md        ← pin and voltage reference
├── LEARNINGS.md       ← locked-in truths from completed experiments
└── hx711/
    ├── README.md      ← HX711 sensor context
    └── 001-freeze-test/
        ├── PLAN.md
        ├── RESULTS.md
        └── CONCLUSION.md
```

Experiment app code lives at:
```
~/ArduinoApps/experiments/<sensor>/<NNN>-<name>/app/
```
