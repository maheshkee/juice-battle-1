# SKILL.md — Operating Rules for Claude in experiments/

Read this before generating any code or modifying any file in this workspace.

---

## MCU Sketch Rules

- **Pattern source**: always copy MCU sketch structure from `~/ArduinoApps/digital-scale/sketch/sketch.ino` — the golden reference
- **Output**: always `Bridge.notify("log", String(msg))`, never `Monitor.println()` or `Serial.println()`
  - `Monitor.begin()` makes a synchronous RPC call to Python. If Python has no handler, MCU hangs forever before any output. Never call it.
  - `Serial.println()` goes to MPU CDC, not app logs.
- **setup() requires**:
  ```cpp
  delay(3000);  // wait for Python container before connecting Bridge
  Bridge.begin();
  Bridge.provide_safe("your_method", handler);  // use provide_safe for blocking handlers
  Bridge.notify("log", String("MCU ready."));
  ```
  **Never call `Monitor.begin()`.**
- **Compile command**: mirror exactly what digital-scale uses — do not invent flags

---

## HX711 Hard Constraints

| Item | Value |
|------|-------|
| DT pin | D7 ONLY |
| SCK pin | D6 ONLY |
| Forbidden pins | D2, D3, D4, D5 — STM32U585 timer conflicts, symptom: 0x7FFFFF or 0x800000 |
| Library | NONE — raw bit-bang only |
| Timing | delayMicroseconds(1) after EVERY GPIO edge — non-negotiable |
| DOUT pullup | INPUT_PULLUP — HX711 DOUT is open-drain |

---

## App Structure

Every experiment app follows this layout:
```
<NNN>-<name>/
├── PLAN.md
├── RESULTS.md
├── CONCLUSION.md
└── app/
    ├── app.yaml
    └── sketch/
        ├── sketch.ino
        └── sketch.yaml
```

**`python/main.py` is ALWAYS required** — even for sketch-only experiments.
The App Lab log system captures `Monitor.println()` output through the Python
container. If no Python process is running, Monitor output is silently dropped
and logs are empty. The minimum viable main.py:

```python
from arduino.app_utils import App, Bridge

Bridge.provide("log", lambda data: print(str(data), flush=True))
App.run()
```

**Do NOT use Monitor.println() for diagnostic output.** `Monitor.begin()` on the
MCU makes a synchronous RPC call (`mon/connected`) to the Python side. If Python
has no handler registered, the call hangs and the MCU freezes before any output.

**Correct output pattern for experiments:**
- MCU: `Bridge.notify("log", String(msg))` — fire and forget, never blocks
- Python: `Bridge.provide("log", lambda data: print(str(data), flush=True))`

`Bridge.begin()` does NOT exist on the Python side (confirmed AttributeError).
`App.run()` alone is not enough — at least one `Bridge.provide()` must be registered.

Assets are added only if the experiment requires a web UI.

---

## deploy.sh — APP_NAME Rule

The standard deploy.sh uses `APP_NAME="$(basename "$SCRIPT_DIR")"`.
For experiment apps nested at `.../001-freeze-test/app/`, basename = `app` — wrong.

**Rule**: every experiment's `app/deploy.sh` must set APP_NAME explicitly:
```bash
APP_NAME="hx711-001-freeze-test"   # set explicitly — never use basename here
```
Pattern: `<sensor>-<NNN>-<name>` — unique, identifiable in `arduino-app-cli app list`.

---

## Symlink Rule — arduino-app-cli lookup path

`arduino-app-cli` only looks one level deep under `~/ArduinoApps/`. It does:
```
stat /home/arduino/ArduinoApps/<app-name>
```
It does **not** find apps nested at `.../experiments/hx711/001-freeze-test/app/`.

**Rule**: after creating any experiment app, always create a symlink at the expected path:
```bash
ln -s ~/ArduinoApps/experiments/<sensor>/<NNN>-<name>/app \
      ~/ArduinoApps/<APP_NAME>
```
Example:
```bash
ln -s ~/ArduinoApps/experiments/hx711/001-freeze-test/app \
      ~/ArduinoApps/hx711-001-freeze-test
```
The symlink must be created **before** running `deploy.sh` or any `arduino-app-cli` command.
deploy.sh must still be run from the real `app/` path, not through the symlink.

---

## Experiment App Structure

Each experiment gets an `app/` subfolder inside its numbered folder. Code and docs live together:
```
hx711/001-freeze-test/
├── PLAN.md        ← test design
├── RESULTS.md     ← raw output
├── CONCLUSION.md  ← locked finding
└── app/           ← deployable app (app.yaml + sketch/)
```

---

## Session Rules

- Read existing files fully before modifying anything
- Plan first → show plan → wait for approval → then generate files
- One chunk at a time — never jump ahead
- No hardcoded paths anywhere — always `$SCRIPT_DIR` dynamic resolution

---

## HX711 Calibration Pattern

Single-session calibration (Part A style):
```python
KNOWN_WEIGHT_G = 130.0          # weighed on reference scale before experiment

# Step 1: tare (empty scale)
raw_zero = bridge_call("take_reading")

# Step 2: known weight on scale
raw_w1 = bridge_call("take_reading")
cal_factor = (raw_w1 - raw_zero) / KNOWN_WEIGHT_G

# Step 3+: any reading → grams
grams = (raw - raw_zero) / cal_factor
```

Persistent calibration (Part B+ style — load from file):
```python
# cal.json written once: {"raw_zero": -13086, "cal_factor": 103.02}
with open("cal.json") as f:
    cal = json.load(f)
grams = (raw - cal["raw_zero"]) / cal["cal_factor"]
```

**WARNING**: tare is invalidated if load cell is physically moved or remounted.
Negative cal_factor = sign reversal = load cell disturbed. Re-tare before use.
Verified constants for this hardware (2026-05-02): raw_zero=-13086, cal_factor=103.02

---

## Safety Rules (Hardware)

- **BLE transport**: `le` only — never `auto` (kills BT adapter, needs reboot)
- **JCTL pins**: 1.8V only — 3.3V = hardware damage
- **MCU headers**: 3.3V logic — A0 and A1 are NOT 5V tolerant

---

## Deploy Reference

```bash
cd ~/ArduinoApps/experiments/hx711/001-freeze-test/app && bash deploy.sh
arduino-app-cli app logs user:hx711-001-freeze-test --follow
```

---

## HX711 Calibration Architecture (verified 2026-05-02)

### The two-variable model

```
grams = (raw_value - TARE) / CAL_FACTOR
```

**TARE:**
- Session variable. Re-derive every boot. Never load from file.
- Drifts with temperature, power cycle, mounting.
- Normal range this hardware: -12000 to -14000 raw.
- Stability check: two reads within 500 raw units. Use average.
- Range check: must be between -100000 and 0.

**CAL_FACTOR:**
- Hardware constant. Derive once, store to config.json, load every boot.
- Changes only if: load cell damaged, wiring topology changes, gain changes.
- Verified value this hardware: 103.0 raw/g (range 94-105 across all runs).
- Sanity check: derived value must be within 50% of 103.0.
- NEVER hardcode in source code - topology changes the value.

### Wiring topology effect on CAL_FACTOR

```
Single cell gain 128:               ~103 raw/g
4 cells full bridge, 1 HX711:       ~103 raw/g  (signals add, same sensitivity)
4 cells, 1 cell only, 1 HX711:      ~412 raw/g  (only 1/4 load seen)
4 cells, 4 HX711s summed:           each ~412, sum = ~103
```

### First boot calibration sequence

1. Prompt user for known weight (g)
2. Take tare (stability check + range check)
3. Place known weight, take reading (stability check + sanity check)
4. cal_factor = (raw_w1 - tare) / known_g
5. Store to config.json: {cal_factor, cal_date, topology, threshold_g}

### Every boot sequence

1. Load cal_factor from config.json (if missing: run first boot)
2. Take fresh tare (stability check always)
3. Ready to measure

### Config file format

```json
{
  "cal_factor": 103.02,
  "cal_date": "2026-05-02",
  "cal_weight_g": 500,
  "topology": "single_cell_gain128",
  "threshold_g": 8.0
}
```

### Event threshold

Noise floor (mechanical drift) = ±4g on this hardware.
Minimum production threshold = 8g (2× noise floor).
Set in config.json as threshold_g.

---

## Per-unit calibration rule

Every physical machine must be calibrated independently.
NEVER copy cal_factor from one machine to another, even if:
  - Same load cell model
  - Same wiring topology  
  - Same HX711 chip model
  - Same code

Why: manufacturing tolerance between cells (±0.5%), mounting
geometry differences, HX711 reference voltage variation between
chips — all cause 1-3% cal_factor difference between units.

For gas cylinder monitoring:
  - Relative changes (delta W) are accurate even with wrong cal_factor
  - Absolute weight readings will be systematically off by error %
  - Each deployed unit needs first-boot calibration with a known weight
  - Each unit stores its own config.json with its own cal_factor

Production deployment checklist (per unit):
  1. Install hardware
  2. Run first-boot calibration with verified known weight
  3. Confirm cal_factor is within 80-130 raw/g (sane range)
  4. Store to config.json on that unit
  5. Never overwrite with cal_factor from another unit

---
## WORKING MODE — CRITICAL RULE

Same rule applies to all experiments:

PLANNING / RESEARCH / BRAINSTORMING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION → Claude Code CLI only.

Chat produces the experiment design and a CLI prompt.
CLI receives that prompt and builds the experiment.

Never start building an experiment without a design prompt from chat.
Never write experiment code speculatively.
---
