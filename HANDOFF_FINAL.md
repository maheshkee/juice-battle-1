# Juice Battle — Handoff S014 → S015
Date: 2026-07-30
Session: S014

## Current system state
- JB-0 (MAC 70:AF:09:32:F3:C2): connected, subscribed, data flowing
- JB-1 (MAC 10:00:3B:CD:63:32): connected, subscribed, data flowing
- Both nodes: running from USB power adapters — no laptop required
- Services: juice-ble-scanner + juice-battle running, boot-enabled
- Dashboard: http://AQ3:5000 — live, shows restored counts on connect
- Active DB session: 79 (open, resumable, glass_counts={0:1, 1:0})

## What D01 does (fully working)
On every service restart:
  1. game.start() calls storage.get_resumable_session()
  2. Finds session with ended_at IS NULL (session 79)
  3. SUMs glasses_counted from pour_events for that session per node
  4. Restores _glass_count in RAM before any state wipe
  5. Dashboard receives restored count on browser connect via _on_browser_connect
  6. Crowd sees correct count — restart is invisible

## S015 opening sequence
1. Confirm both nodes connected: journalctl -u juice-ble-scanner -n 20 | grep subscri
2. Place jars on platforms, wait 10s
3. Pour 2-3 glasses per node, verify counts increment from restored value
4. Run DB query to confirm glasses_counted writing:
   sqlite3 hub/data/jb.db "SELECT node_id, SUM(glasses_counted), COUNT(*) FROM pour_events WHERE session_id=79 GROUP BY node_id;"
5. Restart service, confirm RESTORED shows updated counts
6. Then build: per-node manual reset (node_resets table)

## S015 build queue (in order)
Stage 0: Per-node manual reset
  - storage.py: node_resets table + log_node_reset() + update get_resumable_session() query
  - game.py: reset_node(node_id) method
  - dashboard.py: POST /reset/<node_id> endpoint + reset button per jar card

Stage 1 (pre-Stage 3 prerequisite): ble_scanner.py _connect() threading fix
  - Move device.Connect() + time.sleep(4) to a thread
  - GLib loop stays spinning during reconnect — JB-1 data unaffected by JB-0 reconnect
  - _on_connect_success runs on GLib loop via GLib.idle_add

Stage 2: D03 — ring buffer in ble_scanner.py
  - deque(maxlen=200) buffers events when no TCP client
  - Flush on client connect

Stage 3: BLE dropout — NODE_DISCONNECTED/CONNECTED pipeline
  - ble_scanner.py: emit on BlueZ disconnect/reconnect signal (after subscription)
  - transport.py: recognise and pass new event types
  - game.py: node_status='disconnected'/'reconnecting', partial_g reset on reconnect
  - dashboard.py: disconnected badge

Stage 4: D02 verification
  - Scenario 1: hub-only restart (D01 handles)
  - Scenario 2: node-only restart (partial_g reset on NODE_CONNECTED)
  - Scenario 3: full power loss

## Known gaps (not bugs, documented)
- ble_scanner.py has no startup discovery phase — after bluetooth restart,
  must run: sudo timeout 60 bluetoothctl scan on
  Then scanner reconnects automatically. Fix: trigger scan at startup in S015.
- _connect() blocks GLib loop for up to 29s on reconnect (device.Connect + sleep 4)
  JB-1 data freezes during JB-0 reconnect. Fix: threading, S015 Stage 1.

## Key file locations
Hub:      ~/ArduinoApps/juice_battle/hub/
Firmware: ~/ArduinoApps/juice_battle/firmware/node/
DB:       ~/ArduinoApps/juice_battle/hub/data/jb.db
Services: juice-ble-scanner.service, juice-battle.service
