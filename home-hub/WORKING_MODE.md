# WORKING_MODE.md
# Working Mode Contract — All Arduino UNO Q Projects
# Applies to: home-hub, experiments, and every future app on this board
# Last updated: 2026-05-05

---

## The One Rule

PLANNING / RESEARCH / BRAINSTORMING / LEARNING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION / FILE EDITING → Claude Code CLI only.

These two modes never mix. Chat does not write code. CLI does not make
architecture decisions. Every session belongs to exactly one mode.

---

## What Each Mode Does

### Claude.ai Chat (this session)
- Understands the problem from first principles
- Derives requirements from real-world constraints
- Designs architecture and data flow
- Decides experiment structure and acceptance criteria
- Produces a precise, structured prompt for CLI
- Updates project knowledge files (SENSOR_CHARACTERISATION.md etc.)
- Produces HANDOFF.md at end of session

### Claude Code CLI (board session)
- Reads CLAUDE.md and relevant SKILL.md before touching anything
- Receives the design prompt from chat — executes it exactly
- Writes all code, creates all files, edits configs, runs commands
- Never adds features not in the prompt
- Never makes architecture decisions
- Updates CLAUDE.md at end of session with what changed and current state

---

## Why This Rule Exists

Chat has:
- Full project knowledge files
- Reasoning context across the whole session
- First-principles derivations
- Architecture history

CLI has:
- Direct board access
- File system
- Compile and deploy tools

Mixing them produces code that ignores architecture decisions,
hardcodes values that should be computed, and breaks the
knowledge continuity between sessions.

---

## Every CLI Session — Mandatory Checklist

1. Read ~/ArduinoApps/home-hub/CLAUDE.md
2. Read relevant SKILL.md for the task at hand
3. Read SENSOR_CHARACTERISATION.md if touching HX711 or weight measurement
4. Read the design prompt from chat — understand it fully before writing anything
5. Execute the prompt — nothing more, nothing less
6. Update CLAUDE.md: what was built, what was tested, what is current state

---

## Every Chat Session — Mandatory Checklist

1. Read HANDOFF.md from previous session if provided
2. Search project knowledge for relevant context before answering
3. Never suggest code without a design phase first
4. Every implementation task ends with a CLI prompt, not code in chat
5. Produce HANDOFF.md at end of session

---

## Every New Project — Mandatory Checklist

1. Create APP_NAME/CLAUDE.md from day one
2. Reference this WORKING_MODE.md in it
3. Never hardcode: paths, usernames, hostnames, thresholds, cal factors
4. Never write code without a design prompt from chat
5. Add SENSOR_CHARACTERISATION.md reference if any sensor is involved

---

## Prompt Quality Standard

A CLI prompt is only ready to send when it contains:

| Element | Example |
|---------|---------|
| Files to read first | "Read ~/ArduinoApps/home-hub/CLAUDE.md first" |
| Exact file paths to create/edit | "Create ~/ArduinoApps/experiments/hx711/003-noise/app/sketch/sketch.ino" |
| Locked constants to use | "CAL_FACTOR = 106.7, DT=D7, SCK=D6" |
| Architecture decisions | "Use millis() pacing at TOP of loop(), not inside state cases" |
| Acceptance condition | "Deploy and confirm Bridge.notify fires in logs every 120ms" |
| What NOT to do | "Do not use any external HX711 library" |

A prompt missing any of these elements goes back to chat for completion.

---

## Non-Negotiable Rules (apply in both modes)

These rules apply everywhere, always, regardless of mode:

| Rule | Detail |
|------|--------|
| No hardcoding | Paths, usernames, hostnames, thresholds, cal factors — all computed or loaded from config |
| DT=D7, SCK=D6 | Never change. D2-D5 have STM32U585 timer conflicts |
| No external HX711 library | Raw bit-bang only. Copy from home-hub sketch |
| All three corrupt filters | LONG_MIN, -1, 0x7FFFFF — all required, always |
| millis() pacing at TOP of loop() | Never inside state cases |
| Read before edit | Always read full file before any Python edit |
| Never touch home-hub until experiments conclude | Experiments live in ~/ArduinoApps/experiments/ |
| Commit only tested working code | Never commit until verified on hardware |
| JCTL = 1.8V only | 3.3V on JCTL = hardware damage |
