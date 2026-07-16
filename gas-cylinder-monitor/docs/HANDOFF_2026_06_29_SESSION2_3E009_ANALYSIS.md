# HANDOFF — 29 Jun 2026 — Session 2 — 3E-009 Analysis & RCA

## ⚡ READ THIS FIRST — IMMEDIATE PRIORITIES

Before anything else in the new chat, four fixes need to be deployed via Claude Code CLI on AQ3.
In priority order:

| # | Fix | What | Where | Urgency |
|---|-----|------|-------|---------|
| 1 | READING_STALE_S → 1800 | One-line change, 900→1800 | hub_watchdog.py | DO FIRST |
| 2 | WiFi power save off | iwconfig power off, make permanent | host shell | DO SECOND |
| 3 | CMD_TARE protection on restart | Hub must not tare if steel_g anchored | domain.py / main.py | DESIGN + IMPLEMENT |
| 4 | ESP32 reset reason logging | esp_reset_reason() in firmware boot | node firmware | Arduino IDE on Windows |

---

## WHO WE ARE AND WHAT WE'RE BUILDING

**Project:** Gratian Technologies — Project 13 — Gas Cylinder Monitor V1
**Purpose:** LPG gas cylinder weight monitor for Indian households
**Hub:** `arduino@AQ3` (192.168.88.20), WebUI port 7000
**Architecture seam (non-negotiable):** Node outputs `{grams, quality, sigma}` only. Hub owns ALL domain logic, timestamps, analytics.

### Working rules (all non-negotiable)
- All design/architecture decisions happen in chat first
- All code written EXCLUSIVELY via Claude Code CLI on AQ3 — never write code directly in chat
- Diagnose from evidence before writing any fix — paste CLI output first, then fix
- Build slowly: small → complex, one chunk verified before next
- NO HARDCODING: scripts derive all paths dynamically (SCRIPT_DIR, APP_NAME, APP_DIR). Never hardcode usernames, hostnames, absolute paths, or app names
- Deploy commands given separately from CLI prompts, never embedded
- Data protocol: NEVER paste raw data into chat — always targeted SQL queries with aggregates, grep not cat for logs, analysis scripts on AQ3 → paste only the output report

### Claude Code CLI (critical)
- Version: **2.1.129 — PINNED. Never update.**
- `DISABLE_AUTOUPDATER=1` is in `~/.bashrc` on AQ3
- v2.1.131+ causes Bus error on Cortex-A53. Do not touch.
- Install path: `npm install -g @anthropic-ai/claude-code@<version>` — never the native installer

---

## CURRENT SYSTEM STATE (29 Jun 2026, 11:02 IST)

### Hub
- Session 56, running since 11:02 IST today (Mon 29 Jun)
- Hub watchdog: `gas-cylinder-watchdog.service` ACTIVE since 11:02:39
- cylinder_state: UNINSTALLED (state lost on last crash)
- tare_raw: **-107041.4** ← HUB tare, intact, correct. DO NOT re-tare hub.
- cal_factor: **36.2231** ← intact, correct
- cal_tare_session: boot13_verified_2026-06-23
- steel_g: **null** (not yet set in this session)
- device_name: GasCylMonitor
- device_address: 10:00:3B:CD:63:32
- All domain constants: still at **TEST values** (see production revert section below)

### Node (ESP32-C3)
- Currently on boot 38 or later
- Node tare_raw: **633,819.2** ← WRONG. Stone was absorbed during boot 38 CMD_TARE event.
- Node readings: ~70g (worthless — stone absorbed into tare)
- Node hardware: healthy (quality=GOOD, sigma consistent throughout all 2841 rows of 3E-009)

### Physical platform
- 20kg market stone is STILL physically on the platform
- Hub says UNINSTALLED, node reads ~70g — both consistent with wrong tare having fired

### What must happen before next 3E-009 run
1. Remove stone from platform
2. Deploy all 4 fixes
3. Hub sends TARE on next connection (empty platform) → node gets fresh clean tare
4. Place stone fresh, start experiment as 3E-009 attempt #2

---

## 3E-009 EXPERIMENT — WHAT HAPPENED

### Setup
- 20kg market stone on 3-cell YZC-161A platform
- Started: 26 Jun 2026 16:53 IST
- Planned: 65-hour run (unattended)
- Actual valid data: ~24.3h (2841 TRACKING rows in SQLite)
- Data ends: 27 Jun 17:09:19 IST (last TRACKING row)

### Weight curve — confirmed data points (from SQLite + handoff)

| Time (IST) | T+ from start | gas_g | Phase |
|------------|---------------|-------|-------|
| 26 Jun 17:03 | T+0.17h | 4558.7g | First valid reading |
| 26 Jun 17:35 | T+0.70h | ~4597g | Pre-creep (monotonic fall begins) |
| 26 Jun 19:10 | T+2.28h | ~4430g | Plateau starts |
| 26 Jun 19:30 | T+2.62h | ~4432g | Plateau confirmed |
| 27 Jun 00:53 | T+8h | ~4438g | Stable overnight |
| 27 Jun 06:52 | T+13.98h | ~4445g | → Hub crash #1 |
| 27 Jun 08:48 | T+15.92h | ~4480g | Thermal excursion begins |
| 27 Jun ~10:30 | T+17.5h | **4860.9g** | PEAK — thermal excursion |
| 27 Jun 11:00 | T+18.12h | ~4640g | Thermal subsiding |
| 27 Jun 15:00 | T+22h | ~4437g | Back to stable baseline |
| 27 Jun 17:05 | T+24.12h | ~4430g | Fully stable |
| 27 Jun 17:09 | T+24.27h | **4429g** | LAST TRACKING ROW |

### Key findings from 3E-009 (confirmed)
- **Creep plateau time:** ~2h 45min from stone placement — well within 24h MIN_DATA_HOURS gate ✓
- **Stable baseline:** 4429–4435g (variance <4g over any 10-minute window at plateau) ✓
- **Post-plateau drift rate (night, no thermal):** ~40g over 18h = ~2.2g/hr
- **Thermal excursion amplitude:** up to 430g peak-to-trough (morning sun hitting platform)
- **Platform hardware health:** quality=GOOD, sigma=5.99 throughout all 2841 rows ✓

### 3E-009 formal pass criteria — NOT YET MET
Needs 3 clean runs (zero crashes, full 65h window) to formally determine stabilization time, stable value range, and drift budget. This was attempt #1, crashed at T+24h.

---

## ROOT CAUSE ANALYSIS — EVIDENCE-BASED

All three causes confirmed from kernel logs and node logs. Evidence pasted in previous session.

---

### RCA1 — PRIMARY: WCN3990 Modem Firmware Crash

**Evidence from `journalctl -b -1 -n 300`:**
```
kernel: remoteproc remoteproc0: handling crash #90 in modem
kernel: ath10k_snoc c800000.wifi: firmware crashed!
```

**Mechanism:**
- WCN3990 modem firmware crashes repeatedly (~1 per 15 min average in boot -1)
- Each crash brings down the BLE adapter
- Modem recovery takes 13–17 minutes (with variance)
- READING_STALE_S was 900s (15 min) — just barely too tight against recovery variance
- When recovery took 16–17 min, watchdog threshold exceeded → Linux reboot
- The reboot interrupted recovery, making the next cycle longer → cascading

**Proof fix works:** Boot -1 (Sun 28 Jun 12:02 to Mon 29 Jun 11:02) had 90 modem crashes and ZERO watchdog reboots — because it was the boot where the modem happened to recover fast enough each time. Increasing READING_STALE_S to 30 min provides reliable headroom.

**Fix 1:** Change `READING_STALE_S` from 900 to **1800** in hub_watchdog.py. One line.

**Fix 2 (companion):** WiFi power saving causes the modem to enter deep sleep, increasing recovery time and crash frequency. Disable permanently:
```bash
# Check current state
iwconfig wlan0 | grep -i power

# Disable for current session
sudo iwconfig wlan0 power off

# Make permanent — create a NetworkManager dispatcher script
# OR add to /etc/rc.local
# OR use nmcli — check which method AQ3 uses before implementing
# Implementation must be dynamic — no hardcoded interface names
```

---

### RCA2: ESP32 Node Spontaneous Reboot

**Evidence from node logs:**
- Boot 36 ran for 88,277s (~24.5h) then ended with NO error logged
- Boot 37 ran only 33 min then ended silently — same pattern
- No crash events, no panic entries in node journal
- Node hardware confirmed healthy (quality=GOOD throughout)

**Mechanism (suspected):** NimBLE stack state accumulation or heap fragmentation over extended uptime. The 24.5h duration is suspicious — some BLE stacks have known issues with very long-running connections.

**Fix 4:** Add `esp_reset_reason()` logging to node firmware boot sequence. On the next run, the first BOOT heartbeat will tell us exactly what caused the reset:
```cpp
#include "esp_system.h"
esp_reset_reason_t reason = esp_reset_reason();
// log this value in the BOOT event
// Possible values: ESP_RST_POWERON, ESP_RST_SW, ESP_RST_PANIC,
//                  ESP_RST_WDT, ESP_RST_BROWNOUT, ESP_RST_SDIO, etc.
```
Note: This requires re-flashing the node firmware via Arduino IDE on the Windows laptop (COM11).

---

### RCA3 — DATA DESTRUCTION: Wrong CMD_TARE on Hub Restart

**Evidence from `node_2026-06-27_17-56-41.log`:**
```
#0003 boot=38 event=PHASE_COMPLETE phase=TARE_WAIT result=CMD_TARE
#0004 boot=38 event=TARE_CHECK result=NO_REF delta=0.0g
#0005 boot=38 event=PHASE_COMPLETE phase=TARE result=OK mean=633819.2
```

**Mechanism:**
- Hub boot -4 started at 17:55 Jun 27 (after cascade of crashes)
- Hub state was UNINSTALLED (lost on crash — state not persisted robustly enough)
- Hub connected to node boot 38, sent CMD_TARE with 20kg stone on platform
- Node set tare_raw = 633,819 (stone absorbed)
- All subsequent node readings: ~70g
- Zero TRACKING rows ever written again
- 3E-009 data collection permanently ended at 17:58 Jun 27

**Fix 3:** Hub restart logic must check config.json before sending any TARE command:
```
IF config.json has (tare_raw AND cal_factor AND steel_g AND steel_anchored_at is recent):
    → Send SKIP_TARE
    → Attempt CROSS_CHECK to verify stone is still there
    → Only if CROSS_CHECK fails → mark UNINSTALLED, send CMD_TARE
ELSE IF config.json has (tare_raw AND cal_factor) but steel_g is null:
    → We have calibration but no cylinder data → normal startup flow
ELSE:
    → Fresh install → send CMD_TARE (normal)
```
The current bug: hub sent CMD_TARE simply because cylinder_state was UNINSTALLED in memory, without consulting config.json. config.json is the authoritative persistent store — it must be checked first.

---

### What a previous analysis got right and wrong

A prior session proposed a "BLE Connection Manager" to fix ghost connections, add notification re-subscription, and build a self-healing state machine in ble_subscriber.py.

**Right:** Those are real architectural weaknesses. They should be implemented as Phase 2 hardening.

**Wrong:** That analysis blamed these weaknesses as the root cause of the crashes without checking kernel logs first. The actual cause was WCN3990 hardware-level modem crashes — invisible to the application layer. Building the BLE Connection Manager without fixing READING_STALE_S would not have prevented a single hub reboot.

**Rule confirmed and locked in:** Always establish root cause from kernel logs (`journalctl -k`) before designing any fix. Code review is not root cause analysis.

---

## HUB REBOOT TIMELINE (from `last reboot` output)

```
Boot -7:  Fri 26 Jun 16:59  →  Sat 27 Jun 06:52  (13h 53min) → CRASH (modem)
Boot -6:  Sat 27 Jun 06:52  →  Sat 27 Jun 17:08  (10h 16min) → CRASH (modem)
Boot -5:  Sat 27 Jun 17:08  →  Sat 27 Jun 17:55  (47 min)    → CRASH (modem)
Boot -4:  Sat 27 Jun 17:55  →  Sat 27 Jun 18:45  (50 min)    → ??? (boot -4 connected to node boot 38 → wrong tare fired)
Boot -3:  Sat 27 Jun 18:45  →  Sun 28 Jun 00:13  (5h 28min)  → CRASH (modem)
Boot -2:  Sun 28 Jun 00:13  →  Sun 28 Jun 12:02  (11h 49min) → CRASH (modem)
Boot -1:  Sun 28 Jun 12:02  →  Mon 29 Jun 11:02  (23h)       → 90 modem crashes, ZERO watchdog reboots ← PROOF FIX WORKS
Boot  0:  Mon 29 Jun 11:02  →  running                        ← current session
```

### Node boot timeline (from node logs)
```
Node boot 36:  26 Jun ~16:53  →  27 Jun ~17:24  (88,277s = 24.5h) → silent reboot (no error)
Node boot 37:  27 Jun ~17:24  →  27 Jun ~17:57  (2,016s = 33 min) → silent reboot (no error)
Node boot 38:  27 Jun ~17:57  →  CMD_TARE fired at t=43s           → EXPERIMENT DESTROYED
```

---

## UPDATED EXPERIMENT ROADMAP

| Status | ID | Purpose | Gate |
|--------|-----|---------|------|
| DONE ✓ | 3E-001 | Noise floor characterisation | Locked |
| DONE ✓ | 3E-002 | Linearity test | Locked |
| DONE ✓ | 3E-004 | Calibration verification | Locked |
| DONE ✓ | 3E-E005 | Calibration + full run | Locked |
| **DO NOW** | Fixes 1–4 | Hub watchdog, WiFi power, TARE protection, ESP32 reset logging | Before re-run |
| NEXT | 3E-009 ×3 | Long-run stability: stabilisation time, stable value range, drift budget | After fixes |
| NEW | 3E-ENV | Environmental interference: humans, fans, lights, internet load — characterise and protect | After 3E-009 passes |
| AFTER | 3E-008 | Thermal drift: cal_factor vs temperature — mandatory for gas% accuracy | After 3E-ENV |
| QUEUE | 3E-006B | Minimum detectable weight change | Later |
| QUEUE | 3E-007B | False positive testing | Later |
| QUEUE | 3E-010 | Failure injection (remove node, kill hub, pull power) | Later |
| QUEUE | 3E-ZERO | Functional zero — run-to-empty per cylinder brand | Later |
| GATE | Phase 2 | Production revert all 12 test constants; all experiments passed | End |

### 3E-ENV — new experiment (not yet designed)
Motivation: 3E-009 showed a 430g thermal excursion amplitude (morning sun). Before gas% can be trusted in a real home, we need to know what other environmental factors cause drift and by how much. Candidates: direct sunlight, fans/AC, multiple people in the kitchen, heavy internet traffic on the same WiFi, all lights on vs off.

---

## PRODUCTION REVERT — REQUIRED BEFORE PHASE 2

**12 test constants** must be reverted to production values before Phase 2. NONE of these have been changed since 3E-009 setup. All still at test values.

**Hub-side (domain.py) — 7 constants:**

| Constant | Current (TEST) | Production |
|----------|---------------|------------|
| NET_GAS_G | 4535.0 | 14200.0 |
| ALERT_AMBER_DAYS | 0.10417 (2.5h) | 5.0 |
| ALERT_RED_DAYS | 0.0625 (1.5h) | 3.0 |
| ALERT_AMBER_G | scaled | production value |
| ALERT_RED_G | scaled | production value |
| FUNCTIONAL_ZERO_G | 1300.0 (placeholder) | from 3E-ZERO experiment (not yet run) |
| STEEL_PLAUSIBLE_MIN_G | 13000.0 | review before reverting |
| STEEL_PLAUSIBLE_MAX_G | 18000.0 | review before reverting |
| REFILL_GROSS_MIN_G | 22000.0 | review before reverting |

**Node-side firmware — 1 constant:**
- Check node firmware for any test-specific threshold values before Phase 2

Full production revert reference document: `hub/docs/GasMonitor_Complete_Revert_Reference.docx` (committed to git)

---

## KEY FILE PATHS

```
Project root:       ~/ArduinoApps/gas-cylinder-monitor/
Hub Python:         hub/python/
  main.py           Entry point, startup logic, BLE-hub coordination
  ble_subscriber.py BLE connection management
  domain.py         All domain constants and domain logic
  db.py             SQLite operations
  hub_watchdog.py   READING_STALE_S lives here (fix target for Fix 1)
  log_transfer.py   Node log retrieval

Hub assets:         hub/assets/index.html
Config (state):     hub/data/config.json       ← authoritative persistent state
SQLite DB:          hub/data/monitor.db
Hub logs:           hub/logs/hub/hub.log        (RotatingFileHandler 10MB×5)
Node logs:          hub/logs/node/              (per-connection log files)
Host watchdog:      hub/watchdog_host.sh
Watchdog service:   /etc/systemd/system/gas-cylinder-watchdog.service

Project docs:       hub/docs/                   (all reference .docx files)
CLAUDE.md:          project root                (rules for Claude Code)
SESSIONS.md:        project root
EXPERIMENT_PROGRAM.md: project root
LEARNINGS_AND_INSIGHTS.md: project root
```

---

## ACCESS AND TOOLING

```bash
# SSH (always use hostname, never IP)
ssh arduino@AQ3

# Hub log (most recent 100 lines)
tail -100 ~/ArduinoApps/gas-cylinder-monitor/hub/logs/hub/hub.log

# Node logs (list most recent)
ls -lt ~/ArduinoApps/gas-cylinder-monitor/hub/logs/node/ | head -10

# SQLite (example targeted query — never SELECT * without WHERE + LIMIT)
sqlite3 ~/ArduinoApps/gas-cylinder-monitor/hub/data/monitor.db \
  "SELECT COUNT(*), MIN(ts), MAX(ts), MIN(gas_g), MAX(gas_g), AVG(gas_g) FROM readings WHERE state='TRACKING';"

# Config
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json

# Watchdog status
systemctl status gas-cylinder-watchdog.service

# Hub Docker container
docker ps | grep gas
docker logs <container_name> --tail 50

# Kernel log (for modem crash diagnosis)
journalctl -k --since "2 hours ago" | grep -E "(crash|error|wifi|modem|ath10k)" | tail -30
```

**Node firmware flashing:** Arduino IDE on Windows laptop, COM11. Node is ESP32-C3 SuperMini.

---

## FIRST ACTIONS FOR NEW CHAT — STEP BY STEP

### Step 1: Verify current state
```bash
ssh arduino@AQ3
systemctl status gas-cylinder-watchdog.service
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json
```
Confirm: watchdog active, tare_raw=-107041.4, cal_factor=36.2231, steel_g=null.

### Step 2: Fix 1 — READING_STALE_S (via Claude Code CLI)
Open hub_watchdog.py in Claude Code. Find READING_STALE_S. Change 900 → 1800. Restart hub Docker container. Verify watchdog is happy.

### Step 3: Fix 2 — WiFi power save (via Claude Code CLI)
First check: `iwconfig wlan0 | grep -i power`
Disable now: `sudo iwconfig wlan0 power off`
Make permanent: determine what network management AQ3 uses (NetworkManager? systemd-networkd? rc.local?) then implement a dynamic, non-hardcoded permanent disable.

### Step 4: Design Fix 3 — CMD_TARE protection (design in chat first, then code via CLI)
Read the current startup logic in main.py that decides when to send CMD_TARE vs SKIP_TARE.
Design the cross-check logic in chat. Agree on approach. Then implement via Claude Code.

### Step 5: Fix 4 — ESP32 reset reason (discuss in chat, implement later)
This needs Arduino IDE on Windows. It can be deferred until the next time the node firmware needs to be flashed for any reason. Document the change needed.

### Step 6: Prepare for next 3E-009 run
- Remove stone from platform
- Verify hub sends CMD_TARE with empty platform (clean node tare)
- Stone back on, experiment start
- Record start time, log boot numbers

---

## KEY PHYSICS AND DOMAIN FACTS (locked in)

- **Kelvin-Voigt creep:** `ε(t) = (σ/E) × [1 − exp(−t/τ)]` — τ is load-independent, magnitude scales with load. 20kg stone gives ~37× better SNR than 5kg water bowl at same plateau timing.
- **Creep plateau time confirmed:** ~2h 45min for 20kg stone on this platform
- **Burn rate corruption** occurs during creep phase because `gas_consumed` delta doesn't cancel until plateau — this is why MIN_DATA_HOURS=24h gate is correct
- **Steel cancels in delta:** gas_consumed = gross_g − steel_g; burn rate and session data are exact from Day 1 across all install versions
- **FUNCTIONAL_ZERO_G** (1300g) is a conservative placeholder — must be determined per brand via 3E-ZERO experiment (run-to-empty). Weight sensors cannot detect the exact moment the burner dies (regulator stops on pressure, not weight).
- **tare_raw absorbs the physical platform permanently** — rubber mats, drip trays, fixtures become invisible to the system. They must not be added/removed after tare without a fresh tare.
- **HX711 runs at 10Hz** (hardware-locked, JP1 unpopulated). BLE notifies every 30s. This is intentional — prevents WCN3990 chip crashes from excessive BLE traffic.

---

## HARDWARE QUICK REFERENCE

| Component | Detail |
|-----------|--------|
| Hub board | Arduino UNO Q (AQ3), SKU ABX00162/ABX00173 |
| Hub MPU | Qualcomm QRB2210, 4× Cortex-A53, Debian Linux |
| Hub MCU | STM32U585, Cortex-M33, Zephyr + Arduino Core |
| BLE/WiFi | WCBN3536A module (WCN3990 chip) — modem firmware crashes are a known platform characteristic |
| Node | ESP32-C3 SuperMini |
| ADC | GISLAB HX711 (AVIAIC chip), 3.3V ONLY, 10Hz fixed |
| Load cells | 3× YZC-161A 20kg, parallel wired |
| HX711 wiring | DT=D7, SCK=D6 ONLY — never change |
| CAL_FACTOR | 36.2231 raw/g (from hub), 106.7 raw/g (node internal) |
| Voltage discipline | MCU headers: 3.3V logic (5V tolerant except A0, A1). MPU headers (JCTL, JMISC): **1.8V ONLY** — 3.3V = hardware damage |

---

## DATA PROTOCOL (permanent — established 29 Jun 2026)

**NEVER paste raw data into chat.** Every data interaction must follow this protocol:

| Source | What to do | What NOT to do |
|--------|-----------|----------------|
| SQLite | `SELECT COUNT(*), MIN(), MAX(), AVG()` with WHERE clause | `SELECT *` or full table dumps |
| Hub logs | `grep -E "pattern" hub.log \| tail -30` | `cat hub.log` |
| Node logs | `grep -E "pattern" logfile \| head -20` | `cat logfile` |
| Complex analysis | Write Python script on AQ3 via Claude Code → run it → paste only the output summary (~20 lines max) | Paste the script output if it's hundreds of lines |

---

## LEARNINGS LOCKED IN FROM THIS SESSION (29 Jun 2026)

1. **WCN3990 modem firmware crashes are a fact of this platform.** Every BLE-dependent application must give the modem enough recovery time. READING_STALE_S must be ≥20 minutes minimum.

2. **Watchdog thresholds must be calibrated against platform hardware characteristics, not arbitrary values.** 15 minutes felt reasonable; it was wrong. Always derive from measured recovery time + buffer.

3. **Hub restart state recovery must be robust.** config.json is the authoritative persistent store. Hub must NEVER trigger a new node tare if steel_g is already anchored in config.json, unless a CROSS_CHECK actively fails.

4. **Node ESP32 spontaneous reboot is a separate firmware-level issue.** It is not caused by BLE problems or hub crashes. It needs firmware-level instrumentation (esp_reset_reason) before the cause can be known.

5. **Kernel logs are the authoritative source for crash diagnosis** — not application-level code review. `journalctl -k` tells you what actually happened. Code review tells you what could theoretically go wrong.

6. **Thermal excursion (430g peak-to-trough) is the headline finding from 3E-009 partial data.** This makes 3E-008 (thermal drift characterisation) mandatory before gas% readings can be trusted in a real home.

7. **The prior BLE Connection Manager proposal was correct code review but wrong root cause attribution.** Those fixes are still valid and should be implemented in Phase 2 hardening. They were not the crash root cause.

8. **Data protocol must be enforced from the start of every session.** Pasting raw log data into chat burns context fast and makes analysis error-prone. SQL aggregates and grep summaries only.

---

## SESSION CLOSE STATUS

### What was done in this session (29 Jun 2026, sessions 1+2)
- Analysed 3E-009 SQLite data (2841 TRACKING rows) — targets, curve shape, findings
- Read and parsed node logs (boots 36, 37, 38) — crash sequence reconstructed
- Read kernel logs — identified WCN3990 as primary root cause
- Built evidence-based root cause analysis (3 confirmed causes)
- Corrected prior analysis that blamed BLE Connection Manager incorrectly
- Established permanent data protocol
- Added 3E-ENV to experiment roadmap
- Created annotated timeline chart (gas_g vs time with all events marked)
- Created this handoff document

### Session close protocol items (to be done via Claude Code CLI on AQ3)
- [ ] CLAUDE.md updated
- [ ] SESSIONS.md appended
- [ ] LEARNINGS_AND_INSIGHTS.md appended
- [ ] git committed

These should be done at the START of the next session once Claude Code is open, before any fixes are implemented.

---

*Handoff generated: 29 Jun 2026 | Session 2 | 3E-009 analysis complete*
*Next handoff filename: HANDOFF_2026_06_29_SESSION3_[DESCRIPTION].md or HANDOFF_2026_06_30_SESSION1_[DESCRIPTION].md*
