# Juice Battle — BLE Transport: Lessons, Diagnoses, and First Principles
**Date:** 2026-08-13 | **Session:** S024

This document is the canonical reference for everything learned about the BLE transport stack
in the Juice Battle project. Written after S024 — the first session with both nodes stable
simultaneously. Read this before touching ble_scanner.py, firmware BLE code, or the BlueZ
adapter on the hub.

---

## 1. The Stack — Layer by Layer

The data path from load cell to dashboard crosses seven distinct layers. Each layer has its own
failure modes, its own tools, and its own recovery procedure. Understanding which layer is broken
is 80% of the debugging work.

---

### Layer 1 — ESP32-C3 Radio Hardware (NimBLE)

**What it is:**
The physical BLE radio inside the ESP32-C3. Managed by the NimBLE stack compiled into the
Arduino firmware. The node runs as a BLE peripheral: it advertises, accepts connections, and
serves a GATT notification characteristic.

**What it does:**
- Advertises device name `JB-0` or `JB-1` with manufacturer data
- Accepts one connection at a time (peripheral role)
- Sends GATT notifications every ~100ms when subscribed (pour events, diagnostics, heartbeats)
- Blue LED (GPIO 8, active-low) indicates healthy operation: on=idle, fast blink=pour, off=error

**What can go wrong:**
- NimBLE connection state machine diverges from physical link state (ghost connection)
- NVS flash stores stale bonding/pairing state that corrupts reconnect behaviour
- Supervision timeout too long — link dies but stack takes 30s to discover it

**Symptoms:**
- Node not visible in `btmgmt find` — but blue LED is ON → ghost connection
- Node not visible in `btmgmt find` — blue LED OFF → noise gate halt or NVS corruption
- Node connects, immediately disconnects, repeats — NVS corruption or bonding state mismatch

---

### Layer 2 — NimBLE Stack (Advertising, GATT Server, Callbacks)

**What it is:**
The NimBLE BLE stack running on the ESP32-C3. Handles advertising, connection management,
and the GATT server. Our code lives in `comms.cpp`.

**What it does:**
- `comms_init()` starts advertising on boot after noise gate passes
- `onConnect()` callback: logs connection, stops advertising
- `onDisconnect()` callback: logs disconnection, restarts advertising
- `onSubscribe()` callback: hub subscribed to notifications — resume sending

**What can go wrong:**
- `onDisconnect` fails to fire when the link drops abnormally (supervision timeout path)
- Default supervision timeout is 42s — node stays in "connected" limbo for 42 seconds
  after hub disconnects, unable to advertise during this window
- After `onDisconnect` fires (eventually), advertising resumes and hub can reconnect

**Critical design decision — supervision timeout:**
The supervision timeout in NimBLE defaults to 42 × 10ms × 100 = 42s. On an unclean
disconnect, the node waits the full supervision timeout before firing `onDisconnect`.
During this window, the node is invisible. The fix is to call `updateConnParams()` inside
`onSubscribe()` to set timeout=500 (5 seconds):

```cpp
void onSubscribe(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo, uint16_t subValue) {
    if (subValue == 1 || subValue == 2) {
        pServer->updateConnParams(connInfo.getConnHandle(), 24, 40, 0, 500);
    }
}
```

**Status as of S024:** NOT yet implemented for JB-1 (new chip). Ghost connection risk remains.

---

### Layer 3 — BLE Radio Link (Supervision Timeout, LL_TERMINATE_IND)

**What it is:**
The physical BLE link layer. Exists between the ESP32-C3 radio and the BlueZ controller on
the hub. Managed by the Link Layer (LL) specification, not by application code.

**What it does:**
- Maintains the ACL (Asynchronous Connection-oriented Logical) link
- Sends `LL_TERMINATE_IND` PDU on clean disconnection
- Supervision timeout: if no packets received within timeout, link is declared dead
- Both ends independently detect link loss — but may not agree on timing

**What can go wrong:**
- Node power-cycled without sending `LL_TERMINATE_IND` → hub side has stale HCI state
- Supervision timeout mismatch: hub declares dead at T1, node declares dead at T2
  During the window between T1 and T2, node is in limbo — cannot advertise, hub is
  trying to reconnect to a ghost

**Symptoms at this layer:**
- `hcidump` shows no `LL_TERMINATE_IND` on disconnect
- Hub log: `le-connection-abort-by-local` on next connect attempt
- Hub log: `connect attempt immediately failed` with no D-Bus error detail

---

### Layer 4 — HCI — Host Controller Interface

**What it is:**
The bridge between BlueZ (kernel BLE host) and the Qualcomm UART BLE controller on the
Arduino UNO Q. All BLE commands and events cross this interface. HCI state is maintained
independently of application state.

**What it does:**
- Passes LE_Create_Connection, LE_Cancel_Connection, LE_Set_Scan_Enable commands
- Returns HCI events: connection complete, disconnection complete, command status
- Maintains connection handles — these are HCI-level identifiers, not BlueZ paths

**What can go wrong:**
- HCI state corrupted by unclean disconnect — next connect returns `le-connection-abort-by-local`
- hciconfig `down/up` on Qualcomm UART platform returns errno 95 (Operation not supported)
  — the hciconfig path is broken on this hardware
- HCI needs physical reset: `systemctl restart bluetooth` reinitialises the UART controller

**Recovery procedure (exact order, non-negotiable):**
```bash
sudo hciconfig hci0 down     # may fail with error 95 on this platform — ignore
sudo hciconfig hci0 up       # may fail — ignore
sudo systemctl restart bluetooth
sleep 15                     # mandatory — UART controller needs time to reinitialise
```

The 15-second wait is not optional. Starting the scanner before bluetooth is ready causes
`SetDiscoveryFilter: UnknownObject` and the scanner exits immediately.

---

### Layer 5 — BlueZ Kernel Stack (Device Cache, GATT Client, Discovery)

**What it is:**
The Linux BlueZ BLE stack. Runs as a kernel service (`bluetooth.service`). Manages the
GATT client on the hub side — discovers services, reads characteristics, manages the device
registry.

**What it does:**
- Maintains a device registry: every seen BLE device has a D-Bus object path
  (e.g. `/org/bluez/hci0/dev_70_AF_09_32_F3_C2`)
- On `Connect()`: performs GATT service discovery, caches result in `/var/lib/bluetooth/`
- On disconnect: path may persist (device stays in registry) or be evicted (path deleted)
- Discovery: `StartDiscovery()` arms scanning; `InterfacesAdded` fires when device seen

**What can go wrong:**
- Device path persists after eviction: `InterfacesAdded` never fires again for a cached device
  → `_check_known_devices` 10s poll is required to catch these
- GATT cache stale: BlueZ cached wrong service layout from a previous firmware version
  → `bluetoothctl remove <MAC>` then reconnect forces re-discovery
- `InterfacesRemoved` fires when device is evicted entirely — must clean `_active_connections`
  or watchdog skips the node (believes it's still connected)
- Discovery held by scanner → `btmgmt find` returns Busy — stop scanner first

**Critical BlueZ fact:**
BlueZ device paths are derived from MAC address. If you replace the chip with a different MAC,
the old path (`dev_10_00_3B_CD_63_32`) becomes orphaned — BlueZ tries to connect to a
non-existent device. Remove the old entry: `bluetoothctl remove 10:00:3B:CD:63:32`.

---

### Layer 6 — D-Bus / GLib Event Loop (PropertiesChanged, InterfacesAdded)

**What it is:**
The Python application talks to BlueZ via D-Bus. All BlueZ signals (device connected,
device disconnected, characteristic value changed) arrive as D-Bus signals. The GLib main loop
dispatches these signals to registered Python callbacks.

**What it does:**
- `PropertiesChanged` on `Device1`: `Connected` property changes → connect/disconnect events
- `PropertiesChanged` on `GattCharacteristic1`: `Value` property changes → notification data
- `InterfacesAdded`: new device appeared in BlueZ registry → try connecting
- `InterfacesRemoved`: device evicted from BlueZ registry → clean state, reschedule

**What can go wrong:**
- Signal registered too late (after `StartDiscovery`) → miss InterfacesAdded for fast devices
  Fix: register all signal receivers BEFORE `StartDiscovery()`
- GATT Value notifications arrive with `dbus.Array` not `bytes` → `struct.unpack` fails
  Fix: `bytes(changed['Value'])` always, never pass dbus.Array directly to struct
- `Connected=False` fires during `device.Connect()` 4-second GATT window →
  `_on_connect_success` registers phantom connection
  Fix: `abort_event` threading.Event wakes connect worker immediately

**Why GLib, not asyncio:**
dbus-python's `dbus.mainloop.glib.DBusGMainLoop` integrates natively with GLib. asyncio
has no native D-Bus integration that works with dbus-python. All BlueZ signal dispatch runs
on the GLib loop. asyncio would require bridging (`asyncio.run_coroutine_threadsafe`) for
every signal — complex and fragile. GLib is the correct choice for a dbus-python consumer.

---

### Layer 7 — Python Application (ble_scanner.py)

**What it is:**
The hub-side application. Manages BLE connection state, dispatches GATT notifications as JSON
events to TCP clients (the game logic process), and runs two watchdogs.

**What it does:**
- Connects to JB-0 and JB-1 by name (advertised name, not MAC, for connect)
- KNOWN_NODES maps name → MAC for watchdog identification only
- Emits NDJSON events to TCP clients: HEARTBEAT, POUR_ACTIVE, POUR_SETTLED, DIAG,
  NODE_CONNECTED, NODE_DISCONNECTED
- Ring buffer (200 events): replays to reconnecting TCP clients on connect
- Per-node watchdog: 30s silence → soft eviction via D-Bus Disconnect
- Global watchdog: 120s no packets from any node → hard reset (adapter + systemctl)

**State that must stay consistent:**
- `_active_connections: dict[str, str]` — name → dev_path. Source of truth for "is connected"
- `_connecting_nodes: set[str]` — names currently in connect attempt. Storm guard.
- `_notify_subs: dict[str, str]` — char_path → node_name. Tracks active notification subscriptions
- `_node_last_seen: dict[int, float]` — node_id → epoch. Fed by every DIAG packet

---

## 2. Failure Modes — Canonical Diagnoses

### A. Ghost Connection — NimBLE Thinks Connected, Stops Advertising

**Symptom:**
- `btmgmt find` returns nothing (or only other devices, not the node)
- Blue LED on node is **ON** (solid or fast blink) — node believes it is connected
- Hub log: trying to connect, device not found, or no `InterfacesAdded` firing
- Can persist for up to 42 seconds (default supervision timeout)

**Root cause:**
NimBLE received no `LL_TERMINATE_IND` from the hub (hub crashed, cable pulled, etc.)
and has not yet reached the supervision timeout. The node's BLE radio is in "connected"
state and will not advertise until it detects the link is dead.

**Fix:**
Power cycle the node. This immediately clears NimBLE connection state and resumes advertising.

**Permanent fix (S025):**
In `onSubscribe()`, call `updateConnParams()` with timeout=500 (5 seconds). After 5 seconds
without a packet from the hub, the node self-detects the ghost and fires `onDisconnect`,
restarting advertising automatically.

**Do NOT:**
- Debug at BlueZ layer — BlueZ doesn't know the node exists in this state
- Use `bluetoothctl scan on` expecting to see the node — it won't be there
- Wait — it will eventually self-recover (42s default) but power cycle is faster and certain

---

### B. HCI Abort — le-connection-abort-by-local

**Symptom:**
- Hub log: `Connect to JB-x failed: le-connection-abort-by-local`
- Connect attempt returns immediately (not after 25s timeout)
- Happens after unclean disconnect or adapter reset attempt

**Root cause:**
The HCI controller has a dirty connection state from a previous unclean disconnect. The
local HCI controller aborts the new connect attempt because it believes the previous
connection is still in progress or not cleanly terminated.

**Fix — exact order:**
```bash
sudo hciconfig hci0 down
sudo hciconfig hci0 up
sudo systemctl restart bluetooth
sleep 15
sudo systemctl start juice-ble-scanner
```

**Warning — error 95:**
On the Arduino UNO Q (Qualcomm UART), `hciconfig hci0 down` may return:
`Can't init device hci0: Operation not supported (95)`
This is expected. The commands are included in the watchdog anyway to ensure correct
sequencing — the errors are harmless. The `systemctl restart bluetooth` is the operative
step.

**Do NOT:**
- Retry `device.Connect()` immediately — HCI needs time to fully reinitialise
- Skip the 15-second sleep — adapter will not be ready and scanner will exit on SetDiscoveryFilter

---

### C. Watchdog Race — Both Watchdogs Fire Simultaneously

**Symptom:**
- Hub log: per-node watchdog fires `[WATCHDOG-NODE] JB-x silent for 30s`
- Immediately followed by global watchdog: `Watchdog triggered - no BLE packets for 30s`
- Both fire at the same moment, triggering both a soft eviction and a hard adapter reset
- Cascade: reconnect attempt starts, then adapter is reset mid-attempt

**Root cause:**
Both watchdogs shared a 30-second threshold. The per-node watchdog evicts the node (D-Bus
Disconnect), which triggers a reconnect. The global watchdog simultaneously sees 30s silence
and fires the hard reset, destroying the reconnect attempt.

**Fix:**
- Per-node watchdog: 30s threshold (fast soft eviction)
- Global watchdog: 120s threshold (only fires when both nodes are silent — genuine adapter fault)

**Do NOT:**
- Use the same threshold for both watchdogs
- Set global watchdog < 60s — legitimate one-node-down scenarios will trigger false resets

---

### D. 4-Second GATT Blind Window

**Symptom:**
- Hub log: `NODE_CONNECTED` emitted for JB-x
- Node immediately goes silent — no DIAG or HEARTBEAT events
- `_active_connections` contains JB-x but `_notify_subs` does not
- Watchdog eventually fires 30s later

**Root cause:**
After `device.Connect()` returns, the connect worker calls `time.sleep(4)` to wait for GATT
service discovery. If the node disconnects during this 4-second window, `PropertiesChanged`
fires `Connected=False` — but `_active_connections` is not yet populated (it's populated by
`_on_connect_success` after the sleep). The disconnect handler finds nothing to clean up.
After the sleep, `_on_connect_success` runs and adds a phantom entry.

**Fix:**
Replace `time.sleep(4)` with `abort_event.wait(timeout=4)`:
```python
abort_event = threading.Event()
_connect_abort_events[dev_path] = abort_event
# ... in connect worker:
aborted = abort_event.wait(timeout=4)
if aborted:
    GLib.idle_add(_on_connect_fail, dev_path, node_name)
    return
GLib.idle_add(_on_connect_success, dev_path, node_name)
```
`_properties_changed` sets the event when `Connected=False` fires. Worker wakes immediately
and routes to `_on_connect_fail` instead of creating a phantom.

**Do NOT:**
- Ignore this bug — it creates a state where the hub believes a node is connected when it is not
- Use `time.sleep()` in connect worker for any reason

---

### E. Concurrent Connect Storm — InProgress Errors

**Symptom:**
- Hub log: multiple `org.bluez.Error.InProgress` errors
- Connect never succeeds — each attempt is rejected immediately
- Logs show `_connect` being called multiple times for the same node

**Root cause:**
`_check_known_devices` polls every 10s and calls `_connect` for any node not in
`_active_connections`. If a node is mid-connect (device.Connect() blocking in thread),
`_connecting_nodes` is the guard — but if the guard is not checked before `idle_add`,
multiple `_connect` calls fire simultaneously.

**Fix:**
`_connecting_nodes.add(name)` must be called **before** `GLib.idle_add(_connect, ...)` at
every call site. The guard check inside `_connect` must check `_connecting_nodes` before
starting a thread.

**Do NOT:**
- Call `bluetoothctl remove <MAC>` during an InProgress storm — this deletes the device path
  and all in-flight connect attempts fail permanently until rediscovery
- Restart the scanner during an InProgress storm without first stopping it cleanly

---

### F. btmgmt find Returns Busy

**Symptom:**
```
$ btmgmt find
...
hci0 LE scan failed with status 0x0b (Busy)
```
No devices returned. Appears to be adapter wedge — it is not.

**Root cause:**
The BLE scanner holds the discovery session. BlueZ only allows one discovery session at a time.
`btmgmt find` attempts to start its own session and is rejected.

**Fix:**
```bash
sudo systemctl stop juice-ble-scanner
btmgmt find
sudo systemctl start juice-ble-scanner
```

**Do NOT:**
- Interpret Busy as adapter wedge — the adapter is healthy
- Restart bluetooth service — unnecessary and causes 15s delay

---

### G. BlueZ Adapter Not Ready After bluetooth Restart

**Symptom:**
- Hub log: `SetDiscoveryFilter: org.freedesktop.DBus.Error.UnknownObject`
- Scanner exits immediately on startup after a bluetooth service restart

**Root cause:**
The scanner started before the Qualcomm UART controller finished reinitialising. BlueZ
registers the adapter in D-Bus, but the UART controller firmware is still starting up.
The adapter object exists in D-Bus but is not yet operational.

**Fix:**
Always wait 15 seconds after `systemctl restart bluetooth` before starting the scanner:
```bash
sudo systemctl restart bluetooth && sleep 15 && sudo systemctl start juice-ble-scanner
```

**Do NOT:**
- Use `sleep 3` or `sleep 5` — insufficient on this platform. 15s is the measured minimum.
- Start the scanner immediately via systemd After= dependency without a delay

---

### H. NVS Corruption / Stale BLE State

**Symptom:**
- Node connects briefly (1-5 seconds), then disconnects
- Behaviour is asymmetric: identical firmware on two nodes, one works, one doesn't
- Happens after double-flash (flash while connected, or flash mid-session)
- May loop indefinitely: connect → 2s → disconnect → 10s → reconnect → repeat

**Root cause:**
NimBLE stores bonding/pairing state in NVS flash. A mid-flash or double-flash can leave
partial NVS entries that corrupt the BLE state machine on boot.

**Fix:**
```bash
esptool.py --chip esp32c3 --port /dev/ttyUSBx erase_flash
# then reflash firmware normally via Arduino IDE
```

**Do NOT:**
- Assume firmware bug before erasing NVS — the fix is almost always erase + reflash
- Use `Preferences.clear()` in code to fix this — the NVS namespace used by NimBLE
  internally is not the same as application NVS

---

### I. hciconfig Fails — Operation Not Supported (95)

**Symptom:**
```
$ sudo hciconfig hci0 down
Can't init device hci0: Operation not supported (95)
```

**Root cause:**
Qualcomm UART BLE controller on Arduino UNO Q. `hciconfig` uses the HCI IOCTL interface
which is not supported for UART-attached controllers. The hardware reset path requires the
bluetooth service to reinitialise the UART transport.

**Fix:**
`systemctl restart bluetooth`. The hciconfig commands are still included in the watchdog
reset sequence for correct ordering — the error 95 is harmless and expected. The operative
step is `systemctl restart bluetooth`.

**Do NOT:**
- Rely on `hciconfig` for adapter recovery on this platform
- Remove the hciconfig commands from the watchdog — they enforce ordering and are harmless

---

### J. Noise Gate Halt — Node Boots But Never Advertises

**Symptom:**
- Node not found by `btmgmt find`
- Blue LED is **OFF**
- No serial output after `[NOISE] Measuring noise under current load...`
- Happens when platform is unstable (vibrating, unsupported, load cell swinging)

**Root cause:**
The noise gate in `juicebattle.ino` halts the boot sequence if `sigma_g ≥ 30g`:
```cpp
if (g_noise.quality == FAILED) {
    Serial.println("[NOISE] FAILED - sigma > 10g - hardware fault. Halting.");
    while (true) delay(1000);
}
```
`comms_init()` is never called. BLE radio is never started. Node is invisible.

**Fix:**
Power cycle with load cell platform stable and completely empty.

**Critical tell — LED state distinguishes this from ghost connection:**
- Ghost connection: blue LED **ON** (NimBLE connected, not advertising)
- Noise gate halt: blue LED **OFF** (comms_init never called)

**Do NOT:**
- Debug at BlueZ/hub layer — the node is not advertising, BlueZ cannot see it
- Assume hardware fault — almost always environmental vibration or unsupported platform

---

## 3. The Hub Scanner — Key Design Decisions

### Why GLib event loop, not asyncio

`dbus-python` provides `dbus.mainloop.glib.DBusGMainLoop` which integrates BlueZ signals
natively into GLib. All BlueZ events (`InterfacesAdded`, `PropertiesChanged`, `InterfacesRemoved`)
are dispatched by GLib. There is no asyncio D-Bus integration that works with dbus-python.
Using asyncio would require threading bridges for every signal — complexity with no benefit.
GLib is the correct event loop for this use case.

### Why connect worker runs in a thread

`device.Connect()` blocks for up to 25 seconds (D-Bus timeout). Running it on the GLib loop
would freeze the entire event loop, starving JB-1 data during a JB-0 reconnect. The connect
worker runs in a daemon thread: `device.Connect()` blocks in the thread, GLib loop stays
responsive. All state updates are posted back to the GLib loop via `GLib.idle_add()` —
never from the thread directly.

### Why _active_connections and _connecting_nodes are separate

`_active_connections: dict[str, str]` = name → dev_path. Source of truth for "is fully
connected with active GATT subscription." A node is only added here by `_on_connect_success`,
which runs on the GLib loop after the 4-second GATT discovery window completes.

`_connecting_nodes: set[str]` = names currently mid-connect-attempt. This is the storm
guard. It is pre-claimed at every call site before `GLib.idle_add(_connect, ...)`. Without
it, `_check_known_devices` (10s poll) and `_on_connect_fail` retry can both call `Connect()`
simultaneously, producing `InProgress` errors.

The two sets are separate because a node can be in `_connecting_nodes` but not yet in
`_active_connections` — the window between "starting connect" and "GATT subscription
confirmed." The disconnect handler must not mistake this window for a dead connection.

### Why abort_event closes the blind window

During the 4-second GATT discovery wait after `device.Connect()` returns, a disconnect can
fire `PropertiesChanged(Connected=False)`. Without the abort mechanism, this signal arrives
when `_active_connections` is still empty — the disconnect handler finds nothing to clean
up. After the 4-second sleep, `_on_connect_success` adds a phantom entry.

`abort_event = threading.Event()` is stored in `_connect_abort_events[dev_path]`. When
`_properties_changed` sees `Connected=False` for a device in `_connect_abort_events`, it
sets the event. The connect worker's `abort_event.wait(timeout=4)` returns immediately with
`aborted=True`, routes to `_on_connect_fail`, and no phantom is created.

### Why per-node watchdog uses device.Disconnect(), not bluetoothctl remove

`bluetoothctl remove <MAC>` deletes the device from the BlueZ registry entirely. The
dev_path (`/org/bluez/hci0/dev_...`) becomes stale. Any in-flight connect attempt using
that path fails permanently until BlueZ rediscovers the device via `StartDiscovery`. This
adds 10–30 seconds of unnecessary downtime.

`device.Disconnect()` triggers `PropertiesChanged(Connected=False)` which fires
`_properties_changed`, which runs the standard reconnect path. The dev_path remains valid.
Reconnect attempt starts in 10 seconds via `_reconnect_in(10000, ...)`.

### Why global watchdog threshold is 120s, not 30s

The per-node watchdog fires at 30s silence per node. If JB-0 goes silent, the per-node
watchdog evicts and reconnects it — global packet counter resets when JB-0 reconnects.
A global watchdog at 30s would fire during this normal recovery window, triggering a
destructive adapter reset while a reconnect is already in progress.

120 seconds means the global watchdog only fires when **both** nodes have been silent for
two minutes — a genuine adapter wedge scenario, not a routine node reconnect.

### The _properties_changed handler — what it catches and what it misses

**Catches:**
- Clean disconnects: `Connected=False` fires immediately via `LL_TERMINATE_IND`
- Unclean disconnects: `Connected=False` fires when supervision timeout expires
- Disconnects during GATT window: sets `abort_event` to prevent phantom connection

**Misses:**
- Device eviction from BlueZ registry: this fires `InterfacesRemoved`, not `PropertiesChanged`
  → `_interfaces_removed` handler covers this case
- Node never appearing (ghost connection): node not advertising, never fires any signal
  → no handler covers this — requires operator power cycle

### The _check_known_devices 10s poll — why it exists

When the scanner starts, devices already in the BlueZ cache will not fire `InterfacesAdded`
— they are already in the registry. Without the poll, nodes that were paired before the
scanner started would never connect.

The poll also catches edge cases where `InterfacesAdded` was missed (signal receiver
registered slightly after the device appeared). 10-second interval is intentional:
fast enough to reconnect within a reasonable window, slow enough to not spam connect
attempts if a node is mid-reconnect.

---

## 4. Calibration — Lessons Learned

### Why NOMINAL_COUNTS_PER_GRAM must never be hardcoded

`NOMINAL_COUNTS_PER_GRAM = 54.0f` is derived from the CZL601 40kg load cell + ADS1232
gain=128 + VREF=5V calculation: `54 counts/gram` theoretically. The measured value on
the original JB-0 chip was also ~54 counts/gram, which validated the constant.

The new JB-1 chip (AC:27:6E:53:DC:4A) reads ~98 counts/gram. Same load cell, same
wiring, same gain setting. The hardware variance is ~1.8×.

Impact of wrong NOMINAL_COUNTS_PER_GRAM:
- `wait_for_stable()` threshold: `25g × 54 counts = 1350 counts`. At 98 real counts/gram,
  a 1350-count spread represents only 13.8g — too tight, stability check fails spuriously.
- `sigma_tare_g` computation: reported sigma is wrong by the same ratio, stored in NVS.
- `ADS_NOMINAL_COUNTS_PER_GRAM` used in noise.cpp: sigma_g wrong before calibration,
  propagates to stability engine slope_threshold.

Fix applied in S024: derive counts/gram from the first calibration point at runtime:
```cpp
float measured = fabsf((float)(raw_refs[0] - raw_zero)) / ref_g[0];
```
This is chip-agnostic. Any chip, any load cell — calibration self-characterises.

### The polarity inversion bug (return -data, guard was <=)

`ads1232_read_raw()` negates its result because the green/white wires at ADS1232 INNA+/INNA-
are physically swapped: `return -data;`

Effect: empty platform reads ~-49800. Adding weight makes the reading more negative (~-100280
for 500g). Weight makes raw_ref **less than** (more negative than) raw_zero.

The Phase 2 guard was written for positive polarity:
```cpp
if (raw_ref <= raw_zero) {  // BUG: always true for negated ADC
```
This evaluates as `-100280 <= -49800` which is always true. Every weight step was rejected
as "reading not above tare — check wiring" before the block average result was even used.

Fix: invert the comparison:
```cpp
if (raw_ref >= raw_zero) {  // correct for negated ADC
```
Now rejects the case where weight produced no change or wrong direction.

### How derived_cpg fixes chip-agnostic calibration

The `derived_cpg` block runs after the first weight step completes successfully:
```cpp
float measured = fabsf((float)(raw_refs[0] - raw_zero)) / ref_g[0];
if (measured > 10.0f && measured < 500.0f) {
    derived_cpg = measured;
    Serial.printf("[CAL] derived counts/gram: %.2f (nominal was %.2f)\n", ...);
}
```
`fabsf` handles the polarity inversion — the result is always positive regardless of wire
swap direction. The guard `10 < measured < 500` rejects physically implausible values.

For JB-1: `fabsf(-100280 - (-49800)) / 500.0 = 50480 / 500 = 100.96 counts/gram`.
This matches observed hardware behaviour.

**Current limitation:** `derived_cpg` is printed but not stored. `CalResult` has no
`counts_per_gram` field. `sigma_tare_g` is still computed with `NOMINAL_COUNTS_PER_GRAM`.
Fix deferred to S025.

### The NVS persistence model

`cal_save_to_nvs()` stores: `raw_zero`, `raw_500`, `raw_1000`, `raw_5000`, `confidence`,
`sigma_tare_g`. The `valid` boolean key marks the cal as complete.

`cal_load_from_nvs()` reads these on every boot. If valid=true, calibration is skipped and
the node boots directly to noise measurement.

Survives: power cycle, reboot, firmware OTA update (NVS namespace is separate from code).
Does NOT survive: `esptool erase_flash` (wipes all NVS).

After erase_flash, the node will enter calibration mode on next boot. Operator must have
all three calibration weights (500g, 1000g, 5000g) available.

### Startup sequence — jar placement timing

The node captures its tare baseline at boot in `scale_capture_baseline()`. Whatever is on
the platform at boot becomes the zero reference for the game session.

**Correct procedure:**
1. Place empty jar on platform
2. Power on node
3. Node boots, captures baseline (jar weight = tare)
4. Game sees only delta from jar weight — juice added = positive delta

**Wrong procedure (causes scoring errors):**
- Power on node first, then place jar → jar weight registers as a pour event

### Calibration weight sequence

Calibration asks for three reference weights in sequence:
1. 500g (CAL_REF_1_G)
2. 1000g (CAL_REF_2_G)
3. 5000g (CAL_REF_3_G)

After each weight: "Remove weight, press Enter for next." Do not place the next weight
until prompted. The 10-second countdown (`CAL_SETTLING_COUNTDOWN_S`) after Enter gives
the platform time to stop vibrating before stability sampling starts.

---

## 5. Ops Rules — Non-Negotiable

**BLE scanning:**
- `btmgmt find` is the correct tool for manual BLE device scan (not `hcitool lescan`)
- `hcitool lescan` does not work on this platform
- Always `sudo systemctl stop juice-ble-scanner` before running `btmgmt find`
- Restart scanner after: `sudo systemctl start juice-ble-scanner`

**Adapter reset (exact sequence):**
```bash
sudo hciconfig hci0 down     # may return error 95 — ignore
sudo hciconfig hci0 up       # may return error 95 — ignore
sudo systemctl restart bluetooth
sleep 15                     # mandatory
sudo systemctl start juice-ble-scanner
```

**Git discipline:**
- Never `git push origin main` from the `juice_battle/` subdirectory context
- Archived branch: `juice-battle-main` (push: `git push origin HEAD:juice-battle-main`)
- Monorepo updates: `git push origin <branch>:main` from monorepo root

**Game configuration:**
- `ROUND_SIZE = 2` for development/testing
- `ROUND_SIZE = 10` for live stall
- Change in `hub/config.py` before going live

**Pre-stall reset procedure:**
```bash
sudo systemctl stop juice-battle
rm hub/data/jb.db
sudo systemctl start juice-battle
```
Always reset DB before a live stall. Today's test pours contaminate round scoring.

**Jar placement (always):**
- Empty jar on platform BEFORE node power-on — every session, every stall.

---

## 6. Platform Quirks — Arduino UNO Q / Qualcomm UART

**hciconfig:**
`hciconfig hci0 down/up` returns error 95 (Operation not supported) on this platform.
The Qualcomm UART BLE controller cannot be reset via IOCTL. Use `systemctl restart bluetooth`.
The hciconfig commands are harmless and kept for sequencing — do not remove them from scripts.

**hcitool lescan:**
Does not work. Returns error or hangs. Use `btmgmt find` for all BLE device scanning.

**Bluetooth service restart settle time:**
15 seconds minimum. The UART controller firmware reinitialisation takes longer than PCIe
or USB BLE adapters. Testing at 3s and 5s both failed with `UnknownObject`. 15s confirmed
working.

**Board reboot:**
The nuclear option when adapter is genuinely wedged and `systemctl restart bluetooth` does
not recover. Equivalent to power cycling the Qualcomm controller. Reserve for cases where
15s wait + scanner restart fails twice.

**Audio — ALSA card numbers:**
ALSA card numbers (`hw:0`, `hw:1`) change on reboot depending on USB enumeration order.
Always use card name: `hw:Device` (the USB Audio Device's stable name).
Setting `AUDIODEV=hw:Device` in systemd causes ALSA underruns on this platform — remove
the env var from the service file and let pygame/SDL auto-detect.

**Audio — sample rate:**
The fuzzy_horizon.mp3 file is encoded at 48kHz. pygame mixer must be initialised at 48kHz
or SDL will resample, causing crackling and distortion:
```python
pygame.mixer.init(frequency=48000, size=-16, channels=2, buffer=8192)
```
Buffer 8192 eliminates underruns on the AQ3's USB audio path.

**xdotool and DISPLAY:**
`xdotool` requires `DISPLAY=:0` to be set in the calling environment. Inline export
does not work:
```bash
DISPLAY=:0 xdotool key F5   # does NOT work
export DISPLAY=:0 && xdotool key F5   # works
```
Add to systemd service: `Environment=DISPLAY=:0`
