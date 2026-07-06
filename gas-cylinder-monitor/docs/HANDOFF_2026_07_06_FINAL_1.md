# HANDOFF — 2026-07-06 · Session 62 Close · FINAL_1
> Load HANDOFF_2026_07_01_SESSION60_MASTER_REFERENCE.md for full architectural detail,
> hardware specs, complete fix history, and every design decision's full reasoning.
> This document is the fast-continuity entry point — everything here is also in the
> master reference, but organized for "pick up immediately" rather than "look something
> specific up."

---

## ONE-LINE STATE

3E-009 attempt #3 has been running unattended since **2026-07-03 16:07:59 IST**, targeting
a 3-night run through Monday morning — **that target has now arrived.** First job of the
new session: find out what actually happened, efficiently, without drowning in three
days of raw logs.

---

## FIRST THING TO DO — efficient data extraction, not raw log dumps

Three days of data at ~2 readings/minute is roughly 8,000-9,000 DB rows and multiple
node/hub log files. **Do not cat, tail -f, or dump raw logs as a first move.** Use
aggregates and targeted queries; only pull raw lines once an aggregate points at a
specific window worth inspecting closely.

**Known landmine, applies to every query below:** the database's `ts` column is a
human-readable string (`"03 Jul 2026  16:07:59"`), NOT ISO format. Comparing it with
`>=` against an ISO-style date string silently returns wrong rows with no error — this
bit us hard mid-session. Always find a boundary row via `LIKE` pattern match against
the real stored format first, then filter by `id >=` that boundary — never compare `ts`
directly with a range operator.

**Recommended first pass — a single script, not fifteen separate commands:**
```bash
cat > /tmp/session63_first_look.sh << 'SCRIPT_EOF'
#!/bin/bash
echo "===== 1. CURRENT TIME & HOST UPTIME ====="
date '+%Y-%m-%d %H:%M:%S %Z'
uptime -p

echo ""
echo "===== 2. IS THE RUN STILL ALIVE RIGHT NOW ====="
arduino-app-cli app list | grep gas
systemctl status gas-cylinder-watchdog.service --no-pager | grep Active

echo ""
echo "===== 3. HOST REBOOT HISTORY SINCE LAUNCH ====="
last reboot | head -10

echo ""
echo "===== 4. NODE BOOT NUMBERS SEEN SINCE LAUNCH (more = more reboots) ====="
grep -oh "boot=[0-9]*" ~/ArduinoApps/gas-cylinder-monitor/hub/logs/node/*.log 2>/dev/null | sort -t= -k2 -n -u | tail -10

echo ""
echo "===== 5. RESET REASON BREAKDOWN, ALL BOOTS ====="
grep -oh "reset=[A-Z_]*" ~/ArduinoApps/gas-cylinder-monitor/hub/logs/node/*.log 2>/dev/null | sort | uniq -c

echo ""
echo "===== 6. WCN3990 CRASH COUNT SINCE LAUNCH ====="
journalctl -k --since "2026-07-03 16:07:59" | grep -c "firmware crashed"
journalctl -k --since "2026-07-03 16:07:59" | grep -c "Frame reassembly failed"

echo ""
echo "===== 7. WIFI POWER SAVE STATUS RIGHT NOW ====="
/sbin/iw dev wlan0 get power_save

echo ""
echo "===== 8. FIND THE ATTEMPT-3 LAUNCH BOUNDARY ROW ====="
sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
"SELECT MIN(id) FROM readings WHERE ts LIKE '03 Jul 2026  16:07%';"

echo ""
echo "===== 9. FULL AGGREGATE STATS FOR THE ENTIRE ATTEMPT (TRACKING only) ====="
sqlite3 -header -column ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
"SELECT COUNT(*), MIN(ts), MAX(ts), MIN(grams), MAX(grams), AVG(grams),
        MIN(sigma), MAX(sigma)
 FROM readings
 WHERE id >= (SELECT MIN(id) FROM readings WHERE ts LIKE '03 Jul 2026  16:07%')
 AND cylinder_state = 'TRACKING';"

echo ""
echo "===== 10. ANY GAPS LARGER THAN 60s (candidate reboot/staleness windows) ====="
echo "(run the Python gap-detection pass separately once this script confirms the run is real)"

echo ""
echo "===== 11. STATE TRANSITIONS ACROSS THE WHOLE RUN ====="
sqlite3 -header -column ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
"SELECT id, ts, cylinder_state, grams FROM
 (SELECT id, ts, cylinder_state, grams,
  LAG(cylinder_state) OVER (ORDER BY id) as prev_state
  FROM readings
  WHERE id >= (SELECT MIN(id) FROM readings WHERE ts LIKE '03 Jul 2026  16:07%'))
 WHERE cylinder_state != prev_state OR prev_state IS NULL;"

echo ""
echo "===== 12. WATCHDOG ESCALATION EVENTS ACROSS THE WHOLE RUN ====="
grep -a "LEVEL1\|LEVEL2\|LEVEL3" ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | grep -c "LEVEL1"
grep -a "LEVEL2_RESTART_TRIGGERED" ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | wc -l
grep -a "LEVEL3_REBOOT_TRIGGERED" ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log | wc -l

echo ""
echo "===== 13. EXPORT THE FULL ATTEMPT-3 CSV ====="
mkdir -p ~/ArduinoApps/gas-cylinder-monitor/hub/data/experiments
sqlite3 -header -csv ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
"SELECT id, ts, grams, quality, sigma, cylinder_state FROM readings
 WHERE id >= (SELECT MIN(id) FROM readings WHERE ts LIKE '03 Jul 2026  16:07%')
 ORDER BY id;" \
> ~/ArduinoApps/gas-cylinder-monitor/hub/data/experiments/3E-009-attempt3-full.csv
wc -l ~/ArduinoApps/gas-cylinder-monitor/hub/data/experiments/3E-009-attempt3-full.csv
SCRIPT_EOF
bash /tmp/session63_first_look.sh
```

This one script tells the whole story before touching a single raw log line: is it still
running, how many reboots happened, whether Fix 2 survived the whole 3 days, whether any
state transitions occurred that shouldn't have, and produces the one CSV file needed for
real charting — without ever dumping a full log file into chat.

**Once that comes back**, decide what (if anything) needs deeper inspection — a specific
gap, a specific state transition — and pull *only* that narrow window, the same
discipline used all through Session 62.

---

## THE FULL STORYLINE — what happened this session, compressed

**Where it started:** verifying Session 60/61's four fixes survived, protecting 3E-009
attempt #1's data (7,867-row CSV, confirmed intact), and deciding — deliberately — to
run a multi-attempt stability campaign rather than trust a single 65h run.

**Fix 4 (reset reason + heap logging):** designed, flashed, verified live. Confirmed
N-TARE-CHECK and HEAVY_LOAD_THRESHOLD_G were already correctly implemented — no new
firmware work needed for those two.

**The WiFi power-save saga:** discovered Fix 2 had silently failed — the boot-time
oneshot script raced interface bring-up and could fail outright, and even when it
succeeded, NetworkManager's own profile default (`powersave=0`) meant nothing durable
was actually set. Rebuilt properly: NM profile modification (`powersave=2`) plus a
**dispatcher script** reacting to any connection event, for any network, forever —
proven to survive a genuine hard power-cycle, not just a soft reboot. Patched into
`setup.sh` with zero hardcoded interface/profile names. Confirmed via real research
that this entire chip's instability is a known, industry-wide issue (2018 kernel patch,
other Arduino UNO Q owners independently affected) — not something this project's code
invented.

**3E-009 attempt #2:** ran ~14h38m, one watchdog-triggered reboot at the 5h16m mark. The
watchdog's own escalation timing was proven correct to within 9 seconds using nothing
but its documented constants and arithmetic — genuinely satisfying, rigorous proof. The
actual *root cause* of the 41-minute BLE silence itself was never conclusively found —
kernel log was empty in the predicted window, which rules out the already-solved
power-save trigger recurring and leaves the real cause still open.

**The `config.json` mystery:** chased most of one night. Multiple hypotheses tested and
disproven in sequence (host/container mount mismatch — disproven; a second orphaned
process — disproven, exactly one container and one process confirmed running). Final
proof via `stat`: the file checked all session hadn't been modified since **June 23** —
meaning this was never a functional bug, purely a visibility gap. The app's real config
path remains unresolved — a genuine open item for Session 63, findable via a literal
source grep for the `_CONFIG_PATH` assignment.

**Two full product designs, locked and documented in the master reference:**
- **CYLINDER_ABSENT / UNINSTALLED redesign** — UNBLOCKED. The blocking question since
  June 29th ("how long is a typical removal?") turned out to have a better answer than
  either option: duration doesn't matter, weight-match on return does. Plus an explicit
  "Uninstall" button, mirroring the existing "Install" button.
- **Cooking Intelligence (G8/G9/G10)**, including full whistle-by-whistle event tracking
  — a major, explicitly high-priority product goal. Requires zero node/firmware/BLE
  changes; it's a hub-side bookmark-and-interpolate feature on data already being
  collected. Includes a documented, honestly-scoped limitation (burn rate isn't smooth
  around whistle-adjacent flame adjustments — interpolation needs explicit wider
  uncertainty bounds there, not false precision) and a tiered connectivity-gap recovery
  hierarchy (real data → SPIFFS backfill → whole-session total still valid → honest
  "unavailable" only as a last resort).

**The stuck-sensor blind spot:** confirmed with certainty via direct source read —
`tare.cpp` never computes variance at all, so the "stuck" health check has silently
auto-passed every single boot since inception. Fix fully specified but **deliberately
not flashed** — the plan is to derive a real, measured threshold from attempt #3's
variance data rather than guess a number, then implement properly in Session 63.

**G5 Analytics status corrected:** live logs directly show working burn-rate and
days-remaining calculations, contradicting an earlier "not built" finding from the
project-knowledge staleness audit. Extent of what's actually built vs. stubbed needs a
real look, not re-assumed either way.

**Attempt #3 launched** 2026-07-03 16:07:59 IST, after a full physical power-cycle
reset of both node and hub (node boot=47, `reset=POWERON` — confirmed as a genuine
power cycle). Watchdog Level 3 (reboot escalation) was temporarily disabled mid-session
for a live-diagnosis attempt, then **fully restored** before this launch — confirmed via
git commit `48a9ab4`. This is not optional to double-check but should already be correct.

---

## PENDING — carried into this session, in rough priority order

| Item | Status | Notes |
|---|---|---|
| **Evaluate attempt #3** | Due now | Use the script above — first thing to do |
| `_CONFIG_PATH` real location | Unresolved | Grep source directly, don't infer further |
| CYLINDER_ABSENT implementation | Designed, unblocked | Ready to build in `domain.py` |
| health.cpp stuck-check fix | Designed, needs real data | Derive threshold from attempt #3's variance readings first |
| Cooking Intelligence build | Fully designed | Needs companion-app/voice channel — not started |
| SPIFFS backfill capacity check | Not done | ~9KB/40min outage vs. actual partition size — unverified |
| G5 Analytics real build extent | Contradiction found, not resolved | Direct code read needed |
| WebUI stale-on-load bug | Backlogged (person's own list) | Push last-known-state on connect, not wait for next 30s cycle |
| `ts` column format fix | Known, deferred | Not urgent — `id`-boundary workaround is reliable |
| 12 test constants revert | Not started | Only before real production, not blocking |
| 3E-008/3E-ENV/3E-ZERO | Blocked | Behind 3E-009 passing cleanly first |

---

## WORKING PRINCIPLES — unchanged, still in force

- Diagnose from evidence before any fix — this session repeatedly disproved plausible-
  sounding theories by actually testing them, and that was always the right call
- No hardcoded paths, usernames, hostnames, interface names, or profile names — always
  derive dynamically
- All design/analysis in chat; all code changes via Claude Code CLI on AQ3, never
  written directly in a chat response
- CLI does fact-gathering and mechanical doc updates only; Claude (chat) authors every
  handoff/master-reference update — CLI has no visibility into session reasoning
- One verified chunk at a time; show the diff before applying, verify after
- No raw log dumps into chat — aggregates, targeted greps, or short Python analysis only
- `ssh arduino@AQ3` — hostname, never IP, always
- Never trust the `ts` column with a range comparison — pattern-match a boundary, then
  filter by `id`
- `grep` without `-a` can silently degrade to a useless match mode on any log with a
  stray non-UTF8 byte — force text mode on application logs
- Claude Code CLI pinned at v2.1.129, `DISABLE_AUTOUPDATER=1` — verify each session

---

*Session 62 · Gratian Technologies · Project 13*
