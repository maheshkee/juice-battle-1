# SESSION HANDOFF — 2026-06-22 SESSION5
# Gas Cylinder Monitor V1 — Next Chat Entry Point
# Supersedes HANDOFF_2026_06_18_FINAL_2.md for ongoing issues found in testing.
# Use BOTH this file and FINAL_2 to reconstruct full context.

---

## How to use this document
Read HANDOFF_2026_06_18_FINAL_2.md first for full background.
Then read this file for everything that happened on 2026-06-22.
Working mode: design in chat, all code via Claude Code CLI only.

---

## Current position (one line)
Node boot=42 running. Hub deployed. Percentage tracking working correctly.
Thermal drift diagnosed: ~-70g warm-state zero offset after 20-25 min.
Alert banner not showing (no topbar visible — likely CSS/browser cache issue).
Two experiments designed: 3E-009 (thermal drift) and 3E-010 (overnight long-run).
Auto-start not yet confirmed working (arduino-app-cli command found but not verified).
Two cosmetic fixes pending: clamp grams display at 0, clamp pct display at 0.

---

## What happened in session 5 (2026-06-22)

### Testing observations — boot=42
Node boot=42, sigma=5.83g (within healthy range).

**Tare drift across boots — important:**
```
boot=37: tare_raw = -105716.6
boot=39: tare_raw = -105229.3
boot=41: tare_raw = -105126.7
boot=42: tare_raw = -104473.7  ← 653 raw counts lighter than boot=41 = ~18g
Total drift boot=37→42: ~34g over 5 boots
```
This suggests slow mechanical creep — cells not fully recovering to original position
between load/unload cycles. Feeds into 3E-009 experiment.

**Thermal drift on empty platform — boot=42 data:**
```
t=104s (boot):  0g     ← tare taken here
t=194s (3min):  -76g   ← drift starts immediately after weight removal
t=1006s (17min): -70g  ← continuing to drift
t=1397s (23min): -128g ← peak spike
t=2029s (34min): -77g  ← stabilising
t=2360s (39min): -75g  ← stable band ~-70 to -75g
t=3352s (56min): -62g  ← slight recovery, still -60 to -70g range
```

**Conclusion:** Drift stabilises at approximately **-70g warm-state zero offset**
after ~20-25 minutes. Not monotonically growing. Spikes to -128g, -162g are
noise oscillations on top of the -70g baseline.

**This is NOT viscoelastic creep** — that recovers in 60-90 seconds.
This is **thermal expansion of strain gauges** causing a stable warm-state offset.

**Production impact:** The -70g drift has zero effect on consumption tracking
because gas% is always computed as delta from anchor, not absolute.
It affects absolute zero display only — hence the cosmetic fix needed.

**Anchor worked correctly:**
```
Line #134: t=3546s — weight placed, PLACED event at 46.7g
Line #134: t=3563s — heartbeat at 1288.1g (full weight settled)
Hub anchored at ~1288g
Screenshots confirm: 1274g=99%, 1112g=86%, 115g=9% — all correct
```

**Percentage tracking verified on this boot:**
1274g → 99% ✓
1112g → 86% ✓
115g → 9% ✓ (bar turned red)

### Issues found

**Issue 1 — Alert banner not showing**
Percentage and bar colour work correctly. But the alert banner text at the
top of screen is not appearing. Topbar (DEV/PROD toggle, node dot) also missing
from screenshots — suggests CSS/browser cache issue or wrong HTML being served.

Pending diagnosis:
```bash
docker exec gas-cylinder-monitor-hub-main-1 grep -c "alert-banner" /app/assets/index.html
```
Should return 2+. If 0, wrong HTML in container → force rebuild needed.

**Issue 2 — Grams display shows negative on empty platform**
Platform empty after weight removal → WebUI shows -111g, -114g etc.
Physics is correct (thermal drift), but displaying negative grams to user is wrong.
Fix: clamp display at 0 in index.html JS.

**Issue 3 — Auto-start not verified**
arduino-app-cli properties set default user:gas-cylinder-monitor/hub
This command was identified as correct but NOT yet confirmed to have been run
successfully. Must be verified:
```bash
arduino-app-cli app list | grep gas-cylinder
```
Should show DEFAULT in status column. If not, run the command.

### Hub side — what changed in this session
- App auto-start command identified: arduino-app-cli properties set default user:gas-cylinder-monitor/hub
- DEVICE_SETUP.md updated with Step 4 (auto-start instruction) — committed
- 3E-009 and 3E-010 experiment designs added to EXPERIMENT_PROGRAM.md — committed
- setup_sudoers.sh NOT changed (correctly kept clean)

### Commits in this session
Check git log for commits after 9c4a807 (last commit from session 4).

---

## Pending fixes — design locked, not yet built

### Fix 1 — Clamp grams display at 0 (cosmetic, index.html only)
```javascript
// In applyUpdate(), replace:
gramsEl.textContent = waiting ? '--' : Math.round(data.grams);
// With:
var displayGrams = Math.max(0, Math.round(data.grams));
gramsEl.textContent = waiting ? '--' : displayGrams;
```
Also hide percentage row when grams < 0:
```javascript
if (data.grams < 0) {
    pctRowEl.style.display = 'none';
    pctBarBg.style.display = 'none';
}
```

### Fix 2 — Clamp percentage display at 0-100 (cosmetic, index.html only)
Already partially done (bar is clamped). Ensure pct number display is also clamped:
```javascript
var clampedPct = Math.min(100, Math.max(0, data.pct));
pctValEl.textContent = Math.round(clampedPct);
```

### Fix 3 — Diagnose and fix alert banner not showing
First run the diagnostic:
```bash
docker exec gas-cylinder-monitor-hub-main-1 grep -c "alert-banner" /app/assets/index.html
```
If 0: force rebuild:
```bash
cd ~/ArduinoApps/gas-cylinder-monitor/hub
docker compose down
docker compose build --no-cache
bash deploy.sh
```
If 2+: browser cache issue → hard refresh (Ctrl+Shift+R)

---

## Two experiments designed and locked

### 3E-009 — Thermal drift characterisation
Status: DESIGNED, NOT YET RUN
Gate: No prerequisites — can run immediately
Goal: Characterise load cell zero drift curve — rate, stabilisation time, magnitude,
reproducibility. Results needed before designing HUB-001 auto-retare.
Full design in docs/EXPERIMENT_PROGRAM.md.

### 3E-010 — Overnight long-run stability test
Status: DESIGNED, BLOCKED on N1 + N-LOG-TRANSFER
Gate: N1 (journal→SPIFFS) and DUMP_LOG FSM must be built first
Goal: Verify node runs 10+ hours standalone, retrieve full journal next morning.
Full design in docs/EXPERIMENT_PROGRAM.md.

---

## Key finding — thermal drift production impact

**The -70g warm-state zero is acceptable for production V1.**

Reason: Gas consumption is always computed as:
```
consumed = anchor_grams - current_grams
```
Both anchor and current readings have the same thermal offset — it cancels out in
the subtraction. The percentage is drift-immune as long as it is computed
relative to a recent anchor (same thermal state).

Only scenario where drift matters: anchor taken at cold state (t=104s), weight
removed for >20 min, then consumption computed across the thermal transition.
Solution: HUB-001 auto-retare (when platform empty, re-zero) — already in backlog.

---

## Thermal drift — what to add to LEARNINGS_AND_INSIGHTS.md next session

Add as L-071:
```
L-071 — YZC-161A warm-state zero offset: ~-70g after 20-25 minutes

Observed: boot=42, empty platform, t=1006s to t=3352s
Offset stabilises at approximately -70g after ~20-25 minutes of powered operation.
This is thermal expansion of strain gauges, NOT viscoelastic creep.
Viscoelastic creep recovers in 60-90s. This does not.

Key difference from creep:
  Creep: caused by sudden mechanical load removal → recovers quickly
  Thermal drift: caused by resistive heating of strain gauges → stabilises slowly

Production impact: ZERO on consumption tracking (delta cancels drift).
Display impact: shows negative grams on empty platform when thermally warm.
Fix: clamp display at 0 (cosmetic), HUB-001 auto-retare (functional).

Warm-state offset evolution (boot=42):
  t=194s:   -76g    (3 min)
  t=1006s:  -70g   (17 min)
  t=2360s:  -75g   (39 min) ← stabilised
  t=3352s:  -62g   (56 min) ← slight recovery

3E-009 will produce the definitive characterisation.
```

---

## Tare drift across boots — what to add to LEARNINGS_AND_INSIGHTS.md

Add as L-072:
```
L-072 — Tare_raw drifts lighter across boots (mechanical creep accumulation)

Observed:
  boot=37: tare_raw = -105716.6
  boot=39: tare_raw = -105229.3
  boot=41: tare_raw = -105126.7
  boot=42: tare_raw = -104473.7
  Total drift: ~34g over 5 boots

Cause: YZC-161A beams undergo permanent set (mechanical creep) under repeated
load/unload cycles. Each cycle leaves the beam slightly deformed. The tare raw
value drifts lighter because the beams are progressively settling.

Production impact: cal_factor derivation assumes a stable mechanical zero.
If tare_raw drifts significantly, the cal_factor derived in one session may
not match the next. Monitor tare_raw across boots for production calibration.

This will be characterised fully in 3E-009.
```

---

## Auto-start — verification steps for next session

```bash
# 1. Check if default is set
arduino-app-cli app list | grep gas-cylinder

# 2. If DEFAULT not showing, set it:
arduino-app-cli properties set default user:gas-cylinder-monitor/hub

# 3. Verify with reboot test:
sudo reboot
# After 60 seconds:
docker ps | grep gas-cylinder  # should show container running
```

---

## Next session opening actions (in order)

1. Read HANDOFF_2026_06_18_FINAL_2.md AND this file
2. Run alert banner diagnostic:
   ```bash
   docker exec gas-cylinder-monitor-hub-main-1 grep -c "alert-banner" /app/assets/index.html
   ```
3. Fix alert banner based on diagnostic result
4. Apply Fix 1 + Fix 2 (grams and pct display clamp) via CLI
5. Verify auto-start working
6. Add L-071 and L-072 to LEARNINGS_AND_INSIGHTS.md
7. Then proceed to N1 (journal→SPIFFS) — the main next build item

---

## Node current state
- boot=42, gas_monitor_v1 with NimBLE advertising restart
- sigma=5.83g (healthy — within documented range)
- tare_raw=-104473.7 (drifting lighter across boots — see L-072 above)
- TARE_CHECK_THRESHOLD_G = 1000g (DEV) — restore to 2000g before production

## Hub current state
- Deployed at 192.168.88.20:7000
- dev_mode = True (from SQLite)
- starting_weight = 1761.8g (from last anchor, may be stale)
- All percentage tracking working correctly
- Alert banner: UNVERIFIED — needs diagnostic

## Latest git commits (check git log for exact hashes)
- docs: add Step 4 auto-start setup with correct app ID
- docs: 3E-009 thermal drift experiment design, 3E-010 overnight long-run design
- Plus all commits from session 4 (see HANDOFF_2026_06_18_FINAL_2.md)

---

## Opening prompt for next chat

"Good morning. Continuing gas-cylinder-monitor V1.
Read HANDOFF_2026_06_18_FINAL_2.md AND
HANDOFF_2026_06_22_SESSION5_THERMAL_DRIFT_DIAGNOSIS.md fully before responding.

Context: boot=42 running. Percentage tracking works. Thermal drift diagnosed as
~-70g warm-state zero offset — normal physics, cosmetic fix needed.
Alert banner not confirmed working — needs diagnostic first.

Today:
1. Run alert banner diagnostic and fix
2. Apply grams display clamp (negative → 0) and pct clamp (0-100)
3. Verify auto-start
4. Add L-071 and L-072 to LEARNINGS
5. Then proceed to N1 (journal→SPIFFS)

Start by confirming you read both handoffs and state current position."

---

*End of handoff. Next chat is ready.*
