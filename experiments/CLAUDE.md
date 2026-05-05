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

---
## WORKING MODE (added 2026-05-05)

PLANNING / RESEARCH / BRAINSTORMING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION → Claude Code CLI only.

Every CLI session must:
1. Read CLAUDE.md completely
2. Read relevant SKILL.md
3. Read docs/SENSOR_CHARACTERISATION.md if touching HX711
4. Read docs/LEARNINGS_AND_INSIGHTS.md for known bugs
5. Execute the design prompt — nothing more, nothing less
6. Update CLAUDE.md at end: what changed, current state

---
## DEBUGGING RULES (added 2026-05-05)

1. Read all relevant files before suggesting any fix
2. Reproduce symptom exactly before diagnosing
3. Think from atomic level — what instruction, what value, what register
4. One diagnostic at a time — print intermediate values
5. One fix at a time — verify before next fix
6. Never patch without understanding root cause
7. Document open questions in docs/LEARNINGS_AND_INSIGHTS.md

---
## NEVER DO (each caused a real bug — see docs/LEARNINGS_AND_INSIGHTS.md)

- while(count<N) inside state case → Bridge interrupt accumulation
- double accumulator in for loop → sum=0 on STM32U585
- double array on stack in loop() → stack corruption, hang
- Tare with weight on scale → cal_factor ≈ 0
- @Bridge.on() in Python → AttributeError
- Bridge.notify before Python ready → message lost silently
- Hardcode threshold_g or cal_factor → wrong for every environment
- millis() guard inside state case → stale reads
- Monitor.begin() → hangs MCU
- D2-D5 for HX711 → timer conflicts
