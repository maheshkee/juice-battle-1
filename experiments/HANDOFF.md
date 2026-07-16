# HANDOFF — HX711 Experiments Session 2026-05-02
# Paste this to Claude at the start of next session

---

## What to do first in next session

1. Read this file completely
2. Read ~/ArduinoApps/experiments/LEARNINGS.md
3. Read ~/ArduinoApps/experiments/STATUS.md
4. Then proceed

---

## Session summary

Full day of HX711 experimentation on AQ3. Two experiments run.
H1 freeze confirmed. Calibration derived. Water spoon test done.
Multiple App Lab patterns locked in from real failures.

---

## Locked-in hardware facts (verified today on real hardware)

### HX711 behavior
H1 confirmed: HX711 freezes after conversion. DOUT stays LOW
until MCU reads 24 bits + 25th gain pulse. Next conversion starts
only after 25th pulse. Proven by S1=S2=-1, DOUT LOW all 30s, S3=10308.

Post-stall settling: first conversion after long stall = 400-554ms.
Normal conversions = 100ms (10 Hz at RATE=0).

25th pulse fires from inside hx711_read_raw() automatically.
DOUT goes HIGH at +0ms after 25th pulse. HX711 resets instantly.

### Calibration — this hardware, this load cell
```
Single load cell + HX711 gain 128:
  CAL_FACTOR = 103.0 raw/g  (verified range 94-105 across all runs)
  TARE range = -12000 to -14000 raw (varies per session, normal)
  Formula: grams = (raw_value - tare) / cal_factor
```

### Cal factor dependency — critical for production
```
Wiring topology affects cal_factor:

Single cell, gain 128:              ~103 raw/g
4 cells full bridge, 1 HX711:       ~103 raw/g  (signals add up)
4 cells, 1 cell wired, 1 HX711:     ~412 raw/g  (only 1/4 load seen)
4 cells, 4 HX711s, readings summed: each ~412, divide by 4 = ~103

NEVER hardcode 103 in production — derive from known weight on
first boot, store to config file. Tare always fresh each session.
```

### Tare behavior
Tare drifts with temperature, power cycle, mounting changes.
Always re-tare at start of each session.
Normal range for this setup: -12000 to -14000 raw.
Outside this range = something on scale or hardware issue.

### Repeatability / noise floor
With nothing removed, readings drift ±4g over 30 seconds.
This is mechanical + thermal drift, not electronics noise.
Production event threshold must be >4g to avoid false triggers.
Recommended: 8-10g minimum change to trigger weight event.

### Minimum detectable change
5.35g detected cleanly with 20-sample averaging (verified).
Noise floor characterization (experiment 002) still pending.

---

## App Lab patterns — all confirmed from real failures today

### NEVER use Monitor.println()
Monitor.begin() makes blocking RPC to Python (mon/connected).
Without Python handler registered, MCU hangs forever. Zero output.
Fix: Bridge.notify("log", String(msg)) + Bridge.provide("log", handler)

### setup() correct order
```cpp
void setup() {
    pinMode(SCK, OUTPUT); digitalWrite(SCK, LOW);
    pinMode(DT, INPUT_PULLUP);
    delay(3000);       // wait for Python container
    Bridge.begin();    // NO Monitor.begin()
    Bridge.provide_safe("take_reading", handle_take_reading);
    Bridge.notify("log", String("MCU ready."));
}
void loop() {}
```

### Python — NEVER use threading
Threading (daemon threads) fails silently in App Lab Docker.
No error shown. Thread starts but poll loop never executes.
Fix: App.run(user_loop=my_loop) — user_loop called repeatedly.

### Python correct pattern
```python
from arduino.app_utils import App, Bridge
import os, time, json

TRIGGER = "/app/trigger.txt"  # /app = app folder inside Docker

ctx = {"state": "start"}

def user_loop():
    if ctx["state"] == "some_state":
        if os.path.exists(TRIGGER):
            os.remove(TRIGGER)
            result = int(Bridge.call("take_reading"))
            # process result
    time.sleep(0.5)

def on_log(data):
    print(str(data), flush=True)

Bridge.provide("log", on_log)
App.run(user_loop=user_loop)  # LAST LINE — no threading
```

### Bridge.provide_safe() for blocking MCU handlers
Handlers blocking >100ms must use provide_safe().
20 reads × 100ms = 2s — always provide_safe() for HX711 reads.
Never call Bridge.notify() from inside a provide_safe() handler.

### Symlink required for nested experiment apps
```bash
ln -s ~/ArduinoApps/experiments/hx711/NNN-name/app \
      ~/ArduinoApps/APP_NAME
```
APP_NAME pattern: sensor-NNN-name (hx711-006-water-spoon-a)

### Log command
```bash
arduino-app-cli app logs user:APP_NAME --follow
```

### Trigger file path
Inside Docker: /app/trigger.txt
On host:       ~/ArduinoApps/APP_NAME/trigger.txt
Python uses:   os.path.expanduser() for ~ — never raw ~

### delay(3000) before Bridge.begin()
Python container needs ~3s to start after app launch.

---

## Experiment 006 Part A — results

### Best clean run (weight blocks, 146g)
```
cal_factor = 101.54 raw/g
Tare       = -12395 raw
W1         = 146.00g (baseline)
W2         = 150.08g (delta = +4.08g — nothing removed, drift only)
W3         = 135.77g (delta = -14.31g — ~14g removed)
W3-W1      = -10.23g
```

### Water run (clean)
```
cal_factor = 103.02 raw/g
W1         = 130.00g
W2         = 123.71g (delta = -6.29g)
W3         = 118.36g (delta = -5.35g)
```

### Conclusion
System reliably detects ~5g changes with 20-sample averaging.
Mechanical drift ±4g over 30 seconds is the practical noise floor.
Minimum useful threshold for event detection: 8-10g.

---

## Experiment 006 Part B — PENDING

Needs measuring tool (syringe or measuring cup — decide this session).
Same app, same procedure.
Goal: verify system measures known removal amount accurately.
Expected: each measured removal reads within ±2g of known amount.

---

## Production architecture for gas-cylinder-monitor

### Event-driven MCU loop (target — experiment 007)
```
MCU loop (10 Hz continuous):
  read raw → convert to grams → compare to last reading
  if |current - last| > threshold (8-10g):
      Bridge.notify("weight_event", current_grams)
      last = current

Python:
  Bridge.provide("weight_event", handler)
  handler: timestamp + log + store to SQLite
```

No triggers. No human interaction. Fully automatic.
This is experiment 007 — after 006 Part B and 002 noise baseline.

### First-boot calibration for production
```
First boot:
  prompt for known weight
  derive cal_factor = (raw_w1 - tare) / known_g
  store to ~/ArduinoApps/gas-cylinder-monitor/config.json
  verify: if |cal_factor - 103| / 103 > 0.15 → warn, retry

Every boot:
  load cal_factor from config.json
  take fresh tare
  start monitoring
```

---

## Experiment queue

```
006 Part B  — measured water removal (this session or next)
002         — noise baseline 10Hz vs 80Hz
007 (new)   — continuous event-driven reading, auto detection
005         — calibration linearity (multiple known weights)
home-hub    — graduate working patterns to production
```

---

## Files to update on board (CLI prompt below)

1. ~/ArduinoApps/experiments/LEARNINGS.md — add L1-L10
2. ~/ArduinoApps/experiments/STATUS.md — update state
3. ~/ArduinoApps/experiments/PLAN.md — add experiment 007
4. ~/ArduinoApps/experiments/hx711/001-freeze-test/RESULTS.md — fill in
5. ~/ArduinoApps/experiments/hx711/001-freeze-test/CONCLUSION.md — fill in
6. ~/ArduinoApps/experiments/hx711/006-water-spoon-test/RESULTS.md — fill in
7. ~/ArduinoApps/experiments/hx711/006-water-spoon-test/CONCLUSION.md — fill in
8. ~/ArduinoApps/home-hub/CLAUDE.md — fix Bridge.on() error
9. ~/ArduinoApps/experiments/SKILL.md — fix Monitor.begin() contradiction

---

## CLI prompt to update all board documents

Paste this to CLI:

```
Read ~/ArduinoApps/experiments/HANDOFF.md first.
Then update the following files on the board.
Read each file before modifying. Never overwrite without reading first.

TASK 1 — Add to ~/ArduinoApps/experiments/LEARNINGS.md:

## Hardware-verified — 2026-05-02

L1: H1 confirmed. HX711 freezes after conversion. DOUT stays LOW
    until MCU reads 24 bits + 25th gain pulse. Next conversion starts
    only after 25th pulse fires. Proven on real hardware.
    S1=S2=-1 after 30s stall. DOUT LOW all 30s. S3=10308.

L2: Post-stall settling = 400-554ms.
    First conversion after long stall takes longer than normal 100ms.
    Datasheet spec: 400ms settling after reset. Subsequent = 100ms.

L3: 25th pulse is the next-conversion trigger.
    DOUT goes HIGH at +0ms after 25th SCK pulse in hx711_read_raw().
    HX711 resets and starts fresh 100ms window instantly.

L4: CAL_FACTOR = 103.0 raw/g for this load cell + HX711 gain 128.
    Verified range across all clean runs: 94-105 raw/g.
    Hardware constant. Changes only if load cell damaged or wiring topology changes.
    Four cells full bridge = same ~103. One of four cells = ~412. Four HX711s summed = ~103.

L5: Tare range = -12000 to -14000 raw for this hardware.
    Drifts with temperature, power cycle, mounting. Re-tare every session.
    Outside this range = something on scale or hardware fault.

L6: Repeatability = ±4g drift over 30 seconds.
    Mechanical + thermal drift, not electronics noise.
    Production event threshold must be >4g. Recommended: 8-10g.

L7: Minimum detectable change = 5.35g with 20-sample averaging.
    Noise floor characterization (experiment 002) still pending.

L8: Monitor.begin() blocks MCU forever in App Lab.
    Fix: Bridge.notify("log", msg) + Python Bridge.provide("log", handler).

L9: Threading fails silently in App Lab Docker.
    Fix: App.run(user_loop=my_loop). No import threading. No daemon threads.

L10: Bridge.provide_safe() required for MCU handlers blocking >100ms.
     Never call Bridge.notify() from inside a provide_safe() handler.

L11: delay(3000) before Bridge.begin() in setup().
     Python container needs ~3s. Without it Bridge handshake unstable.

L12: Cal_factor must be derived fresh on first boot and stored to config.
     Never hardcode in production — wiring topology changes the value.
     First boot: derive from known weight, store to config.json.
     Every boot: load from config, take fresh tare, start monitoring.

TASK 2 — Update ~/ArduinoApps/experiments/STATUS.md:
Replace entire contents with:

# Experiments Status
Last updated: 2026-05-02

## Board
AQ3 at 192.168.1.161

## Completed
001-freeze-test: H1 confirmed. Hardware verified 2026-05-02.
006-water-spoon-test Part A: Complete. 5g detection verified.

## Active
006-water-spoon-test Part B: PENDING — needs measuring tool.

## Queued
002: Noise baseline
007: Continuous event-driven reading (new — designed 2026-05-02)
005: Calibration linearity

## Calibration state
CAL_FACTOR = 103.0 raw/g (hardware constant, this load cell)
Tare: re-derived each session, range -12000 to -14000 raw
Threshold: 8-10g minimum for reliable event detection

TASK 3 — Add to ~/ArduinoApps/experiments/PLAN.md:

## Experiment 007 — continuous event-driven weight detection
Goal: MCU reads at 10Hz continuously, auto-detects weight changes
above threshold, pushes weight_event to Python without any trigger.
Threshold: 8-10g (above mechanical drift floor of ±4g).
Validation: pour water in 3 separate amounts, verify 3 events
appear in log automatically with correct gram values.
Prerequisite: 006 Part B complete, 002 noise baseline complete.

TASK 4 — Fill ~/ArduinoApps/experiments/hx711/001-freeze-test/RESULTS.md:

# Experiment 001 Results
Date: 2026-05-02
Board: AQ3 at 192.168.1.161

S1 = -1  at t=8230ms  (empty scale baseline)
DOUT during 30s pause: LOW every second, all 30 readings, zero HIGH
S2 = -1  at t=38254ms  (frozen pre-pause value — weight added during pause invisible)
DOUT HIGH at +0ms after S2 read, LOW again at +554ms
S3 = 10308  at t=38819ms  (first fresh conversion after stall)

TASK 5 — Fill ~/ArduinoApps/experiments/hx711/001-freeze-test/CONCLUSION.md:

# Experiment 001 Conclusion
Hypothesis confirmed: H1 (freeze)

Evidence:
1. S2=S1=-1: weight added during 30s pause completely invisible
2. DOUT LOW all 30 seconds: zero autonomous conversions during stall
3. S3=10308: fresh reading after resume reflects actual weight
4. DOUT HIGH at +0ms: instant reset on 25th pulse
5. 554ms settling: matches datasheet 400ms spec

Impact on gas-cylinder-monitor:
MCU must read HX711 at 10Hz continuously. Any stall = lost data.
Event-driven architecture required (experiment 007).

Graduated to LEARNINGS.md: L1, L2, L3 — 2026-05-02

TASK 6 — Fill ~/ArduinoApps/experiments/hx711/006-water-spoon-test/RESULTS.md:

# Experiment 006 Part A Results
Date: 2026-05-02

Best water run:
  cal_factor=103.02, Tare=-13086
  W1=130.00g, W2=123.71g, W3=118.36g
  W2-W1=-6.29g, W3-W2=-5.35g

Best weight block run:
  cal_factor=101.54, Tare=-12395
  W1=146.00g, W2=150.08g (+4.08g drift), W3=135.77g
  W3-W1=-10.23g (~14g removed)

Repeatability: ±4g drift over 30s with nothing removed.
Min detection: 5.35g clean.

TASK 7 — Fill ~/ArduinoApps/experiments/hx711/006-water-spoon-test/CONCLUSION.md:

# Experiment 006 Part A Conclusion

System reliably detects ~5g weight changes using 20-sample averaging.
Mechanical drift ±4g is the practical noise floor for this setup.
Minimum production threshold: 8-10g for reliable event detection.
Cal_factor stable at 103 raw/g across all valid runs.
Stability checks (tare + W1 + W2/W3) essential for reliable readings.

Part B pending: measured removal to verify accuracy against known amounts.
Graduated to LEARNINGS.md: L4-L7 — 2026-05-02

TASK 8 — Fix ~/ArduinoApps/home-hub/CLAUDE.md:
Find any line containing Bridge.on('weight_event')
Replace with: Bridge.provide("weight_event", handler)
Add comment: # Bridge.on() does not exist — confirmed 2026-05-02

TASK 9 — Fix ~/ArduinoApps/experiments/SKILL.md:
Find the section saying Monitor.println() is the output path.
Replace with correct pattern:
  NEVER Monitor.println() — causes MCU hang.
  CORRECT: Bridge.notify("log", String(msg)) from MCU
           Bridge.provide("log", lambda d: print(str(d), flush=True)) in Python

After all tasks: print list of all files modified.
```

---

## Board quick reference

```
SSH:     ssh arduino@192.168.1.161
Logs:    arduino-app-cli app logs user:APP_NAME --follow
Deploy:  cd ~/ArduinoApps/APP_NAME && bash deploy.sh
Trigger: touch ~/ArduinoApps/APP_NAME/trigger.txt
Stop:    arduino-app-cli app stop user:APP_NAME
Start:   arduino-app-cli app start user:APP_NAME
```

## Active apps
```
hx711-001-freeze-test    → experiments/hx711/001-freeze-test/app/
hx711-006-water-spoon-a  → experiments/hx711/006-water-spoon-test/app/
digital-scale            → golden reference, never modify
home-hub                 → production, gas monitor pending
```
