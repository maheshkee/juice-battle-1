# Data analysis protocol
# How to read, analyze, and visualize accumulated system data — from 3 days to
# many months. Follow this whenever the question is "what happened over time,"
# not "what's happening right now."
# Version 1 — written 2026-07-06, Session 63.

---

## Why this exists

By Session 62's close, `hub/logs/node/` already held 180+ files spanning June 22 to
July 6 — under a month of operation. A production unit runs for years. Without a
deliberate strategy, "let's look at the data" becomes "grep 180 files and hope,"
which gets slower and less reliable every single month. This protocol exists so
that answering "what happened last week" or "what happened last quarter" takes the
same few minutes either way.

---

## Data source inventory — one job each, same discipline as the documentation system

| Source | Location | Granularity | What it's actually for |
|---|---|---|---|
| `monitor.db` (`readings` table) | `hub/data/monitor.db` | ~1 row per successful BLE reading (~2/min) | **The primary source for any time-series question.** Weight, quality, sigma, state, gas%, alerts — all indexed, all queryable. Start here, always. |
| Node logs | `hub/logs/node/*.log` | One file per node boot; every heartbeat + boot-phase event | Diagnosing a *specific* incident (a crash, a fault, a boot anomaly) once the DB has told you *when* to look. Not for bulk trend analysis — 180+ files is already too many to grep blindly. |
| `hub.log` | `hub/logs/hub/hub.log` | Structured `hub_logger.*` calls only (WATCHDOG, BLE, DOMAIN tags) | Watchdog escalation history, BLE connect/disconnect events, state-change audit trail. Does **not** contain plain `print()` output — that only reaches `arduino-app-cli app logs`, a separate, shorter-retention channel. |
| `config.json` | `hub/data/config.json` | Current snapshot only | What the system believes *right now*. Not time-series — useless for "how did this change over time." |
| `hub/data/experiments/*.csv` | Manual exports | Frozen point-in-time | Permanent backups of specific analyzed runs. Not automatically maintained — don't expect it to contain recent data unless someone explicitly exported it. |

**Rule of thumb: the database answers "what," the logs answer "why" for one specific already-identified moment.** Never reverse that order.

---

## The permanent landmine — and the real fix, not just the workaround

`ts` is stored as human-readable text (`"03 Jul 2026  16:07:59"`), not a sortable
format. Comparing it with `>=` against an ISO-style bound **silently returns wrong
rows with no error** — this cost real time in Session 62. The workaround (pattern-match
a boundary row via `LIKE`, then filter by `id >=`) works, but it's a workaround, and
it doesn't scale gracefully to "find every Tuesday over 6 months."

**The real fix, worth doing now rather than repeating the workaround for years:**
```sql
ALTER TABLE readings ADD COLUMN ts_epoch INTEGER;
```
Then a one-time backfill script:
```python
import sqlite3, time
from datetime import datetime

conn = sqlite3.connect('monitor.db')
cur = conn.cursor()
cur.execute("SELECT id, ts FROM readings WHERE ts_epoch IS NULL")
rows = cur.fetchall()
for row_id, ts_str in rows:
    dt = datetime.strptime(ts_str.strip(), '%d %b %Y  %H:%M:%S')
    epoch = int(time.mktime(dt.timetuple()))
    cur.execute("UPDATE readings SET ts_epoch = ? WHERE id = ?", (epoch, row_id))
conn.commit()
```
And going forward, whatever code path inserts new rows (find it in `db.py`) needs one
extra line writing `int(time.time())` into `ts_epoch` alongside the existing `ts`
string. After this, every future query becomes a normal, correct range comparison —
`WHERE ts_epoch >= ? AND ts_epoch < ?` — no pattern-matching workaround needed ever
again. **This is genuinely worth an hour now, given the alternative is re-deriving
the workaround every session for the life of the product.**

---

## For real long-term scale — a rollup table, not just a bigger export

At 2 readings/minute, one month is ~86,000 rows — still fine for SQLite. But a year
is over a million, and "how has burn rate trended over 6 months" shouldn't require
scanning every raw row every time. Once `ts_epoch` exists, add a small daily rollup:

```sql
CREATE TABLE IF NOT EXISTS daily_summary (
    date TEXT PRIMARY KEY,
    reading_count INTEGER,
    min_grams REAL,
    max_grams REAL,
    avg_grams REAL,
    state_changes INTEGER,
    watchdog_events INTEGER
);
```
Populated by one small script run once daily (cron or a systemd timer), computing
that day's aggregates from `readings` and inserting one row. Answering "trend over
the last 6 months" then means reading ~180 tiny rows instead of ~1 million — instant,
regardless of how much raw history accumulates underneath. **Not urgent for this
week's data volume — becomes worth building once a few months of history exist.**

---

## The methodology — follow this every time, whether it's 3 days or 3 months

1. **Establish the time window first.** Never default to "everything ever." Even for
   "the whole 3-night run," that's still a bounded window with a known start.
2. **Find the boundary via pattern match** (or `ts_epoch` range, once it exists) —
   never a raw `ts` string comparison with `>=`.
3. **Run on-device SQL aggregates before exporting anything.** Counts, min/max/avg,
   gap detection (`LAG()` window function on timestamps), state-transition detection
   (`LAG()` on `cylinder_state`). This alone answers most "what happened" questions
   without moving a single row off the device.
4. **Only export raw rows for a window the aggregates actually flagged as
   interesting** — not the full period by default. A gap, a state change, an
   escalation event — export ±10 minutes around it, not the whole run.
5. **For routine trend charts over the full period, pre-aggregate on-device** — one
   row per 10 or 30 minutes (min/max/avg), not every 30-second raw reading. Keeps
   exports small regardless of how much history exists underneath.
6. **Only go to node/hub log files for a specific, already-identified incident
   window.** Never grep all files blindly — use the DB to find *when*, then open
   *only* the one node log file whose filename timestamp matches that window.
7. **Upload the resulting small file to chat for real charting** — matplotlib via
   the bash tool, same as Session 62's weight-timeline chart. Never ask for a chart
   to be built from a raw log dump or an unbounded query.
8. **For a genuine recurring dashboard need** (not a one-off investigation), invest
   in the external tooling below rather than repeating this manual process indefinitely.

---

## Tooling

### On-device (always available, no setup)
`sqlite3`, `awk`, `grep -a`, `journalctl` — everything used throughout Session 62.
Sufficient for steps 1-6 above, always.

### In-chat (for real charts, moderate data volumes)
Upload a CSV (ideally pre-aggregated per the methodology above) directly into the
conversation — Python via the bash tool (pandas + matplotlib) builds real, accurate
charts from real numbers. This is what produced the weight-timeline chart in Session
62. Works well up to tens of thousands of rows; beyond that, aggregate first.

### External tools — for genuine long-term, recurring dashboards
Two honest recommendations, different scale:

- **DB Browser for SQLite** (free, desktop GUI) — good for occasional manual
  exploration of `monitor.db` without writing queries by hand each time. Lightweight,
  no setup, but doesn't scale to automated recurring dashboards.
- **Grafana** — the actual right tool once this project wants a real, always-on
  historical dashboard rather than a one-off analysis session. Can point at SQLite
  directly via a plugin, or ingest via a lightweight export pipeline. This is more
  setup investment than the other options, but it's the correct destination for a
  product that will accumulate months of continuous sensor data — worth planning for,
  not urgent this week.

---

## What never to do

- Never `cat`, `tail -f`, or dump a full log file into chat as a first move
- Never compare `ts` with a range operator (`>=`, `<`) — pattern-match a boundary or
  use `ts_epoch` once it exists
- Never grep across all node log files when the DB can tell you which single file
  to look at
- Never export the full history when only a trend or a specific window is needed
- Never ask for a chart before the underlying CSV has been verified (row count,
  time span, a `head`/`tail` sanity check) — same discipline as every chart built
  in Session 62

---

*Version 1. Written 2026-07-06, Session 63, in response to node logs already
exceeding 180 files after less than a month of operation. Update this document the
same way as `SESSION_CLOSE_PROTOCOL.md` — targeted edits with a reason, not a silent
rewrite.*
