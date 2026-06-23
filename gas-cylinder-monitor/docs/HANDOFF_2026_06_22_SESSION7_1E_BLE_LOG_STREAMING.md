# SESSION HANDOFF — 2026-06-22 SESSION7
# Gas Cylinder Monitor V1
# Topic: 1E BLE log characteristic streaming

## Session goal
Build 1E — full DUMP_LOG → BLE stream → LOG_END → CLEAR_LOG pipeline.
Node streams /node_journal.log to hub via log characteristic.
Hub saves to logs/node/node_YYYY-MM-DD_HH-MM-SS.log.

## What was built this session

### Node changes
- log_transfer.h — FSM enum (LT_IDLE/LT_SENDING/LT_DONE), four function declarations
- log_transfer.cpp — full FSM implementation, paced at 10Hz via HX711 DOUT events
- ble.h — added extern bool g_mtu_ready
- ble.cpp — added g_mtu_ready=false definition, onMTUChange callback sets flag,
            added #include log_transfer.h, log_transfer_abort() in onDisconnect
- gas_monitor_v1.ino — #include log_transfer.h, wired 3 stubs to real calls,
                        log_transfer_tick() after ble_notify() in STATE_RUNNING,
                        delay(10) added to STATE_TARE_WAIT (watchdog fix)

### Hub changes
- ble_subscriber.py — LOG_CHAR_UUID + CMD_CHAR_UUID constants,
                      on_log_line callback in __init__, self.cmd_char = None,
                      _find_characteristic discovers all 3 chars in one loop,
                      _subscribe_log_notify + _on_log_notify methods,
                      write_command() with cmd.strip() before WriteValue,
                      _connecting guard prevents duplicate connect
- main.py — import shutil + datetime, LOG_DIR + LOG_TMP constants,
            os.makedirs(LOG_DIR), on_log_line() handler with LOG_START/LOG_END,
            threading.Timer(5.0) DUMP_LOG after on_node_connected,
            on_log_line=on_log_line in BLESubscriber instantiation,
            duplicate LOG_START guard

## Hardware verified this session
- MTU negotiated: 255 bytes on QRB2210 + NimBLE pairing
- 233 lines streamed cleanly, 21102 bytes file
- Second transfer after CLEAR_LOG: 16 lines, 1468 bytes, no duplicates
- Abort-and-preserve path verified on live BLE drop
- Watchdog fix verified: boot=6 ran 5000+ seconds clean after delay(10)

## Key bugs found and fixed
- FreeRTOS watchdog in STATE_TARE_WAIT: delay(10) fix
- write_command trailing newline: cmd.strip() fix
- Duplicate connect on hub restart: _connecting flag fix
- Duplicate LOG_START: g_log_transfer_on guard fix
- Full chip erase bricked 2nd stage bootloader: recovered via esptool --no-stub merged.bin

## Gate result
PASSED — 1E complete, end-to-end verified on hardware boot=6

## Next session
CAL timeout fix — HIGH PRIORITY
120s timeout on STATE_CAL → 36.0 fallback → DEGRADED quality tag
