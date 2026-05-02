# 🧠 WORKING CONTRACT — Engineering Philosophy & Execution Rules

## Purpose
This document defines how we think, design, plan, and execute work on this system.  
It is the **single source of truth for engineering behavior** across all phases.

This is not optional guidance.  
These are **rules** — deviations must be explicit and justified.

---

# 1. THINK BEFORE CODING

## Core Principle
Clarity before action. No silent assumptions.

## Rules
- State assumptions explicitly before implementation
- If uncertain → ask first, don’t guess
- If multiple interpretations exist:
  - Present all valid options
  - Do NOT silently choose one
- If a simpler approach exists → call it out
- If something is unclear:
  - Stop immediately
  - Explain what is unclear
  - Ask for clarification

---

# 2. SIMPLICITY FIRST

## Core Principle
Minimum viable solution. No speculation.

## Rules
- Solve ONLY the problem asked — nothing extra
- No speculative features
- No unnecessary abstractions
- No “future-proofing” unless explicitly required
- No configurability unless required
- No handling of impossible scenarios

## Standard
If 200 lines can be written in 50 → rewrite it

## Check
Would a senior engineer say this is overcomplicated?  
If yes → simplify

---

# 3. SURGICAL CHANGES

## Core Principle
Precision over cleanup

## Rules
- Modify ONLY what is required
- Do NOT refactor unrelated code
- Do NOT change formatting or style unnecessarily
- Match existing code style (even if imperfect)

## Cleanup Rules
- Remove ONLY:
  - Unused imports introduced by your change
  - Variables/functions made unused by your change

- Do NOT remove:
  - Pre-existing dead code
  - Unrelated logic

## Exception
If you notice issues:
- Mention them
- Do NOT fix unless asked

## Test
Every changed line must directly trace to the requirement

---

# 4. GOAL-DRIVEN EXECUTION

## Core Principle
Everything must be verifiable

## Rules
Convert vague tasks → measurable goals

Examples:
- “Fix bug” → write failing test → make it pass
- “Add validation” → define invalid inputs → test → pass
- “Refactor” → behavior must remain unchanged

## Multi-step Work
Always define a plan:

1. Step → verification  
2. Step → verification  
3. Step → verification  

---

# 5. SEPARATION OF RESPONSIBILITIES

## Core Principle
Design here. Code elsewhere.

## Rules
- This environment is for:
  - Planning
  - Architecture
  - Debugging strategy
  - Design decisions

- Code is written by:
  - CLI agents (e.g. Codex)

---

# 6. PROMPT-DRIVEN DEVELOPMENT

## Core Principle
Code quality depends on prompt quality

## Rules
- Every implementation task must be converted into:
  - A precise, structured prompt
- Prompts must include:
  - Context
  - Constraints
  - Exact task
  - Expected output format

---

# 7. STAGE-BASED DEVELOPMENT

## Core Principle
No jumping ahead. No big-bang builds.

## Rules
- Work in phases
- Each phase is divided into chunks

---

## Phase Workflow

For every chunk:

### 1. PLAN
- Define goal
- Define boundaries

### 2. DESIGN
- Architecture
- Data flow
- Responsibilities

### 3. SPECIFY
- Inputs / Outputs
- Constraints
- Tools / tech

### 4. IMPLEMENT
- Via CLI agent (prompt-driven)

### 5. VERIFY
- Define success condition
- Test outcome

---

# 8. CHUNK-BASED EXECUTION

## Core Principle
Small, verifiable units

## Rules
- Never implement large features in one shot
- Each chunk must be:
  - Clearly defined
  - Independently testable
  - Small enough to reason about

---

# 9. TESTING STRATEGY

## Core Principle
Always validate behavior

## Rules
- If hardware is available → test on device
- If not → use unit tests / simulations

---

# 10. CONTINUOUS EVOLUTION

## Core Principle
This document grows with the system

## Rules
- Add new rules when insights are discovered
- Prevent repeated mistakes by documenting them

---

# FINAL RULE

If a decision violates this contract:
- It must be explicitly stated
- It must be justified

Otherwise:
→ It is incorrect
