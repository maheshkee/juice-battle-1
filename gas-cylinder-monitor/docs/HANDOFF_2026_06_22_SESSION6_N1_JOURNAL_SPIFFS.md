# SESSION HANDOFF — 2026-06-22 SESSION6
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_22_SESSION5_THERMAL_DRIFT_DIAGNOSIS.md

---

## How to use this document
Read HANDOFF_2026_06_18_FINAL_2.md first for full background.
Then read this file for everything that happened in session 6.
Working mode: design in chat, all code via Claude Code CLI only.

---

## Current position (one line)
N1 complete — journal lines persist to SPIFFS, accumulation verified across power
cycles. Hub anchor fix deployed. Next: 1E BLE log characteristic streaming.

---

## What was built this session

### Node — N1 journal SPIFFS
Files changed: journal.h, journal.cpp, gas_monitor_v1.ino

New globals (journal.h):
  extern uint32_t g_journal_file_bytes;  // RAM counter, init from SPIFFS file size at boot
  extern bool     g_transfer_pending;    // set true when file crosses 25600 bytes
  #define JOURNAL_TRANSFER_THRESHOLD_BYTES  25600U

New function journal_init() behaviour:
  Reads actual SPIFFS file size into g_journal_file_bytes at boot.
  Prints: [DBG] journal_init boot=NN file_bytes=NNN pending=N

New private helper journal_append(line):
  Opens /node_journal.log FILE_APPEND, writes, closes immediately.
  Increments g_journal_file_bytes. Sets g_transfer_pending at 25KB.

All 7 journal functions pattern:
  ++s_seq / snprintf full line into char _buf[256] / Serial.print / journal_append
  SPIFFS file contains complete lines identical to Serial output.

New journal functions:
  journal_tare_check(result, delta_g) — replaces 3 raw Serial.printf in STATE_TARE
  journal_retare(new_tare, old_tare)  — replaces 1 raw Serial.printf in STATE_RETARE

STATE_RUNNING: g_transfer_pending stub check added (logs once, no transfer yet).

### Hub — anchor fix
File changed: hub/python/main.py

- ANCHOR_SPREAD_THRESHOLD_G = 30.0 added to constants block
- Anchor spread check: uses ANCHOR_SPREAD_THRESHOLD_G not 2.0*sigma
- g_starting_weight loaded from DB at startup after db_init()

---

## Verified hardware outputs this session

| Check | Result |
|---|---|
| file_bytes=0 on first boot after flash | VERIFIED boot=43 |
| file_bytes=3531 on power cycle reboot | VERIFIED boot=46 |
| tare_check routes through journal (seq#4 not seq#0) | VERIFIED boot=45 |
| Anchor fires at ~5021g not 578g | VERIFIED |
| WebUI 100% on anchor | VERIFIED |
| sigma boot=46 | 3.56g |

---

## Node current state
- boot=46, gas_monitor_v1 with N1 journal SPIFFS
- TARE_CHECK_THRESHOLD_G = 1000g (DEV) — restore to 2000g before production
- JOURNAL_TRANSFER_THRESHOLD_BYTES = 25600U
- g_transfer_pending stub in STATE_RUNNING — not yet wired to transfer FSM

## Hub current state
- Deployed at 192.168.88.20:7000
- dev_mode = True
- ANCHOR_SPREAD_THRESHOLD_G = 30.0 (fixed, not sigma-derived)
- starting_weight loaded from DB at startup
- starting_weight in DB: ~5021g (from this session's test)

---

## Pending fixes (from previous sessions, still open)
- Fix 1: Alert banner not showing — diagnostic pending
- Fix 2: Grams display clamp at 0 (negative grams on empty platform)
- Fix 3: Pct display clamp at 0-100 (shows >100% with non-cylinder weights)
- Fix 4: Auto-start not verified

---

## Next session — 1E design and build

1E activates the BLE log characteristic for streaming /node_journal.log to hub.

Key design decisions locked this session (from MTU discussion):
- Log char UUID: d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c (already registered, notify)
- Wait for onMTUChange() callback with MTU >= 64 before any streaming
- One journal line = one BLE notify packet (fits in 244 bytes after MTU exchange)
- No chunking needed — longest line ~100 bytes, well under 244 byte payload
- Transfer triggered by DUMP_LOG command from hub
- Stream: LOG_START sentinel → lines one by one → LOG_END sentinel
- Hub side: receive lines, write to temp file, on LOG_END rename to
  logs/node/node_YYYY-MM-DD_bootNN.log, send CLEAR_LOG only after confirmed write
- Node side: on CLEAR_LOG, delete /node_journal.log, reset g_journal_file_bytes=0,
  g_transfer_pending=false

Node changes needed for 1E:
  ble.h/ble.cpp: activate log char notify, add g_mtu_ready flag, onMTUChange callback
  journal.cpp or new log_transfer.cpp: streaming FSM (read file line by line, notify)
  gas_monitor_v1.ino: wire g_transfer_pending check to actual transfer start

Hub changes needed for 1E:
  ble_subscriber.py: subscribe to log char notifications, write to temp file
  main.py: on new boot number detected, send DUMP_LOG command

---

## Opening prompt for next session

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_18_FINAL_2.md AND
HANDOFF_2026_06_22_SESSION6_N1_JOURNAL_SPIFFS.md fully before responding.

Context: N1 complete. Journal persists to SPIFFS. Anchor fix deployed.
boot=46 running. file_bytes accumulation verified.

Today: design and build 1E — BLE log characteristic streaming.
Node activates log char notify with MTU gate. Hub receives lines and saves.
Full DUMP_LOG → stream → LOG_END → CLEAR_LOG pipeline.

Start by confirming you read both handoffs and state current position."

---

*End of handoff. Next chat is ready.*
