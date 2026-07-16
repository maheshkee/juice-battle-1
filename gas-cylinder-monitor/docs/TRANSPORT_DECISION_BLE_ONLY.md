# TRANSPORT_DECISION_BLE_ONLY.md
# Gas Cylinder Monitor — Transport Architecture Decision Record
# Decision date: 2026-06-05
# Status: LOCKED. Do not re-open without boss approval.

---

## Decision summary

Transport is BLE-only. WiFi is removed entirely from V1.

Previous plan (WiFi) is superseded. This document is the authoritative record.

---

## Why this decision was made

WiFi requires credential provisioning on a headless ESP32 — no display, no keyboard.
All workarounds (captive portal, BLE provisioning app, hardcoded credentials) add user
friction. Boss decision: eliminate WiFi entirely. BLE sidesteps provisioning completely.
ESP32 advertises, hub connects. Zero user setup for transport.

Range constraint acknowledged and accepted: hub must be within ~5–10m of cylinder
(line of sight) or ~3–5m through walls. Kitchen placement assumed. Boss signed off.

---

## What changes vs the original WiFi plan

| Item | WiFi plan (superseded) | BLE plan (locked) |
|---|---|---|
| Transport | WiFi → router → hub | BLE direct ESP32 → hub |
| ESP32 firmware | WiFi stack + MQTT/HTTP client | BLE GATT server only |
| Hub receiver | MQTT subscriber or HTTP endpoint | BlueZ scan + connect + subscribe |
| Provisioning | SSID + password required | None — no credentials ever |
| Range | Whole home | 5–10m line of sight |
| Dependency | Home router | None |

**What does NOT change:**
- Seam contract: `{grams, quality, sigma}` — identical
- Hub stamps timestamp on receipt — unchanged
- Groups 3–7 (storage, domain, analytics, prediction, WebUI) — completely unchanged
- Group 1 (ESP32 node firmware, HX711, grams output) — completely unchanged

---

## Locked V1 BLE transport contract

```
Transport         : BLE only. No WiFi. No MQTT. No HTTP. Ever.
Topology          : hub-initiated.
                    ESP32 advertises forever.
                    Hub scans → finds ESP32 by service UUID → connects → subscribes.
Sampling rhythm   : 15-min heartbeat (always)
                    + event-driven push on significant weight drop
Delivery          : best-effort. No guaranteed delivery.
                    Readings lost during BLE disconnect are acceptable for V1.
Reconnect         : hub auto-reconnects within 30 seconds, silently, no user action.
Local storage     : none on ESP32. No flash writes. No buffering. No sync.
                    If BLE is down when a reading is ready — reading is discarded.
Seam contract     : {grams: float, quality: GOOD|DEGRADED|FAILED, sigma: float}
                    Hub stamps timestamp on receipt. ESP32 has no RTC.
```

---

## ESP32-C3 firmware behaviour (conceptual, not implementation)

```
BOOT:
  → characterise noise (N=200 samples)
  → derive tare (mean of N=200)
  → start BLE advertising with fixed service UUID
  → wait for hub to connect

LOOP (every 15 minutes — heartbeat):
  → take N=50 samples
  → compute grams, quality, sigma
  → update GATT characteristic value
  → notify hub if connected, discard if not

EVENT (significant drop detected):
  → take N=50 samples immediately
  → update + notify hub if connected, discard if not
```

ESP32 never initiates connection. ESP32 never reconnects. ESP32 just advertises and
pushes. All connection management lives on the hub side.

---

## UNO Q hub behaviour (conceptual, not implementation)

```
BOOT:
  → start BlueZ scan for service UUID
  → when found: connect + subscribe to weight characteristic
  → on notification received: stamp timestamp, store, compute gas%

RECONNECT (if BLE drops):
  → hub detects disconnection
  → restart scan automatically
  → reconnect within 30 seconds
  → resume receiving notifications
  → no user action ever required
```

---

## BLE stack on UNO Q hub

- BLE runs on QRB2210 Linux side via BlueZ — not on STM32 MCU
- Python accesses BlueZ via D-Bus
- Inside App Lab Docker: D-Bus access requires socat socket forwarding from host
- This pattern is known territory from motion-sensor-webui project
- socat command and app.yaml sockets: config from motion-sensor-webui — reuse pattern

---

## UUIDs — to be defined at Group 2 design start (in chat, not in code)

UUIDs must be locked in chat before any Group 2 code is written.
A mismatch between ESP32 firmware and hub Python means they will never connect.
Debugging a UUID mismatch is painful and wastes time.

When Group 2 design begins:
1. Define service UUID (128-bit, random, project-specific)
2. Define weight characteristic UUID (128-bit, random, project-specific)
3. Lock both in this document
4. Use identically in ESP32 firmware and hub Python

Placeholder (replace at Group 2 design):
```
Service UUID         : TBD — define in Group 2 design chat
Weight char UUID     : TBD — define in Group 2 design chat
Characteristic props : NOTIFY (hub subscribes, ESP32 pushes)
Characteristic value : JSON string — {"grams": 29420.5, "quality": "GOOD", "sigma": 2.3}
```

---

## What Group 2 must build

### ESP32-C3 side (node/)
- BLE GATT server with one service, one notify characteristic
- Advertising loop — continuous, fixed UUID, fixed device name
- On hub subscribe: start sending weight notifications at heartbeat rhythm
- On hub disconnect: continue advertising, discard readings until reconnect
- No connection state machine on ESP32 side — hub owns all of that
- Library: Arduino ESP32 BLE (BLEDevice, BLEServer, BLECharacteristic, BLEDescriptor)

### UNO Q hub side (hub/)
- BlueZ scan for ESP32 service UUID
- Connect + subscribe to weight characteristic
- On notification: parse JSON, stamp timestamp, pass to storage layer
- Auto-reconnect loop with 30-second target recovery time
- socat D-Bus forwarding — copy pattern from motion-sensor-webui
- Language: Python (App Lab)

---

## What Group 2 does NOT build

- No WiFi stack anywhere
- No MQTT broker
- No HTTP endpoints
- No local storage or sync on ESP32
- No user-facing pairing UI (hub finds ESP32 automatically by UUID)
- No authentication or encryption (V1 — local home network only)

---

## Gate condition for Group 2

One weight reading travels from ESP32-C3 to UNO Q hub via BLE and arrives correctly
in the hub Python process with hub-stamped timestamp.
Reconnect after hub reboot completes within 30 seconds automatically.

---

## Files to update when Group 2 begins

- ARCHITECTURE.md — update pipeline diagram (WiFi → BLE)
- INTERFACE_CONTRACTS.md — update transport section
- TRANSPORT_SPECIFICATION.md — rewrite for BLE (currently WiFi)
- CLAUDE.md — update Group 2 description
- PROJECT_CONTEXT.md — update transport entry
- This file — fill in UUIDs once defined

---

## Session start checklist for Group 2 design

Before designing Group 2, confirm:
1. This document is read fully
2. UUIDs are not yet defined — define them first in chat
3. Motion-sensor-webui socat pattern is reviewed for reuse
4. Group 1 is fully PASSED (E-000 through E-002 minimum)
5. Design in chat first, all code via Claude Code CLI

---

*Decision locked 2026-06-05. Do not reopen without boss approval.*
*Next action: complete Group 1 experiments, then design Group 2 using this document.*
