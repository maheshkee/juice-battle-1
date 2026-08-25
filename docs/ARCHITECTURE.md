# ARCHITECTURE — Juice Battle
# Status: current as of 2026-08-20. Replaces the Phase 0 WiFi/MQTT stub
# (that design was abandoned before S007 — never built).

## System overview

```
CZL601 (jar 0, Lemon)          CZL601 (jar 1, Melon)
        │                                │
   ADS1232 ADC                      ADS1232 ADC
        │                                │
 ESP32-C3 — JB-0                  ESP32-C3 — JB-1
 (firmware/node/)                 (firmware/node/)
 NODE_ID resolved at boot         NODE_ID resolved at boot
 from BT MAC (NODE_MAC_TABLE      from BT MAC (NODE_MAC_TABLE
 in juicebattle.ino — one         in juicebattle.ino)
 binary works on either node)
        │        BLE GATT notify         │
        └──────────────┬──────────────────┘
                        │
              Arduino UNO Q — hub, hostname AQ3
              ~/ArduinoApps/juice_battle/
                        │
         hub/ble_scanner.py  (GATT central, host Linux,
         systemd: juice-ble-scanner — kept separate from
         the main app so a BLE hiccup can't kill the game)
                        │ TCP :7001, NDJSON
         hub/transport.py  (TCP client, inside juice-battle)
                        │
         hub/main.py  (orchestrator — zero logic, wires modules)
              ┌─────────┼─────────┐
        game.py     storage.py   ambient.py
     (all scoring   (SQLite:     (pygame mixer:
      + rounds)      jb.db)       music + sfx)
              └─────────┬─────────┘
         hub/dashboard.py (Flask + Flask-SocketIO :5000)
                        │
         Chromium kiosk → /v4 (splash.html redirects here)
         + /ops (phone control panel) + /state (JSON API)
```

---

## Communication protocols

| Link | Protocol | Verified |
|---|---|---|
| Load cell → ADS1232 | Analog differential | S003 |
| ADS1232 → ESP32-C3 | Bit-bang, SCLK/DOUT, `delayMicroseconds(2)` per edge | S003 |
| ESP32-C3 → AQ3 | BLE GATT notify (NimBLE) | S007 |
| `ble_scanner.py` → `transport.py` | TCP `:7001`, NDJSON (one JSON object per line) | S007 |
| hub → browser | Flask + Flask-SocketIO v4.6.1 (served locally, no CDN) | S010 |

There is **no MQTT and no WiFi-based sensor link** — the ESP32-C3 nodes talk to
the hub exclusively over BLE. The UNO Q's own MCU (Zephyr) is not in this data
path at all; both sensor nodes are separate ESP32-C3 boards external to the
UNO Q.

---

## Data flow

1. Each node reads its load cell via `ads1232_read_raw()`, converts through
   `cal_to_grams()` (calibrated per node, NVS-persisted), and runs a 4-state
   stability machine (`STAB_WAITING` → `STAB_POUR_IN_PROGRESS` → `STAB_STABLE_SETTLED`)
   to decide when a reading represents a genuine settled pour vs. noise/motion.
2. The node streams `HEARTBEAT` / `POUR_ACTIVE` / `POUR_SETTLED` / `DIAG` /
   `CAL_COMPLETE` / `SIGMA_ALERT` messages over BLE GATT notify — a fixed
   13-byte payload (see `docs/INTERFACE_CONTRACTS.md`). **The node never
   decides what counts as a scored pour** — it only reports raw deltas.
3. `ble_scanner.py` (GATT central, its own systemd service) decodes each
   notification and republishes it as one NDJSON line on a local TCP server.
4. `transport.py` (TCP client living inside the main `juice-battle` process)
   parses NDJSON and calls into `game.py`.
5. `game.py` is the only place scoring decisions are made: noise-floor
   filtering (3×σ), disturbance/bounce suppression on large negative deltas,
   an implausibility ceiling that rejects jar-lift events, split-pour
   accumulation across multiple settle events, glass counting, and round-end
   triggering.
6. `storage.py` persists every scored event, session, and round result to
   SQLite (`hub/data/jb.db`).
7. `dashboard.py` pushes state to the kiosk and ops panel via Socket.IO
   (500ms loop) and serves `/state` as JSON.

---

## Architecture laws — non-negotiable

- **Hub = brain.** Owns all logic, state, scoring, history.
- **Node = sensor.** Reports `delta_g` + `sigma_g` only. No decisions, no
  business logic, no knowledge of glass volume or score.
- **`main.py` / `juicebattle.ino` = orchestrator.** Zero logic. Wire modules
  only — if there's a conditional, calculation, or threshold, it's in the
  wrong file.

---

## Actual DB schema (`hub/data/jb.db`)

Four tables — `sessions`, `pour_events`, `node_health`, `error_log` — plus
`round_results`, `kv_store`, `overflow_events`, `node_resets` added since.
See `hub/storage.py` for the authoritative `CREATE TABLE` statements; this
doc does not duplicate the schema to avoid drifting out of sync with it again.

---

## Open architecture question (2026-08-20, unresolved)

`ads1232.cpp` hardcodes a single ADC-negation compensation
(`return -data`) shared identically by both nodes, with no per-node
branching, while `cal.cpp`'s polarity fix (2026-08-13) is a global sign
flip tuned for JB-1's replacement chip. If JB-0 and JB-1 don't share the
same physical wiring polarity, this shared-code assumption is a latent
correctness risk. See `docs/RESEARCH.md` and `CLAUDE.md` for the current
state of this investigation — not closed out as of this writing.
