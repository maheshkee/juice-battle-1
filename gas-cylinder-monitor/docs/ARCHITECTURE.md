# ARCHITECTURE.md — gas-cylinder-monitor
# Modular structure for production node and hub
# Last updated: 2026-06-12

---

## Overview

Two independent codebases. The seam between them is always:
`{grams: float, quality: GOOD|DEGRADED|FAILED, sigma: float}` over BLE GATT notify.
Neither side ever crosses into the other's domain.

```
Load cell → HX711 → ESP32-C3 (node/) ──BLE──▶ UNO Q hub (hub/)
```

---

## node/ — ESP32-C3 firmware (Arduino C++)

```
node/
├── sketch.ino          orchestrator only — boot sequence + loop(), calls modules
├── hx711.h/.cpp        bit-bang, corrupt filters (LONG_MIN, -1, 0x7FFFFF)
├── tare.h/.cpp         stability gate, N-sample tare derivation
├── noise.h/.cpp        floor characterisation, STD + threshold derivation
├── weight.h/.cpp       grams + quality struct {value, quality, sigma}
├── ble.h/.cpp          GATT server + notify, deviceConnected flag
└── config.h/.cpp       config.json read/write (cal_factor, UUIDs, thresholds)
```

### Module responsibilities

| Module | Inputs | Outputs | Owns |
|--------|--------|---------|------|
| hx711 | GPIO4 (DOUT), GPIO3 (SCK) | raw int32 | 25-pulse bit-bang, noInterrupts(), sign-extend, 3 corrupt filters |
| tare | N raw reads | tare_raw float | dynamic stability gate (spread + inter-window drift), post-settle mean |
| noise | N raw reads + tare | noise_std_raw, threshold_raw | N=200 STD derivation, 4× threshold rule |
| weight | raw + tare + cal_factor | {grams, quality, sigma} | subtract tare, divide by cal_factor, GOOD/DEGRADED/FAILED |
| ble | {grams, quality, sigma} | BLE notify | GATT server, CCCD subscribe, notify loop, reconnect |
| config | filesystem | cal_factor, UUIDs, etc. | LittleFS JSON read/write, never hardcode values |

### sketch.ino boot sequence

```
Phase 0: power-on settle (wait for creep to finish — variable, can be 160s+)
Phase 1: tare derivation (unloaded, after settle)
Phase 2: noise characterisation (N=200, BLE off for lab; N=200 BLE on for production)
Phase 3: BLE advertise
Phase 4: loop — sample → compute → notify if connected, discard if not
```

### Locked hardware values (2026-06-12)

```
GPIO4 = DOUT, GPIO3 = SCK
HX711 VCC = 3.3V (DOUT safe for ESP32-C3 GPIO — no level shifter)
cal_factor = 36.1 raw/g  (3-cell YZC-161A parallel, shared plate — LOCKED 2026-06-12)
BLE service UUID:  aa206b91-235b-42aa-b370-453a3feedf35
BLE char UUID:     b9b25bb1-f2a9-4545-b48f-295ab2789f41
BLE device name:   GasCylMonitor
BLE device MAC:    10:00:3B:CD:63:32
```

---

## hub/ — UNO Q QRB2210 Linux (Python)

```
hub/
├── app.py              main Flask app — WebUI routes + Socket.IO push
├── ble_receiver.py     BlueZ subscriber (bleak) — self-provisioning, MAC cache
├── storage.py          SQLite reads/writes (readings + refill_events tables)
├── domain.py           steel derivation, gas% state machine, anchor event logic
├── analytics.py        burn rate, daily consumption, sliding window
├── prediction.py       days remaining, confidence interval
├── config.json         device MAC, UUIDs, cal_factor, cylinder state
└── assets/             WebUI frontend (HTML/JS/CSS — copy from home-hub/ at Group 7)
```

### Module responsibilities

| Module | Inputs | Outputs | Owns |
|--------|--------|---------|------|
| ble_receiver | BLE GATT notify | {grams, quality, sigma, timestamp} | bleak scanner, name filter, MAC provisioning, reconnect loop |
| storage | reading structs | SQLite rows | schema, INSERT, SELECT, migration |
| domain | grams + SQLite history | gas%, steel, cylinder_state | anchor event detection, steel derivation, gas% formula |
| analytics | SQLite history | burn_rate_g_per_day, daily_used | sliding window, session detection |
| prediction | burn_rate + gas_remaining | days_remaining, confidence | linear extrapolation |
| app | all modules | WebUI + Socket.IO | Flask routes, real-time push to browser |

### Hub install

```bash
pip3 install -r hub/requirements.txt --break-system-packages
```

### BLE rules (QRB2210-specific)

```
bleak service_uuids filter: IGNORED by BlueZ on QRB2210 — use name filter in app layer
BLE scan transport: "le" only — "auto" kills QRB2210 Bluetooth adapter
MAC provisioning: null in config.json → scan by name → cache MAC → all subsequent runs use MAC
```

---

## Interface contract — the only seam

```json
{
  "grams":   244.7,
  "quality": "GOOD",
  "sigma":   0.49
}
```

- `quality` = `GOOD` | `DEGRADED` | `FAILED`
- Hub stamps `timestamp` on receipt (ESP32-C3 has no RTC)
- Hub MUST check `quality` before storing or computing gas%
- `FAILED` and `DEGRADED` readings must not be stored as valid weight measurements

---

## What belongs where — decision rule

> "Does this require a pin, a raw count, or a bit-bang operation?"
> YES → node/
> NO → hub/

> "Does this require SQLite history, a timestamp, or gas%?"
> YES → hub/
> NO → node/

The node never knows gas%. The hub never touches raw ADC counts.
