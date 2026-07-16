# SESSION HANDOFF — 2026-06-02
# Gas Cylinder Weight Monitor — V1 architecture brainstorm
# Paste into the next chat session for full context.

---

## 0. How to use this document

This captures the **2026-06-02 brainstorm session** that designed the V1 product end-goal and **solved the steel/gas/percentage logic**. It is a design/brainstorm handoff. Working mode still applies: design/plan/brainstorm in Claude chat; implementation goes to Claude Code CLI only, in verified chunks.

**Read alongside:** `RESEARCH_AND_LEARNINGS.md` (the durable findings) and `PLAN_FORWARD.md` (course + experiments + docs to create). This handoff is the *narrative*; those are the *reference* and the *plan*.

---

## 1. Where we are

Following the **ESP32-C3 pivot** (see prior `HANDOFF_ESP32_PIVOT.md`): HX711 moves to an ESP32-C3 sensor node; the UNO Q becomes the storage/intelligence/connectivity **hub ("SBC")**. Today we brainstormed the **full V1 end-goal** and resolved the central data-model questions before any transport/implementation work.

**V1 end-goal (user's words, distilled):** user places a cylinder (full / partial / empty) on a scale (4 cells final, 1 cell + substitute weights in dev). ESP32 reads weight, sends to UNO Q hub. Hub shows weight in grams + %; notifies consumption two ways — **pull** (user requests → ESP32 reads → hub shows in app/display) and **event-driven** (periodic/usage-based). Hub does **data analytics** (daily/hourly usage, patterns) and **predicts run-out**, reported daily at a set time.

---

## 2. What this session ACCOMPLISHED

The product's hardest conceptual problem — turning one gross weight into an honest gas %/prediction — is **solved**:

1. **Percentage truth + the 52% trap** — must subtract steel: `% = (gross − steel)/14200`. (§4 of RESEARCH doc.)
2. **Anchor-event method** — full install is the **primary guaranteed anchor** (`steel = gross − capacity`); empty floor is an **opportunistic cross-check**. Corrected from an earlier over-reliance on the empty floor.
3. **Capacity classifiable, brand invisible & unnecessary** — type from well-separated gross bands; steel measured directly, brand never needed.
4. **Error budget** — ±150 g fill tolerance is negligible (constant offset, cancels in slope); the real enemy is `cal_factor` drift (~6.5% ≈ 923 g).
5. **Partial cold start** — provably unsolvable to a *point* by sensing alone; bounded to a **±5% interval** (position = full/partial/empty classification for free); collapses to exact via one input or one observed known-state event; **blind only at first boot**, self-heals by first refill.
6. **Δ-tracking is calibration-free** — usage/burn-rate/patterns work day one; only absolute gauge + prediction need steel.

Full reasoning for all of the above is in `RESEARCH_AND_LEARNINGS.md`.

---

## 3. DECISIONS LOCKED today

- **Power → USB** (stationary scale; battery trilemma; pull needs always-listening). Battery deferred to v1.x.
- **Sampling → hybrid:** internal fast read (few s, not stored) + **15-min heartbeat snapshot (authoritative spine)** + **event/session record on N≈30–50 g drop w/ hysteresis (UX only)** + **pull on demand**.
- **% math → `(gross − steel)/14200`**; steel obtained via anchors, not assumed.
- **Steel/capacity → install-anchor primary + interval cold-start + one-tap tare backup.**
- **Transport → WiFi (likely MQTT) for V1** (USB removes BLE's power advantage; tiny data rate; single node; avoids documented QRB2210 BLE pain). BLE remains the fallback — **parked for later deep-storm**.
- **Hub storage → simple for now** (e.g. sqlite, minimal schema). **Parked for later deep-storm.**
- **Hardware (item 6) → 3.3 V; two ESP32 GPIO, one SCK + one DOUT** (exact pins chosen at bring-up).
- **Scope (item 7) → single node / single cylinder for V1.** Fleet deferred.

---

## 4. PARKED for future deep-storms (interim simple approaches recorded)

| # | Topic | Interim approach for now | Deep-storm later? |
|---|-------|--------------------------|-------------------|
| 1 | Transport | WiFi (MQTT-style); BLE fallback | Yes — confirm protocol, security/pairing, reconnect |
| 2 | Hub storage | sqlite, minimal raw+derived schema | Yes — schema, retention, "store everything raw" |
| 3 | Prediction | linear trend fit on daily net consumption → days-left | Yes — staircase-aware fit, robustness, confidence |
| 4 | Analytics + alerts | used-today, basic hourly pattern, end-of-day report | Yes — anomaly/leak detection, report channel (app push vs Telegram) |
| 5 | Companion surface | LAN web UI (WebUI brick + Socket.IO, prior experience) | Yes — phone vs web vs PWA, its transport |

---

## 5. OPEN threads remaining (not yet designed)

- Transport details (protocol, pairing, reconnect/buffering on link loss).
- Hub storage schema + retention.
- Prediction method (staircase-aware trend fit).
- Analytics outputs + leak detection + end-of-day report delivery channel.
- Companion app type + its link.
- Hardware: ESP32 pin pick, **3.3 V level-shift check**, 4-cell summing approach (one HX711 + combinator vs four), `cal_factor` re-derivation, wiring-noise hardening.
- Clock/time-sync (ESP32 has no RTC; 15-min spine + EOD report need real timestamps → likely sourced on the hub).
- Confirm the UNO Q's own STM32 MCU is **idle** in V1 (ESP32 owns sensing).

---

## 6. WORTHY experiments under the new goal (triaged)

**New, gating:**
- **E-000 ESP32-C3 + HX711 bring-up** — pins + **3.3 V logic-level check** + first clean raw read. Gates everything.
- **`cal_factor` re-derivation on ESP32** (raw→grams). Prior 106.7 raw/g was STM32-specific.
- **Transport bring-up** — smallest "send one reading ESP32→UNO Q" end-to-end.

**Ported (re-homed to ESP32):**
- **005 calibration linearity** — multi-point cal across weight range, low-range linearity + hysteresis. (Do NOT finish on the STM32 — abandoned MCU.)
- **006B measured water removal** — validates Δ-consumption accuracy (now central). Needs measuring cup.
- **007B threshold stress** — validates event N≈30–50 g. Lower priority (spine carries accuracy).
- **Noise re-characterization + wiring hardening** on ESP32.

**Later:** 4-cell summing rig (when cells on hand).

**Post-MVP characterization (gated behind cal_factor + wiring hardening):** the dominant error (~6.5% ≈ 923 g cal_factor drift) lives here. Three experiments, run only after the end-to-end loop works and the analog wiring is hardened (else contact noise can't be separated from real drift): **thermal drift (controlled)** — vary temperature, measure cal_factor + scale-zero shift, derive °C→g coefficient [heat-source method PENDING — decide at run time]; **long-run passive stability** — known weight left untouched for days, baseline wander + mechanical creep; **diurnal/in-situ drift** — real kitchen heat/cool cycle, feeds the V1 decision *do we need active temperature compensation, or do per-boot re-zero + anchor cross-checks already swamp it in software?* Queue position: after the MVP loop; background/long-duration, not a gating bring-up chunk.

**Dropped:** anything STM32-only; STM32 double-bug check (re-verify float fresh on ESP32).

Test weights on hand: six identical 10 g blocks, 82 g adapter, 112 g container, 227 g speaker. (158 g reference is gone.) Identical 10 g blocks enable reference-free linearity.

---

## 7. Suggested opening for next session

"Continuing the gas monitor V1. The steel/gas/percentage logic is solved (see RESEARCH_AND_LEARNINGS.md). Today: set up the new project + its docs, then start the ESP32-C3 + HX711 bring-up (E-000) — pins, 3.3 V level check, first clean raw read. Working mode unchanged: design here, implement via Claude Code CLI in verified chunks."

First concrete action: scaffold the new project and create its baseline docs (see `PLAN_FORWARD.md` §C), then E-000 hardware bring-up.
