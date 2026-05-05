# CLAUDE.md — home-hub + digital-scale | AQ3
# Board: Arduino UNO Q AQ3 (4GB) | IP: 192.168.1.161
# Last updated: 2026-04-30 | Read this fully before doing ANYTHING

---

## Board Architecture

```
SSH → MPU (QRB2210, Debian Linux) — Python, BLE, WebUI, App Lab Docker
         ↓ Bridge RPC (Arduino_RouterBridge)
      MCU (STM32U585, Zephyr @ 160MHz) — sketch.ino, GPIO, HX711
```

---

## HX711 — THE CONFIRMED WORKING CONFIGURATION

These facts were proven after a full day of R&D. Never deviate.

| Parameter     | Value       | Why                                              |
|---------------|-------------|--------------------------------------------------|
| DT pin        | D7          | Conflict-free. D2/D3/D4/D5 have timer mux issues |
| SCK pin       | D6          | Conflict-free. All others produced corrupt reads  |
| Library       | NONE        | Raw bit-bang in sketch.ino. No external lib.     |
| Bridge pattern| notify()    | MCU pushes every 500ms. NOT provide_safe+polling  |
| Cal factor    | 420.0f      | Starting point. Tune with known weight.           |
| Power         | 5V          | Green PCB HX711 clones need 5V AVDD              |
| DOUT pullup   | INPUT_PULLUP| Required — HX711 DOUT is open-drain              |

### The Working Bit-Bang Recipe (copy verbatim, never change timing)

```cpp
static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 1 gain pulse = gain 128 (Channel A)
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}
```

### Bridge.notify() Pattern (NOT provide_safe + Python polling)

```cpp
// In loop() — MCU pushes every PUSH_INTERVAL_MS
void loop() {
    static uint32_t last_push = 0;
    if (millis() - last_push < PUSH_INTERVAL_MS) return;
    last_push = millis();
    long raw = hx711_read_average(SAMPLE_COUNT);
    if (raw == LONG_MIN) {
        Bridge.notify("weight_event", String("{\"sensor_ok\":false}"));
        return;
    }
    float grams = (float)(raw - g_tare_offset) / CALIBRATION_FACTOR;
    // ... build JSON ...
    Bridge.notify("weight_event", json);
}
```

```python
# In Python main.py — listen, don't poll
def on_weight(data):
    ui.send_message('weight_update', data)

Bridge.provide('weight_event', on_weight)
```

---

## Reference App — digital-scale (WORKING, DO NOT BREAK)

```
~/ArduinoApps/digital-scale/
├── sketch/sketch.ino      ← THE reference. DT=7, SCK=6, Bridge.notify()
├── sketch/sketch.yaml     ← Arduino_RouterBridge only
├── python/main.py         ← Bridge.provide("weight_event", handler) listener
├── assets/index.html      ← WebUI: kg, g, STABLE, TARE button
└── assets/socket.io.min.js
```

When in doubt about HX711 implementation — copy from digital-scale sketch verbatim.

---

## App Status

| App | Status | Notes |
|-----|--------|-------|
| digital-scale | ✅ WORKING | Live weight, tare, stable detection |
| home-hub BLE | ✅ WORKING | Advertising as YT-Display |
| home-hub YouTube | ✅ WORKING | Flutter app control |
| home-hub weight widget | ⚠ NEEDS UPDATE | Must use D7/D6 + Bridge.notify() |
| home-hub gas monitor | ❌ DEFERRED | 6hr cycles not active |
| home-hub BT speaker | ❌ STUB | bt_manager.py all no-ops |

---

## Gas Monitor — Smart System Design

This is NOT a simple weight scale. It is an advanced smart gas monitoring system for LPG cylinders.

### What it does

| Feature | Description |
|---------|-------------|
| Live weight | 500ms MCU readings → real-time kg/g display |
| 6hr snapshot | Every 6 hours Python records weight to SQLite |
| Daily usage | kg consumed per day from snapshot deltas |
| Weekly trend | Rolling 7-day avg daily consumption |
| Monthly trend | Rolling 30-day avg daily consumption |
| High-usage flag | Days where consumption > 2× 30-day baseline |
| Days-left prediction | Weighted 7d+30d avg → days until refill needed |
| Refill detection | Weight jump >5kg → new cylinder event, reset learning |
| Low-gas alert | BLE push + WebUI alert when net_kg < REFILL_THRESHOLD |

### Prediction Algorithm — Multi-Window Adaptive

NOT a simple 2-point linear extrapolation. Learning from history:

```
7-day avg  = total_consumed_7d / 7      ← responsive to recent habits
30-day avg = total_consumed_30d / 30    ← baseline, filters anomaly days

weighted_rate = (0.7 × 7day_avg) + (0.3 × 30day_avg)
days_left = net_kg_remaining / weighted_rate

confidence = HIGH  if |7day_avg - 30day_avg| < 0.2 kg/day
           = LOW   if diverging (seasonal shift, new household member, guests)
```

More data = better accuracy. First 7 days: low confidence. After 30 days: high confidence.

### High-Usage Day Detection

```
baseline_rate = 30-day rolling avg (kg/day)
today_consumed = today_start_weight - current_weight
if today_consumed > 2.0 × baseline_rate:
    flag as HIGH_USAGE_DAY
```

Surfaces: festival cooking, guests, cold weather heating, equipment malfunction.

### Refill Detection

```
if (new_weight - prev_snapshot_weight) > 5.0 kg:
    → log refill_history (timestamp, pre_net, post_net)
    → invalidate learning window (don't let pre-refill trend bias new cylinder)
    → recalculate baseline from fresh data only
```

### SQLite Schema — Full

```sql
readings (id, timestamp INTEGER, weight_kg REAL, net_kg REAL)
daily_aggregates (id, date_epoch INTEGER, avg_net_kg REAL, consumed_kg REAL)
refill_history (id, timestamp INTEGER, pre_net_kg REAL, post_net_kg REAL)
cylinder_templates (id, brand TEXT, tare_kg REAL)
```

### Target Cylinder Types (Indian market)

| Type | Gross | Tare | Net gas |
|------|-------|------|---------|
| 14.2 kg (standard) | ~28 kg | ~13.8 kg | 14.2 kg |
| 5 kg (small) | ~10.5 kg | ~5.5 kg | 5 kg |
| 19 kg (commercial) | ~35 kg | ~16 kg | 19 kg |

---

## home-hub File Map

```
~/ArduinoApps/home-hub/
├── CLAUDE.md                    ← this file
├── deploy.sh                    ← always use this
├── python/
│   ├── main.py                  ← weight_poll_loop here (NEEDS UPDATE to Bridge.provide("weight_event", handler))
│   ├── config.py                ← REFILL_THRESHOLD_KG=8.0, GAS_DB_PATH
│   ├── bt_manager.py            ← STUB — do not delete
│   ├── ble_gatt_serve.py        ← DO NOT TOUCH
│   ├── queue_engine.py          ← DO NOT TOUCH
│   ├── local_engine.py          ← DO NOT TOUCH
│   └── services/gas_monitor.py  ← implemented, deferred
├── sketch/
│   ├── sketch.ino               ← NEEDS UPDATE: DT=7 SCK=6 + Bridge.notify()
│   ├── ScaleHX711.cpp/.h        ← CAN BE DELETED after migration
│   └── sketch.yaml
└── assets/
    └── splash.html              ← weight widget in #home div
```

---

## HX711 Calibration & Tare — Locked Strategy (2026-05-04)

### Tare — self-validating, no hardcoded range
TARE_SAMPLES     = 5
TARE_STABILITY   = 600 raw  (max spread across 5 samples)
TARE_MAX_RETRIES = 3
TARE_RETRY_MS    = 2000ms (managed by state machine, never blocking)

Collect 5 valid samples. spread = max - min.
If spread < 600: accept average as tare.
If spread >= 600: discard, wait via state machine, retry.
After 3 failures: LONG_MIN = hardware fault, halt and log.
Always log: "TARE OK = <value>, spread=<spread>"
Never hardcode expected tare range — it changes with mounting and session.

### Cal factor — derive fresh, never hardcode
CAL_FACTOR = (weight_raw - tare) / known_grams
Use state machine approach — never blocking delay() during calibration sequence.
Acceptance range for this hardware: 94–112 raw/g
Verified cal_factor for this load cell + HX711 + current mounting: 106.7 raw/g
Re-derive whenever load cell is remounted or wiring changes.

### Corrupt value filters — always use all three
Filter these in hx711_read_average() — copy from home-hub, not digital-scale:
  raw == LONG_MIN   (wait_ready timeout)
  raw == -1         (0xFFFFFF — all bits HIGH, not ready)
  raw == 0x7FFFFF   (positive saturation — pin/timer conflict)

### Debugging order — most issues are timing/code, not hardware
When readings are wrong, check in this order:
1. Is setup() using blocking delay()? — move all reads to loop() state machine
2. Is hx711_read_average() missing the -1 and 0x7FFFFF guards?
3. Is the bit-bang missing delayMicroseconds(1) on any edge?
4. Is DT=D7 and SCK=D6? — D2/D3/D4/D5 have timer conflicts
5. Only after all above confirmed — suspect physical wiring

Hardware wiring is the LAST thing to check, not the first.
Most bad readings in this project have been caused by:
- Blocking delay() in setup() starving Bridge/HX711 timing
- Missing corrupt value filters
- Wrong pin assignments
Physical wiring faults produce: values jumping in exact multiples,
readings lower than tare, or zero readings across all apps including
golden reference (digital-scale, home-hub).

---

## Critical Rules — Never Violate

1. HX711 DT = D7 ONLY. SCK = D6 ONLY. Any other pin = corrupt/no reads.
2. Bridge.notify() from loop() for weight. NOT Bridge.provide_safe() + Python polling.
3. No external HX711 library. Raw bit-bang only. digital-scale proves this.
4. BLE scan = le transport ONLY. Auto transport kills BT adapter on QRB2210.
5. Never add sockets: to app.yaml.
6. bt_manager.py EXISTS as stub — do not delete, do not recreate from scratch.
7. Never use sed/regex to edit Python files — use python3 read/replace/write.
8. JCTL = 1.8V ONLY. 3.3V on JCTL = hardware damage.
9. No hardcoded paths, usernames, hostnames in any script.
10. delayMicroseconds(1) after EVERY GPIO edge in HX711 bit-bang. Both HIGH and LOW.

---

## BLE UUIDs (never change)

- Service:  a01c0000-0000-0000-0000-000000000000
- CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
- EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)

---

## Deploy Commands

```bash
# Normal deploy
cd ~/ArduinoApps/home-hub && bash deploy.sh
cd ~/ArduinoApps/digital-scale && bash deploy.sh

# Force full recompile
rm -rf .cache && rm -rf ~/.arduino15/internal && bash deploy.sh

# Watch logs
arduino-app-cli app logs user:home-hub --follow
arduino-app-cli app logs user:digital-scale --follow

# Docker fallback (if app-cli logs empty)
sudo docker logs $(sudo docker ps | grep home-hub | awk '{print $1}') 2>&1 | tail -50
```

---

## Next Session Priorities

### Phase 1 — Hardware baseline (do first)
1. Calibrate digital-scale with known weight → real CALIBRATION_FACTOR (not 420.0f estimate)
2. Migrate home-hub sketch: DT=7, SCK=6 + Bridge.notify() copied from digital-scale verbatim
3. Update home-hub main.py: remove weight_poll_loop, add Bridge.provide("weight_event", handler) listener  # Bridge.on() does not exist — confirmed 2026-05-02
4. Tare persistence: skip auto-tare on boot if weight > 2kg (cylinder already on scale)

### Phase 2 — Gas monitor smart features
5. Re-enable 6hr snapshot cycle: time.sleep(21600) + SQLite writes
6. Implement daily_aggregates table: Python aggregates snapshots at midnight
7. Multi-window prediction: 7-day + 30-day weighted average (see algorithm in Gas Monitor section)
8. High-usage day detection: flag days > 2× 30-day baseline
9. Refill detection: weight jump > 5kg → log to refill_history, reset learning window

### Phase 3 — UI + alerts
10. Gas dashboard in splash.html: days_left, weekly trend, high-usage flags, refill history
11. Low-gas BLE alert: push_evt when net_kg < REFILL_THRESHOLD
12. BT speaker: D-Bus A2DP (never bluetoothctl)

---

## Things to Revert Before Production

| File | Current | Should be |
|------|---------|-----------|
| home-hub python/main.py | time.sleep(30) gas cycle | time.sleep(21600) |

---

## Git State

Repo: git@github.com:gratiantechnologies/project13.git  
Branch: main  
Uncommitted: home-hub sketch changes, digital-scale new app  

```bash
git add -A
git commit -m "feat: digital-scale working, DT=D7 SCK=D6, Bridge.notify architecture"
git push
```

---

## HX711 + Load Cell — Confirmed Working (2026-05-01)

### Hardware Setup (CRITICAL — never change)
- DT = D7 (PB2) ONLY
- SCK = D6 (PB1) ONLY
- No external library — raw bit-bang only
- delayMicroseconds(1) after EVERY GPIO edge
- CALIBRATION_FACTOR = 100.0f (confirmed 2026-05-01 with 10g/20g/30g blocks)
- SAMPLE_COUNT = 5, TARE_SAMPLE_COUNT = 20, STABILITY_THRESHOLD = 5.0f
- PUSH_INTERVAL_MS = 500

### Load Cell Wiring (confirmed working)
- Red   → E+
- Black → E-
- White → A-
- Green → A+
- HX711 VCC → 5V pin (NOT 3.3V)
- HX711 GND → GND

### Load Cell Mounting (CRITICAL)
- One end FIXED (clamped/screwed to surface)
- Other end FREE (hangs over edge, nothing touching it)
- Weight placed on free end only
- If both ends rest on surface → corrupt readings (0.0/4.6/25.1 cycling)

### Architecture (confirmed working)
- MCU: Bridge.notify("weight_event", json) from loop() every 500ms
- Python: Bridge.provide("weight_event", handler) — NOT Bridge.on() (does not exist)
- JSON fields: grams (float), weight_kg (float), stable (bool), sensor_ok (bool)

### Calibration Procedure
1. Mount load cell properly (one end fixed, one end free)
2. Power on, wait for tare to complete in setup()
3. Note RAW values with nothing on scale (empty baseline)
4. Place known weight, note RAW values
5. net_units = RAW_with_weight - RAW_empty
6. cal_factor = net_units / actual_grams
7. Update CALIBRATION_FACTOR in sketch.ino, redeploy

### Debugging Reference
- RAW = -1 → HX711 not ready when MCU read it (add to filter in hx711_read_average)
- RAW = 0x7FFFFF → pin conflict (wrong pin, timer mux issue)
- RAW = 0x800000 → pin conflict (wrong pin, timer mux issue)
- Readings unresponsive to weight → check mounting (free end must be free)
- Ghost fixed value repeating → free end touching surface intermittently

### Working Reference
sketch/sketch_working_reference.ino — DO NOT MODIFY
digital-scale app at ~/ArduinoApps/digital-scale/ — DO NOT MODIFY

---

## Weight Measurement Architecture (verified 2026-05-02)

### Calibration model

```
grams = (raw_value - tare) / cal_factor
```

tare:       fresh every boot, never stored
cal_factor: stored in config.json, loaded every boot

### Config file location

`~/ArduinoApps/home-hub/config.json`

```json
{
  "cal_factor": 103.02,
  "cal_date": "2026-05-02",
  "topology": "single_cell_gain128",
  "threshold_g": 8.0
}
```

### Event-driven MCU loop (production target)

MCU reads at 10Hz continuously.
When |current - last| > threshold_raw:
    Bridge.notify("weight_event", grams_string)
Python receives and logs with timestamp.
No triggers, no polling files, no human interaction.

### Threshold

Mechanical noise floor = ±4g.
threshold_g = 8.0 (from config).
threshold_raw = threshold_g * cal_factor = ~824 raw units.

### Wiring note for 4-cell upgrade

4 cells full bridge → same cal_factor ~103
1 of 4 cells wired → cal_factor ~412
Always re-derive cal_factor after any wiring change.

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

This project follows a strict separation between planning and implementation.

PLANNING / RESEARCH / BRAINSTORMING / LEARNING → happens in Claude.ai chat only.
CODE WRITING / IMPLEMENTATION / FILE EDITING → happens here in Claude Code CLI only.

Claude.ai chat produces:
- Architecture decisions
- Experiment designs
- Prompts for CLI

CLI receives those prompts and:
- Writes all code
- Creates all files
- Edits all configs
- Runs all commands on the board

NEVER write code speculatively in chat.
NEVER implement anything in CLI without a design prompt from chat.
Every CLI session starts by reading CLAUDE.md and relevant SKILL.md files.
Every CLI session ends by updating CLAUDE.md with what was done and what changed.

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
---

## WORKING MODE (CRITICAL — read first)

PLANNING / RESEARCH / BRAINSTORMING / LEARNING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION / FILE EDITING → Claude Code CLI only.

Chat produces architecture decisions, experiment designs, CLI prompts.
CLI receives those prompts and executes them — nothing more, nothing less.

Every CLI session:
1. Read CLAUDE.md completely
2. Read relevant SKILL.md
3. Read SENSOR_CHARACTERISATION.md if touching HX711 or weight
4. Read LEARNINGS_AND_INSIGHTS.md for known bugs and fixes
5. Execute the design prompt from chat
6. Update CLAUDE.md with what changed and current state

---

## HOW TO APPROACH ANY PROBLEM — THINKING RULES

### Planning and design (chat phase)

Before designing anything:
1. Understand the real-world requirement first — not the technical requirement
   Example: don't ask "how many samples?" — ask "what is the smallest gas
   change we need to detect?" Then derive the sample count from that.

2. Derive from first principles — never accept a number without a source
   Every constant must come from measurement or calculation, not intuition.
   "It worked before" is not a reason. "Derived from 3.15g/min burn rate" is.

3. Challenge every assumption — especially inherited ones
   Ask: where did this number come from? What breaks if it's wrong?
   If the answer is "I don't know" — that's what needs to be fixed first.

4. Design modularly — one verified unit before the next
   Never design a 500-line sketch. Design hx711.cpp, verify it works,
   then add tare.cpp, verify, then add noise.cpp, verify. Layer by layer.

---

### Debugging (when something goes wrong)

**Step 1 — reproduce exactly**
Before diagnosing, confirm the symptom is consistent and reproducible.
A flaky bug is harder to fix than a consistent one. Make it consistent first.

**Step 2 — read before touching**
Read the full file. Read LEARNINGS_AND_INSIGHTS.md. Read this CLAUDE.md.
The bug may already be documented. Patch-without-reading wastes everyone's time.

**Step 3 — think from atomic level**
Every bug is ultimately an instruction doing the wrong thing.
The processor fetches an instruction, decodes it, executes it.
One of those steps is wrong. Find which one.

Ask: at the moment the wrong value appears, what exactly is in memory?
Not "what should be there" — what IS there?

Example from 2026-05-05:
- Symptom: sum=0.000000 despite real array values
- Wrong diagnosis: "double is broken" (not proven)
- Correct approach: print sum after loop, print individual array values
- Result: array had real values, loop produced zero — isolated to the loop
- Then: tried float instead — worked → double accumulator is the issue

**Step 4 — one diagnostic at a time**
Add one print statement. Deploy. Read the output. Form a new hypothesis.
Don't add 10 print statements at once — you won't know which one told you what.

**Step 5 — distinguish symptoms from root causes**
sum=0 is a symptom. "double arithmetic broken" might be the cause.
Fix the root cause, not the symptom. Unless the root cause is unknown
and fixing the symptom unblocks progress — in which case document the
open question in LEARNINGS_AND_INSIGHTS.md and move forward.

**Step 6 — never patch what you don't understand**
If you don't know why a fix works, write it down as an open question.
Patches without understanding become the next session's mystery bug.

---

### When to stop debugging and move forward

- If the symptom is fixed and the root cause is documented as an open question
- If 3 different diagnostic approaches all point to the same cause
- If the fix is correct regardless of the exact root cause

When to NOT stop:
- When the fix makes the symptom disappear but could mask a deeper problem
- When the root cause affects other parts of the system

---

## HX711 RULES (hardware-verified, never override)

DT=D7, SCK=D6 — never change
noInterrupts() wraps 24-bit read — never remove
delayMicroseconds(1) after every GPIO edge — never remove
All four corrupt filters on every read:
  if (r == LONG_MIN) — wait_ready timeout
  if (r == -1)       — all bits HIGH
  if (r == 0x7FFFFF) — positive saturation
  if (r < -5000000L || r > 5000000L) — out of physical range

One sample per loop() iteration — never use blocking while loops
millis() pacing at TOP of loop() — never inside state cases
float only — never use double in MCU sketch
Bridge.provide() not Bridge.on() in Python
App.run() is last line of main.py

---

## NEVER DO THESE (each caused a real bug)

| Never do | Why | Bug date |
|----------|-----|----------|
| while(count < N) inside state case | Bridge interrupt accumulation → timeouts | 2026-05-05 |
| double accumulator in for loop | sum=0 on STM32U585 | 2026-05-05 |
| double array on stack in loop() | Stack corruption → hang | 2026-05-05 |
| Tare with weight on scale | cal_factor ≈ 0 → CAL_FAIL | 2026-05-05 |
| @Bridge.on() in Python | AttributeError — doesn't exist | 2026-05-02 |
| Bridge.notify before Python ready | Message lost silently | 2026-05-05 |
| Hardcode threshold_g | Wrong for every environment except bench | 2026-05-05 |
| Hardcode cal_factor | Wrong for every load cell mounting | 2026-05-04 |
| millis() guard inside state case | Stale reads, std=4224g | 2026-05-04 |
| Monitor.begin() | Hangs MCU if Python handler missing | 2026-05-02 |
| D2-D5 for HX711 | Timer conflicts → 0x7FFFFF constant output | 2026-05-02 |
