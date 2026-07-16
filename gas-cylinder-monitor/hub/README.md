# hub/ — UNO Q Python Hub

This directory contains the Python hub for the gas-cylinder-monitor.
Status: EMPTY — scaffold only. Group 2 (transport) has not been done yet.

---

## What This Hub Does

- Receives `{grams, quality, sigma}` from ESP32-C3 node over WiFi
- Stamps timestamp on receipt (ESP32-C3 has no RTC)
- Derives cylinder steel via anchor events: `steel = gross_at_install − 14.2 kg`
- Computes gas remaining and %: `gas% = (grams − steel) / 14200 × 100`
- Stores to SQLite (readings every 15 min, refill_events per cylinder change)
- Runs analytics: burn rate, consumption patterns
- Runs prediction: days remaining with confidence
- Serves WebUI dashboard (Flask / Socket.IO)

**Does NOT:** touch an HX711, call Bridge.notify, or see raw ADC counts.

---

## Platform

- Arduino UNO Q AQ3 at 192.168.1.161
- App Lab Docker container (Python inside Docker)
- QRB2210 Linux (Debian)
- `/app` inside container = this hub/ directory on host

---

## Toolchain

Same App Lab / Bridge / Python patterns as home-hub. Reference:
- `docs/platform/UNO_Q_Part2_AppLab_Bridge.md`
- home-hub source at `~/ArduinoApps/home-hub/` for patterns

**Note:** The UNO Q's STM32U585 MCU is idle in V1. All sensing is done by the ESP32-C3.
Hub Python never calls Bridge (no Bridge.provide, no Bridge.call) for sensor data.

---

## Wheels / TypeLibs

When WebUI phase (Group 7) begins, copy from home-hub:

```bash
cp -r ~/ArduinoApps/home-hub/wheels/    hub/wheels/
cp -r ~/ArduinoApps/home-hub/typelibs/  hub/typelibs/
cp ~/ArduinoApps/home-hub/assets/socket.io.min.js  hub/assets/
```

Do NOT copy now. Do NOT commit wheels/ to git (.gitignore covers it).

---

## JCTL Warning

UNO Q JCTL header = 1.8V ONLY. 3.3V on any JCTL pin = immediate hardware damage.
