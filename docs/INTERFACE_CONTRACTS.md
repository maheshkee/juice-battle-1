# INTERFACE CONTRACTS — Juice Battle
# Status: current as of 2026-08-20. Replaces the Phase 0 MQTT stub (that
# design was abandoned before S007 — never built; the actual transport is BLE).

All data boundaries between components are defined here. Contract first,
code second — always. Source of truth for the wire format is
`firmware/node/comms.h`; if this doc and the header ever disagree, the
header wins and this doc needs fixing.

---

## 1. ESP32-C3 Node → Hub (BLE GATT notify)

### GATT identifiers (`comms.h`)
```
JB_SERVICE_UUID  7b4c0e00-9aab-11ed-a8fc-0242ac120002
JB_CHAR_UUID     7b4c0f00-9aab-11ed-a8fc-0242ac120002
HUB_MAC          14:B5:CD:E7:41:DD   (AQ3's BLE adapter — nodes reject any
                                       other peer at onConnect())
```

### Message types
| Value | Name | Fires |
|---|---|---|
| `0x01` | `HEARTBEAT` | Every 2000ms (`COMMS_HEARTBEAT_INTERVAL_MS`) |
| `0x02` | `POUR_ACTIVE` | Every 200ms while `STAB_POUR_IN_PROGRESS` |
| `0x03` | `POUR_SETTLED` | One-shot when `STAB_STABLE_SETTLED` fires — the only message the hub scores |
| `0x04` | `CAL_COMPLETE` | One-shot after successful calibration load |
| `0x05` | `SIGMA_ALERT` | One-shot at boot if σ is dangerously high |
| `0x06` | `DIAG` | Every 5000ms (`COMMS_DIAG_INTERVAL_MS`) |

### Payload — 13 bytes, fixed layout, floats via `memcpy` (never cast float*→byte*)

**Standard messages (`0x01`–`0x05`):**
```
Byte  0      version   (COMMS_PAYLOAD_VERSION = 0x01)
Byte  1      msg_type  (COMMS_MSG_*)
Byte  2      node_id   (resolved at boot from BT MAC — see below)
Bytes 3–6    delta_g   (float, little-endian)
Bytes 7–10   sigma_g   (float, little-endian, set once at comms_init)
Bytes 11–12  seq_num   (uint16_t, little-endian, wraps at 65535)
```

**`DIAG` (`0x06`) — different layout for bytes 3–12:**
```
Bytes 3–6    current_g  (float — ema_g, live weight on platform right now)
Bytes 7–10   slope_gs   (float — rate of weight change)
Byte  11     state      (uint8_t, StabilityState enum)
Byte  12     quality    (uint8_t, Quality enum — 0=GOOD, 1=DEGRADED, 2=FAILED)
```

### `node_id` resolution
Not compiled in, not read from `config.h`. `juicebattle.ino`'s
`resolve_node_id()` reads the ESP32's factory BT MAC at boot and looks it up
in a `NODE_MAC_TABLE` — so one identical binary works on either physical
node. Current table:
```
70:AF:09:32:F3:C2  → node 0 (JB-0)
10:00:3B:CD:63:32  → node 1 (JB-1, old chip — retired 2026-08-13)
AC:27:6E:53:DC:4A  → node 1 (JB-1, current chip)
```

---

## 2. `ble_scanner.py` → `transport.py` (TCP `:7001`, NDJSON)

`ble_scanner.py` is GATT central, decodes the 13-byte payload above, and
republishes each event as one JSON object per line on a local TCP server
(`TRANSPORT_HOST=0.0.0.0`, `TRANSPORT_PORT=7001` in `hub/config.py`).
`transport.py` is the TCP client, living inside the main `juice-battle`
process, and hands parsed events to `game.py`.

### Example lines
```json
{"msg":"HEARTBEAT","node":0,"delta_g":0.0,"sigma_g":2.8,"seq":1234}
{"msg":"DIAG","node":1,"current_g":0.0,"slope_gs":0.0,"state":0,"quality":0,"seq":5678}
{"msg":"NODE_CONNECTED","node":0,...}
{"msg":"NODE_DISCONNECTED","node":1,...}
```
`NODE_CONNECTED` / `NODE_DISCONNECTED` are synthesized by `ble_scanner.py`
itself from BlueZ connect/disconnect signals — they have no corresponding
BLE payload from the node.

A ring buffer (`deque`, last 200 events) in `ble_scanner.py` holds recent
events so a reconnecting TCP client isn't starved during a brief gap.

---

## 3. Hub internal module wiring (Python)

`main.py` is the only place that imports and wires the other modules — no
module imports another module directly. Current real modules (not the
originally-planned `receiver.py`/`game_engine.py`/`persona_engine.py`,
which were never built and are empty stubs left from bootstrap):

```
config.py     — all tunable constants, single source of truth
storage.py    — SQLite persistence (hub/data/jb.db)
transport.py  — TCP NDJSON client
game.py       — all scoring/round/session logic
dashboard.py  — Flask + Flask-SocketIO web server, kiosk/ops UI, /state API
ambient.py    — background music + sound effects (pygame.mixer)
```

---

## 4. Hub → Browser (Flask-SocketIO, port 5000)

Full push loop lives in `dashboard.py` (`_push_loop`, runs every 500ms as a
background thread, reads `game.get_state()` under lock). `/state` serves
the same snapshot as plain JSON for polling clients (ops tooling, curl).
For the exact current field set, read `dashboard.py`'s `_push_loop` and
`_state_json` directly — this doc intentionally does not duplicate that
schema, since it has drifted out of sync with actual code before.

---

## 5. Config (`hub/config.py`) — key thresholds

```python
GLASS_VOLUME_G   = 150.0   # grams per scored glass
POUR_SIGMA_K     = 3.0     # noise floor multiplier (3-sigma rule)
POUR_MIN_G       = 10.0    # absolute floor, fault-mode
POUR_WINDOW_S    = 20.0    # split-pour accumulation window
POUR_MAX_G_FRAC  = 3.0     # implausibility ceiling = GLASS_VOLUME_G * this
BOUNCE_SETTLE_S  = 5.0     # suppression after a large negative disturbance
ANOMALY_SETTLE_S = 30.0    # suppression after a jar-removal anomaly
ROUND_SIZE       = 2       # glasses per round — set to 10 before a real stall
TRANSPORT_PORT   = 7001
DASHBOARD_PORT   = 5000
```
This list is illustrative, not authoritative — `hub/config.py` is the source
of truth; read it directly before relying on a specific value here.
