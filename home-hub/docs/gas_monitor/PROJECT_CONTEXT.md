# Gas Cylinder Monitor — Project Context
# home-hub service | Arduino UNO Q AQ3 | Updated: 2026-04-30

---

## Problem Statement

Indian households use sealed LPG cylinders with no visible gas level indicator. The only current method is to shake the cylinder and guess. The LPG model in India is **replacement, not refill** — when gas runs out, a delivery agent brings a brand-new full cylinder and takes the old empty one away. Each replacement cylinder has a different tare (shell) weight. Households routinely run out of gas mid-cooking with 1–3 days wait for a replacement delivery.

---

## Target User

**Indian homemaker using LPG for daily cooking.**

- Cooks 2–3 meals per day on LPG
- Non-technical — does not open apps to check gas level
- Books refill by phone or app when reminded
- Cares about: never running out unexpectedly, knowing when to call for refill
- Does not care about: raw weight numbers, sensor accuracy, battery life details

---

## Product Summary

A weight sensor permanently mounted under the LPG cylinder. It measures the total weight every 6 hours, subtracts the cylinder tare to compute gas remaining, and calculates how many days until empty based on the household's actual consumption rate. The result is always visible on the home screen — no app needed. A low-gas alert goes to the phone via BLE when fewer than 5 days remain.

This is a service inside **home-hub**. It shares the board, screen, and Flutter app with the YouTube display service.

---

## Platform

| Component | Part | Role |
|-----------|------|------|
| Board | Arduino UNO Q AQ3 (4GB) | Both processors on one board |
| MPU | QRB2210, Debian Linux | Intelligence: SQLite, prediction, UI, BLE alerts |
| MCU | STM32U585, Zephyr RTOS | Real-time: HX711 reading, stability detection |
| Load cell | YZC-161A 20kg, ±0.05% | Measures cylinder + gas weight |
| Amplifier | HX711 24-bit ADC | Amplifies 2mV load cell signal to readable counts |
| Bridge | LPUART1, 9600 baud, MSGPACK | MCU ↔ MPU communication |
| Storage | SQLite (`data/gas_monitor.db`) | Readings, predictions, templates |
| Display | USB-C HDMI LCD (1920×1080) | Always-on weight widget on home screen |
| Phone | Flutter Android app | BLE remote: view status, receive alerts |

**Why dual-processor:** Linux cannot guarantee real-time ADC timing. MCU handles deterministic sensor reading; Linux handles all computation and storage. Clean separation: MCU says "weight=18.42kg, stable=true"; Linux says "6.2kg gas left, ~8 days remaining."

---

## Version History

| Version | Scope | Status |
|---------|-------|--------|
| v0.1 | HX711 reading, weight widget on screen (polling every 2s) | In progress — calibration pending |
| v0.2 | 6hr measurement cycle, SQLite storage, last-read timestamp on screen | Not started |
| v0.3 | 7-day prediction, days_left on screen | Not started |
| v0.4 | BLE alert when days_left < 5, gas_status EVT to Flutter | Not started |
| v0.5 | Refill detection (>8kg weight jump = new cylinder) | Not started |
| v1.0 | Multi-cylinder templates, full sellable product | Not started |

---

## India-Specific Facts (Never Ignore)

- **Replacement model, not refill.** Every new cylinder has a different tare. Tare cannot be learned from the previous cylinder — it is a different object.
- **Strategy:** Use a brand template tare at setup. Infer actual tare from the lowest weight point before each refill event. Apply weighted correction (70% old + 30% new) so the estimate converges over 2–3 cycles.
- **Refill detection rule:** Weight jump > 8kg between consecutive readings = new cylinder delivered.
- **Standard cylinders:** Indane 14.2kg domestic tare ~15.5kg; HP Gas ~15.7kg; Bharat Gas ~15.3kg.
- **Alert lead time:** 5 days is enough to book a refill and wait for delivery.

---

## Critical Constants (from config.py)

| Constant | Value | Location |
|----------|-------|----------|
| REFILL_THRESHOLD_KG | 8.0 | config.py |
| PREDICTION_WINDOW_DAYS | 7 | config.py |
| SENSOR_SAMPLE_COUNT | 20 | config.py |
| GAS_DB_PATH | data/gas_monitor.db | config.py |

All thresholds live in `config.py`. Never hardcode values in `gas_monitor.py` or `sketch.ino`.

---

## Session 2026-05-01 — Weight Pipeline Working

### What Was Built
- home-hub sketch rewritten: D7/D6 raw bit-bang, Bridge.notify("weight_event")
- Python main.py: removed weight_poll_loop, added Bridge.provide("weight_event")
- Calibration factor confirmed: 100.0f
- Accuracy verified: 10g→10.4g, 20g→20.6g, 30g→32.4g, ~235g→233-254g

### Key Learnings
- Bridge.on() does not exist — Bridge.provide() is correct Python API
- RAW=-1 reads must be filtered in hx711_read_average()
- Load cell mounting is critical — free end must be genuinely free
- Wiring: Red→E+, Black→E-, White→A-, Green→A+

### Current State
- Weight reads correctly in logs and on splash.html UI
- CALIBRATION_FACTOR = 100.0f in sketch.ino
- sketch_working_reference.ino saved as backup
- gas_monitor.py: initialized but 6hr cycles not yet active
- SQLite: gas_monitor.db exists, schema created, no readings yet

### Next Steps
1. Proper load cell mechanical mounting (permanent fixture)
2. Re-calibrate with heavier known weight (500g or 1kg) for gas cylinder range accuracy
3. Enable gas_monitor.py 6hr snapshot cycle
4. Build gas dashboard UI on splash.html
