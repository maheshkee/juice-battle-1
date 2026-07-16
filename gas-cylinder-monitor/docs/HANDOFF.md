# HANDOFF.md — gas-cylinder-monitor
# Last updated: 2026-06-04 (architecture pivot ingested)

---

## Current session: ESP32 Pivot Ingested — Folder Corrected

**Date:** 2026-06-04
**What was done:**
- Safety snapshot committed (822c007) — STM32 scaffold preserved in git
- New folder structure created: node/ hub/ docs/reference/specs/ docs/reference/specs/_source/
- reference-code/hx711-modular/ renamed → reference-code/stm32-hx711-modular/
- All 28 inbox files ingested with dedup (see STEP 2 dedup report below)
- CLAUDE.md, README.md, SKILL.md completely rewritten for ESP32 architecture
- docs/PLAN.md rewritten around 7 phased chunk-groups
- docs/reference/ARCHITECTURE.md rewritten for node/hub architecture
- docs/reference/INTERFACE_CONTRACTS.md created (the node↔hub seam)
- docs/PROJECT_CONTEXT.md created (one-screen context)
- node/README.md, hub/README.md created
- reference-code/stm32-hx711-modular/PORTING_NOTE.md created
- No product code written. No App Lab app created.

**Current state:**
- SCAFFOLD ONLY. node/ and hub/ are empty (just .gitkeep).
- Next: E-000 ESP32-C3 + HX711 bring-up — design in chat, implement via CLI.

---

## Next session starts here

1. Read CLAUDE.md (rewritten — covers node/hub split, 3.3V gate, ESP32 rules)
2. Read docs/PLAN.md (chunk-group 1 is next: E-000 bring-up)
3. Read docs/SCOPE.md (V1 locked scope)
4. Read docs/PROJECT_CONTEXT.md (one-screen summary)
5. **Design E-000 in Claude.ai chat first**: GPIO pin selection, 3.3V logic-level
   assessment, first bit-bang read. Chat produces CLI prompt. Then execute in CLI.
6. Gate: stable non-corrupt raw stream from HX711 on ESP32-C3.

**The 3.3V gate is not optional.** Check DOUT/SCK logic-level compatibility with
HX711 at 5V VCC before powering. Level-shift if needed. This is E-000 chunk 1.

---

## Session 2026-06-02: Architecture Brainstorm — V1 Designed

**Source:** SESSION_HANDOFF_2026_06_02.md (archived in inbox, ingested here)

**What was accomplished:**

The product's hardest conceptual problem — turning one gross weight into an honest gas %
— is solved:

1. **Percentage truth + the 52% trap:** must subtract steel: `% = (gross − steel)/14200`.
2. **Anchor-event method:** full install is the primary guaranteed anchor
   (`steel = gross − capacity`); empty floor is an opportunistic cross-check.
3. **Capacity classifiable, brand invisible & unnecessary:** type from well-separated
   gross bands; steel measured directly, brand never needed.
4. **Error budget:** ±150 g fill tolerance is negligible (cancels in slope);
   the real enemy is cal_factor drift (~6.5% ≈ 923 g).
5. **Partial cold start:** bounded to ±5% interval; collapses to exact via one input
   or one observed known-state event; blind only at first boot, self-heals by first refill.
6. **Δ-tracking is calibration-free:** usage/burn-rate/patterns work day one.

**Decisions locked in that session:**
- Power → USB (stationary scale; battery trilemma dissolved)
- Sampling → hybrid (fast internal read + 15-min heartbeat spine + event/session records)
- % math → `(gross − steel)/14200`
- Steel/capacity → install-anchor primary + interval cold-start + one-tap backup
- Transport → WiFi (MQTT-style) for V1; BLE fallback parked
- Hub storage → sqlite, minimal raw schema; deep-storm later
- Scope → single node / single cylinder for V1

Full reasoning in docs/RESEARCH.md (Part I) and docs/SCOPE.md.

---

## Session 2026-06-02: ESP32 Pivot

**Source:** HANDOFF_ESP32_PIVOT.md (archived at docs/reference/HANDOFF_ESP32_PIVOT.md)

ESP32-C3 becomes the sensor node (owns HX711). UNO Q becomes the hub (Python, SQLite,
WebUI, intelligence). The STM32U585 MCU on UNO Q is idle in V1.

What carries over (MCU-agnostic):
- HX711 raw bit-bang logic (ports to ESP32; pin numbers change)
- Three corrupt-value filters (LONG_MIN, -1, 0x7FFFFF)
- Module result-struct contract {value, quality, diagnosis}
- Non-blocking one-sample-per-loop millis() pacing
- Adaptive retry logic
- Data intelligence roadmap

What does NOT carry:
- DT=D7/SCK=D6 (STM32 timer-conflict constraint, void on ESP32-C3)
- cal_factor = 106.7 (STM32-specific, VOID — re-derive on ESP32)
- float-only assumption (STM32 double-broken bug; re-verify on ESP32-C3)
- Bridge.notify / App Lab integration (ESP32 uses WiFi)
- wait_ready timeout 400ms (tuned for Bridge load; re-tune on ESP32)

---

## Session 2026-06-03: Scaffold Created (STM32 era — now superseded)

**Source:** Previous HANDOFF.md

- Created ~/ArduinoApps/gas-cylinder-monitor/ as a clean reference root
- Wrote initial CLAUDE.md, README.md, SKILL.md for STM32 architecture
- No product code written, no App Lab app created
- **Status:** Superseded by ESP32 pivot ingestion (this session)

---
