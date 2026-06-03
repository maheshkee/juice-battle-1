# HANDOFF.md — gas-cylinder-monitor
# Last updated: 2026-06-03

---

## Session: Migration — consolidated reference folder created

**What was done:**
- Created ~/ArduinoApps/gas-cylinder-monitor/ as a clean, de-duplicated reference root
- Copied canonical source files from home-hub/docs and experiments/ (see README.md for dedup decisions)
- Wrote new CLAUDE.md, README.md, SKILL.md, docs/HANDOFF.md, docs/reference/EXPERIMENT_HISTORY.md
- Wrote .gitignore
- No product code was written. No App Lab app was created.
- app/ directory is intentionally empty — scaffold only

**Current state:**
- Folder structure and all reference docs are in place
- Phase 1 (load cell reading) design has NOT been done yet — do that in chat first
- Wheels, typelibs, socket.io live in home-hub/ and must NOT be duplicated here

---

## Next session starts here

1. Open Claude.ai chat with this HANDOFF.md
2. Read CLAUDE.md and docs/PLAN.md to understand where Phase 1 begins
3. Design Phase 1 (load cell reading, state machine, Bridge.notify) in chat
4. Chat produces a precise CLI prompt with locked constants from SENSOR_CHARACTERISATION.md
5. Execute that prompt in Claude Code CLI — nothing else

---
