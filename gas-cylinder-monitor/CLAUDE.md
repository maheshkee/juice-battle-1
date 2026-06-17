# CLAUDE.md — gas-cylinder-monitor
# Board: Arduino UNO Q AQ3 | IP: 192.168.1.161 | user: arduino
# Last updated: 2026-06-17
# Read this FULLY before doing anything in this directory.

---

## What This Product Is

LPG cylinder weight monitor for Indian households. An **ESP32-C3 sensor node** reads a
20 kg load cell via HX711, computes gross weight in grams, sends
`{grams, quality, sigma}` over BLE to the **UNO Q hub**. The hub stamps a timestamp,
derives cylinder steel via anchor events, computes gas %, stores in SQLite, runs analytics
and prediction, and serves a WebUI.

Development phase uses water in a container — not a gas cylinder. Weight is weight.
No code path may be hardcoded for "gas" semantics.

```
Load cell → HX711 → ESP32-C3 (grams) ──BLE──▶ UNO Q hub (everything else)
            [------ node/ ----------]           [-------- hub/ --------------]
```

---

## Two Contexts — NEVER Blur These

The single biggest failure mode is writing node code in the hub or hub logic in the node.

---

### node/ context — ESP32-C3

**Board:** ESP32-C3 (in hand). Flashed via Arduino IDE / PlatformIO.
NOT App Lab, NOT Bridge, NOT Bridge.notify — ESP32 has no Bridge.

**Owns:**
- HX711 raw bit-bang (24-bit + 25th gain pulse)
- Three corrupt filters (LONG_MIN, -1, 0x7FFFFF)
- N-sample averaging
- Scale-zero tare (self-computing, never hardcoded)
- cal_factor derivation (never hardcoded; VOID the old STM32 value of 106.7)
- Noise characterisation (N=200 lab, N=50 production)
- BLE send → payload: `{grams: float, quality: "GOOD"|"DEGRADED"|"FAILED", sigma: float}`

**Node outputs grams only.** Never computes gas %. Has no clock, no history,
no steel knowledge.

**SAFETY GATE — check before powering:**
HX711 VCC is 5V. ESP32-C3 GPIO is 3.3V. **DOUT/SCK logic levels vs ESP32-C3 GPIO
tolerance must be verified before applying power. Level-shift if needed.**
This is the first gate of E-000. Do not skip it.

**Pins:** TBD at bring-up. The old DT=D7/SCK=D6 rule was an STM32U585 timer-conflict
constraint. It does **NOT** apply to the ESP32-C3. Pick any two GPIO; validate on ESP32.

**cal_factor:** The old value of 106.7 raw/g was STM32U585-specific. It is **VOID** on
ESP32-C3. Re-derive completely during E-000/calibration experiments.

**float vs double:** The double-broken bug (sum=0 on STM32U585) was platform-specific.
Re-verify on ESP32-C3. Use float as safe default until verified on hardware.

**No Bridge, no App Lab, no delay(3000)/Bridge.begin():** those are UNO Q App Lab
patterns only. ESP32-C3 firmware is standard Arduino/PlatformIO with WiFi libraries.

---

### hub/ context — UNO Q QRB2210 Linux

**Board:** UNO Q AQ3 at 192.168.1.161. App Lab / Docker / Python world.

**Owns:**
- BLE receive via BlueZ (listen for GATT notify from ESP32)
- Timestamp stamping on receipt (ESP32-C3 has no RTC)
- Cylinder steel derivation (anchor events from SQLite history)
- `gas% = (grams - steel) / 14200 × 100`
- SQLite storage (readings + refill_events tables)
- Analytics + burn rate + prediction
- WebUI (Flask / Socket.IO dashboard)
- BLE alerts (future)

**Hub NEVER touches:**
- A raw HX711 count
- A pin or bit-bang operation
- Any sensor register or timing
- Hub starts at "receive grams via BLE" — nothing before that

**Wheels/typelibs/socket.io:** live in home-hub/ — one `cp` away when WebUI phase arrives.
Do NOT copy now. Do NOT commit wheels/ to git.

---

## Non-Negotiable Rules (Both Contexts)

| Rule | Detail |
|------|--------|
| No hardcoding | cal_factor, tare, steel, thresholds — all derived or from config. No buried constants. |
| HX711 raw bit-bang | No external HX711 library. Copy from reference-code/stm32-hx711-modular/ PORT THE LOGIC, not the code. |
| Node→hub payload is grams | Never raw ADC counts. Never gas %. The seam is always grams. |
| Modules return {value, quality, diagnosis} | Never just a bool. GOOD/DEGRADED/FAILED enables graduated response. |
| Small → verify → compound | One chunk at a time, gated by hardware verification. Never jump ahead. |
| Adaptive retry | Never halt in production. 2s/10s/30s/60s backoff + degraded operation. |
| No blocking in state cases | One sample per loop() iteration. millis() pacing at TOP of loop(). |
| float is safe default | Re-verify double on ESP32-C3 before using it. |

---

## Every-Session Read Order

Before writing a single line of code:

1. `~/ArduinoApps/gas-cylinder-monitor/CLAUDE.md` ← this file
2. `~/ArduinoApps/WORKING_MODE.md`
3. `docs/PLAN.md` ← chunk-groups, where we are
4. `docs/SCOPE.md` ← V1 locked scope
5. `docs/PROJECT_CONTEXT.md` ← one-screen current state
6. `docs/HANDOFF.md` ← what the last session left
7. Relevant `docs/reference/specs/` for the current chunk-group
8. The design prompt from chat

Do not touch code until all eight are read.

---

## Hub Self-Contained Rule

Hub wheels/, typelibs/, and socket.io.min.js are built/copied by hub/setup.sh
from system sources only. No dependency on other projects.
Never copy from home-hub or youtube-display — those may not exist in production.
Do not commit wheels/ to git (.gitignore covers it).

NOTE 2026-06-15: hub/ is now self-contained. setup.sh builds wheels from source.
The home-hub copy pattern above is superseded for gas-cylinder-monitor hub.

---

## Current State — 2026-06-17 (SESSION2)

Status:         Node Layer 1 COMPLETE + 3E-006B COMPLETE
Production sketch: node/gas_monitor_v1/gas_monitor_v1.ino
Modules:        hx711, tare, noise, cal, weight, ble, health, journal — all .h/.cpp

Transport:      BLE-only (WiFi removed entirely)
Platform:       3-cell YZC-161A parallel → HX711 → ESP32-C3 SuperMini
Wiring locked:
  ESP32-C3 GPIO4=DT, GPIO3=SCK, 3V3=VDD, GND=GND
  All 3 red→E+, all 3 black→E−, all 3 green→A+, all 3 white→A−
  Direct soldered/twisted — NOT breadboard

Arduino IDE locked:
  esp32 by Espressif v3.0.7, Board: ESP32C3 Dev Module
  Port: COM11, USB CDC On Boot: ENABLED
  Libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon

Verified hardware values:
  cal_factor:   ~36 raw/g (3-cell parallel, derived every boot — never hardcoded)
  sigma:        3.48–5.33g (boot-to-boot variation — wider range observed SESSION2)
  zero accuracy: ±3g
  weight accuracy: ±7g across 200g–1700g
  threshold_g:  4 × sigma (~14–21g depending on boot sigma)
  linear range: 200g–1700g
  min detectable removal: 20g (1 trial SESSION2), hard floor 10g

Boot timing (verified 2026-06-17):
  SETTLE: ~2.1s
  TARE:   ~21s (200 samples × 100ms)
  NOISE:  ~20s (200 samples × 100ms)
  CAL:    variable (waits for human input)
  Total boot: ~60s excluding CAL wait

Journal format (1D — verified 2026-06-17):
  #SEQ t=T boot=B [TAG] event=NAME key=val key=val
  Tags: [BOOT] [RUN] [HB] [FAULT]
  Events: START, PHASE_COMPLETE, BOOT_COMPLETE, QUALITY_CHANGE,
          WEIGHT_EVENT, HEARTBEAT, PHASE_FAIL
  Boot counter persisted in config.json

weight_update() API (updated SESSION2):
  Signature: weight_update(long raw, float tare_raw, float cal_factor, float sigma_g) — 4 args
  Delay-line detector: 20-tick delay line, s_event_pending lockout flag
  Returns: WeightResult with event (NONE/PLACED/REMOVED) and delta fields

journal_run() API (updated SESSION2):
  Signature: journal_run(float grams, float sigma, const HealthResult&, WeightEvent, float delta) — 5 args

Known TODOs (deferred, tracked):
  TODO 1B-stuck:       tare_variance_raw=0.0f — stuck check always fails
                       Fix: update TareResult struct to expose variance
  TODO 1B-persistence: prev_cal_factor/prev_sigma_g not read from config.json
                       Fix: read/write at boot and after CAL_SUCCESS

Hub status: DEPLOYED skeleton at arduino@AQ3 gas-cylinder-monitor/hub
            WebUI at AQ3:7000 — no gas logic yet
            BLE subscriber: _check_known_devices() fix applied (SESSION2)

Current position: 3E-006B COMPLETE. min detectable removal = 20g (1 trial).
Next action:      3E-007B — repeat 3 trials to confirm 20g minimum.
                  Design in chat. Implement via Claude Code CLI on ESP32-C3.

Backlog:
  1E: BLE journal transport — see PROJECT_CONTEXT.md for design.
      Not yet implemented. Do not confuse with existing BLE weight notify.
      Requires a second BLE characteristic, separate UUID.

---

## NEVER DO (each caused a real bug — see docs/LEARNINGS.md for full history)

| Never do | Why | Context |
|----------|-----|---------|
| while(count < N) inside state case | Bridge interrupt accumulation → timeouts | STM32 bug 2026-05-05 |
| double accumulator in for loop | sum=0 on STM32U585 | STM32-specific bug |
| double array on stack in loop() | Stack corruption → hang | STM32-specific bug |
| Tare with weight on scale | cal_factor ≈ 0 → CAL_FAIL | Both platforms |
| @Bridge.on() in Python | AttributeError — doesn't exist | App Lab only |
| Bridge.notify before Python ready | Message lost silently | App Lab only |
| Hardcode threshold_g | Wrong for every environment | Both platforms |
| Hardcode cal_factor | Wrong for every load cell mounting + VOID on ESP32 | Both platforms |
| millis() guard inside state case | Stale reads | Both platforms |
| Monitor.begin() | Hangs MCU if Python handler missing | App Lab only |
| D2–D5 for HX711 on STM32 | Timer conflicts → 0x7FFFFF | STM32 ONLY, void on ESP32 |
| Use DT=D7/SCK=D6 on ESP32 | Those are STM32 timer-conflict constraints only | ESP32: pick any GPIO |
| Use cal_factor=106.7 on ESP32 | STM32 figure, VOID on ESP32-C3 | ESP32 bring-up gate |
| Skip 3.3V logic-level check | May damage ESP32-C3 GPIO or get corrupt reads | SAFETY gate |
| Use bleak service_uuids filter alone on QRB2210 | Filter ignored - returns all BLE devices | Use name filter in app layer (L-020) |
| Hardcode device MAC address | Breaks on hardware replacement/repair | Store in config.json, self-provision |
| Use "auto" BLE scan transport on QRB2210 | Kills Bluetooth adapter | Use "le" only |
| Start hub Python before BlueZ ready | BLE scan fails silently | Use After=bluetooth.target in systemd |
| RemoveDevice before Connect on fresh BLE discovery | Deletes the D-Bus object → UnknownObject error | BlueZ QRB2210 |
| "auto" transport in SetDiscoveryFilter | Kills BT adapter on QRB2210 | Hardware bug |
| deploy app without restarting socat service | dbus.sock may not exist | Hub |
| Hardcode APP_NAME in hub scripts | Read from app.yaml — folder name ≠ app name | Hub |
| List package names in requirements.txt for wheels | Must be /app/wheels/ file paths | Hub |
| Detect weight events by tick-to-tick delta in journal.cpp | journal is a service module — detection belongs in weight.cpp (computation module). Cross-module detection causes cascade events. | Node 2026-06-17 |

---

## Known assumptions

- noise_recompute_sigma() assumes s_samples[] is in raw-count units.  Only valid when called after boot-sequence noise char (cal_factor=0 path).  Do not call after any recalibration flow without reviewing this assumption.

- health.cpp: tare_variance_raw is always 0.0f — tare.h does not yet expose variance. Stuck check (bit 1) always passes. TODO 1B-stuck: update TareResult struct to include a variance field and pass it through the orchestrator.

- health.cpp: g_prev_cal_factor and g_prev_sigma_g are set from the current boot only — no config.json persistence yet. Cal drift and erratic checks skip every boot via the -1.0f first-boot sentinel. TODO 1B-persistence: read prev values from config.json at startup (before STATE_SETTLE), write cur values to config.json after CAL_SUCCESS.

- health.cpp: noise_recompute_sigma() unit assumption (raw-count samples) is unchanged — the recomputed sigma fed into health_check() is only valid on the standard single-boot sequence. See noise_recompute_sigma() assumption above.
