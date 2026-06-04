# Session close protocol
# How every session ends. Follow this sequence without skipping steps.
# Written from observed practice — 2026-06-04.

---

## Why this document exists
Every session produces knowledge, measured outputs, and code. If not saved correctly,
context is lost between sessions and the next chat starts blind. This protocol ensures
nothing is lost and every document stays current and trustworthy.

---

## The two types of output every session produces

### Type 1 — Permanent knowledge (never deleted, only appended)
Things learned that are true forever or until hardware changes.
Goes into: LEARNINGS_AND_INSIGHTS.md, RESEARCH.md

### Type 2 — State snapshot (updated to reflect current reality)
Where we are right now. Changes every session.
Goes into: CLAUDE.md, PROJECT_CONTEXT.md, SESSIONS.md, HANDOFF files

---

## End-of-session sequence — follow in order

### Step 1 — Code is already on the board (done during session)
All code written via Claude Code CLI during the session lives on the board already.
Nothing to do here — just confirm Claude Code confirmed each file created/updated.

### Step 2 — Update CLAUDE.md
What to update:
- Current position (which experiment/group we are at)
- What was completed this session (gate result)
- What is next (next experiment/chunk)
- Any new locked values (wiring, pins, confirmed constants)
- Any new rules discovered this session
CLI: Claude Code updates CLAUDE.md current state section.

### Step 3 — Update PROJECT_CONTEXT.md
What to update:
- Hardware table: any new confirmed values or wiring
- Current state block: built sketches, gate results
- Open questions: mark RESOLVED if answered this session
- Next action: update to reflect what E-00x is next
CLI: Claude Code updates PROJECT_CONTEXT.md.

### Step 4 — Append to SESSIONS.md
Never overwrite. Always append a new session block at the bottom.
Each session block contains:
- Session number and date
- Goal of the session
- Real hardware outputs (actual measured numbers — not estimates)
- Gate result (PASSED / FAILED / IN PROGRESS)
- What was built (sketch names and locations)
CLI: Claude Code appends new session block to SESSIONS.md.

### Step 5 — Append to LEARNINGS_AND_INSIGHTS.md
Never overwrite. Always append new L-XXX entries at the bottom.
Each entry contains:
- L-number (increment from last entry)
- Title describing the insight
- Date
- The WHY explained from first principles
- Verified: what real measurement confirmed it (if applicable)
What qualifies as a learning:
- Any "why does this work" question answered from first principles
- Any rule that must never be violated and why
- Any surprising discovery from real hardware
- Any value or constant with its derivation reasoning
- Any comparison between two approaches with reasoning for the choice
- Any re-evaluation rule (what changes when setup changes)
What does NOT go here:
- Step-by-step instructions (those go in HANDOFF or SKILL.md)
- Raw measured numbers without explanation (those go in SESSIONS.md)
- Architecture decisions (those go in ARCHITECTURE.md)
CLI: Claude Code appends new L-XXX entries to LEARNINGS_AND_INSIGHTS.md.

### Step 6 — Append to RESEARCH.md
Only if new hardware-specific findings were confirmed on real hardware this session.
Never overwrite existing sections. Append new dated section at bottom before Change Log.
What goes here:
- Confirmed pin assignments
- Confirmed voltage/logic level behaviour
- Confirmed cal_factor ranges (rough or derived)
- Confirmed IDE/toolchain setup
- Hardware-specific gotchas confirmed on real hardware
Update the Change Log table with a new row.
CLI: Claude Code appends to RESEARCH.md and updates Change Log.

### Step 7 — Create session HANDOFF file
Named: HANDOFF_YYYY_MM_DD_SESSIONN_DESCRIPTION.md
If first session of the day: HANDOFF_2026_06_04_SESSION1_description.md
If second session: HANDOFF_2026_06_04_SESSION2_description.md
Never overwrite an existing HANDOFF file — always create a new one with session number.
Contains:
- Session goal
- Hardware used
- Wiring locked (full table)
- Toolchain setup locked
- Real measured outputs (table)
- What was built (sketch locations)
- Gate result
- Next session: what E-00x builds next
CLI: Claude Code creates new HANDOFF file in docs/.

### Step 8 — Create HANDOFF_FINAL for next chat
This is different from the session HANDOFF. This is the entry point document for the
next chat session. Claude (not Claude Code) generates this directly in chat as a
downloadable file.
Named: HANDOFF_YYYY_MM_DD_FINAL.md (one per day, overwrite if multiple sessions same day)
Contains everything the next chat needs to be immediately operational:
- Current position (one line)
- What this product is (pipeline summary)
- Hardware table
- Wiring locked (full table)
- Toolchain setup locked
- Real measured outputs from latest session
- All sketches built so far
- What next experiment must build (detailed spec)
- Key rules never to violate
- Folder structure
- Session start checklist
How: Claude generates this in chat → user downloads → SCPs to board → git commits.
SCP command provided by Claude in chat.

### Step 9 — Verify all files exist
Run these checks on the board before committing:
  ls docs/HANDOFF_YYYY_MM_DD_SESSION*.md  → session handoff exists
  ls docs/SESSIONS.md                      → exists
  ls docs/LEARNINGS_AND_INSIGHTS.md        → exists
  tail -30 docs/RESEARCH.md               → new section visible
  head -20 CLAUDE.md                       → current position updated
If any check fails — fix before committing.

### Step 10 — Git commit and push
Commit message format (no author names, no tool names):
  First line: type(scope): short description of what changed
  Body: bullet list of exactly what was added/updated
  Types: feat / fix / docs / refactor
  Scope: experiment name or area (E-000, E-001, hub, node, docs)
Example:
  docs: add session close protocol and mental model learnings

  - Add SESSION_CLOSE_PROTOCOL.md
  - Append L-006 L-007 to LEARNINGS_AND_INSIGHTS.md
  - Update CLAUDE.md PROJECT_CONTEXT.md current state
  - Add SESSIONS.md session 002 block
  - Add HANDOFF_2026_06_04_SESSION2_E000.md

Commands:
  git add -A
  git commit -m "your message"
  git push
If push rejected (collaborator pushed): git pull --rebase && git push

### Step 11 — Generate next session opening prompt
Claude provides a short opening prompt for the next chat session.
Format:
  "Good [morning/afternoon]. Continuing [product] V1.
   Read the attached handoff document [FILENAME] fully before responding.
   Context: [one line summary of current position]
   Today we [what E-00x builds].
   Start by confirming you read the handoff and state current position."

---

## Document ownership map
| Document | Action | Trigger |
|---|---|---|
| CLAUDE.md | Update current state | Every session |
| PROJECT_CONTEXT.md | Update state + open questions | Every session |
| SESSIONS.md | Append new session block | Every session |
| LEARNINGS_AND_INSIGHTS.md | Append new L-XXX entries | Every session that produces insights |
| RESEARCH.md | Append new hardware findings | Only when real hardware confirmed |
| HANDOFF_YYYY_MM_DD_SESSION*.md | Create new file | Every session |
| HANDOFF_YYYY_MM_DD_FINAL.md | Create/overwrite | Every day (last session of day) |
| ARCHITECTURE.md | Update | Only when architecture changes |
| PLAN.md | Update | Only when plan/scope changes |
| SCOPE.md | Update | Only when scope changes |
| node/E00x/ sketches | Create | When experiment implemented |
| node/STOP/ | Already exists | No change needed |
| node/HW_VERIFY/ | Update if verification logic changes | When new checks needed |

---

## What Claude generates directly in chat (not via Claude Code)
- HANDOFF_YYYY_MM_DD_FINAL.md — downloadable file, Claude creates it
- Opening prompt for next session — Claude writes it in chat
- CLI prompts for Claude Code — Claude writes them in chat
Everything else is written by Claude Code CLI on the board.

---

## Modular sketch principle

### Rule
Single-file sketches are acceptable for early experiments (E-000, E-001, E-002).
The main production sketch must be modular — never one long monolithic .ino file.

### Structure
One orchestrator + multiple focused module files:
- sketch.ino — orchestrator only. setup() and loop(). No sensor logic. No math.
  Calls modules. Passes data between them. Nothing else.
- hx711.h / hx711.cpp — raw bit-bang read. Corrupt filters. Nothing else.
- tare.h / tare.cpp — tare derivation and validation. Nothing else.
- cal.h / cal.cpp — cal_factor derivation and storage. Nothing else.
- noise.h / noise.cpp — noise floor characterisation. Nothing else.
- delta.h / delta.cpp — sliding window delta detector. Nothing else.
- weight.h / weight.cpp — grams computation from raw. Nothing else.
- comms.h / comms.cpp — WiFi send, payload construction. Nothing else.

### Why modular
- Each module can be tested independently without the full system
- A bug in tare does not require reading 500 lines of sketch to find
- Modules can be reused — hx711.cpp ports unchanged to any future MCU
- New capability (4-cell summing, BLE fallback) = new module, orchestrator unchanged
- Easier to hand off — a collaborator reads one file, not everything

### When to go modular
Transition from single-file to modular happens at Group 1 completion — when all
experiments (E-000 through E-00x) are done and the production node sketch begins.
Experiments stay single-file — they are throwaway characterisation code.
Production code is always modular from the first line.

### Module contract (non-negotiable)
Every module must:
- Return a result struct containing: value + quality (GOOD/DEGRADED/FAILED) + diagnosis string
- Never call hx711_read() directly except hx711.cpp — all others receive raw passed in
- Never block — return immediately, let orchestrator manage state
- Never use String class — use char buf[] and snprintf only
- Never use global variables shared across modules — pass everything via function arguments

### Orchestrator contract (non-negotiable)
sketch.ino must:
- Contain only setup(), loop(), and state machine cases
- Have no sensor math, no averaging, no threshold logic
- Pace itself with millis() guard at TOP of loop() only
- Pass raw readings down to modules, receive result structs back
- Make all decisions based on result.quality — never on raw values directly

---

## What never goes in any document
- Usernames or hostnames hardcoded (use 192.168.1.161 format for IPs only)
- Tool names in git commit messages
- Estimated or assumed values presented as verified (always mark DERIVED vs VERIFIED)
- STM32-era values carried forward without re-derivation note
- Architecture decisions mixed into LEARNINGS (they are different documents)

---

## Key principle
Real measured numbers belong in SESSIONS.md.
The WHY behind them belongs in LEARNINGS_AND_INSIGHTS.md.
The current state belongs in CLAUDE.md and PROJECT_CONTEXT.md.
The next session entry point belongs in HANDOFF_FINAL.
Never mix these. Each document has one job.

---

*This protocol was derived from the 2026-06-04 session practice.
Update it if the process improves — it is a living document.*
