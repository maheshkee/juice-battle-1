# SESSION HANDOFF — 2026-06-18 SESSION2
# Gas Cylinder Monitor — Full Day Record
# For next session entry point use: HANDOFF_2026_06_18_FINAL_2.md

## Session goal
Hub DEV mode, auto-anchor, percentage tracking, two-level alerts, first working demo.

## Node changes
- N-TARE-CHECK: tare.h/.cpp + gas_monitor_v1.ino. Threshold=1000g DEV (restore 2000g production)
- NimBLE advertising restart: ble.cpp — NimBLEDevice::startAdvertising() in onDisconnect()

## Hub changes
- db.py: db_get_dev_mode() / db_set_dev_mode()
- main.py: DEV/PROD branching, 3-reading spread anchor, g_weight_was_removed gate
- main.py: two-level alerts, PROD scaffold, dev_mode in payload, node_status events
- main.py: on_set_dev_mode(sid, data) fix, on_node_connected/disconnected
- ble_subscriber.py: IST timestamp, on_connected/on_disconnected hooks
- assets/index.html: topbar, DEV/PROD toggle, alert banner, calibrating placeholder
- hub/deploy.sh: BT power-on + bluetooth restart before container start
- hub/setup_sudoers.sh: passwordless sudo for all deploy commands
- hub/DEVICE_SETUP.md: one-time commissioning guide

## Constants locked
DAILY_USE_DEFAULT_G=350, ALERT_AMBER_G=2000, ALERT_RED_G=1000, MIN_HISTORY_DAYS=7, ANCHOR_SPREAD_THRESHOLD_G=30

## Demo verified
1694.9g anchor, 100%→56%→20%→3%, amber+red alerts, toggle, NimBLE restart, IST timestamp, MAC in topbar

## Open items
- N1 journal→SPIFFS: NEXT
- CAL timeout (120s→36.0→DEGRADED): HIGH priority
- TARE_CHECK_THRESHOLD_G: 1000g DEV — restore 2000g before production
- HUB-WATCHDOG: designed, NOT BUILT — required before production
- Gas domain Group 4: NOT BUILT
- TODO 1B-stuck, 1B-persistence: deferred

## Latest commits
9c4a807 docs: add sudoers sync reminder
