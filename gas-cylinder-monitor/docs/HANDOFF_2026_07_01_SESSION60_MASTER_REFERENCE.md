# Gas Cylinder Monitor V1 — Master Project Reference
**Gratian Technologies · Project 13**
**Last updated: 2026-07-01 · Session 60**
**Purpose: Single authoritative reference from current state to final shipped product**

> Load this document at the start of every session. It supersedes all previous handoff documents.
> After each session, update current state section and re-commit.

---

## QUICK STATUS BOARD

| Item | Status |
|------|--------|
| Hub session | 60 |
| Node boot | 38+ |
| Stone on platform | **YES — do not tare hub** |
| Fix 1 — READING_STALE_S→1800 | ✓ DONE |
| Fix 2 — WiFi power save off | ⚠ PENDING — /sbin path issue |
| Fix 3 — CMD_TARE protection | ✓ DONE |
| TZ fix — Docker IST | ✓ DONE (was already set) |
| Fix 4 — esp_reset_reason + heap_caps | NEXT SESSION |
| config.json atomic writes | NEXT SESSION |
| 3E-009 attempt #2 | NOT YET LAUNCHED |
| Test constants reverted | NO — 12 still at test values |

---

## PART 1 — ARCHITECTURE (LOCKED, NEVER CHANGE)

### The fundamental seam — non-negotiable
Node outputs exactly three values: `{grams: float, quality: GOOD|DEGRADED|FAILED, sigma: float}`

Hub owns everything else: timestamps, gas%, state machine, analytics, alerts, calibration decisions, domain logic.

Node never does domain logic. This seam must never move regardless of any future feature request.

### System topology
```
3× YZC-161A load cells (parallel wiring)
    ↓
GISLAB HX711 (raw bit-bang, no library, noInterrupts() during 25-pulse read)
    ↓
ESP32-C3 SuperMini (BLE GATT server — notifies every 30s minimum, NEVER faster)
    ↓  BLE (hub-initiated connection, node advertises forever)
Arduino UNO Q — AQ3 (QRB2210 MPU + WCN3990 modem + Debian Linux)
    ↓
Python hub process (Docker container, App Lab)
    ↓
SQLite monitor.db + config.json (persistent state)
    ↓
WebUI (port 7000)
```

### AQ3 platform architecture
- **MPU**: Qualcomm QRB2210, 4× Cortex-A53 @ 1.8 GHz, Debian Linux
- **WCN3990**: Separate Hexagon DSP coprocessor on same silicon, closed-source firmware, manages BLE + WiFi as an independent subsystem communicating via QMI
- **SSR (Subsystem Restart)**: Qualcomm's crash-detect-reload mechanism for WCN3990 — by design, expected to crash occasionally, built-in self-recovery. Application layer cannot prevent crashes, only tolerate them gracefully.

### Locked architectural decisions
| Decision | What | Why it's locked |
|----------|------|-----------------|
| BLE-only transport on node | No WiFi on ESP32 | Zero provisioning complexity — no SSID/password ever |
| Hub stamps all timestamps | ESP32 has no RTC | Single authoritative time source |
| tare_raw absorbs platform | Platform weight cancels mathematically | Never re-tare platform after initial setup |
| CMD_TARE only from hub | Hub has domain context | Node never knows if a cylinder is being tracked |
| BLE notify ≥ 30s | WCN3990 hardware constraint | Faster rates crash the modem — this is physics, not config |
| config.json = truth | All persistent state lives here | In-memory state is ephemeral — survives nothing |
| Node modular sketch | hx711.h/.cpp, tare.h/.cpp, cal.h/.cpp | Testable, maintainable, no spaghetti |
| Hub: no hardcoded values | Always derive dynamically | Paths, usernames, interface names, thresholds via config or derivation |

---

## PART 2 — HARDWARE STACK (LOCKED)

### HX711 constants — NEVER CHANGE THESE
| Constant | Value | Note |
|----------|-------|------|
| DT pin | D7 | ONLY ever D7 on AQ3 |
| SCK pin | D6 | ONLY ever D6 on AQ3 |
| CAL_FACTOR | 36.2231 raw/g | 3-cell platform, experimentally verified |
| Reading mode | Raw bit-bang only | No external library |
| Corrupt filters | LONG_MIN, -1, 0x7FFFFF | All three required |
| Interrupt guard | noInterrupts() during 25-pulse sequence | Mandatory |

### Load cell wiring
- 3× YZC-161A in parallel: same-color wires twisted together, direct to HX711
- Unequal load distribution still gives correct total — proven via Wheatstone bridge / KCL
- Platform plate + rubber mats + drip trays permanently absorbed by tare_raw
- gas_g = gross_g − steel_g (platform cancels — never factors into gas calculation)

### Voltage discipline — violations cause hardware damage
| Header | Voltage | Exception |
|--------|---------|-----------|
| MCU headers (Arduino standard) | 3.3V logic, 5V tolerant | EXCEPT A0, A1 |
| JCTL (MPU) | 1.8V ONLY | 3.3V = hardware damage, no exception |
| JMISC (MPU) | 1.8V ONLY | 3.3V = hardware damage, no exception |

### Node (ESP32-C3 SuperMini)
| Item | Value |
|------|-------|
| MAC | 10:00:3B:CD:63:32 |
| Device name | GasCylMonitor |
| Service UUID | aa206b91-235b-42aa-b370-453a3feedf35 |
| Weight char (notify) | b9b25bb1-f2a9-4545-b48f-295ab2789f41 |
| Command char (write-NR) | c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b |
| Log char (notify) | d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c |
| Payload format | `{"grams":29420.5,"quality":"GOOD","sigma":2.3}` |
| Command format | ASCII string e.g. `TARE\n`, `SET_CAL:36.2231\n` |

### Hub (Arduino UNO Q — AQ3)
| Item | Value |
|------|-------|
| Hostname | AQ3 (mDNS/Avahi — always use hostname, never IP) |
| SSH | `arduino@AQ3` |
| WebUI | `http://AQ3:7000` |
| MAC (WiFi) | 14:b5:cd:e7:41:dd |

---

## PART 3 — CURRENT SYSTEM STATE (2026-07-01)

### config.json (last known)
```json
{
  "tare_raw": -107041.4,
  "cal_factor": 36.2231,
  "cylinder_state": "UNINSTALLED",
  "steel_g": null,
  "brand": null,
  "steel_source": null
}
```
Note: `steel_g: null` means no valid measurement session. `tare_raw` is the hub's platform tare, not the node's wrong tare.

### Node state
- Node boot 38+ with **wrong tare** — `tare_raw = 633819.2` (20kg stone absorbed)
- Node reading ~70g (noise floor with stone tared out)
- **20kg stone still on platform — do NOT tare hub until stone is removed**

### Hub watchdog
- `READING_STALE_S`: **1800** (updated this session from 900) ✓
- Service: `gas-cylinder-watchdog.service` — active, running

### Database
- 2841 TRACKING rows from 3E-009 attempt 1 (valid, first 24.5h only)
- All rows: `quality=GOOD`, `sigma=5.99` — hardware was healthy throughout
- Data corrupted from boot 38 onwards (wrong tare — all subsequent readings ~70g, no TRACKING rows)

---

## PART 4 — 3E-009 POST-MORTEM (LOCKED)

### Three root causes — evidence-confirmed
| RC | Root Cause | Status | Fix |
|----|-----------|--------|-----|
| RC1 | WCN3990 firmware crashes every ~15 min (94 in 23h). Recovery takes 13–17 min. Old 15 min watchdog fired before recovery completed → Linux reboot → cascade. | **PRIMARY** | Fix 1 + Fix 2 |
| RC2 | Node reboot after 24.5h — **proved DOWNSTREAM of RC1**. Boot 36 and boot 37 both ended 1.5 min before a Linux reboot. Hub's watchdog reboot dropped BLE; node's NimBLE reset in response. Not an independent node failure. | **REFRAMED / DOWNSTREAM** | Fix 1+2 may eliminate with zero node changes |
| RC3 | Wrong CMD_TARE on hub restart destroyed experiment data. Hub came up UNINSTALLED in memory (didn't read config.json), sent CMD_TARE with 20kg stone on platform. Stone absorbed into tare. All readings after boot 38 show ~70g. 2841 rows valid, zero rows after the fatal tare. | **CONFIRMED / DATA LOSS** | Fix 3 |

### Cascade chain (how one root cause became three symptoms)
```
WCN3990 crash (RC1)
    → BLE drops on hub side
    → Hub gets no readings
    → If recovery > 15 min → watchdog fires → Linux reboots
    → BLE drops for node
    → Node NimBLE resets → new node boot number (RC2 — downstream)
    → Hub reconnects → (old code) sends CMD_TARE regardless of config
    → FATAL if weight on platform (RC3)
```

### What the 2841 valid rows proved
- Creep plateau reached at ~2h45m post-placement
- Stable plateau: 19,913–19,930g, ±1.6g variance
- Thermal excursion: 430g peak-to-trough during morning sun exposure (09:00–12:00)
- Hardware health: quality=GOOD, sigma=5.99 throughout — load cell hardware is clean

---

## PART 5 — ALL FIXES (STATUS AND PRINCIPLE)

### Fix 1 — READING_STALE_S → 1800 ✓ DONE
**File**: `hub/python/hub_watchdog.py`
**Change**: `READING_STALE_S = 900` → `READING_STALE_S = 1800`
**Restart**: `sudo systemctl restart gas-cylinder-watchdog.service`
**Why 1800**: 2× worst observed recovery time (17 min). Boot -1 proved 90 crashes with zero watchdog reboots when recoveries completed inside the window.
**Long-term principle**: This is a derived value, not a set-once constant. Re-derive whenever BSP changes. Always maintain ≥ 2× measured worst-case recovery window.

### Fix 2 — WiFi power save → off (permanent) ⚠ PENDING
**Why**: Power state transitions are a documented WCN3990 crash trigger. Expected to reduce crash frequency significantly.
**Method**: systemd oneshot service with dynamic interface derivation
**Key**: Full paths `/sbin/iw` and `/sbin/iwconfig` — these tools are in `/sbin`, not in arduino user PATH
**File to create**: `/etc/systemd/system/wifi-power-save-off.service`

```ini
[Unit]
Description=Disable WiFi power saving on boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'IFACE=$(/sbin/iw dev | awk "/Interface/{print \$2; exit}"); /sbin/iwconfig "$IFACE" power off && echo "wifi-power-save-off: disabled on $IFACE"'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**Deploy** (terminal, not Claude Code):
```bash
sudo systemctl daemon-reload
sudo systemctl enable wifi-power-save-off
sudo systemctl start wifi-power-save-off
systemctl status wifi-power-save-off.service
/sbin/iwconfig | grep -A1 "Power Management"
```

**Long-term principle**: Off permanently on this platform — not a per-experiment toggle. Dynamic interface name always. Customer onboarding flow must apply this setting.

### Fix 3 — CMD_TARE cross-check on hub restart ✓ DONE
**File**: `hub/python/ble_subscriber.py` — `_send_tare_commands()` method
**Change**: Guard block reads `steel_g` + `tare_raw` from config.json before any TARE decision. If both non-null → force SKIP_TARE + SET_CAL, return early. `cylinder_state` in memory cannot override this.
**Log when triggered**: `[BLE_SUB] PROTECTIVE_SKIP: ...`
**Long-term principle**: Two rules must both hold forever: (1) hub never sends CMD_TARE without config confirmation. (2) config.json writes are atomic. Either rule alone is insufficient.

### Fix 4 — esp_reset_reason() + heap_caps per heartbeat — NEXT SESSION
**Target**: Node firmware (ESP32-C3 SuperMini)
**Method**: Arduino IDE re-flash, COM11, Windows laptop
**What to add**:
- `esp_reset_reason()` — log value in every BOOT event
- `heap_caps_get_largest_free_block(MALLOC_CAP_8BIT)` — log in every heartbeat (not just at boot)
**Scope change**: No longer "find unknown root cause" — now "confirm downstream hypothesis and add permanent observability"
**Long-term principle**: `heap_caps_get_largest_free_block()` stays in every heartbeat forever. Downward trend in largest-free-block with stable total-free-heap = unambiguous fragmentation fingerprint.

### TZ fix — Docker IST ✓ DONE (was already present)
**File**: `hub/python/main.py` lines 1–4
```python
import os, time
os.environ['TZ'] = 'Asia/Kolkata'
time.tzset()
```
**Note**: `docker exec <container> date` shows container OS clock (UTC) — this is irrelevant. Python process uses IST via tzset. Timestamps in DB and logs are correct.
**Long-term principle**: Verify TZ after every container rebuild. All RCA depends on trustworthy timestamps.

### config.json atomic writes — NEXT SESSION
**Why**: A crash mid-write leaves config in undefined state. Silently undermines Fix 3's protective check.
**What**: In all hub Python modules that write config.json — replace `json.dump()` direct writes with:
```python
import tempfile, os
tmp = config_path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.flush()
    os.fsync(f.fileno())
os.rename(tmp, config_path)
```
**Long-term principle**: config.json is the system's only persistent truth. Writes must be atomic. No exceptions.

---

## PART 6 — EXPERIMENT PROGRAM

### Completed and locked
| ID | What | Result |
|----|------|--------|
| 3E-001 | Noise floor characterisation | sigma=5.99g BLE-on. Threshold=18.54g. Locked. |
| 3E-002 | Linearity test | Linear 200–1700g. Single cal_factor valid across range. Locked. |
| 3E-004 | Calibration verification | CAL_FACTOR=36.2231 raw/g. Locked. |
| 3E-E005 | Cal + full run end-to-end | Self-calibrating boot. ±7g accuracy verified. Locked. |

### 3E-009 — Long-run stability (RETRY REQUIRED)
**What**: 65h continuous run with 20kg stone on 3-cell platform
**Attempt 1**: FAILED at 24.5h — three confirmed root causes (see Part 4)
**Attempt 2**: Launch after Fix 2 complete + stone removed + fresh tare on clean node
**Pass criteria**:
- 65h continuous, no watchdog reboots
- No CMD_TARE events (PROTECTIVE_SKIP should be visible in logs if triggered)
- Stable sigma throughout
- node reboots absent or dramatically reduced (confirms RC2 downstream hypothesis)
**Data target**: Full creep curve, stable plateau value, confirmed drift budget

### 3E-008 — Thermal drift characterisation (MANDATORY GATE)
**Gate**: Must pass 3E-009 first
**Why mandatory**: 430g thermal excursion measured in 3E-009 attempt 1. Cannot determine gas% accuracy without knowing the drift budget across a full kitchen day.
**Method**: Run through a complete kitchen day cycle (early morning cool → midday peak → evening cooling). Log weight continuously with no load changes.
**Output**: Thermal coefficient (grams drift per °C), max excursion window, recommended compensation strategy.
**Production gate**: This experiment's output feeds directly into the gas% accuracy specification.

### 3E-ENV — Environmental interference (DESIGN PENDING)
**Gate**: After 3E-008
**Motivation**: 3E-009 showed 430g thermal excursion from sun alone. Other environmental variables uncharacterised.
**Candidates to test**: Direct sunlight, fans/AC, multiple people moving in kitchen, heavy internet traffic on same WiFi, all appliances on simultaneously.
**What we measure**: Which variables cause reading drift, and by how much.
**Output**: Environmental interference budget + mitigation strategies for each.

### 3E-ZERO — Run cylinder to empty (MANDATORY GATE)
**Gate**: After 3E-ENV
**Why mandatory**: `FUNCTIONAL_ZERO_G` cannot be assumed — the gas regulator stops on pressure, not weight. The amount of LPG remaining when pressure drops below regulator cutoff is unknown and varies by cylinder brand and age.
**Method**: Install a real cylinder, monitor until stove flame dies, record weight at that moment.
**Output**: Confirmed `FUNCTIONAL_ZERO_G` per cylinder brand — replaces the current 1300g placeholder.
**Production impact**: Without this, LOW_GAS alerts fire at wrong thresholds and "days remaining" is uncalibrated.

### Remaining experiment queue
| ID | What | Gate | Answers |
|----|------|------|---------|
| 3E-006B | Minimum detectable weight change | After 3E-009 | Smallest removal system reliably detects |
| 3E-007B | False positive rate | After 3E-009 | How many false removal triggers on stable load |
| 3E-010 | Load cell failure injection | After 3E-ENV | Does health module detect open cell correctly |

---

## PART 7 — V1 BUILD REMAINING

### Node firmware — pending
| Item | Status | What | How |
|------|--------|------|-----|
| Fix 4 (reset reason + heap_caps) | NEXT SESSION | Observability + hypothesis confirmation | Arduino IDE re-flash, COM11 |
| N-TARE-CHECK | PENDING | Hub-offline self-protect: if heavy load + SPIFFS valid → skip fresh tare | Arduino IDE re-flash, COM11 |
| HEAVY_LOAD_THRESHOLD_G | PENDING | Restore 1000g → 2000g (was changed for testing) | Same re-flash as N-TARE-CHECK |

### Hub software — pending
| Item | Status | What |
|------|--------|------|
| config.json atomic writes | NEXT SESSION | Write safety for all modules that touch config |
| G5 Analytics | NOT BUILT | Burn rate from real data only. Rolling 7-day average. Days remaining calculation. |
| G7 WebUI | NOT BUILT | Full dashboard: gas gauge, trend chart, prediction, brand picker, alert display |
| BLE Connection Manager | PHASE 2 | Ghost connection self-healing. Track 2 — defense-in-depth only. |

### Production constants revert — 12 constants
**None have been changed. All still at test values. Must revert ALL before Phase 2.**
**Reference doc**: `hub/docs/GasMonitor_Complete_Revert_Reference.docx`

**Hub-side — domain.py**:
| Constant | Current TEST value | Production target | Depends on |
|----------|--------------------|-------------------|------------|
| NET_GAS_G | 4535.0 | 14200.0 | — |
| ALERT_AMBER_DAYS | 0.10417 (2.5h) | 5.0 | — |
| ALERT_RED_DAYS | 0.0625 (1.5h) | 3.0 | — |
| FUNCTIONAL_ZERO_G | 1300.0 (placeholder) | Experiment result | 3E-ZERO experiment |
| STEEL_PLAUSIBLE_MIN_G | 13000.0 | TBD | Review before revert |
| STEEL_PLAUSIBLE_MAX_G | 18000.0 | TBD | Review before revert |
| REFILL_GROSS_MIN_G | 22000.0 | TBD | Review before revert |
| ALERT_AMBER_G | Scaled from test | Production value | — |
| ALERT_RED_G | Scaled from test | Production value | — |

**Node firmware**: Audit for test-specific threshold values before Phase 2 re-flash.

---

## PART 8 — SESSION SEQUENCE (NEXT ~4 SESSIONS)

### Session 60 (today) — remaining work
1. Complete Fix 2 — WiFi power save using `/sbin/iw` and `/sbin/iwconfig` full paths
2. Verify: `systemctl status wifi-power-save-off.service` + `/sbin/iwconfig | grep -A1 "Power Management"`
3. Session close protocol (CLAUDE.md, SESSIONS.md, LEARNINGS.md, handoff doc, git commit, SCP)
4. Remove 20kg stone from platform
5. Verify platform empty, fresh tare on node
6. Launch 3E-009 attempt #2 — 65h run — walk away

### Session 61 (after 65h run)
1. Immediately export 3E-009 #2 data to CSV before any code changes
2. Analyze: did node reboots disappear? (confirms downstream hypothesis)
3. Fix 4 — node firmware re-flash: Arduino IDE, COM11, Windows laptop
4. config.json atomic writes — all hub Python modules
5. WCN3990 crash frequency investigation (firmware version, crash context, NM/Avahi correlation)
6. Design 3E-008 thermal drift experiment protocol

### Session 62
1. N-TARE-CHECK + HEAVY_LOAD_THRESHOLD_G restore — node firmware re-flash
2. Run 3E-008 thermal drift characterisation
3. Design 3E-ENV protocol

### Sessions 63+ (Phase 2)
1. 3E-ENV — environmental interference
2. 3E-ZERO — run to empty
3. G5 Analytics — burn rate, days remaining
4. G7 WebUI — full dashboard
5. BLE Connection Manager — Phase 2 hardening
6. Revert all 12 test constants
7. 3E-006B, 3E-007B, 3E-010 — remaining experiments
8. Final production gate check
9. Ship

---

## PART 9 — V2 ROADMAP

### Cooking Intelligence (G8/G9/G10)
| Feature | What | How |
|---------|------|-----|
| G8 — Session detection | Detect cooking start/end from weight rate-of-change signature | Analytics on burn rate delta |
| G9 — Dish tagging | User tags what they cooked after session | WebUI/app prompt post-session |
| G10 — Cooking calendar | Historical view of cooking sessions, frequency, gas per dish | SQLite analytics layer |

### Platform expansion
| Feature | What |
|---------|------|
| Phone app | Native Android/iOS replacing WebUI for end users |
| Remote alerts | WhatsApp/Telegram push on LOW_GAS and CRITICAL states |
| Multi-cylinder | Two cylinders on one hub (primary + backup) |
| Cloud sync | Analytics across household history, refill reminders |

### Hardware V2 (not yet designed)
| Item | Why |
|------|-----|
| Dedicated BLE-only module | Replace WCN3990 combo chip — eliminates firmware crash class entirely |
| Battery backup on hub | Cover power cuts without data loss |
| Consolidated PCB | Replace breadboard/dev board assembly — productionisable |
| Thermal compensation | On-board temperature sensor feeding cal_factor correction |

---

## PART 10 — PRODUCTION GATE CHECKLIST

Every item must be true before any V1 unit ships:

**Experiments**
- [ ] 3E-009 passes — 65h clean run, no watchdog reboots, no CMD_TARE events
- [ ] 3E-008 complete — thermal drift characterised and within acceptable budget
- [ ] 3E-ENV complete — environmental interference characterised
- [ ] 3E-ZERO complete — FUNCTIONAL_ZERO_G confirmed experimentally (not placeholder)
- [ ] 3E-006B, 3E-007B — min detectable change and false positive rate characterised
- [ ] 3E-010 — load cell failure injection verified

**Code**
- [ ] All 12 test constants reverted to production values (all reviewed, none skipped)
- [ ] Fix 2 confirmed surviving reboot (WiFi power save off persistent)
- [ ] Fix 4 deployed — esp_reset_reason + heap_caps in every heartbeat
- [ ] N-TARE-CHECK deployed in node firmware
- [ ] config.json atomic writes implemented in all hub modules
- [ ] G5 Analytics built, tested with real data
- [ ] G7 WebUI built and verified end-to-end
- [ ] BLE Connection Manager built (Phase 2 hardening)

**Platform**
- [ ] READING_STALE_S=1800 — re-verify if BSP has changed
- [ ] DISABLE_AUTOUPDATER=1 confirmed in `~/.bashrc`
- [ ] Docker TZ verified IST after any container rebuild
- [ ] WiFi power save confirmed off after any reboot

---

## PART 11 — KEY FILE PATHS

```
Project root:               ~/ArduinoApps/gas-cylinder-monitor/
Hub Python:                 hub/python/
  main.py                   Entry point — TZ fix at top (lines 1–4)
  ble_subscriber.py         BLE transport + CMD_TARE protection (Fix 3 done)
  domain.py                 All domain constants and state machine (test constants here)
  db.py                     SQLite abstraction — no domain logic ever
  hub_watchdog.py           READING_STALE_S = 1800 (Fix 1 done)
  log_transfer.py           Node log retrieval

Hub assets:                 hub/assets/index.html
Config (state):             hub/data/config.json          ← authoritative persistent state
SQLite DB:                  hub/data/monitor.db
Hub logs:                   hub/logs/hub/hub.log           (RotatingFileHandler 10MB×5)
Node logs:                  hub/logs/node/                 (node_YYYY-MM-DD_bootNN.log)
Host watchdog script:       hub/watchdog_host.sh
Watchdog service:           /etc/systemd/system/gas-cylinder-watchdog.service
WiFi power save service:    /etc/systemd/system/wifi-power-save-off.service   ← Fix 2 pending

Project docs:               hub/docs/
Analysis scripts:           hub/docs/analyse_crashes.py
CLAUDE.md:                  project root    ← Claude Code briefing
SESSIONS.md:                project root    ← session log (append only)
EXPERIMENT_PROGRAM.md:      project root
LEARNINGS_AND_INSIGHTS.md:  project root    ← permanent learnings (append only)
Revert reference:           hub/docs/GasMonitor_Complete_Revert_Reference.docx

Git remote:                 gratiantechnologies/project13
```

---

## PART 12 — ACCESS AND TOOLING

### SSH
```bash
ssh arduino@AQ3    # always hostname, never IP — mDNS/Avahi handles resolution
```

### Claude Code CLI — CRITICAL CONSTRAINTS
```bash
claude    # from SSH session on AQ3
# PINNED at v2.1.129 — NEVER upgrade without confirming Bun compatibility with Cortex-A53
# DISABLE_AUTOUPDATER=1 must be present in ~/.bashrc
# v2.1.131+ causes Bus error on Cortex-A53 — will break Claude Code entirely
```

### Essential hub commands
```bash
# Hub logs
tail -100 ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log

# Node logs (most recent)
ls -lt ~/ArduinoApps/gas-cylinder-monitor/hub/logs/node/ | head -10

# SQLite (targeted queries only — never SELECT * without WHERE + LIMIT)
sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
  "SELECT COUNT(*), MIN(ts), MAX(ts), MIN(gas_g), MAX(gas_g) FROM readings WHERE state='TRACKING';"

# Config state
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json

# Watchdog
systemctl status gas-cylinder-watchdog.service

# Hub container
docker ps | grep gas
docker logs $(docker ps --filter name=gas -q) --tail 50
docker restart $(docker ps --filter name=gas -q)

# Kernel log — modem crashes (ALWAYS check this first on any stability failure)
journalctl -k --since "2 hours ago" | grep -E "(crash|error|wifi|modem|ath10k)" | tail -30

# Modem crash count in last 24h
journalctl -k --since "24 hours ago" | grep -c "firmware crashed"

# WiFi power save status
/sbin/iwconfig | grep -A1 "Power Management"

# Network interface (dynamic — never hardcode wlan0)
/sbin/iw dev | awk '/Interface/{print $2; exit}'

# Crash correlation analysis
python3 ~/ArduinoApps/gas-cylinder-monitor/hub/docs/analyse_crashes.py
```

### Node firmware flashing
- **Tool**: Arduino IDE v3.0.7 on Windows laptop (v3.3.9 is broken on Windows — do not use)
- **Port**: COM11
- **Board setting**: ESP32C3 Dev Module
- **Critical setting**: USB CDC On Boot = **ENABLED**
- **Upload failures**: lower baud rate to 115200 — NEVER use "Erase All Flash"
- **Flash wipes SPIFFS**: power cycle does not — SPIFFS accumulation tests use power cycle only

---

## PART 13 — CRITICAL RULES AND LEARNINGS

### Hardware rules — violations cause damage or data loss
- BLE notify interval **minimum 30s** — WCN3990 crashes on faster rates. This is a hardware constraint. Never change.
- MCU headers: 3.3V logic, 5V tolerant **EXCEPT A0, A1**
- MPU headers (JCTL, JMISC): **1.8V ONLY** — connecting 3.3V here destroys hardware
- HX711: DT=D7, SCK=D6 **only ever these pins** on AQ3
- `noInterrupts()` mandatory during HX711 25-pulse read sequence
- Never use `String` class in Arduino — `snprintf` into `char` arrays only
- No `float` vs `double` confusion — verify per platform

### Architecture rules — violations corrupt data or break the system
- Node never does domain logic — ever, for any reason
- Hub owns timestamps, gas%, state machine, calibration decisions
- `tare_raw` absorbs platform permanently — gas_g = gross_g − steel_g (platform cancels in math)
- Burn rate from real measured data only — no population averages, no assumed priors
- In LOW_GAS state: never show "—" for days_remaining — user needs this information most right now
- `FUNCTIONAL_ZERO_G` must be experimentally determined — 1300g is a placeholder, not a real value
- `steel_g + tare_raw` together = a valid measurement session. Either alone is insufficient for CMD_TARE protection.

### Development process rules
- All design and analysis in chat. All code via Claude Code CLI on AQ3 only.
- Diagnose from evidence before any fix. No code written until root cause confirmed.
- No hardcoding: paths, usernames, interface names, hostnames, app names — always derive dynamically
- Never raw-paste data into chat — targeted SQL aggregates or Python analysis script output only (max 20 lines)
- Build one chunk at a time, verified working before next chunk starts
- Deploy commands given in terminal separately from Claude Code prompts
- Read SKILL.md before any code session

### RCA discipline — the most important process rule
- **`journalctl -k` is ALWAYS first** on any stability failure — before Python logs, before application code
- Hardware-level failures (WCN3990, brownout, OOM) are invisible at the application layer
- Application code review is phase 2, never phase 1
- Correlation of timestamps across journalctl, hub.log, and node logs is the method
- Code review without kernel log evidence is not root cause analysis — it is speculation

### WCN3990-specific rules
- Crashes are **unpreventable** — closed-source Hexagon DSP firmware in signed binary
- Correct engineering goal: **graceful tolerance**, not prevention
- `READING_STALE_S` is a derived value calibrated to hardware — always ≥ 2× measured worst-case recovery
- Re-derive watchdog margin whenever the board support package (BSP) changes
- 94 crashes in 23h is unusually high — after Fix 2, investigate firmware/board-file version match if frequency remains high
- Full crash context: `journalctl -k | grep -B2 -A2 "firmware crashed"` — different crash signatures = different root causes

### Config and persistence rules
- `config.json` is the single source of truth for persistent state — in-memory state survives nothing
- config.json writes must be atomic (write → fsync → rename) — not yet implemented, pending next session
- CMD_TARE requires explicit `steel_g + tare_raw` null-check from config.json first — Fix 3 implements this
- Docker container `date` shows UTC — Python process timezone is set independently via `time.tzset()`

---

## PART 14 — SESSION CLOSE PROTOCOL

Every session must complete these steps in order before the chat ends:

1. Append one-line summary to `SESSIONS.md`
2. Append any new learnings to `LEARNINGS_AND_INSIGHTS.md` (append only — never delete entries)
3. Update `CLAUDE.md` if any rules, paths, or context changed
4. Write `HANDOFF_YYYY_MM_DD_FINAL_[N].md` as next-session entry point (N increments if multiple finals same day — never overwrite)
5. Update this master reference document (current state section at minimum)
6. Git commit everything: `git add -A && git commit -m "session [N]: [description]"`
7. SCP docs to AQ3: `scp HANDOFF_... arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/hub/docs/`
8. Verify `DISABLE_AUTOUPDATER=1` still in `~/.bashrc` on AQ3

---

## PART 15 — NEXT SESSION ENTRY CHECKLIST

Load this document first. Then verify in order:

```bash
# 1. Fix 2 survived reboot?
systemctl status wifi-power-save-off.service
/sbin/iwconfig | grep -A1 "Power Management"

# 2. Hub running?
docker ps | grep gas

docker logs $(docker ps --filter name=gas -q) --tail 20

# 3. Watchdog running?
systemctl status gas-cylinder-watchdog.service

# 4. 3E-009 #2 still running?
tail -50 ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log

# 5. Config state?
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json

# 6. Claude Code version?
grep DISABLE_AUTOUPDATER ~/.bashrc
```

Then proceed with the session plan from Part 8.

---

*Gratian Technologies · Project 13 · Gas Cylinder Monitor V1*
*Document version: 2026-07-01 · Session 60*
*Next update due: After Session 61 (post 3E-009 attempt #2 analysis)*
