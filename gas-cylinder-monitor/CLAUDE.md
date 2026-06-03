# CLAUDE.md — gas-cylinder-monitor | AQ3
# Board: Arduino UNO Q AQ3 | IP: 192.168.1.161 | user: arduino
# Last updated: 2026-06-03 (migration session — scaffold only)
# Read this FULLY before doing anything in this directory.

---

## (a) What This Product Is

A permanent weight monitor for an Indian LPG cylinder. A single HX711 24-bit ADC reads a 20kg load cell mounted under the cylinder. The MCU (STM32U585) reads the weight continuously and pushes events to the Linux MPU (QRB2210) via Bridge.notify. The MPU records snapshots to SQLite, computes gas remaining, predicts days until refill, and surfaces alerts via BLE and the home screen.

**Development phase uses water in a container — not a gas cylinder.** Weight is weight. No code path may be hardcoded for "gas" semantics. The product detects weight changes; what is being weighed is irrelevant to the sensor layer.

---

## (b) Board

```
Board:  Arduino UNO Q AQ3
IP:     192.168.1.161
User:   arduino
SSH:    ssh arduino@192.168.1.161
```

---

## (c) Locked Hardware Constants

From `docs/reference/SENSOR_CHARACTERISATION.md` and `docs/RESEARCH.md`.

### ✅ Hardware-verified on AQ3

```
DT pin              = D7 ONLY            (never change)
SCK pin             = D6 ONLY            (never change)
HX711 VCC           = 5V                 (green PCB clones require 5V AVDD)
Load cell wiring    = Red→E+, Black→E-, Green→A+, White→A-
wait_ready timeout  = 400ms              (tuned for AQ3 under Bridge load)
millis() pacing     = 120ms              (at TOP of loop() only)
TARE range          = -12799 to -13737 raw  (varies — always self-compute)
TARE spread         = 37–174 raw         (within 600 threshold)
CAL_FACTOR range    = 100–107 raw/g      (varies — always self-compute)
NOISE STD range     = 1.33–2.36g        (varies — always self-compute)
THRESHOLD range     = 2.38–4.23g        (derived from STD)
FALLBACK threshold  = 8.0g              (if characterisation fails all retries)
```

### Platform rules (STM32U585 Zephyr/Arduino Core)

```
float ONLY — never use double anywhere in MCU sketch
  Why: double accumulator loops produce sum=0 on this platform
  Why: double arrays on stack inside loop() corrupt stack frame → hang
```

### All four corrupt filters (required on every read path)

```cpp
if (r == LONG_MIN)                  continue;  // wait_ready timeout
if (r == -1)                        continue;  // not ready
if (r == 0x7FFFFF)                  continue;  // positive saturation
if (r < -5000000L || r > 5000000L)  continue;  // out of range
// After gram conversion:
if (g < -50.0f || g > 50.0f)        continue;  // grams sanity
```

---

## (d) Non-Negotiable Rules

| Rule | Detail |
|------|--------|
| No external HX711 library | Raw bit-bang only. Copy from reference-code/hx711-modular/. |
| No hardcoded cal_factor | Derive at boot, store config.json, load on subsequent boots. |
| No hardcoded tare | Re-derive every boot. Never load from file. |
| No hardcoded threshold_g | Derive from NOISE_MEASURE at every boot. Fallback = 8.0g. |
| No blocking in setup() | setup() does delay(3000) + Bridge.begin() only. |
| No blocking while in state cases | One sample per loop() iteration. |
| snprintf not String+= | Heap fragmentation on long-running MCU. |
| sketch.yaml required | Without it, arduino-app-cli uses wrong platform/compiler. |
| DT=D7, SCK=D6 | D2–D5 have STM32U585 timer conflicts → 0x7FFFFF corrupt. |
| millis() pacing at TOP of loop() | Never guard pacing inside a state case. |

---

## (e) Every-Session Read Order

Before writing a single line of code in any CLI session:

1. `~/ArduinoApps/gas-cylinder-monitor/CLAUDE.md` ← this file
2. `~/ArduinoApps/WORKING_MODE.md`
3. `docs/PLAN.md`
4. `docs/PROJECT_CONTEXT.md`
5. `docs/HANDOFF.md`
6. Relevant `SKILL.md` for the task
7. The design prompt from chat

Do not touch code until all seven are read.

---

## (f) Phase 5–6 Dependencies — Do NOT Duplicate

Wheels, typelibs, and socket.io.min.js live in `home-hub/` and are one `cp` away:

```bash
# BLE Python wheels
cp -r ~/ArduinoApps/home-hub/wheels/    <app>/wheels/

# GObject typelibs for D-Bus
cp -r ~/ArduinoApps/home-hub/typelibs/  <app>/typelibs/

# Socket.IO client JS
cp ~/ArduinoApps/home-hub/assets/socket.io.min.js  <app>/assets/
```

Do NOT commit wheels/ or typelibs/ to git (they are in .gitignore).
Do NOT copy them into this reference folder now — copy into the app/ when Phase 5 begins.

---

## (g) Current State — 2026-06-03

```
Status:        SCAFFOLD ONLY
app/ folder:   empty — no App Lab app exists yet
Phase 1:       load cell reading — design in chat first, then implement in CLI
Reference docs: complete — see docs/ tree
Product code:  none written
```

**Next action:** Open Claude.ai chat, read this CLAUDE.md and docs/PLAN.md,
design Phase 1 (load cell reading state machine, Bridge.notify, Python listener).
Chat produces a CLI prompt. Then execute in CLI.

---

## NEVER DO (each caused a real bug — see docs/LEARNINGS.md for full history)

| Never do | Why | Bug date |
|----------|-----|----------|
| while(count < N) inside state case | Bridge interrupt accumulation → timeouts | 2026-05-05 |
| double accumulator in for loop | sum=0 on STM32U585 | 2026-05-05 |
| double array on stack in loop() | Stack corruption → hang | 2026-05-05 |
| Tare with weight on scale | cal_factor ≈ 0 → CAL_FAIL | 2026-05-05 |
| @Bridge.on() in Python | AttributeError — doesn't exist | 2026-05-02 |
| Bridge.notify before Python ready | Message lost silently | 2026-05-05 |
| Hardcode threshold_g | Wrong for every environment | 2026-05-05 |
| Hardcode cal_factor | Wrong for every load cell mounting | 2026-05-04 |
| millis() guard inside state case | Stale reads, std=4224g | 2026-05-04 |
| Monitor.begin() | Hangs MCU if Python handler missing | 2026-05-02 |
| D2–D5 for HX711 | Timer conflicts → 0x7FFFFF constant | 2026-05-02 |
