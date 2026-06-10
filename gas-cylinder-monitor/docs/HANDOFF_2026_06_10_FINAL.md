# SESSION HANDOFF — 2026-06-10 FINAL
# Gas Cylinder Monitor — Next Chat Entry Point
# Version: v2 (4-cell pivot session)
# Paste this into the next chat session to restore full context instantly.

---

## CRITICAL: READ THIS FIRST

This handoff marks a **major project pivot**. The boss has approved moving directly to
the 4-cell production hardware setup. The single-cell experiment baseline is complete
and is now a historical reference, not the active development path.

The next chat's job is **documentation updates only** — no code, no implementation.
Read every section carefully before doing anything.

---

## What this product is

LPG gas cylinder weight monitor for Indian households.
ESP32-C3 sensor node reads 4× YZC-161A load cells via one HX711, computes gross weight
in grams, sends over BLE to Arduino UNO Q (AQ3) hub.
Hub derives gas%, stores in SQLite, serves WebUI dashboard.

```
4× Load cells (parallel) → HX711 → ESP32-C3 (BLE) → UNO Q AQ3 (Python, SQLite, WebUI)
```

Transport: BLE-only (WiFi removed permanently). See TRANSPORT_DECISION_BLE_ONLY.md.
Seam: node outputs {grams, quality, sigma} only. Hub stamps timestamp. Node never computes gas%.

---

## Hardware — current physical state

| Item | Detail |
|---|---|
| Arduino UNO Q AQ3 | `arduino@AQ3` (always hostname, never IP) |
| ESP32-C3 SuperMini HW-466AB | sensor node — owns all HX711 + load cell work |
| GISLAB HX711 module | green PCB, AVIAIC chip |
| YZC-161A 20kg load cells | **4× cells now** — assembled on circular wooden platform |
| Platform | Round wooden board (~400mm diameter) |
| Cell feet | Small decorative round wooden discs — one under each cell |
| Wiring | Currently breadboard only — no junction block yet |

**4-cell platform is physically built and sitting on the desk.**
Photos exist in the session. Wiring is breadboard-based for the experiment phase.

---

## Experiment status — single-cell era (SUPERSEDED)

| Experiment | Status | Date | Notes |
|---|---|---|---|
| E-000 ESP32 + HX711 bring-up | PASSED | 2026-06-04 | Single cell |
| E-001 tare + cal_factor + grams | PASSED | 2026-06-05 | Single cell, ~105 counts/g |
| E-002 noise floor characterisation | PASSED | 2026-06-08 | Single cell, STD 0.67g (BLE off), 1.81g (BLE on) |
| E-003 BLE transport validation | PASSED | 2026-06-08 | grams=246.2g quality=GOOD sigma=0.49g confirmed |

**All above experiments are SUPERSEDED as production baseline.**
They remain valid as:
- Proof that firmware works
- Proof that HX711 communication works
- Proof that BLE transport works
- Historical noise/cal data for single-cell configuration

The 4-cell platform requires its own characterisation series (see below).

---

## What the next chat must do — documentation updates ONLY

**Mode: design and documentation in chat only. No Claude Code CLI. No implementation.**

Work through the following tasks in order. Each task is one focused session chunk.

---

### TASK 1 — Update EXPERIMENT_PROGRAM.md

Add a new experiment group: **Group 0 — 4-Cell Platform Bring-Up and Characterisation**.

The new experiments map exactly to the old single-cell experiments but on the new hardware:

| New ID | Maps to | Objective |
|---|---|---|
| 4E-000 | E-000 | 4-cell parallel bring-up — verify all four cells contribute, clean readings |
| 4E-001 | E-001 | Re-derive cal_factor on assembled 4-cell platform |
| 4E-002 | E-002 | Re-run noise floor characterisation on 4-cell platform |
| 4E-003 | — NEW — | Load distribution validation — same weight at different positions gives same reading |
| 4E-004 | E-003 | BLE transport validation on 4-cell hardware (likely passes without change) |

For each new experiment, use the same template as existing experiments:
- Objective, Background Theory, Equipment, Procedure, Data To Capture, Acceptance Criteria, Failure Criteria, Decision Impact.

Also mark old single-cell experiments with status note:
`Status: PASSED (Single-cell baseline — superseded by 4E-xxx series)`

Key notes for the new experiments:

**4E-000 acceptance criteria:**
- Clean raw readings from all 4 cells in parallel
- No corrupt values
- Lift one corner of platform — reading drops by approximately 25% of that cell's contribution
- All four wires confirmed correctly wired (same colour convention: Red=E+, Black=E−, Green=A+, White=A−)

**4E-001 notes:**
- cal_factor will be approximately 4× the single-cell value (~420 counts/gram)
- Must use reference weight ≥ 1 kg (heavier than single-cell experiments)
- Procedure: same as E-001 but on 4-cell platform

**4E-002 notes:**
- Run with BLE off → measure STD and derive threshold
- Run with BLE on → measure STD and derive threshold
- Compare with single-cell baseline (STD 0.67g BLE-off, 1.81g BLE-on)
- 4-cell parallel may have different noise floor

**4E-003 — NEW experiment (no single-cell equivalent):**
- Place a known reference weight (e.g. 5 kg or 10 kg) at five positions: centre, and near each of the 4 corners
- Record grams at each position
- Acceptance criterion: all five readings within ±2% of each other
- This validates the parallel bridge averaging is working correctly

---

### TASK 2 — Update HARDWARE.md

Change the hardware baseline from single-cell to 4-cell.

Add a new section: **Production Platform Hardware (4-Cell)**

Include:
- 4× YZC-161A 20kg load cells in parallel
- Round wooden platform (~400mm diameter) — prototype/development version
- One cell per corner, fixed end bolted to foot, free end contacts platform
- All wiring currently breadboard-based for experiments
- Parallel wiring: all E+ joined, all E− joined, all A+ joined, all A− joined
- Junction block: currently breadboard — to be replaced with screw-terminal block post-validation
- Single 4-wire cable from junction to HX711 (E+, E−, A+, A−)

Add a note in the single-cell hardware section:
`Note: Single-cell setup superseded. Used only for E-000 through E-003 baseline experiments.`

Key hardware facts to add (from session research, now locked):
```
4-cell cal_factor:     ~420 counts/gram (approx 4× single-cell value) — to be re-derived in 4E-001
4-cell tare_raw:       unknown — to be derived in 4E-000
4-cell noise floor:    unknown — to be characterised in 4E-002
Cell sensitivity:      1 mV/V × 3.3V excitation = 3.3 mV full scale (per cell)
Bus output at full scale: 3.3 mV / 4 = 0.825 mV average → same total as single cell
```

---

### TASK 3 — Update PLAN.md

The v2.0 entry in the product roadmap previously listed "4-cell summing" as a future feature.
This must be moved to V1 — it is now the current hardware baseline, not a future version.

Before change:
```
| v2.0 | 4-cell summing, ML on QRB2210 (TFLite) | Future |
```

After change:
```
| V1-MVP | Weight reading (4-cell parallel) + transport + storage + domain + WebUI | Groups 0–4 + 7 |
```

Also add a new section: **4-Cell Pivot (2026-06-10)**
```
Decision: Boss approved moving directly to 4-cell production hardware.
Single-cell experiments (E-000 to E-003) complete and passed — serve as firmware/transport baseline.
All future development on 4-cell platform only.
What changes: hardware, cal_factor, tare_raw, noise characterisation.
What stays identical: firmware code, BLE transport, hub code, seam contract, gas equations.
```

---

### TASK 4 — Update SESSIONS.md

Add this session entry:

```
## Session 2026-06-10

### Topics covered
- Deep dive: voltage — ESP32-C3 power architecture, AMS1117 LDO, 3.3V vs 5V excitation
- Deep dive: 4-cell load cell mechanics — atomic level to MCU, parallel bridge physics,
  voltage averaging math, complete worked example (4 different weights, 7 stages)
- 4-cell pivot decision from boss — moved to 4-cell as production baseline immediately
- Hardware review: 4-cell platform physically built, breadboard wiring, on desk ready

### Decisions made
- 4-cell platform is now the production hardware baseline
- Single-cell experiments (E-000 to E-003) are superseded historical baseline
- New experiment series 4E-000 to 4E-004 required
- Firmware unchanged — only cal_factor and tare_raw need re-derivation
- Voltage: 3.3V excitation locked permanently, no benefit to 5V

### Documents produced this session
- GasCylinder_HardwareDesign_Reference_2026.md (.docx also) — full theory reference
- VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md — voltage + 4-cell physics deep dive
- HANDOFF_2026_06_10_FINAL.md — this document

### What was NOT done (for next session)
- No document updates to existing project files
- No code changes
- No new experiments run
```

---

### TASK 5 — Update CLAUDE.md

CLAUDE.md is the single most important context file. Update the following sections:

**Current position:**
```
Previous: E-003 PASSED (BLE transport, single cell)
Current:  4-CELL PIVOT — documentation update phase
Next:     4E-000 (4-cell parallel bring-up, breadboard wiring)
```

**Hardware:**
Change `YZC-161A 20kg load cell` (singular) to `YZC-161A 20kg load cells × 4 (parallel, on wooden platform)`

**Locked hardware constants — update:**
```
CAL_FACTOR (single cell, VOID on 4-cell): 105 counts/gram
CAL_FACTOR (4-cell parallel, TBD in 4E-001): expected ~420 counts/gram
TARE_RAW (4-cell, TBD in 4E-000): unknown
Noise STD BLE-off (4-cell, TBD in 4E-002): unknown
Noise STD BLE-on (4-cell, TBD in 4E-002): unknown
```

**Experiment status table:**
Mark E-000 through E-003 as PASSED (single-cell, superseded).
Add 4E-000 through 4E-004 as PENDING.

---

### TASK 6 — Update EXPERIMENT_HISTORY.md

Add a new section at the top (most recent first):

```
## 2026-06-10 — 4-Cell Pivot

Hardware changed to 4-cell parallel platform.
Single-cell experiments below are superseded as production baseline.
They remain as firmware/transport validation evidence.

New experiment series pending: 4E-000 through 4E-004.
```

---

### TASK 7 — Create new reference document in docs/

Create `docs/VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md` on AQ3 board.

This file already exists in this session's outputs — SCP it to AQ3:
```bash
# From your laptop:
scp VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/docs/
```

Content: complete reference for voltage architecture and 4-cell parallel bridge physics.
This is the "theory reference" document for future sessions and for the boss.

---

### TASK 8 — Git commit

After all document updates are complete, commit everything:

```bash
cd ~/ArduinoApps/gas-cylinder-monitor
git add .
git commit -m "docs: 4-cell pivot — update experiments, hardware, plan, and add theory reference docs

- EXPERIMENT_PROGRAM.md: add 4E-000 to 4E-004 series, mark single-cell as superseded
- HARDWARE.md: update to 4-cell as production baseline
- PLAN.md: move 4-cell to V1, document pivot decision
- SESSIONS.md: log 2026-06-10 session
- CLAUDE.md: update current position and hardware constants
- EXPERIMENT_HISTORY.md: add pivot entry
- docs/: add VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md
- docs/: add GasCylinder_HardwareDesign_Reference_2026.md (full session theory doc)"
git push
```

---

## After documentation is complete — what comes next

Once all 8 tasks above are done, the next implementation phase begins:

### Phase 1 — 4E-000: Parallel bring-up (no code changes needed)
1. Wire all 4 cells in parallel on breadboard (all reds together, all blacks together, all greens together, all whites together)
2. Flash existing single-cell firmware (UNCHANGED)
3. Tare on empty platform
4. Place 1 kg reference weight at centre — record reading
5. Move weight to each corner — verify readings within ±2% of each other
6. PASS → proceed to 4E-001

### Phase 2 — 4E-001: Cal_factor re-derivation
- Same procedure as E-001 but with 4-cell platform
- Use ≥1 kg reference weight
- Expected new cal_factor: ~420 counts/gram
- Write to config.json

### Phase 3 — 4E-002: Noise characterisation
- Same procedure as E-002 but with 4-cell platform
- Run BLE-off baseline then BLE-on
- Derive new STD and 4σ threshold

### Phase 4 — 4E-003: Distribution validation (new)
- Place reference weight at 5 positions
- Verify all within ±2%

### Phase 5 — 4E-004: BLE transport
- Run existing BLE test on 4-cell hardware
- Almost certainly passes without change

---

## Wiring — locked, unchanged from single-cell

### ESP32-C3 → HX711
| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V — destroys GPIO |
| GND | GND | |
| GPIO4 | SDO (DOUT) | safe GPIO, not strapping pin |
| GPIO3 | SCK | safe GPIO, not strapping pin |

### Load cell wire colours → HX711 (for all 4 cells, joined in parallel)
| Wire colour | Signal | Join all 4 to → |
|---|---|---|
| Red | E+ | HX711 E+ |
| Black | E− | HX711 E− |
| Green | A+ | HX711 A+ (INNA) |
| White | A− | HX711 A− (INPA) |

### Arduino IDE — locked setup (unchanged)
- Package: esp32 by Espressif Systems **v3.0.7** (NOT v3.3.9)
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: **ENABLED**
- First flash: hold BOOT → click Upload → release after 2s

---

## Key technical facts locked in this session

### Voltage (Part 1 of today's research)
- HX711 is CMOS — DT output = VCC always. 3.3V VCC = 3.3V DT. 5V VCC = 5V DT = destroys GPIO.
- ESP32-C3 GPIO absolute max input: 3.6V. 5V = permanent damage.
- AMS1117-3.3 LDO on SuperMini: accepts 3.6V–15V input, outputs stable 3.3V.
- 3.3V vs 5V excitation: identical performance. Both use 25.6% of ADC range. Noise independent of VCC.
- Production power: any 5V ≥1A USB charger → USB-C port. Identical to laptop USB.

### 4-Cell mechanics (Part 2 of today's research)
- Parallel bridge: all 4 A+ joined → bus voltage = arithmetic average of 4 individual voltages.
- Average of 4 cell outputs ∝ total weight / 4. HX711 sees signal proportional to total weight.
- Load distribution irrelevant: 7.2/7.8/7.1/7.46 kg gives same reading as 7.39/7.39/7.39/7.39 kg.
- 4-cell cal_factor ≈ 4× single-cell value (~420 counts/gram vs ~105).
- Firmware unchanged. Hub unchanged. Seam contract unchanged.
- Must re-derive: cal_factor, tare_raw, noise floor — all on 4-cell assembled platform.

---

## Documents produced this session (upload to project knowledge)

| File | Description |
|---|---|
| `GasCylinder_HardwareDesign_Reference_2026.md` | Full session theory: load cell physics through long-term drift (Sections 1–7, Appendices 1–4) |
| `GasCylinder_HardwareDesign_Reference_2026.docx` | Same content, Word format for boss/sharing |
| `VOLTAGE_AND_4CELL_MECHANICS_REFERENCE.md` | Today's deep dive: voltage architecture + 4-cell parallel bridge mechanics |
| `HANDOFF_2026_06_10_FINAL.md` | This document |

All four should be:
1. Uploaded to Claude project knowledge files
2. SCP'd to `arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/docs/`
3. Committed to git

---

## One open question before 4E-000

**Load cell mounting orientation needs verification.**

From photos: the cells are sandwiched between the circular top plate and the small round wooden feet.
The wire exits come from one end of each cell — that is the **fixed end** (bolted to the foot/base).
The smooth rounded end is the **free end** (contacts the top plate).

Before running 4E-000, confirm visually that:
- Fixed end (wire exit side) → bolted to the small wooden foot below
- Free end (smooth side) → touching the circular top plate above
- All four cells oriented this way consistently

If any cell is reversed, that cell's signal will be inverted — readings will be wrong.
This is verified experimentally in 4E-000 by lifting one corner and checking the reading drops.

---

*End of handoff — gas-cylinder-monitor | Gratian Technologies | June 2026*
*Previous handoff: HANDOFF_2026_06_08_FINAL.md*
*This handoff: HANDOFF_2026_06_10_FINAL.md*
