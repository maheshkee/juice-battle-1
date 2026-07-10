# WORKING CONTRACT — Juice Battle
# Engineering Philosophy and Execution Rules

This is the single source of truth for how we think, design, plan, and execute on this project.
These are rules — deviations must be explicit and justified.

---

## 1. THINK BEFORE CODING

- State all assumptions before implementing
- If uncertain → ask, do not guess
- If multiple valid approaches exist → present them, do not silently choose one
- If a simpler approach exists → say so
- Clarity before action, always

---

## 2. SIMPLICITY FIRST

- Solve ONLY the problem asked — nothing extra
- No speculative features
- No unnecessary abstractions
- No future-proofing unless explicitly required
- If 200 lines can be written in 50 → rewrite it

---

## 3. SURGICAL CHANGES

- Modify only what is required
- Do not refactor unrelated code
- Match existing code style (even if imperfect)
- Remove only imports/variables made unused by your own change
- If you notice other issues → mention them, do NOT fix unless asked

---

## 4. ORCHESTRATOR LAW (non-negotiable)

### Hub side (Python)
- `main.py` owns NO logic. It wires modules, starts services, routes callbacks. Nothing else.
- Each Python module exposes exactly: `start_service()` and `handle_cmd(cmd: str)`
- No module imports another module directly. All coordination goes through `main.py`.
- If `main.py` grows beyond wiring — stop and extract a module.

### Node side (C++)
- `node.ino` contains only `setup()`, `loop()`, and state machine cases. No logic inline.
- No sensor math, no averaging, no threshold comparisons inline in `node.ino`.
- Every module returns a result struct: `{value, quality: GOOD/DEGRADED/FAILED, diagnosis}`.
- Never block in a module — return immediately, let the orchestrator manage state.
- Never use `String` class — use `char buf[]` and `snprintf` only.
- Never share global variables across modules — pass everything via function arguments.
- `node.ino` paces itself with a `millis()` guard at the TOP of `loop()` only.
- `node.ino` makes all decisions based on `result.quality` — never on raw values directly.

---

## 5. MODULE BOUNDARIES

### Python module contract
```
Module          Owns                                Exposes
──────────────────────────────────────────────────────────────────────
receiver.py     WiFi/MQTT connection to both nodes  start_service()
                Inbound payload parsing             handle_cmd(cmd: str)
                Node connection state               get_node_status() → dict

game_engine.py  Pour event detection                start_service()
                Score calculation                   handle_cmd(cmd: str)
                Game state machine                  get_game_state() → dict
                SQLite persistence                  on_weight_update_cb (set by main)

persona_engine.py Emotion state per persona          start_service()
                  Battle narrative generation        handle_cmd(cmd: str)
                  Emoji / animation event emission   on_game_event_cb (set by main)

dashboard.py    Socket.IO bridge to browser          start_service()
                Translates game events → UI events  handle_cmd(cmd: str)
```

### C++ module contract (ESP32 node firmware)
```
Module          Owns                                Returns
──────────────────────────────────────────────────────────────────────
ads1232.cpp     Raw 24-bit bit-bang read            WeightRaw {raw, quality, diagnosis}
weight_engine   Tare, calibration, filter, event    WeightResult {grams, is_pour, quality}
comms.cpp       WiFi connect, MQTT/UDP publish       bool (success/fail)
```

---

## 6. JUICE BATTLE-SPECIFIC RULES

1. **NODE_ID is the only thing that differs between node A and node B.**
   It lives ONLY in `config.h`. Never hardcoded anywhere else in the firmware.

2. **Calibration requires three known reference weights.**
   Always verify against 100g, 250g, and 500g. Never adjust calibration by feel.

3. **Dashboard design follows the data model — never the reverse.**
   Design the data schema first. The UI adapts to it.

4. **Game state must be fully restorable from a cold start.**
   No assumption of sequential startup order.

5. **ADS1232 voltage discipline:**
   - AVDD = 5V (analog supply — from 5V rail via board)
   - DVDD = 3.3V (digital supply — from 3.3V rail)
   - ESP32-C3 GPIO = 3.3V — compatible with ADS1232 DVDD

6. **UNO Q voltage discipline (always):**
   - MCU headers: 3.3V logic. A0, A1 are NOT 5V tolerant.
   - MPU JCTL header: 1.8V ONLY. 3.3V = hardware damage.

7. **No MQTT credentials or WiFi passwords in source code.**
   Always in `config.h` which is in `.gitignore`.

---

## 7. TOOL SPLIT

- Claude Chat = research, analysis, architecture, design, debugging, generating CLI prompts
- Claude CLI = implementation, file creation, running commands on the board

**CLI prompt format (required for every implementation task):**
```
PROJECT: Juice Battle
PHASE: [current phase · chunk name]
TASK: [one precise sentence]
CONTEXT: [what just happened / what this enables]
LOCATION: [file path(s) to create or modify]
CONSTRAINTS: [voltage rules · existing patterns · hardware limits]
IMPLEMENTATION: [detailed description]
EXPECTED RESULT: [how to verify success]
DO NOT: [explicitly forbidden approaches]
```

---

## 8. STAGE-BASED DEVELOPMENT

- Work in phases. Each phase is divided into chunks.
- A chunk must be: clearly defined, independently testable, small enough to reason about.
- Experiments (probing unknown hardware behaviour) stay in single files — throwaway.
- Production code is modular from the first line.

For every chunk:
1. PLAN — define goal and boundaries
2. DESIGN — architecture, data flow, responsibilities
3. SPECIFY — inputs/outputs, constraints, tools
4. IMPLEMENT — via Claude CLI (prompt-driven)
5. VERIFY — test against defined success condition

---

## 9. TESTING STRATEGY

- If hardware is available → test on device
- If not → use unit tests or simulations (see `tests/mock_node.py`)
- Every calibration change must be verified against three known reference weights.

---

## 10. DOCUMENT DISCIPLINE

One job per document. No fact lives in two places.

| Document               | Owns                                    | Never contains                |
|------------------------|-----------------------------------------|-------------------------------|
| WORKING_CONTRACT.md    | Engineering rules                       | Design decisions, session logs|
| SESSION_CLOSE_PROTOCOL | How to end a session                    | Session content itself        |
| PROJECT_BRIEF.md       | Vision, MVP, scope, non-goals           | Technical design              |
| HARDWARE_MANIFEST.md   | Physical inventory, confirmed specs     | Software architecture         |
| ARCHITECTURE.md        | System design, data flow                | Session records, measurements |
| INTERFACE_CONTRACTS.md | Data schemas, API contracts             | Implementation details        |
| RESEARCH.md            | Hardware discoveries, datasheet notes   | Architecture decisions        |
| LEARNINGS_AND_INSIGHTS | What surprised us, what changed         | Current state                 |
| PROJECT_CONTEXT.md     | One-screen current state                | History                       |
| HANDOFF_FINAL.md       | Right-now state + next task             | Permanent facts               |
| SNNN_description.md    | Historical record of one session        | Current state                 |

---

## FINAL RULE

If a decision violates this contract → it must be explicitly stated and justified.
Otherwise it is wrong.
