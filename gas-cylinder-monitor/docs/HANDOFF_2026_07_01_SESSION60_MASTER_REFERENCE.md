# Gas Cylinder Monitor V1 — Master Project Reference
**Gratian Technologies · Project 13**
**Last updated: 2026-07-02 · Session 61**
**Purpose: Single authoritative reference from current state to final shipped product**

> Load this document at the start of every session. It supersedes all previous handoff documents.
> Updates are targeted-section edits, not full rewrites — see CHANGELOG below and
> `docs/SESSION_CLOSE_PROTOCOL.md` for the update discipline. Full audit due at Session 65
> (5-session cadence) or the next phase gate, whichever comes first.

---

## CHANGELOG (most recent first — never delete old lines)

- **Session 62 addendum 2:** CYLINDER_ABSENT design UNBLOCKED — resolved via
  weight-match-not-duration, plus new explicit "Uninstall" button requirement.
  Connectivity-gap handling upgraded from a flat fallback to a tiered recovery
  hierarchy. `config.json` mystery reopened — proven live and reproducible (not a
  bad terminal read), leading hypothesis shifted to a host-vs-container file mismatch,
  pending direct verification.
- **Session 62 addendum:** Cooking Intelligence (Part 9) expanded with the full
  event-based/whistle-tracking design — a major, explicitly high-priority product goal,
  permanently documented per the product owner's request. Also: corrected an earlier
  same-session claim about the health.cpp "stuck" check's failure direction — source
  re-verification in progress rather than trusting a months-old note either way.
- **Session 61 addendum:** before trimming `PROJECT_CONTEXT.md` down to its new scoped
  role, salvaged three items that existed nowhere else in this master reference: HUB-001
  and HUB-002 (deferred hub features, Part 9) and two unconfirmed firmware TODOs from
  2026-06-18 (Part 7). Caught by the person reviewing the CLI's proposed diff before
  approving it — the diff would have been correct once salvage was done, but wasn't
  wrong to pause on.
- **Session 61 (2026-07-02):** Fix 4 (`esp_reset_reason` + `heap_caps_get_largest_free_block`)
  implemented, flashed, and verified live on node boot 45. N-TARE-CHECK and
  `HEAVY_LOAD_THRESHOLD_G=2000g` confirmed **already implemented** — no new firmware work
  needed, resolving a stale backlog item. 3E-009 attempt #2 **deliberately deferred** — running
  2–3 more stability attempts before trusting a single 65h run. G5 Analytics / G7 WebUI
  confirmed **not built** (source-verified), resolving an apparent conflict with a stale
  pre-pivot git commit message. UNINSTALLED-state redesign (`CYLINDER_ABSENT` intermediate
  state + weight-matching) designed but not implemented — blocked on one product decision.
  `SESSION_CLOSE_PROTOCOL.md` rewritten to v2 — `PROJECT_CONTEXT.md`/`RESEARCH.md` revived
  with scoped roles, CLI restricted to fact-gathering, master reference now updated by Claude
  in chat with targeted edits instead of full rewrites.

---

## QUICK STATUS BOARD

| Item | Status |
|------|--------|
| Hub session | 61 |
| Node boot | 45 |
| Stone on platform | NO — removed, platform empty |
| Fix 1 — READING_STALE_S→1800 | ✓ DONE |
| Fix 2 — WiFi power save off | ✓ DONE — confirmed survived reboot (Session 61) |
| Fix 3 — CMD_TARE protection | ✓ DONE |
| TZ fix — Docker IST | ✓ DONE |
| Fix 4 — esp_reset_reason + heap_caps | ✓ DONE — verified live on boot 45 (Session 61) |
| N-TARE-CHECK | ✓ DONE — confirmed already implemented, not new work (Session 61) |
| HEAVY_LOAD_THRESHOLD_G restore | ✓ DONE — confirmed already at 2000g (Session 61) |
| config.json atomic writes | NEXT SESSION |
| 3E-009 attempt #2 | DEFERRED — stability confidence campaign (2–3 attempts) first |
| UNINSTALLED / CYLINDER_ABSENT redesign | DESIGNED, UNBLOCKED — ready to implement (weight-match resolves duration question) |
| Test constants reverted | NO — 12 still at test values |
| G5 Analytics / G7 WebUI | CONFIRMED NOT BUILT (source-verified, Session 61) |

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
| App Lab ID | `user:gas-cylinder-monitor/hub` — app.yaml lives in `hub/`, not project root |

---

## PART 3 — CURRENT SYSTEM STATE (2026-07-02)

### config.json (hub, last known — Session 60 snapshot)
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
Note: `steel_g: null` means no valid measurement session. This is the hub's own reference
tare, used by the Fix 3 protective guard — separate from the node's SPIFFS tare below.

**Unverified this session** — flag for next session start: whether the hub's `tare_raw`
field gets updated to reflect the node's fresh Session 61 tare. Not confirmed either way;
check `config.json` at next session open before assuming sync.

### Node state — updated Session 61
- Node re-flashed with Fix 4, now on **boot 45**
- Fresh tare completed on empty platform via CMD_TARE (not SKIP_TARE — `steel_g` was null,
  so Fix 3's guard correctly did not fire): `tare_raw=-96218.4` saved to SPIFFS,
  spread=0.0 (excellent stability, no vibration during tare)
- `cal_factor=36.2231` reapplied via SET_CAL
- Readings post-tare in the 0–20g range — correct for empty platform with sensor noise
- Fix 4 fields confirmed live: `reset=OTHER` at boot (expected — USB/esptool flash reset
  path, not a fault; see Part 13), `heap_max_block=114676` bytes flat across 14+ heartbeats
  post-flash (clean baseline for future fragmentation comparison)

### Hub watchdog
- `READING_STALE_S`: **1800** — unchanged, confirmed still active Session 61
- Service: `gas-cylinder-watchdog.service` — active, confirmed running Session 61

### Database
- 3E-009 attempt #1 data: **CSV export confirmed complete and safe** —
  `hub/data/experiments/readings.csv`, 7867 rows (all states: UNINSTALLED, TRACKING,
  post-bad-tare noise), header and format verified Session 61
- 2841 of those rows are TRACKING-state, hardware-verified `quality=GOOD, sigma=5.99`
  throughout — the valid experimental data from the first 24.5h

---

## PART 4 — 3E-009 POST-MORTEM (LOCKED)

### Three root causes — evidence-confirmed
| RC | Root Cause | Status | Fix |
|----|-----------|--------|-----|
| RC1 | WCN3990 firmware crashes every ~15 min (94 in 23h). Recovery takes 13–17 min. Old 15 min watchdog fired before recovery completed → Linux reboot → cascade. | **PRIMARY** | Fix 1 + Fix 2 |
| RC2 | Node reboot after 24.5h — **proved DOWNSTREAM of RC1**. Boot 36 and boot 37 both ended 1.5 minutes before a Linux reboot. Hub's watchdog reboot dropped BLE; node's NimBLE reset in response. Not an independent node failure. | **REFRAMED / DOWNSTREAM** | Fix 1+2 may eliminate with zero node changes |
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

### Fix 2 — WiFi power save → off (permanent) ✓ DONE
**Why**: Power state transitions are a documented WCN3990 crash trigger.
**Method**: systemd oneshot service with dynamic interface derivation, using `/sbin/iw` (not `iwconfig` — ath10k uses nl80211, not the legacy WEXT interface `iwconfig` requires)
**File**: `/etc/systemd/system/wifi-power-save-off.service`
**Verified Session 61**: Survived a reboot — `systemctl status` showed clean exit, `/sbin/iw dev wlan0 get power_save` confirmed `Power save: off`.
**Long-term principle**: Off permanently on this platform — not a per-experiment toggle. Dynamic interface name always.

### Fix 3 — CMD_TARE cross-check on hub restart ✓ DONE
**File**: `hub/python/ble_subscriber.py` — `_send_tare_commands()` method
**Change**: Guard block reads `steel_g` + `tare_raw` from config.json before any TARE decision. If both non-null → force SKIP_TARE + SET_CAL, return early.
**Log when triggered**: `[BLE_SUB] PROTECTIVE_SKIP: ...`
**Verified Session 61**: Guard correctly did NOT fire when `steel_g` was null — CMD_TARE went through cleanly on an empty platform, exactly as designed.
**Long-term principle**: Two rules must both hold forever: (1) hub never sends CMD_TARE without config confirmation. (2) config.json writes are atomic. Either rule alone is insufficient.

### Fix 4 — esp_reset_reason() + heap_caps per heartbeat ✓ DONE (Session 61)
**Target**: Node firmware (ESP32-C3 SuperMini), `journal.cpp` only
**Method**: Two surgical edits — `journal_boot_start()` gained `esp_reset_reason()` with a switch-mapped string; `journal_heartbeat_tick()` gained `heap_caps_get_largest_free_block(MALLOC_CAP_8BIT)`. New includes: `esp_system.h`, `esp_heap_caps.h`. No other function touched — diff confirmed surgical.
**Verified live**: Boot 45, `#0001 ... [BOOT] event=START fw=1.0 reset=OTHER` and `#0010 ... heap_max_block=114676` both present and correctly formatted.
**Note on `reset=OTHER`**: expected on this boot — a USB/esptool-triggered flash reset doesn't map to any of the named `esp_reset_reason_t` values, so it correctly falls through to OTHER. This is not a fault. Future sessions should expect `POWERON` on clean power cycles and `BROWNOUT`/`TASK_WDT`/etc. only on genuine fault conditions.
**Long-term principle**: `heap_caps_get_largest_free_block()` stays in every heartbeat forever. Downward trend in largest-free-block with stable total-free-heap = unambiguous fragmentation fingerprint. Session 61 baseline: 114676 bytes, flat.

### N-TARE-CHECK ✓ DONE — confirmed already implemented (Session 61)
**Discovery**: Believed pending per Session 60 backlog. Direct source read of the
`STATE_TARE_WAIT` block in `gas_monitor_v1.ino` (lines ~122–175) showed the
`TIMEOUT_SAVED_TARE` branch already does exactly this: if SPIFFS has a saved tare+cal and
current weight exceeds `HEAVY_LOAD_THRESHOLD_G`, skip fresh tare, preserve the saved value,
set `g_cal_degraded=true`.
**Action taken**: None — verified working as-is. Backlog item closed without code change.
**Principle for future sessions**: verify backlog items against actual firmware source
before assuming a fix is still pending. Tracking docs can go stale in the other
direction too — marking something as TODO when it's already done wastes a session.

### HEAVY_LOAD_THRESHOLD_G ✓ DONE — confirmed already at 2000g (Session 61)
**Discovery**: Same source read confirmed `static const float HEAVY_LOAD_THRESHOLD_G = 2000.0f;` already in place — the 1000g→2000g restore from the Session 60 backlog had already happened, untracked.
**Action taken**: None — verified, not re-changed.

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

### 3E-009 — Long-run stability (STABILITY CAMPAIGN IN PROGRESS)
**What**: 65h continuous run with 20kg stone on 3-cell platform
**Attempt 1**: FAILED at 24.5h — three confirmed root causes (see Part 4)
**Attempt 2**: **Deliberately deferred (Session 61)** — decision made to run 2–3 stability
attempts over coming days before trusting Session 60's fixes on the strength of a single
65h run. This is a decision, not a failure or a blocker — fixes 1–4 are all verified
individually; what remains unproven is their combined effect over a genuinely long run.
**Pass criteria** (unchanged):
- 65h continuous, no watchdog reboots
- No CMD_TARE events (PROTECTIVE_SKIP should be visible in logs if triggered)
- Stable sigma throughout
- node reboots absent or dramatically reduced (confirms RC2 downstream hypothesis)
**Data target**: Full creep curve, stable plateau value, confirmed drift budget

### 3E-008 — Thermal drift characterisation (MANDATORY GATE)
**Gate**: Must pass 3E-009 first (i.e. after the stability campaign concludes)
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
**Why mandatory**: `FUNCTIONAL_ZERO_G` cannot be assumed — the gas regulator stops on pressure, not weight. The amount of LPG remaining when pressure drops below regulator cutoff is unknown and varies by cylinder brand and age. Design already locked in `GasMonitor_FunctionalZero_Design.docx` (2026-06-25) — implementation blocked on this experiment's real data, not on further design work.
**Method**: Install a real cylinder, monitor until stove flame dies, record weight at that moment.
**Output**: Confirmed `FUNCTIONAL_ZERO_G` per cylinder brand — replaces the current 1300g placeholder.
**Production impact**: Without this, LOW_GAS alerts fire at wrong thresholds and "days remaining" is uncalibrated.

### Remaining experiment queue
| ID | What | Gate | Answers |
|----|------|------|---------|
| 3E-006B | Minimum detectable weight change | After 3E-009 campaign | Smallest removal system reliably detects |
| 3E-007B | False positive rate | After 3E-009 campaign | How many false removal triggers on stable load |
| 3E-010 | Load cell failure injection | After 3E-ENV | Does health module detect open cell correctly |

---

## PART 7 — V1 BUILD REMAINING

### Node firmware — pending
| Item | Status | What | How |
|------|--------|------|-----|
| Fix 4 (reset reason + heap_caps) | ✓ DONE (Session 61) | Observability + hypothesis confirmation | — |
| N-TARE-CHECK | ✓ DONE — already implemented, confirmed (Session 61) | Hub-offline self-protect | — |
| HEAVY_LOAD_THRESHOLD_G | ✓ DONE — confirmed at 2000g (Session 61) | Restore from test value | — |
| UNINSTALLED / CYLINDER_ABSENT redesign | **DESIGNED, UNBLOCKED (Session 62)** | See Part 13 — weight-match resolves duration, plus new explicit "Uninstall" button (WebUI + app) | Hub-side (`domain.py`) — ready to implement, not firmware |

### Hub software — pending
| Item | Status | What |
|------|--------|------|
| config.json atomic writes | NEXT SESSION | Write safety for all modules that touch config |
| UNINSTALLED / CYLINDER_ABSENT state machine | DESIGNED, blocked on product decision | `CYLINDER_ABSENT` intermediate state + weight-matching on return + explicit uninstall button — replaces the current 120s timeout-only logic (see Part 13) |
| G5 Analytics | **CONFIRMED NOT BUILT** (Session 61, source-verified) | Burn rate from real data only. Rolling 7-day average. Days remaining calculation. |
| G7 WebUI | **CONFIRMED NOT BUILT** (Session 61, source-verified) | Full dashboard: gas gauge, trend chart, prediction, brand picker, alert display |
| BLE Connection Manager | PHASE 2 | Ghost connection self-healing. Track 2 — defense-in-depth only. |
| TODO-1B-stuck | **UNCONFIRMED STATUS** | As of 2026-06-18, `tare_variance_raw` was always `0.0f`, making the health module's "stuck" check never actually trigger. Verify against current `tare.cpp`/`health.cpp` before assuming still open — salvaged from `PROJECT_CONTEXT.md` Session 61, not re-checked. |
| TODO-1B-persistence | **UNCONFIRMED STATUS** | As of 2026-06-18, `prev_cal_factor`/`prev_sigma_g` were not persisted to config.json across boots, so cal-drift and erratic checks skipped every boot. Verify against current `health.cpp` before assuming still open — salvaged from `PROJECT_CONTEXT.md` Session 61, not re-checked. |

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

## PART 8 — SESSION SEQUENCE

### Session 61 (2026-07-02) — COMPLETE
1. Verified Fixes 1–3 survived intact, watchdog and hub running
2. Confirmed 3E-009 attempt #1 CSV export safe (7867 rows)
3. **Decision: paused 3E-009 attempt #2** — running 2–3 more attempts over coming days first
4. Fix 4 designed, flashed, verified live on boot 45
5. Discovered N-TARE-CHECK and HEAVY_LOAD_THRESHOLD_G already implemented — closed without code change
6. Resolved G5/G7 status discrepancy — confirmed genuinely not built
7. Reconstructed full week (June 29 – July 2) from chat history + git log + live board state, catching the project-knowledge staleness issue
8. Designed UNINSTALLED/CYLINDER_ABSENT redesign — blocked on one product decision
9. Rewrote `SESSION_CLOSE_PROTOCOL.md` to v2

### Session 62 (next)
1. **First action**: answer the cylinder-removal-duration question (see Part 13) to unblock the UNINSTALLED redesign
2. Implement config.json atomic writes — all hub Python modules
3. Implement UNINSTALLED/CYLINDER_ABSENT state machine once unblocked
4. Launch 3E-009 attempt #2 (first of the stability campaign) — 65h run, walk away
5. WCN3990 crash frequency investigation if attempt #2 shows continued instability

### Session 63 (after attempt #2, and #3 if needed)
1. Analyze stability campaign results — did the combined fixes hold across multiple runs?
2. If stable: proceed to 3E-008 thermal drift design
3. If not stable: return to RCA with the new Fix 4 telemetry (reset reasons, heap trend) as evidence

### Sessions 64+ (Phase 2)
1. 3E-008 → 3E-ENV → 3E-ZERO in sequence
2. G5 Analytics — burn rate, days remaining
3. G7 WebUI — full dashboard
4. BLE Connection Manager — Phase 2 hardening
5. Revert all 12 test constants
6. 3E-006B, 3E-007B, 3E-010 — remaining experiments
7. Final production gate check
8. Ship

---

## PART 9 — V2 ROADMAP

### Deferred hub features (salvaged from PROJECT_CONTEXT.md, Session 61)
| Item | What | Why deferred | Status / gate |
|------|------|---------------|----------------|
| HUB-001 — Auto-retare on cylinder removal | Hub detects a REMOVED event, waits for a settle gate (two consecutive heartbeats within 2×sigma), sends RETARE automatically | **Rejected as too dangerous** — could fire while a cylinder is still on the platform (locked decision, 2026-06-24) | Superseded by the RETARE button below |
| RETARE WebUI button (Option B) | User-explicit button, visible only when `cylinder_state=UNINSTALLED`, confirmation dialog before firing RETARE | Chosen as the safe alternative to HUB-001 | **Designed, not built** — this is the actual V1/V2 path forward, not HUB-001 |
| HUB-002 — Disturbance detection | Platform physically moved with the cylinder still on it — no WEIGHT_EVENT fires since total weight is unchanged. Detected via a heartbeat delta exceeding 5× expected consumption with no matching weight-event | Needs a trusted burn rate to compute "expected consumption" | Gated on G5 Analytics (confirmed not built) |

### Cooking Intelligence (G8/G9/G10) — expanded design, Session 62

**Core architectural insight (locked):** this feature requires **zero changes** to node
firmware, HX711, load cell, or BLE transport. It is entirely a hub + companion-app
feature that bookmarks timestamps onto the continuous weight-vs-time data already
being collected, then computes deltas between bookmarks. The system never needs to
"detect" a whistle from the sensor — an external channel (voice assistant or companion
app) tells the hub *when* an event happened, and the hub looks up what the weight
curve was doing at that moment.

**Precision bound:** resolution is limited to the locked 30-second BLE notify interval
— an event timestamp is matched to the nearest ~30s data point. For typical multi-minute
gaps between cooking events, this is a small fraction of the interval and should not
materially affect accuracy. Worth re-measuring once real sessions are logged, not
assumed correct in advance.

**G8 — Event-based session tracking (replaces any fixed-duration window)**
- A "cooking session" is bounded by two events: an explicit start marker and an
  explicit end marker, of arbitrary duration — not a fixed analytics window.
- Trigger sources: voice command via a connected assistant integration, or a
  button/action in the companion app.
- Output: total gas consumed (g and %) across the session = weight_at_start −
  weight_at_end, adjusted for known noise floor.
- Queryable after the fact — immediately, that evening, or days later — since it's
  just a stored record referencing two already-logged timestamps.

**G9 — Dish tagging**
- User names the dish via voice or companion app, before or after the session
  (e.g., "gongura mutton").
- Session record stores: dish name, start ts, end ts, gas consumed, wall-clock duration.
- Enables per-dish history: "how much gas does gongura mutton usually take?"

**G10 — Sub-event granularity within a session (the whistle-count case)**
This is an explicitly **major, high-priority goal**, not a minor nice-to-have —
stated directly by the product owner as "very very important and one of our goals."
- A session can contain an arbitrary number of ordered sub-event bookmarks, not just
  start/end.
- Concrete worked example: user says "start cooker, 5 whistles." System logs session
  start. Each subsequent whistle is its own timestamped bookmark within the session.
- For N bookmarks (start, whistle_1, whistle_2, ..., whistle_N), the system computes,
  for every consecutive pair: elapsed time (t_i) and gas consumed (x_i) between them —
  t1/x1 between start and whistle 1, t2/x2 between whistle 1 and whistle 2, and so on.
- At session end (5th whistle in the example), report the full per-segment breakdown
  *and* the aggregate total time and total gas across the whole session.

**What this needs, concretely, once V1 ships:**
1. A voice/companion-app event-input channel — new, does not exist yet, entirely
   separate from the sensor pipeline
2. A `sessions` table in the hub's SQLite schema: session_id, dish_name (nullable),
   created_at
3. A `bookmarks` table: session_id, label (start / whistle_N / end), ts,
   weight_at_bookmark_g
4. A simple aggregation query: for each consecutive bookmark pair, Δt = ts_next −
   ts_prev, Δgas = weight_prev − weight_next
5. Companion app UI to browse sessions and dishes historically

**Timing precision — solved without touching BLE (Session 62):** the temptation is to
speed up BLE notifications for finer whistle-timing resolution — this must never
happen. `BLE_NOTIFY_INTERVAL_MS=30000` is locked specifically because faster rates
crash the WCN3990 (the exact failure class this whole project has fought all session).
The correct fix needs no firmware change at all: a whistle's timestamp comes from the
phone/voice assistant, not from the weight sensor, so it already has whatever
precision that platform provides. Only the *gas-consumed* number needs the weight
curve — and since burn rate during active cooking is smooth, linear interpolation
between the two 30-second readings bracketing the event timestamp gives an accurate
estimate with zero hardware risk:
```
weight_at_event ≈ W_before + (W_after − W_before) × (t_event − t_before) / (t_after − t_before)
```
Residual error is bounded by how non-linear burn rate is within a single 30s window —
expected small, but should be validated against real cooking-session data once
collected, not assumed correct in advance.

**Known limitation — connectivity gaps during a session, tiered recovery design (Session 62):**
if a BLE/WCN3990 outage occurs during a whistle-tracking session, the hub may have
zero weight data for part or all of that session — a real, serious gap, not a
theoretical one. Rather than one flat fallback, a cascading hierarchy — try the best
available answer first, degrade gracefully, never fabricate:
1. **Normal case:** real BLE readings, bracket-interpolate as designed above.
2. **Gap, but node-side backfill available:** retrieve the node's own SPIFFS journal
   via the existing `DUMP_LOG` mechanism once reconnected — this is real recorded data,
   just delayed, not an estimate. Strictly preferred over step 3 whenever available.
   (Capacity vs. outage duration still needs checking — see below.)
3. **Gap, no backfill, but the session's start and end readings are both real:** the
   *whole-session total* (start weight − end weight) is still fully trustworthy even
   if a gap sits in the middle — only the *internal* per-whistle breakdown touching the
   gap is compromised. Show the confirmed total, and mark only the specific affected
   segment(s) as unavailable — don't discard the whole session over a partial gap.
4. **Gap covering a session boundary itself** (e.g. the final whistle's own reading is
   missing): no total can be honestly computed. This is the only case that falls back
   to "gas data unavailable — connectivity gap during this session." Last resort, not
   first response.
This ties to the same conservative-bias principle already locked for gas estimates
generally: prefer a smaller, honestly-scoped confirmed number over a larger fabricated
one, and always label anything short of a direct measurement as such in the UI.

**Interpolation safeguard:** never bracket-interpolate across a window where a
`WEIGHT_EVENT` (PLACED/REMOVED) fired, or where either bracketing reading's `quality`
was not `GOOD`. Interpolation assumes a smooth, undisturbed process — if the data
itself suggests something abrupt happened, that assumption no longer holds, and the
gap should be treated as unavailable (or backfilled/totaled per the hierarchy above)
rather than smoothed over.

**Known limitation in the safeguard itself (Session 62):** the jump/quality check above
only catches *discrete* disturbances. It does NOT catch a **rate change** — e.g. a user
turning the flame down right after a whistle, which is common real cooking behavior and
clusters disproportionately near exactly the moments this feature cares about most.
Burn rate isn't perfectly constant across a 30s window in general, and is least likely
to be constant specifically in whistle-adjacent windows. Two refinements, not a full
retreat from interpolation:
1. **Widen uncertainty near whistle bookmarks explicitly.** Any interpolated segment
   touching a whistle-adjacent window should carry a stated error band in the UI/data
   model (e.g. "~14g, ±4g estimated"), not a bare confident number — false precision is
   its own honesty failure, distinct from a bare wrong number.
2. **Unvalidated idea, needs its own safety test before trusting:** an on-demand extra
   reading, requested by the hub over the existing command channel the instant a
   whistle bookmark arrives from the phone — a sparse, rare, event-triggered single
   read, not a sustained rate change. This is a *different traffic pattern* than the
   sustained 1-second polling already proven dangerous, but different is not the same
   as proven safe — would need a dedicated small experiment (an hour of occasional
   on-demand reads, watching WCN3990 crash rate) before ever relying on it.

**SPIFFS backfill capacity — needs checking, not yet done:** at the current ~113
bytes/journal-line and 30s heartbeat interval, a 40-minute outage would produce ~9KB of
node-side journal data. Needs comparing against the actual SPIFFS partition size and
`JOURNAL_TRANSFER_THRESHOLD_BYTES` auto-push/clear threshold to confirm the buffer
wouldn't rotate away before a delayed reconnect can retrieve it.

**Explicitly NOT required:** any node firmware change, any HX711/load-cell change,
any BLE protocol change, any change to the watchdog. Entirely additive on the hub +
companion-app side, built on data the system already collects.

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
- [ ] 3E-009 passes — 65h clean run, no watchdog reboots, no CMD_TARE events (campaign in progress)
- [ ] 3E-008 complete — thermal drift characterised and within acceptable budget
- [ ] 3E-ENV complete — environmental interference characterised
- [ ] 3E-ZERO complete — FUNCTIONAL_ZERO_G confirmed experimentally (not placeholder)
- [ ] 3E-006B, 3E-007B — min detectable change and false positive rate characterised
- [ ] 3E-010 — load cell failure injection verified

**Code**
- [ ] All 12 test constants reverted to production values (all reviewed, none skipped)
- [x] Fix 2 confirmed surviving reboot (WiFi power save off persistent) — verified Session 61
- [x] Fix 4 deployed — esp_reset_reason + heap_caps in every heartbeat — verified Session 61
- [x] N-TARE-CHECK deployed in node firmware — confirmed already present, Session 61
- [ ] config.json atomic writes implemented in all hub modules
- [ ] UNINSTALLED/CYLINDER_ABSENT redesign implemented (blocked on product decision)
- [ ] G5 Analytics built, tested with real data
- [ ] G7 WebUI built and verified end-to-end
- [ ] BLE Connection Manager built (Phase 2 hardening)

**Platform**
- [x] READING_STALE_S=1800 — re-verify if BSP has changed
- [ ] DISABLE_AUTOUPDATER=1 confirmed in `~/.bashrc` (re-verify each session)
- [ ] Docker TZ verified IST after any container rebuild
- [x] WiFi power save confirmed off after reboot — verified Session 61

---

## PART 11 — KEY FILE PATHS

```
Project root:               ~/ArduinoApps/gas-cylinder-monitor/
Hub Python:                 hub/python/
  main.py                   Entry point — TZ fix at top (lines 1–4)
  ble_subscriber.py         BLE transport + CMD_TARE protection (Fix 3 done)
  domain.py                 All domain constants and state machine (test constants here;
                             UNINSTALLED/CYLINDER_ABSENT redesign lands here once unblocked)
  db.py                     SQLite abstraction — no domain logic ever
  hub_watchdog.py           READING_STALE_S = 1800 (Fix 1 done)
  log_transfer.py           Node log retrieval

Hub assets:                 hub/assets/index.html
Config (state):             hub/data/config.json          ← authoritative persistent state
SQLite DB:                  hub/data/monitor.db
CSV export:                 hub/data/experiments/readings.csv   (7867 rows, attempt #1)
Hub logs:                   hub/logs/hub/hub.log           (RotatingFileHandler 10MB×5)
Node logs:                  hub/logs/node/                 (node_YYYY-MM-DD_bootNN.log)
Host watchdog script:       hub/watchdog_host.sh
Watchdog service:           /etc/systemd/system/gas-cylinder-watchdog.service
WiFi power save service:    /etc/systemd/system/wifi-power-save-off.service   ← Fix 2, DONE

Project docs:                docs/
Analysis scripts:            docs/analyse_crashes.py
CLAUDE.md:                   project root    ← Claude Code briefing
PROJECT_CONTEXT.md:          docs/           ← one-screen glance, revived Session 61
SESSIONS.md:                 docs/           ← session log (append only)
RESEARCH.md:                 docs/           ← hardware-verified facts, revived Session 61
LEARNINGS_AND_INSIGHTS.md:   docs/           ← permanent learnings (append only)
SESSION_CLOSE_PROTOCOL.md:   docs/           ← v2 as of Session 61 — authoritative for close steps
Revert reference:            docs/GasMonitor_Complete_Revert_Reference.docx

Git remote:                  gratiantechnologies/project13
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
# If session expired: run `claude`, then type /login inside the interactive session
```

### Essential hub commands
```bash
# Live hub logs — native App Lab way (preferred, discovered Session 61)
arduino-app-cli app logs user:gas-cylinder-monitor/hub --follow
# Note: the App Lab ID is gas-cylinder-monitor/hub, NOT gas-cylinder-monitor —
# app.yaml lives in hub/, so that's the registered path. Check with:
arduino-app-cli app list

# Hub logs — file-based alternative
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

# Hub container (only needed if arduino-app-cli approach doesn't fit the task)
docker ps | grep gas
docker logs $(docker ps --filter name=gas -q) --tail 50
docker restart $(docker ps --filter name=gas -q)

# Kernel log — modem crashes (ALWAYS check this first on any stability failure)
journalctl -k --since "2 hours ago" | grep -E "(crash|error|wifi|modem|ath10k)" | tail -30

# Modem crash count in last 24h
journalctl -k --since "24 hours ago" | grep -c "firmware crashed"

# WiFi power save status
/sbin/iw dev wlan0 get power_save

# Network interface (dynamic — never hardcode wlan0)
/sbin/iw dev | awk '/Interface/{print $2; exit}'

# Crash correlation analysis
python3 ~/ArduinoApps/gas-cylinder-monitor/hub/docs/analyse_crashes.py
```

### Node firmware flashing
- **Tool**: Arduino IDE v3.0.7 on Windows laptop (v3.3.9 is broken on Windows — do not use)
- **Sketch path on Windows**: `C:\Users\mahes\Documents\Arduino\<sketch_name>\` — this is
  where Arduino IDE expects sketches. `C:\Users\mahes\Downloads\` is reserved for
  handoff/documentation files only, never sketch source. (Corrected Session 61 — a prior
  session's memory note had this wrong.)
- **Port**: COM11
- **Board setting**: ESP32C3 Dev Module
- **Critical setting**: USB CDC On Boot = **ENABLED**
- **Upload failures**: lower baud rate to 115200 — NEVER use "Erase All Flash"
- **Flash wipes SPIFFS**: power cycle does not — SPIFFS accumulation tests use power cycle only
- **Windows filename trap**: if downloading a file with the same name as one already in
  Downloads, Windows appends `" (1)"` **with a leading space**. `scp` needs the full path
  quoted in that case — `scp "C:\...\name (1).md" ...` — or the wrong (old) file silently
  gets transferred instead. Confirmed this bit Session 61.

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

### UNINSTALLED / CYLINDER_ABSENT redesign — design UNBLOCKED, ready to implement (Session 62)
**The flaw**: current logic uses a 120-second timeout alone to decide UNINSTALLED. Time
alone is the wrong signal — it can't distinguish "cylinder briefly lifted and replaced"
from "cylinder removed for refill and a different one returned." A same-cylinder return
after 120s currently wipes tracking context (burn rate history, days remaining) when it
shouldn't. **Directly confirmed as a live bug, not a hypothetical** — `config.json` was
found showing `UNINSTALLED` in real time while the database showed continuous `TRACKING`
seconds earlier, on 2026-07-03. This is `REMOVAL_GRACE_S=120.0` firing exactly as
designed — the design itself is the bug.

**The unblocking answer (Session 62):** the product decision that blocked this since
2026-06-29 is resolved — not by picking "quick" vs "long," but by removing duration
from the decision entirely. **Weight match determines continuity, not elapsed time.**
If the platform returns to within noise range of the weight it had when lifted, resume
`TRACKING` regardless of whether that took 30 seconds or 3 hours. Only a very long
failsafe timeout (hours, not 120s) forces `UNINSTALLED` on its own — everything else is
either a weight match (resume) or an explicit user action (see button below).

**The design:**
```
TRACKING
    ↓ weight drops (cylinder lifted) — record lift_weight_g
CYLINDER_ABSENT          ← new intermediate state, replaces immediate timeout logic
    ↓ weight returns, matches lift_weight_g within noise floor — ANY elapsed time
TRACKING resumed         ← same cylinder, no context lost, no button needed
    ↓ weight returns, does NOT match lift_weight_g
INSTALL FLOW             ← different cylinder detected — fresh anchor sequence
    ↓ explicit "Uninstall" button pressed (WebUI + phone app, anytime)
UNINSTALLED              ← the only fully intentional path
    ↓ very long timeout safety net (hours) — cylinder never returned
UNINSTALLED              ← failsafe only
```

**New requirement (Session 62):** an explicit **"Uninstall cylinder" button**, mirroring
the existing "Install cylinder" button already live in the WebUI — same symmetry, same
pattern, user-initiated in both directions. Needs adding to both WebUI and the future
phone app.

This replaces the 120s timer with weight as the primary signal, and makes UNINSTALLED an
intentional user action rather than an accidental consequence of timing. Note: this is a
refinement of the existing 120s "grace window" mechanism already in production (confirmed
working since 2026-06-25, 3E-005 testing) — that mechanism holds TRACKING through a brief
lift-and-replace, but doesn't do weight-matching on longer absences, which is exactly the
gap this design closes.

**Where it lands**: `hub/python/domain.py`. Hub-side only — no firmware
changes needed, since the node already just reports raw weight regardless of hub state.

### Crash diagnosis
- Node NimBLE resets in 3E-009 attempt #1 were downstream cascade effects of WCN3990 modem firmware crashes (Root Cause 1), not independent node bugs. Proven via correlation analysis script (`docs/analyse_crashes.py`) showing node boots 36 and 37 ended ~1.5 minutes before Linux reboots.
- Catastrophic wrong CMD_TARE: hub lost state on crash and re-tared with 20kg stone still on platform, permanently destroying experiment data. Fixed via PROTECTIVE_SKIP guard.
- `esp_reset_reason()` reporting `OTHER` immediately after a firmware flash is **expected
  behavior, not a fault** — a USB/esptool-triggered reset doesn't map to any named
  `esp_reset_reason_t` value. Don't misdiagnose this as a problem in future sessions.
  Expect `POWERON` on genuine power cycles, and `BROWNOUT`/`TASK_WDT`/etc. only on real
  fault conditions.

### RCA discipline — the most important process rule
- **`journalctl -k` is ALWAYS first** on any stability failure — before Python logs, before application code
- Hardware-level failures (WCN3990, brownout, OOM) are invisible at the application layer
- Application code review is phase 2, never phase 1
- Correlation of timestamps across journalctl, hub.log, and node logs is the method
- Code review without kernel log evidence is not root cause analysis — it is speculation
- **Verify backlog items against live source before assuming they're still pending** — N-TARE-CHECK and HEAVY_LOAD_THRESHOLD_G were both already done and mistakenly carried as open items (Session 61 finding)

### WCN3990-specific rules
- Crashes are **unpreventable** — closed-source Hexagon DSP firmware in signed binary
- Correct engineering goal: **graceful tolerance**, not prevention
- `READING_STALE_S` is a derived value calibrated to hardware — always ≥ 2× measured worst-case recovery
- Re-derive watchdog margin whenever the board support package (BSP) changes
- 94 crashes in 23h is unusually high — investigate firmware/board-file version match if frequency remains high across the 3E-009 stability campaign
- Full crash context: `journalctl -k | grep -B2 -A2 "firmware crashed"` — different crash signatures = different root causes

### Config and persistence rules
- `config.json` is the single source of truth for persistent state — in-memory state survives nothing
- config.json writes must be atomic (write → fsync → rename) — not yet implemented, pending next session
- CMD_TARE requires explicit `steel_g + tare_raw` null-check from config.json first — Fix 3 implements this
- Docker container `date` shows UTC — Python process timezone is set independently via `time.tzset()`

### Documentation and tooling rules
- **Project-knowledge-mounted documentation can silently diverge from the live board's
  copies with no warning.** `SESSION_CLOSE_PROTOCOL.md`, `CLAUDE.md`, `SESSIONS.md`, and
  `LEARNINGS_AND_INSIGHTS.md` were all found stale in project knowledge (dated 2026-06-04
  / 2026-05-05) during a Session 61 audit, while the live board copies were current and
  correct. Always verify against live `git log` and file content before trusting mounted
  docs for anything time-sensitive.
- `arduino-app-cli`'s `user:` app ID is derived from the path to the folder **containing
  `app.yaml`**, relative to `~/ArduinoApps/` — not the top-level project folder name. For
  this project that's `gas-cylinder-monitor/hub`, not `gas-cylinder-monitor`. Use
  `arduino-app-cli app list` when unsure.
- Windows filename collision: downloading a file with a name that already exists in
  Downloads gets `" (1)"` appended (with a leading space). `scp` silently transfers the
  wrong file if the intended path isn't quoted — verify with `head`/`diff` after any
  transfer of a document meant to replace an existing one.

---

## PART 14 — SESSION CLOSE PROTOCOL

**This section intentionally does not duplicate the close steps.** As of Session 61, the
close protocol lives in exactly one place: `docs/SESSION_CLOSE_PROTOCOL.md` (v2). Keeping
a second copy here was identified as the same duplication risk that let other documents
go stale — read the actual protocol file at close time, not this pointer.

---

## PART 15 — NEXT SESSION ENTRY CHECKLIST

Load this document first. Then verify in order:

```bash
# 1. Fix 2 still surviving reboot?
systemctl status wifi-power-save-off.service
/sbin/iw dev wlan0 get power_save

# 2. Hub running?
arduino-app-cli app logs user:gas-cylinder-monitor/hub --follow
# (Ctrl+C once confirmed live, then continue)

# 3. Watchdog running?
systemctl status gas-cylinder-watchdog.service

# 4. Config state — check both hub and node are in sync
cat ~/ArduinoApps/gas-cylinder-monitor/hub/data/config.json
# Compare tare_raw here against node's SPIFFS value (-96218.4 as of Session 61) —
# sync was not confirmed at Session 61 close.

# 5. Claude Code version?
grep DISABLE_AUTOUPDATER ~/.bashrc

# 6. One-screen glance
cat ~/ArduinoApps/gas-cylinder-monitor/docs/PROJECT_CONTEXT.md
```

Then: **answer the cylinder-removal-duration product question first** (Part 13) — it
blocks the UNINSTALLED redesign, which is the first substantial work item queued. Only
after that, proceed with Session 62's plan from Part 8.

---

*Gratian Technologies · Project 13 · Gas Cylinder Monitor V1*
*Document version: 2026-07-02 · Session 61*
*Next full audit due: Session 65, or next phase gate, whichever comes first*
