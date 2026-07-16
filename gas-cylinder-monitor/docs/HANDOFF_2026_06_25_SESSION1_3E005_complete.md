# SESSION HANDOFF — 2026-06-25 SESSION1
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_23_FINAL_5.md

---

## How to use this document
Read this file fully before responding. No re-explanation needed.
Working mode: design in chat, all code via Claude Code CLI only.
No code written directly in chat responses — ever.

---

## Current position (one line)
3E-005 water bowl anchor validation COMPLETE AND PASSED. Boss demo done.
5 domain constants still at test values — MUST REVERT before Phase 2 or production.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.

```
3× YZC-161A load cells → parallel junction → HX711 → ESP32-C3 SuperMini
  (BLE GATT notify + cmd char, 30s notify interval)
→ Arduino UNO Q AQ3 hub (Python, BlueZ D-Bus, SQLite, Docker, WebUI port 7000)
```

Architectural seam is strict: node outputs `{grams, quality, sigma}` only.
Hub stamps timestamp, derives steel from anchor events, computes gas%, stores SQLite,
serves WebUI. Gas% = (gross − steel_g) / NET_GAS_G × 100. Never computed on node.

---

## Hardware — locked

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | arduino@AQ3 (never use IP), port 7000 |
| ESP32-C3 SuperMini | BLE sensor node, boot=28 at session end |
| GISLAB HX711 module | Green PCB, AVIAIC chip, 3.3V VCC ONLY — never 5V |
| YZC-161A 20kg load cells ×3 | 3-cell parallel platform |
| Platform | New plate (post swap test), rubber mats, drip tray |
| Claude Code CLI | v2.1.129, DISABLE_AUTOUPDATER=1 in ~/.bashrc |

---

## Wiring — locked, never change

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V — hardware damage |
| GND | GND | |
| GPIO4 | SDO (DOUT) | INPUT_PULLUP mandatory |
| GPIO3 | SCK | OUTPUT |

### 3-cell parallel wiring
All 3 red → E+ | All 3 black → E− | All 3 green → A+ | All 3 white → A−

### HX711 corrupt filters (all three required — never remove one)
- LONG_MIN, -1, 0x7FFFFF

---

## Arduino IDE — locked

| Setting | Value |
|---|---|
| Package | esp32 by Espressif v3.0.7 (NOT v3.3.9) |
| Board | ESP32C3 Dev Module |
| Port | COM11 |
| USB CDC On Boot | ENABLED — mandatory |
| Upload speed (normal) | default |
| Upload speed (if failing) | 115200 |
| Libraries | NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon |

Flash recovery: NEVER use "Erase All Flash" — destroys 2nd stage bootloader.
If upload fails: lower baud to 115200 only.

---

## BLE — locked

```
Service UUID:    aa206b91-235b-42aa-b370-453a3feedf35
Weight char:     b9b25bb1-f2a9-4545-b48f-295ab2789f41  (notify)
Command char:    c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b  (write-without-response)
Log char:        d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c  (notify)
Device name:     GasCylMonitor
Node MAC:        10:00:3B:CD:63:32
BLE notify interval: 30s (decoupled from HX711 read rate — WCN3990 crash prevention)
```

---

## Locked hardware values

| Parameter | Value | Status |
|---|---|---|
| cal_factor | 36.2231 raw/g | VERIFIED boot=13 |
| tare_raw | -89234.5 | VERIFIED boot=25, current platform |
| sigma (clean boot, platform undisturbed) | 3.60g | VERIFIED boot=25 |
| sigma (boot=28, disturbed during noise phase) | 6.91g | OBSERVED |
| sigma healthy range | 2.79–6.91g across boots | VERIFIED |
| NOISE_SIGMA_PASS_G | 8.0g | LOCKED |
| NOISE_SIGMA_WARN_G | 15.0g | LOCKED |
| BLE notify interval | 30s | LOCKED |
| TARE_WAIT timeout | 60s | LOCKED |
| CAL timeout | 120s → 36.0 fallback | LOCKED |
| CAL fallback value | 36.0 raw/g | LOCKED |
| POST_ACTION_WAIT_S | ≥120s | LOCKED |
| READING_STALE_S | 900s | LOCKED |

---

## ⚠️ CRITICAL — Production revert checklist (5 constants, all in domain.py)

**ALL FIVE must be reverted before any Phase 2 or production test.**
Missing even one causes silent wrong readings.

| Constant | Current TEST value | PRODUCTION value |
|---|---|---|
| NET_GAS_G | 4535.0 | 14200.0 |
| ANCHOR_GROSS_MIN_G | 4800.0 | 26000.0 |
| STEEL_PLAUSIBLE_MIN_G | 200.0 | 13000.0 |
| STEEL_PLAUSIBLE_MAX_G | 2000.0 | 18000.0 |
| REFILL_GROSS_MIN_G | 5500.0 | 29000.0 |

REMOVAL_GRACE_S = 120.0 — same value for both test and production. No revert needed.

---

## Hub domain constants — permanent (not in revert list)

| Constant | Value | Note |
|---|---|---|
| DAILY_USE_DEFAULT_G | 350.0 | V1 prior |
| ALERT_AMBER_G | 2000.0 | ~5-6 days at 350g/day |
| ALERT_RED_G | 1000.0 | ~2-3 days at 350g/day |
| ANCHOR_SPREAD_THRESHOLD_G | 30.0 | observed ±15g platform noise |
| ANCHOR_STABILITY_WINDOW_G | 50.0 | TODO: tighten after 3E-009 |
| ANCHOR_MIN_STABLE_READINGS | 5 | validated 3E-005 |
| STEEL_UNKNOWN_PRIOR_G | 16500.0 | conservative prior |
| REMOVAL_GRACE_S | 120.0 | grace window before UNINSTALLED |

---

## Hub module structure — current

```
hub/
├── python/
│   ├── main.py          (~92 lines — orchestrator only, no domain logic)
│   ├── ble_subscriber.py
│   ├── log_transfer.py
│   ├── domain.py        (state machine, G4 logic, all constants)
│   └── db.py
├── assets/
│   └── index.html       (WebUI — gas%, Install button, quality badge, bar)
├── config.json          (baked at deploy — NOT hub/data/config.json)
├── deploy.sh
└── app.yaml
```

Config path discipline: Docker reads `hub/config.json` baked at deploy time.
`hub/data/config.json` is NEVER mounted — writing there has zero effect.

---

## Hub state machine — 4 states

```
UNINSTALLED
  → (user clicks Install cylinder in WebUI) → BOOTSTRAP_ANCHOR
    → (5 stable readings, spread <30g, all >ANCHOR_GROSS_MIN_G) → TRACKING
      → (gas_g < ALERT_AMBER_G) → LOW_GAS
        → (gas_g >= ALERT_AMBER_G) → TRACKING  (auto-clear)

From TRACKING or LOW_GAS:
  gross < 500g for < 120s → stay TRACKING (grace window)
  gross < 500g for > 120s → UNINSTALLED (steel_g cleared)
  gross > REFILL_GROSS_MIN_G → BOOTSTRAP_ANCHOR (refill detected)
```

---

## WebUI — current state

Live at `192.168.88.20:7000`

| Element | Behaviour |
|---|---|
| Grams display | Always visible when connected |
| GOOD/DEGRADED/FAILED badge | Always visible |
| Install cylinder button | Visible ONLY when cylinder_state=UNINSTALLED |
| Calibrating... label | Visible ONLY when cylinder_state=BOOTSTRAP_ANCHOR |
| Gas% + progress bar | Visible ONLY when cylinder_state=TRACKING or LOW_GAS |
| Alert banner | Visible on AMBER/RED/empty alerts |
| Node dot (green) | Connected; grey = disconnected |

Socket.IO event: `weight_update` payload includes:
`{grams, quality, sigma, ts, gas_pct, gas_g, alert_level, cylinder_state, steel_g, steel_source}`

---

## Boot sequence — locked

```
SETTLE (2s)
  → TARE_WAIT (hub sends TARE or SKIP_TARE, 60s timeout)
      Hub logic: cylinder_state=UNINSTALLED → send TARE
                 cylinder_state=TRACKING/BOOTSTRAP_ANCHOR → send SKIP_TARE
    → TARE (N=200 fresh, or load from SPIFFS if SKIP_TARE)
      → N-TARE-CHECK (delta vs saved — if heavy load → use saved tare)
        → NOISE (20s autonomous)
          → CAL (hub sends SET_CAL:36.2231, or 120s timeout → 36.0 fallback)
            → RUNNING
```

Important: N-TARE-CHECK HEAVY_LOAD_THRESHOLD_G is currently 1000g (dev).
Must restore to 2000g before Phase 2 — requires node reflash.

---

## Current system state (at session end)

```
cylinder_state:   UNINSTALLED
steel_g:          None
tare_raw:         -89234.5  (boot=25 new platform)
cal_factor:       36.2231
boot:             28
sigma (boot 28):  6.91g
Hub Docker:       running, port 7000
Node:             powered, RUNNING state
```

---

## What was completed this session (3E-005)

1. Confirmed tare_raw=-89234.5 is correct (not a bug — platform swap test ran through boots 24-25 after handoff was written)
2. Changed 4 domain constants for water bowl test
3. Fixed WebUI gas% field name: `data.pct` → `data.gas_pct`
4. Added "Install cylinder" button to WebUI (state-gated)
5. Added gas% display + green progress bar to WebUI
6. Discovered and fixed infinite re-anchor bug: separated REFILL_GROSS_MIN_G from ANCHOR_GROSS_MIN_G
7. Ran 3E-005 experiment — anchor fired correctly, steel_g=492.8g derived, gas%=100% confirmed
8. Ran boss demo — full end-to-end flow demonstrated live
9. Implemented Option A grace window (REMOVAL_GRACE_S=120s) before UNINSTALLED transition
10. Validated grace window: 30s removal → TRACKING held; 120s+ removal → UNINSTALLED triggered

---

## Known issues / minor bugs (not blocking)

| Issue | Severity | Status |
|---|---|---|
| First reading after anchor fires sends stale BOOTSTRAP_ANCHOR state to WebUI. Self-corrects on next read (30s). | Minor race condition | Deferred — not blocking |
| sigma=6.91g on boot=28 (platform disturbed during noise phase) | Physics, not bug | Monitor only |
| HEAVY_LOAD_THRESHOLD_G on node is 1000g (should be 2000g for production) | Must fix before Phase 2 | Requires reflash |

---

## What is next — Phase 2 prep sequence

### Step 1 — Revert 5 constants (Claude Code CLI)
Revert all 5 constants in `domain.py` to production values (see revert table above).
Deploy hub. Verify with `docker exec` that all 5 show production values.

### Step 2 — Restore node HEAVY_LOAD_THRESHOLD_G
In node firmware, restore `HEAVY_LOAD_THRESHOLD_G` to 2000g.
Reflash via Arduino IDE (COM11, 115200 if needed).
Verify on boot log: N-TARE-CHECK fires correctly with >2000g load.

### Step 3 — 3E-008: Thermal drift characterisation (mini cylinder or water)
Goal: measure how much tare_raw drifts over 6+ hours at ambient temperature.
Equipment: same platform, same node, leave undisturbed.
Acceptance: document drift rate in g/hour.

### Step 4 — 3E-009: 6-hour overnight stability
Goal: confirm TRACKING gas% stays stable over long run with no removal.
Gate: gas% drift < ±2% over 6 hours.

### Step 5 — Production test with real 14.2kg cylinder
Full system test with real gas cylinder.
All 5 constants at production values.
N-TARE-CHECK at 2000g.

---

## Key design principles (must always respect)

| Principle | Detail |
|---|---|
| No hardcoding | All paths derived dynamically — SCRIPT_DIR, APP_NAME, APP_DIR |
| Design in chat | Code via Claude Code CLI only — never write implementation code in chat |
| AQ3 hostname | Always `arduino@AQ3` for SSH/SCP — never IP address |
| No parallel code paths | DEV mode permanently deleted — single production path only |
| Seam contract | Node outputs grams only — hub owns all domain logic |
| tare_raw absorbs platform | Platform plate/mats/trays are mathematically invisible after tare |
| Separate thresholds | ANCHOR_GROSS_MIN_G ≠ REFILL_GROSS_MIN_G — never conflate |
| BLE rate ≠ HX711 rate | 30s BLE notify interval prevents WCN3990 crash |
| Grace window | 120s before UNINSTALLED — do not shorten for production |
| Config path | hub/config.json only — hub/data/config.json is never mounted |

---

## Session start checklist for next chat

Before doing anything:
1. `last reboot | head -5` — confirm no new reboots
2. `docker logs gas-cylinder-monitor-hub-main-1 --tail 5` — hub alive and reading
3. `cat ~/ArduinoApps/gas-cylinder-monitor/hub/config.json | python3 -m json.tool` — confirm cylinder_state and tare_raw
4. Check sigma in latest boot log — if >8g, something is wrong
5. Confirm 5 constants at test values before doing anything with water bowl
6. Confirm 5 constants at production values before doing anything with real cylinder

---

## Folder structure on AQ3

```
~/ArduinoApps/gas-cylinder-monitor/
├── CLAUDE.md                    ← read first every session
├── hub/
│   ├── python/domain.py         ← all domain logic + constants
│   ├── python/main.py           ← orchestrator only
│   ├── python/ble_subscriber.py
│   ├── python/log_transfer.py
│   ├── python/db.py
│   ├── assets/index.html        ← WebUI
│   ├── config.json              ← runtime state (baked at deploy)
│   └── deploy.sh
├── docs/
│   ├── SESSIONS.md
│   ├── LEARNINGS_AND_INSIGHTS.md
│   ├── EXPERIMENT_PROGRAM.md
│   └── HANDOFF_*.md
└── node/                        ← ESP32-C3 firmware (flash via Arduino IDE on Windows)
```

---

## SCP command — copy this handoff to AQ3

```bash
scp HANDOFF_2026_06_25_SESSION1_3E005_complete.md arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/docs/
```

---

*Session 003 — 2026-06-25 — 3E-005 complete. Boss demo passed. Grace window implemented.*
*Next: revert 5 constants → restore HEAVY_LOAD_THRESHOLD_G → Phase 2.*
