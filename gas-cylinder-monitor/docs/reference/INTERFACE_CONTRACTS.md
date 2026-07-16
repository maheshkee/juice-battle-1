# INTERFACE_CONTRACTS.md — Gas Cylinder Monitor
# Last updated: 2026-06-04 (ESP32 pivot — complete rewrite)
# Status: Active. STM32/Bridge contracts below are SUPERSEDED.

---

## 1. Node → Hub Transport Contract  [REASONED — provisional, not yet hardware-verified]

The primary seam in the system. ESP32-C3 node sends; UNO Q hub receives.

### Payload (node → hub, every reading)

```json
{
  "grams":   29420.5,
  "quality": "GOOD",
  "sigma":   2.3
}
```

| Field | Type | Owner | Description |
|-------|------|-------|-------------|
| `grams` | float | node | Gross weight in grams (steel + gas). Not kg. Not %. Not raw counts. |
| `quality` | string | node | Node's assessment: `"GOOD"` / `"DEGRADED"` / `"FAILED"` |
| `sigma` | float | node | Noise std from node's most recent noise characterisation (grams) |

## 1.1 SEAM EXTENSION — approved 2026-07-07, boss-approved

Payload extended from {grams, quality, sigma} to:

```json
{ "grams": 29420.5, "quality": "GOOD", "sigma": 2.3, "temp_c": 31.4 }
```

| Field | Type | Owner | Description |
|---|---|---|---|
| temp_c | float or null | node | Platform-local temperature from DHT22 (GPIO5), co-located with load cell. `null` if DHT22 read failed. |

Rationale: temperature must travel with the physical sensor node, not the hub, to remain correct if hub and platform are ever decoupled. Existing {grams, quality, sigma} semantics, quality states, and timestamp-on-receipt rule are unchanged.

Hub compatibility: `temp_c` is absent in pre-extension firmware payloads. Hub treats missing and `null` identically — stores `NULL` in `readings.temp_c`.

---

**What is NOT in the payload:**
- `timestamp` — stamped by HUB on receipt (ESP32-C3 has no RTC)
- `raw` — raw ADC counts never leave the node
- `tare_raw` — node's internal calibration constant, never shared
- `cal_factor` — node's internal calibration constant, never shared
- `gas_pct` — computed by hub, not node
- `steel` — derived by hub, not node

### Quality semantics

| Value | Meaning | Hub should |
|-------|---------|-----------|
| `GOOD` | N-sample average, all reads non-corrupt, sigma below threshold | Trust, store, compute |
| `DEGRADED` | Noisy or partial — best available reading | Store with flag, surface warning |
| `FAILED` | Cannot produce a valid reading | Log, do not store as measurement |

### Transport protocol (V1 locked: WiFi)

Transport over WiFi (MQTT-style or HTTP POST — details in specs/TRANSPORT_SPECIFICATION.md).
BLE fallback parked for v1.x. The payload contract is transport-agnostic.

---

## 2. Module Result-Struct Contract (Both Node and Hub)

Every functional module in this system returns a result struct. Never return a raw value
or a plain bool.

```
{
  value:     <the computed number or state>
  quality:   GOOD | DEGRADED | FAILED
  diagnosis: <human-readable string: what went wrong and why, or "" if GOOD>
}
```

### Why not bool

A bool forces binary decisions. Quality levels allow graduated responses:
- `GOOD` → proceed normally
- `DEGRADED` → proceed with warning (show on dashboard)
- `FAILED` → halt this flow, surface to user with specific message

The state machine reads `quality` and routes. It never inspects module internals.

### Node module contracts (ESP32-C3)

**hx711 module:** raw read
```
value:   int (24-bit signed raw count)
quality: GOOD | FAILED (LONG_MIN / -1 / 0x7FFFFF → FAILED)
```

**tare module:** scale-zero computation
```
value:   float (tare_raw — raw ADC offset of empty platform)
quality: GOOD | DEGRADED | FAILED
diagnosis: "Spread X raw — environment noisy" or "Hardware fault suspected"
```

**noise module:** characterisation
```
value:   float (threshold_g — 4-sigma event detection threshold)
quality: GOOD | DEGRADED (sigma above sanity ceiling → wiring fault)
diagnosis: "Sigma Xg, PP Yg, threshold Zg" or "Sigma too high — check analog connections"
```

**cal module:** cal_factor derivation
```
value:   float (cal_factor — raw counts per gram)
quality: GOOD | OUT_OF_RANGE | NEGATIVE | UNSTABLE
diagnosis: "Computed X raw/g" or "Negative — place weight AFTER tare completes" etc.
```

### Hub module contracts (Python)

**steel_derivation module:** anchor event processing
```
value:   float (steel_kg — cylinder empty weight)
quality: GOOD | DEGRADED | CALIBRATING
diagnosis: "Derived from install at Xkg" or "Awaiting anchor event"
```

**gas_estimator module:** gross → gas%
```
value:   {"gas_kg": float, "gas_pct": float}
quality: GOOD | DEGRADED (steel not yet derived)
diagnosis: "Gas Xg (Y%), steel Zg" or "Steel not yet known — showing interval [A, B]"
```

---

## 3. Hub ↔ WebUI Contract (Socket.IO events, Python → Browser)

```python
# Push pattern — always use this
ui.send_message("event_name", {payload})
```

| Event | Payload | When |
|-------|---------|------|
| `weight_update` | `{grams, gas_kg, gas_pct, quality, ts}` | Every heartbeat receipt |
| `gas_prediction` | `{days_left, burn_rate_g_per_day, confidence}` | After MIN_HOURS_BURNRATE |
| `state_update` | `{state: "UNINSTALLED"|"TRACKING"|"LOW_GAS"}` | On state transition |
| `low_gas_alert` | `{gas_kg, days_left}` | When state enters LOW_GAS |

---

## 4. Node Payload — Config Values (from docs/SCOPE.md)

```python
# Cylinder detection
REFILL_THRESHOLD_KG    = 6.0   # G jump between readings → new cylinder installed
CAPACITY_KG            = 14.2  # BIS domestic regulation IS 3196
CYLINDER_REMOVED_KG    = 2.0   # G below this → cylinder absent

# Alert thresholds
LOW_GAS_KG             = 2.0
LOW_GAS_DAYS           = 10

# Heartbeat
HEARTBEAT_MIN          = 15    # one weight snapshot every N minutes
```

---

## SUPERSEDED — STM32/Bridge Era Contracts

> The following contracts are VOID. Kept here as history only.
> In the new architecture, Bridge.notify and Bridge.provide are NOT used.
> The ESP32-C3 sends grams over WiFi; it does not use Bridge.

```
[SUPERSEDED — STM32 era]
MCU → Python:    Bridge.notify("weight_event", JSON_string)
Python → MCU:    Bridge.provide("weight_event", handler_function)
Payload:         { "grams": 29.42, "ts": "2026-06-03T08:16:00" }

BLE UUIDs (still valid for home-hub, parked for gas-monitor):
  Service:  a01c0000-0000-0000-0000-000000000000
  CMD char: a01c0001-0000-0000-0000-000000000000 (WRITE)
  EVT char: a01c0002-0000-0000-0000-000000000000 (NOTIFY)
```
