# HANDOFF — 2026-07-01 · Session 60 · FINAL
> Load HANDOFF_2026_07_01_SESSION60_MASTER_REFERENCE.md for full project context.

---

## WHERE WE ARE

All four fixes done. System is prepped and stable. 3E-009 attempt #2 not yet launched — deferred to next session.

**Hub:** Session 60, Docker running, watchdog active.
**Node:** Boot 38+, wrong tare (stone was on platform). Stone removed? — confirm at session start.
**Config:** `tare_raw=-107041.4`, `cal_factor=36.2231`, `steel_g=null`, `cylinder_state=UNINSTALLED`
**DB:** 2841 rows from attempt #1 — valid, not wiped, not yet CSV-exported.

---

## FIXES STATUS

| Fix | Status |
|-----|--------|
| Fix 1 — READING_STALE_S → 1800 | ✓ DONE |
| Fix 2 — WiFi power save off (permanent, /sbin/iw) | ✓ DONE |
| Fix 3 — CMD_TARE PROTECTIVE_SKIP in ble_subscriber.py | ✓ DONE |
| TZ — IST in main.py (was already set) | ✓ DONE |
| Fix 4 — esp_reset_reason + heap_caps (node firmware) | NEXT SESSION |
| config.json atomic writes | NEXT SESSION |

---

## FIRST FIVE THINGS NEXT SESSION

```bash
# 1. Verify Fix 2 survived (if board rebooted since)
systemctl status wifi-power-save-off.service
/sbin/iw dev wlan0 get power_save    # expect: Power save: off

# 2. Hub running?
docker logs $(docker ps --filter name=gas -q) --tail 20

# 3. Watchdog running?
systemctl status gas-cylinder-watchdog.service

# 4. Config state?
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json

# 5. Stone off platform? Confirm physically.
```

---

## THEN IN ORDER

1. **Export 3E-009 attempt #1 CSV** — before launching attempt #2 (2841 rows, permanent backup)
2. **Remove stone if still on platform** (confirm physically)
3. **Fresh node tare** — `docker restart $(docker ps --filter name=gas -q)`, watch logs for `sent TARE` not `PROTECTIVE_SKIP`
4. **Launch 3E-009 attempt #2** — 65h run, walk away
5. **After run:** Fix 4 firmware re-flash, config.json atomic writes, WCN3990 investigation

---

## DO NOT

- Do not wipe `monitor.db` before CSV export
- Do not tare hub while stone is on platform
- Do not run `claude` without confirming `DISABLE_AUTOUPDATER=1` in `~/.bashrc`
- Do not upgrade Claude Code (pinned v2.1.129 — Cortex-A53 Bus error on newer)

---

*Session 60 · Gratian Technologies · Project 13*
