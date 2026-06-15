# CLAUDE.md — gas-cylinder-monitor
# Board: Arduino UNO Q AQ3 | IP: 192.168.1.161 | user: arduino
# Last updated: 2026-06-04 (ESP32 pivot ingested — complete rewrite)
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

## Phase Dependencies — Do NOT Duplicate

Wheels, typelibs, and socket.io.min.js live in `home-hub/` and are one `cp` away:

```bash
cp -r ~/ArduinoApps/home-hub/wheels/     hub/wheels/
cp -r ~/ArduinoApps/home-hub/typelibs/   hub/typelibs/
cp ~/ArduinoApps/home-hub/assets/socket.io.min.js  hub/assets/
```

Copy only when the WebUI phase (Group 7) begins. Never commit wheels/ to git.

---

## Current State - 2026-06-15
Status:         3E-002 COMPLETE AND PASSED (2026-06-15)

3E-001 COMPLETE AND PASSED (2026-06-12)
Experiment series complete:

  E-000  PASSED 2026-06-04  raw bit-bang proven
  E-001  PASSED 2026-06-05  cal_factor single-cell ~106.7 raw/g (VOID on 3-cell)
  E-002  PASSED 2026-06-08  noise floor single-cell BLE-off (VOID on 3-cell)
  E-003  PASSED 2026-06-08  BLE transport single-cell (patterns reused)
  3E-001 PASSED 2026-06-12  cal_factor 3-cell = 36.1 raw/g LOCKED
  3E-002 PASSED 2026-06-15  noise floor 3-cell BLE-off and BLE-on LOCKED

node/ sketches built:
  E000_raw_read, E001_tare_cal_grams, E002_noise_floor,
  E003_ble_transport, 3E001_cal_factor_v5, 3E001_cal_factor_v5_1,
  3E001_cal_factor_v5_2, 3E002_noise_floor_v1, 3E002_noise_floor_v1_ble,
  HW_VERIFY_3CELL, STOP, HW_VERIFY

hub/: empty - not yet started

Wiring locked (do not change without re-verifying):
  ESP32-C3 GPIO4 = DOUT (INPUT_PULLUP), GPIO3 = SCK
  HX711 VDD = 3V3 ONLY - never 5V
  3-cell parallel: all reds → E+, all blacks → E-, all greens → A+, all whites → A-
  Twisted/soldered direct to HX711 terminals - NOT breadboard

Arduino IDE locked:
  esp32 by Espressif v3.0.7, Board: ESP32C3 Dev Module
  Port: COM11, USB CDC On Boot: ENABLED
  SCP to: C:\Users\mahes\Documents\Arduino\

LOCKED CONSTANTS (hardware-verified, never change without re-deriving):
  cal_factor (3-cell parallel, shared plate) = 36.1 raw/g  LOCKED 2026-06-12
  noise_std_g  (BLE off, worst case)         = 4.93g        LOCKED 2026-06-15
  noise_std_g  (BLE on,  worst case)         = 4.64g        LOCKED 2026-06-15
  threshold_g  (BLE on,  production)         = 18.54g       LOCKED 2026-06-15
  BLE EMI penalty on 3-cell platform         = ~1.0x        LOCKED 2026-06-15
  tare_raw: NEVER hardcode - re-derived every boot
  Linear range: 200g - 1800g (verified 3E-001 Stage 3)
  Min reliable weight: ~150g

Current position: 3E-002 COMPLETE. Ready for 3E-003.

Next action:
  Design modular sketch architecture in chat (hx711, tare, noise, weight, ble modules)
  Build 3E-003 BLE transport - ESP32 sends {grams, quality, sigma} to AQ3 hub
  Build hub Python BLE subscriber (bleak, socat pattern from motion-sensor-webui)
  Build minimal WebUI - show weight in grams on screen
  DEMO: boss places weight → hub receives → WebUI shows grams

Target: demo working within 2 days

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
