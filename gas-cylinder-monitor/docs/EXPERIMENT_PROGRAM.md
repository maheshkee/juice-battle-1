---

## 3E-008 - Creep and thermal characterisation under sustained load

Date designed: 2026-07-07
Status: Trial 1 COMPLETE — 2 more trials required before Pass/Fail

### Goal
Measure load cell creep time constant and thermal coefficient under a known static load.
Determine: fast creep τ₁, slow creep τ₂, thermal α (g/°C), and stability plateau.

### Setup
- Platform: stone (known reference load) placed at a precise time (boundary row recorded)
- DHT22 on GPIO5 logging temp_c to DB alongside grams
- Hub running, SQLite logging full time series
- Environment: closed indoor room overnight

### Trial 1 Results — 2026-07-07 to 2026-07-08

Boundary row: id=2207296 | Start: 07 Jul 16:55:34 IST | Duration: 17.53h

Fast creep (Phase A = first 6h, single-exponential fit):
  A = 20210.56 ±0.41g | B = -4.15 ±0.82g | τ₁ = 4721 ±2131s (1.31 ±0.59h)
  Direction: downward (platform conditioned — tiny vs documented 30-80g)

Thermal α: 29.19 ±1.36 g/°C, p=10⁻⁹⁷ (valid for slow changes only)

Slow component: +27g drift h=6-15, τ₂ not yet fitted — Phase A window too short
  Temperature-only explanation: 0.3°C × 29.19 = 8.8g (insufficient — 18g unexplained)
  Interpretation: second viscoelastic component with τ₂ >> 6h

Event at h=15.2: office opened, ventilation spike (DHT22 cooled faster than platform)
  α model predicted weight decrease — actual measurement spiked +126g
  Lesson: α is quasi-static, invalid during rapid airflow (see L-113)

Finding: single-exponential model insufficient — two-component model needed
  raw(t) = A - B₁·exp(-t/τ₁) - B₂·exp(-t/τ₂)

Phase A window for Trial 2: extend to 12h minimum (to capture τ₂)
Status: 2 more trials required. Trial 2 pending (launch after Session 63 close).

---

## 3E-009 - Thermal drift characterisation — PASS (attempt 3, 2026-07-06 to 2026-07-08)

Date designed: 2026-06-22
Status: PASS — 68h 22m 43s, 99.78% coverage (8187/8205 readings), 0 host reboots, 0 WCN3990 crashes
Nightly baseline drift: +147g (N1→N2), +182g (N2→N3) ≈ 165g/night (feeds 3E-008 thermal model)
Priority: HIGH - blocks HUB-001 auto-retare design

### Goal
Characterise load cell zero drift with temperature over time.
Determine: drift rate, stabilisation time, peak magnitude, reproducibility.

### Background
Observed on boot=42: empty platform reading -148g at t=1517s (25 min after boot).
Drift was still growing, not stabilising. This cannot be explained by viscoelastic creep
alone (creep recovers in 60-90s). Thermal expansion of strain gauges is the primary cause.

### Variables to control
| Variable | Control |
|---|---|
| Platform state at start | Empty for minimum 30 min before boot |
| Ambient temperature | Record at start, middle, end of experiment |
| USB power source | Same charger every run |
| Boot number | Record - behaviour may differ early vs late boot |

### Setup
- Node powered from USB charger (not laptop)
- Platform EMPTY throughout Phase A, C, D
- Hub running, logging all heartbeats to SQLite
- Record ambient temperature at start

### Run procedure
Phase A - Cold boot drift (0-30 min):
  - Boot node, platform empty
  - Record grams reading every 30s from hub SQLite
  - Expected: zero starts at 0g, drifts negative over time
  - Measure: drift rate (g/min), stabilisation time (min), peak drift (g)

Phase B - Weight placement at warm state (30-35 min):
  - Place 1000g reference weight
  - Note reading at placement - compare to expected 1000g
  - Leave for 5 min stable

Phase C - Weight removal and recovery (35-50 min):
  - Remove weight at t=35 min
  - Record grams every 30s
  - Measure: time to return to warm-state zero
  - Is recovery symmetric with warmup drift?

Phase D - Extended empty (50-60 min):
  - Platform empty
  - Does zero stabilise? At what value?

### Repeat conditions
Run on 3 different days. Record ambient temperature each run.
Compare: is drift magnitude temperature-dependent or consistent?

### What to measure
- Drift curve shape (monotonic / oscillating / asymptotic)
- Stabilisation time (min) - when does zero stop drifting?
- Peak drift magnitude (g)
- Warm-state zero offset (g) - what does empty platform read after stabilisation?
- Recovery time after weight removal (s)
- Reproducibility across boots and days

### Gate
Results feed into HUB-001 (auto-retare) design and the post-boot stability gate design.
Do not design auto-retare until this experiment is complete.

---

## 3E-010 - Overnight long-run stability test (DESIGNED, NOT RUN)

Date designed: 2026-06-22
Status: BLOCKED on N1 (journalSPIFFS) and N-LOG-TRANSFER (DUMP_LOG FSM)
Priority: HIGH - validates N1 and confirms production duty cycle suitability

### Goal
Verify node runs stably for 8-12 hours standalone without serial monitor.
Retrieve full overnight journal the next morning via BLE DUMP_LOG.

### Prerequisites (must be built first)
1. N1 - journal.cpp appends to /node_journal.log on SPIFFS
2. N-LOG-TRANSFER - hub requests log via DUMP_LOG, saves to logs/node/

### Background
In production the node runs standalone (USB charger, no laptop).
There is no serial monitor. All data must be retrievable via BLE the next morning.
This experiment validates that the full data path works end-to-end.

### Setup
- Node: powered from USB charger only (no laptop, no serial monitor)
- Platform: place known weight (~1000g water bottle or similar)
- Hub: running on AQ3, logging SQLite
- Duration: ~10 hours (power on ~10pm, retrieve ~8am)
- Note: platform weight, ambient temperature, time of power-on

### Run procedure
Evening:
  1. Node power cycle - note boot number N
  2. Wait for hub to connect and anchor (verify in WebUI)
  3. Confirm WebUI shows correct weight and percentage
  4. Leave overnight - do not touch

Morning:
  1. Connect laptop - open Serial Monitor, note current boot number
     (should still be N - no crashes)
  2. Check WebUI - note current reading and reading count in SQLite
  3. Hub sends DUMP_LOG command - node transmits /node_journal.log
  4. Hub saves to: logs/node/node_YYYY-MM-DD_bootNN.log
  5. Hub sends CLEAR_LOG - node deletes SPIFFS file

### What to verify
| Check | Expected |
|---|---|
| Boot number unchanged | Still boot N - no crashes |
| SQLite reading count | ~1200 readings (one per 30s × 10hr) |
| Journal line count | ~1200 lines (one per 30s × 10hr) |
| SQLite count = journal count | Should match - no missed readings |
| Drift over 10 hours | Measure: grams at t=0 vs t=36000 |
| False WEIGHT_EVENTs | Expect 0 on static load over 10 hours |
| BLE reconnects | Note any [BLE] Restarting advertising lines in journal |
| SPIFFS journal integrity | No corrupt lines, no truncation |

### SPIFFS capacity note
At ~80 bytes/line × 1 line/30s:
  10 hours = ~1200 lines = ~96KB  well within 1.5MB SPIFFS partition
  Full SPIFFS at this rate = ~6.5 days
  Production rule: auto-push when SPIFFS >80% full (before 25KB threshold)

### Gate
Pass criteria:
  - No crashes (boot number unchanged)
  - All readings recoverable via DUMP_LOG
  - Drift characterised (feeds into HUB-001 design)
  - Zero false events on static load
