# PLAN.md
# Master Plan — Arduino UNO Q AQ3 Projects
# Last updated: 2026-05-05
# Rule: update this file at the end of every session

---

## Active Board

AQ3 at 192.168.1.161 (password: arduino)

---

## Overall Goal

Build a production gas cylinder monitor for Indian households.
Secondary products: motion-sensor-webui, youtube-display — both parked until
gas monitor experiments conclude.

---

## Critical Path

```
003 noise characterisation ✅ COMPLETE
    ↓
004 modular sketch refactor
    ↓
005 calibration linearity
    ↓
006B measured water removal
    ↓
007B threshold stress test
    ↓
008 temperature drift
    ↓
009 long-run stability
    ↓
010 power cycle recovery
    ↓
011 on-boot calibration flow → config.json
    ↓
012 hybrid architecture
    ↓
home-hub integration
    ↓
gas-cylinder-monitor v0.1
```

---

## Experiment Queue

### ✅ COMPLETE

| # | Name | Key result |
|---|------|-----------|
| 003 | noise-characterisation | STD=1.33–2.36g, THRESHOLD=2.38–4.23g, detector validated |

### 🔜 NEXT SESSION

| Priority | # | Name | Purpose | What you need |
|----------|---|------|---------|---------------|
| 1 | 003 cleanup | Remove DBG lines, remove delay(1) yield from sketch | — |
| 2 | 004 | modular-sketch-refactor | Split flat sketch into modules | Nothing extra |
| 3 | 005 | calibration-linearity | Verify cal_factor across weights | 158g, 300g, 500g weights |
| 4 | 006B | measured-water-removal | Simulate gas consumption | Syringe or measuring cup |
| 5 | 007B | threshold-stress-test | 30min run, count false positives | 30 minutes uninterrupted |

### 📋 QUEUED

| # | Name | Purpose | Dependency |
|---|------|---------|-----------|
| 008 | temperature-drift | Tare drift over 30min | After 007B |
| 009 | long-run-stability | 6hr continuous | After 008 |
| 010 | power-cycle-recovery | Verify recovery from config.json | After 009 |
| 011 | on-boot-calibration-flow | First-boot config.json write pattern | After 010 |
| 012 | hybrid-architecture | Event + scheduled poll combined | After 011 |

---

## Experiment 004 — Modular Sketch Refactor (design locked)

**Goal:** Replace flat single-file sketches with modular structure.
Every new HX711 sketch and home-hub uses same modules.

**Target structure:**
```
sketch/
├── sketch.ino     ← state machine ONLY
├── hx711.h/.cpp   ← bit-bang, wait_ready, corrupt filters
├── tare.h/.cpp    ← self-validating tare
├── noise.h/.cpp   ← noise characterisation, threshold derivation
└── cal.h/.cpp     ← cal_factor derivation
```

**Rules:**
- Refactor 003 sketch first as test case
- Verify identical output before retiring flat version
- hx711.cpp = single source of truth, never diverges between experiments
- Arduino CLI compiles all .cpp files in sketch folder automatically

---

## Experiment 005 — Calibration Linearity

**Goal:** Verify cal_factor is consistent across multiple weights.

**Protocol:**
1. Tare empty scale
2. Place 158g → record raw
3. Place 300g → record raw
4. Place 500g → record raw
5. Compute cal_factor from each
6. Check linearity: all three within ±5% of each other?

**Acceptance:** cal_factor range < 5% across weights → linear, trustworthy
**Failure:** non-linearity → investigate load cell or mounting

---

## Experiment 006B — Measured Water Removal

**Goal:** Find minimum detectable weight removal using controlled subtraction.

**Protocol:**
1. Place container of water on scale (~500g)
2. Stable baseline — confirm TRIGGERED=0
3. Remove water in steps using syringe: 50g, 30g, 20g, 16g, 10g, 5g
4. Each step: wait for delta to stabilise, record TRIGGERED result
5. Find the boundary — smallest removal that reliably triggers

**What you need:** Syringe or precise measuring cup

**Acceptance:** 16g removal → TRIGGERED=1 consistently
**Key finding:** actual minimum detectable removal on this hardware in this environment

---

## Experiment 007B — Threshold Stress Test

**Goal:** Measure false positive rate over 30 minutes with no weight change.

**Protocol:**
1. Place stable weight on scale (e.g. 500g cylinder)
2. Run DELTA_RUNNING for 30 minutes
3. Count TRIGGERED=1 events with no weight change
4. Acceptable rate: < 2 false triggers per hour

**Acceptance:** < 1 false trigger per 30 min run
**Failure:** > 5 false triggers → threshold needs to be higher or
             temporal validation (N consecutive windows) required

---

## Home-Hub Integration (after all experiments complete)

### MCU sketch changes

```
First-boot state machine:
BOOT → TARE → NOISE_CHAR → CAL → write config.json → RUNNING

RUNNING loop:
- Sliding window delta detector → Bridge.notify("weight_event", data)
- Scheduled 6hr snapshot → Bridge.notify("weight_snapshot", data)
```

### Python main.py changes

```python
Bridge.provide("weight_event", on_weight_event)
Bridge.provide("weight_snapshot", on_weight_snapshot)
```

### splash.html gas dashboard

- Current weight display
- Days remaining (with confidence)
- Last refill date
- Consumption trend chart

---

## Gas Cylinder Monitor — Product Roadmap

| Version | Scope | Status |
|---------|-------|--------|
| v0.1 | HX711 reading, self-characterising boot, weight widget | Experiments phase |
| v0.2 | 6hr measurement cycle, SQLite storage | After experiments |
| v0.3 | 7-day prediction, days_left display | After v0.2 |
| v0.4 | BLE alert when days_left < 5 | After v0.3 |
| v0.5 | Refill detection (>8kg jump = new cylinder) | After v0.4 |
| v1.0 | Complete sellable product | — |
| v1.5 | 4-cell upgrade, improved BLE | — |
| v2.0 | Smart alerts, anomaly detection | — |
| v3.0 | Multi-cylinder IoT network | — |

---

## Other Active Products (parked)

### motion-sensor-webui

| Version | Scope | Status |
|---------|-------|--------|
| v1.0 | SR602 PIR + web dashboard | ✅ Complete |
| v1.1 | MCU LEDs red/green | ✅ Complete |
| v1.2 | BLE advertisement from AQ2 Linux | 🔵 Parked |
| v1.3 | AQ1 MCU BLE beacon (friend's ESP32-C3) | 🔵 Parked |

### youtube-display

| Version | Scope | Status |
|---------|-------|--------|
| v1.3 | Queue engine, local MP4, Socket.IO, BLE EVT | ✅ Complete |
| v2.0 | Date-scheduled queues (Harsha's requirement) | 🔵 Parked until home-hub complete |

---

## Key Locked Constants (hardware-verified)

```
DT=D7, SCK=D6                  — never change
CAL_FACTOR range: 100–107      — always self-compute
TARE range: -12799 to -13737   — always self-compute
NOISE STD range: 1.33–2.36g    — varies, always self-compute
THRESHOLD range: 2.38–4.23g    — derived from STD
MIN EVENT: 16g                 — tea/coffee, 5 min
FALLBACK threshold: 8.0g       — if characterisation fails
wait_ready timeout: 400ms      — tuned for AQ3 under Bridge load
millis() pacing: 120ms         — at TOP of loop() only
```

---

## What to Bring Next Session

- Syringe or measuring cup (for 006B)
- 300g and 500g known weights (for 005, or improvise with water)

---

## Change Log

| Date | Change |
|------|--------|
| 2026-05-05 | Created — experiment 003 complete, full queue defined, product roadmap added |
