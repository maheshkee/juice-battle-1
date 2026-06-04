# PLAN FORWARD — Gas Cylinder Weight Monitor (V1, ESP32-C3 + UNO Q Hub)

**Created:** 2026-06-02 · **Horizon:** next several days
**Companion docs:** `RESEARCH_AND_LEARNINGS.md`, `SESSION_HANDOFF_2026_06_02.md`

---

## A. Guiding rules (unchanged — reiterate every session)

- **First principles:** WHY before HOW; nothing floats in isolation; no "it just works".
- **Small → verify → compound.** One chunk at a time, gated by understanding. Never firehose.
- **Claude chat = design/plan/brainstorm.** **Claude Code CLI = implementation only.** Claude generates precise CLI prompts; no raw code dumped in chat. (Documentation `.md` files are an exception — authored as deliverables.)
- **No hardcoding:** derive paths/names dynamically; `cal_factor`, thresholds, steel/capacity always derived or from config.
- **float-only + non-blocking** MCU patterns (re-verify float on ESP32-C3).
- **Maintain proven / derived / reasoned / pending tags** on every documented value.

---

## B. State as of 2026-06-02

### Locked
- Power → **USB**
- Sampling → **hybrid** (internal fast read + 15-min heartbeat spine + event session on N≈30–50 g + pull)
- % math → **`(gross − steel)/14200`**
- Steel/capacity → **install-anchor primary + interval cold-start + one-tap backup**
- Transport → **WiFi (MQTT-style)** for V1 (BLE fallback, parked)
- Hub storage → **simple (sqlite, minimal schema)** for now (parked)
- Hardware item 6 → **3.3 V, two GPIO (1 SCK + 1 DOUT)**, pins TBD at bring-up
- Scope item 7 → **single node / single cylinder**

### Open
- Transport protocol details / reconnect-buffering
- Storage schema + retention
- Prediction method (staircase-aware fit)
- Analytics outputs + leak detection + end-of-day report channel
- Companion app type + its transport
- 4-cell summing approach; `cal_factor` re-derivation; 3.3 V level-shift check; wiring-noise hardening
- Clock/time-sync source (likely hub)
- Confirm UNO Q STM32 idle in V1

### Parked for deep-storm (interim approach in `SESSION_HANDOFF_2026_06_02.md` §4)
1 Transport · 2 Storage · 3 Prediction · 4 Analytics/alerts · 5 Companion surface

---

## C. Documents to create TOMORROW, before starting the project

Create in the new project folder on the UNO Q (and mirror key ones into the Claude project). Grouped by when they're needed.

### Foundation — must exist before the first Claude Code prompt
| Doc | Purpose |
|-----|---------|
| **CLAUDE.md** | Canonical context Claude Code auto-reads: working mode, hard rules (no-hardcode, chunk-gating), hardware constants, pointers to other docs. *Single most important file.* |
| **README.md** | One-screen orientation: what the project is, board IPs, how to run, doc index. |
| **SCOPE.md** | In/out for V1 (single node, USB, WiFi, pull+event, analytics, prediction). Explicit non-goals (fleet, battery, cloud, short-delivery verification → later). |
| **SPEC.md** | Functional requirements: the exact behaviors (grams+%, pull, event, daily report, prediction), inputs/outputs, acceptance criteria. |
| **ARCHITECTURE.md** | System design: ESP32 node ↔ transport ↔ UNO Q hub (store/understand/predict/present); two calibration layers; data flow. |
| **STRUCTURE.md** | Repo/folder layout, file naming (e.g. `sensor-NNN-name`), where node code vs hub code vs docs live. |
| **WORKING_MODE.md** | The chat-vs-CLI discipline, build philosophy, chunk-gating, no-hardcode rule. |
| **INTERFACE_CONTRACTS.md** | Module result-struct contract `{value, quality, diagnosis}`; transport message schema (node→hub payload); pull/event contracts. |

### Supporting — create alongside / as work proceeds
| Doc | Purpose |
|-----|---------|
| **PLAN.md** | Living plan (this doc evolves into it). |
| **MVP.md** | Minimal milestone definition: the smallest end-to-end slice that proves the loop (e.g. ESP32 reads → WiFi → hub stores → shows grams). |
| **STRATEGY.md** | Phased roadmap: V1 → v1.x (battery, short-delivery, fleet) → intelligence v0.3→v2.0→v3.0. |
| **RESEARCH.md / LEARNINGS_AND_INSIGHTS.md** | Seed from `RESEARCH_AND_LEARNINGS.md`; grow with findings. |
| **SENSOR_CHARACTERISATION.md** | ESP32-C3 noise/cal data (re-measured); proven/derived tags. |
| **SKILL.md** (user skill) | New/updated skill for the ESP32-C3 gas-monitor node + hub patterns, so Claude Code applies confirmed configs. |
| **HANDOFF_YYYY_MM_DD.md** | Daily session handoff (template). |

---

## D. Suggested course — next few days

> Each step is gated: verify before the next. Adjust as reality dictates.

### Day 1 (2026-06-03) — Scaffold + first sensing breath
1. Create the **Foundation docs** (§C) in the new project folder.
2. Confirm quick scope one-liners (STM32 idle; clock on hub).
3. **E-000 ESP32-C3 + HX711 bring-up** (CLI, chunked):
   - Pick two GPIO (1 SCK, 1 DOUT); **verify 3.3 V logic-level compatibility with HX711 at 5 V VCC** (level-shift if needed) — *flag before powering*.
   - Minimal raw bit-bang read with the three corrupt-value filters; print raw counts.
   - Gate: stable, non-corrupt raw stream.

### Day 2 — Raw → grams on the new MCU
4. **`cal_factor` re-derivation** on ESP32 (multi-point with the 10 g blocks). Re-verify `float` sufficiency.
5. Begin **noise re-characterization** (N=200 lab); harden the 4 analog connections.
   - Gate: cal_factor derived + noise floor characterized on ESP32.

### Day 3 — First transport breath
6. **Transport bring-up:** ESP32 WiFi → UNO Q hub, send one reading end-to-end (smallest possible MQTT-style or raw socket). Hub receives + prints.
   - Gate: one live weight reading visible on the hub.

### Day 4 — Minimal loop (MVP slice)
7. Hub: **store** heartbeat snapshots (simple sqlite) + **show grams** (pull + 15-min spine).
8. Wire in **steel/capacity** (install-anchor + interval cold-start) → show **% + state**.
   - Gate: end-to-end "place cylinder → see grams + honest %".

### Day 5+ — Validation + intelligence seeds
9. **006B measured water removal** — validate Δ-consumption accuracy.
10. **005 calibration linearity** (ported) — multi-point across range.
11. Seed analytics (used-today) and a first naive prediction (linear fit on daily net).
12. Schedule deep-storms for parked items 1–5 as each becomes the bottleneck.

---

## E. Worthy experiments (full triaged list)

**New, gating:** E-000 ESP32+HX711 bring-up (3.3 V check, pins, raw read) · cal_factor re-derivation · transport bring-up.
**Ported to ESP32:** 005 calibration linearity · 006B measured water removal (needs measuring cup) · 007B threshold stress (lower priority) · noise re-characterization + wiring hardening.
**Post-MVP characterization (gated behind cal_factor + wiring hardening; run after the end-to-end loop works):**
The dominant error source (~6.5% ≈ 923 g cal_factor drift) lives here. Three distinct experiments — DO NOT run before cal_factor exists (can't measure drift of an unestablished quantity) and before wiring is hardened (noisy jumpers can't be separated from real thermal drift):
- **Thermal drift (controlled)** — hold weight constant, vary temperature deliberately; measure how cal_factor + scale zero shift → gives the °C→grams sensitivity coefficient. *Heat-source method: [PENDING — decide at run time].*
- **Long-run zero/stability drift (passive)** — known weight (or empty) left untouched for days, logged; measures baseline wander + mechanical creep over time, separate from temperature.
- **Diurnal / in-situ drift (real-world)** — the kitchen heats during cooking, cools at night; thermal drift *as the product actually experiences it*. **Key V1 decision it feeds:** is active temperature compensation needed, or do per-boot re-zeroing + anchor cross-checks already swamp the drift in software?
- **Queue position:** after the MVP loop is end-to-end. Background / long-duration, not a gating bring-up chunk.

**Later:** 4-cell summing rig.
**Dropped:** STM32-only work; STM32 double-bug check (re-verify float fresh).

---

## F. Reminders / things not to lose

- **3.3 V level-shift check is a safety gate** — do it before trusting any ESP32+HX711 reading.
- **cal_factor is per-MCU** — the STM32 value does not carry.
- **Two calibration layers** (raw→g, g→gas%) are independent — keep separate.
- **Bias predictions safe** (conservative/low-gas end) under uncertainty.
- **Idle samples are evidence** (liveness + leak detection) — keep the uniform grid.
- **Wiring noise moves with the HX711** — harden the analog hop on the new node.
