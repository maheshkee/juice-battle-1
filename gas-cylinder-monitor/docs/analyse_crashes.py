#!/usr/bin/env python3
"""
Read-only. Correlate node boot endings with hub crash/reboot events.
Prints only a summary table — no raw log dumps, no file modifications.

Data sources:
  node boot-end times : hub/logs/node/node_*.log files (session markers)
                        + hub/data/monitor.db (hub-received reading timestamps)
                        monitor.db covers Jun 26 16:40 onwards; boots before
                        that boundary use session-file timestamps as proxies.
  hub crash events    : journalctl (full journal; -k only covers current boot
                        on this platform, so the flag is omitted to reach history)
                        + `last reboot` for Linux-level reboots
"""
import re, subprocess, os, sqlite3, bisect
from datetime import datetime, timedelta

NODE_LOG_DIR = "/home/arduino/ArduinoApps/gas-cylinder-monitor/hub/logs/node"
MONITOR_DB   = "/home/arduino/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db"

SINCE_DAYS = 5
cutoff     = datetime.now() - timedelta(days=SINCE_DAYS)
YEAR       = datetime.now().year

# ── 1. Hub crash / reboot events ─────────────────────────────────────────────

hub_events = []

# Modem / firmware crashes (full journal; -k = current boot only on this platform)
try:
    out = subprocess.run(
        ["journalctl", "--since", f"{SINCE_DAYS} days ago"],
        capture_output=True, text=True, timeout=90
    ).stdout
    seen = set()
    for line in out.splitlines():
        if "firmware crashed" not in line and "handling crash" not in line:
            continue
        m = re.match(r'(\w{3}\s+\d+\s+\d+:\d+:\d+)', line)
        if not m:
            continue
        try:
            ts = datetime.strptime(f"{YEAR} {m.group(1)}", "%Y %b %d %H:%M:%S")
        except ValueError:
            continue
        key = ts.replace(second=0)          # deduplicate same-minute pairs
        if key not in seen:
            seen.add(key)
            hub_events.append(("modem_crash", ts))
except Exception:
    pass

# Linux reboots
try:
    out = subprocess.run(["last", "reboot"], capture_output=True, text=True, timeout=10).stdout
    for line in out.splitlines():
        if "system boot" not in line:
            continue
        m = re.search(r'system boot.*?(\w{3})\s+(\w{3})\s+(\d+)\s+(\d+:\d+)', line)
        if not m:
            continue
        try:
            ts = datetime.strptime(
                f"{YEAR} {m.group(1)} {m.group(2)} {m.group(3)} {m.group(4)}",
                "%Y %a %b %d %H:%M"
            )
        except ValueError:
            continue
        if ts >= cutoff:
            hub_events.append(("linux_reboot", ts))
except Exception:
    pass

hub_events.sort(key=lambda e: e[1])

# ── 2. Build session list from node log files ─────────────────────────────────

node_sessions = []   # list of (file_datetime, filepath)
for fname in sorted(os.listdir(NODE_LOG_DIR)):
    m = re.match(r'node_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.log', fname)
    if m:
        dt = datetime.strptime(
            m.group(1) + " " + m.group(2).replace("-", ":"), "%Y-%m-%d %H:%M:%S"
        )
        node_sessions.append((dt, os.path.join(NODE_LOG_DIR, fname)))

# session window: [file_time, next_file_time)
session_windows = []
for i, (dt, path) in enumerate(node_sessions):
    end = node_sessions[i + 1][0] if i + 1 < len(node_sessions) else datetime.now()
    session_windows.append((dt, end, path))

# ── 3. Active boot per session ────────────────────────────────────────────────
# Active boot = boot with smallest min(t=).  Historical dump entries for
# older boots have large t= values (hours of uptime); the currently-running
# boot has small t= (seconds since its last power-on).

def active_boot_of(path):
    boot_min_t = {}
    with open(path) as f:
        for line in f:
            if "boot=" not in line or " t=" not in line:
                continue
            try:
                b = int(line.split("boot=")[1].split()[0])
                t = float(line.split(" t=")[1].split()[0])
                if b not in boot_min_t or t < boot_min_t[b]:
                    boot_min_t[b] = t
            except (ValueError, IndexError):
                pass
    return min(boot_min_t, key=lambda b: boot_min_t[b]) if boot_min_t else None

# ── 4. Load reading timestamps from monitor.db ───────────────────────────────

conn = sqlite3.connect(MONITOR_DB)
all_ts = []
for (s,) in conn.execute("SELECT ts FROM readings ORDER BY ts"):
    try:
        all_ts.append(datetime.strptime(s.strip(), "%d %b %Y  %H:%M:%S"))
    except ValueError:
        pass
conn.close()

DB_EARLIEST = all_ts[0] if all_ts else datetime.max

def last_reading_in(start_dt, end_dt):
    """Last reading timestamp in [start_dt, end_dt). Returns None if no data."""
    lo = bisect.bisect_left(all_ts, start_dt)
    hi = bisect.bisect_left(all_ts, end_dt)
    return all_ts[hi - 1] if hi > lo else None

# ── 5. Build boot → last-contact map ─────────────────────────────────────────
# For each boot, track:
#   best_ts   – last reading from monitor.db  (preferred, exact)
#   proxy_ts  – next session start (used when DB doesn't cover the period)

boot_best  = {}   # boot -> (timestamp, source_label)
boot_proxy = {}   # boot -> next-session-start as fallback

for i, (start_dt, end_dt, path) in enumerate(session_windows):
    if start_dt < cutoff:
        continue
    boot = active_boot_of(path)
    if boot is None:
        continue

    # Try exact reading from monitor.db
    window_start = start_dt - timedelta(seconds=90)   # pre-dump buffer
    lr = last_reading_in(max(window_start, DB_EARLIEST), end_dt)

    if lr is not None:
        if boot not in boot_best or lr > boot_best[boot][0]:
            boot_best[boot] = (lr, "reading")
    else:
        # No DB reading for this session; record session-end as proxy
        if boot not in boot_proxy or end_dt > boot_proxy[boot]:
            boot_proxy[boot] = end_dt

# Merge: prefer reading; fall back to proxy only if no reading found
boot_end = {}    # boot -> (timestamp, source)
all_boots_seen = set(boot_best) | set(boot_proxy)
for b in all_boots_seen:
    if b in boot_best:
        boot_end[b] = boot_best[b]
    else:
        # proxy: next session start - 30 s (one heartbeat interval before new boot appeared)
        proxy = boot_proxy[b] - timedelta(seconds=30)
        boot_end[b] = (proxy, "proxy")

# Determine currently-active boot (active boot of last node log file)
current_boot = active_boot_of(node_sessions[-1][1]) if node_sessions else None

# ── 6. Match boot ends to nearest hub event ───────────────────────────────────

def nearest_event(ts):
    if not hub_events:
        return "—", "—"
    ev_type, ev_ts = min(hub_events, key=lambda e: abs((e[1] - ts).total_seconds()))
    delta_s = int((ev_ts - ts).total_seconds())
    sign    = "+" if delta_s >= 0 else "-"
    ab      = abs(delta_s)
    return (
        f"{ev_type}  {ev_ts.strftime('%m-%d %H:%M')}",
        f"{sign}{ab // 60:02d}:{ab % 60:02d}"
    )

# ── 7. Print summary table ────────────────────────────────────────────────────

C = (13, 24, 34, 10)
HDR = (f"{'node_boot':<{C[0]}}  {'boot_end_time':<{C[1]}}  "
       f"{'nearest_hub_event':<{C[2]}}  {'delta':>{C[3]}}")
SEP = "-" * len(HDR)

print(HDR)
print(SEP)

for boot in sorted(boot_end):
    ts, src = boot_end[boot]
    src_tag = f"[{src}]"

    if boot == current_boot:
        ev_str, delta_str = "—  (still running)", "—"
        label = f"{boot}(active)"
    else:
        ev_str, delta_str = nearest_event(ts)
        label = str(boot)

    ts_field = f"{ts.strftime('%Y-%m-%d %H:%M:%S')} {src_tag}"
    print(f"{label:<{C[0]}}  {ts_field:<{C[1]}}  {ev_str:<{C[2]}}  {delta_str:>{C[3]}}")

print(SEP)
print(f"hub events in window: {len(hub_events)}  "
      f"({sum(1 for e in hub_events if e[0]=='modem_crash')} modem_crash  "
      f"{sum(1 for e in hub_events if e[0]=='linux_reboot')} linux_reboot)")
print("[reading] = last actual reading from monitor.db  "
      "[proxy] = next session start −30s (no DB coverage before Jun 26 16:40)")
