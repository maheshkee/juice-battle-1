---
# WORKING CONTRACT — All Arduino UNO Q Projects
# Applies to: home-hub, experiments, and every future app on this board

## The One Rule

PLANNING / RESEARCH / BRAINSTORMING / LEARNING → Claude.ai chat only.
CODE WRITING / IMPLEMENTATION / FILE EDITING → Claude Code CLI only.

## What this means in practice

Claude.ai chat session:
- Understands the problem
- Derives requirements from first principles
- Designs architecture and data flow
- Decides experiment structure
- Produces a precise CLI prompt

Claude Code CLI session:
- Reads CLAUDE.md and relevant SKILL.md before touching anything
- Receives the design prompt from chat
- Writes all code, creates all files, runs all commands
- Updates CLAUDE.md at end of session with what changed

## Why this rule exists

Chat has the full reasoning context and project knowledge files.
CLI has direct board access and file system.
Mixing them produces inconsistent code that ignores architecture decisions.

## Every CLI session checklist

1. Read ~/ArduinoApps/home-hub/CLAUDE.md
2. Read relevant SKILL.md for the task
3. Read SENSOR_CHARACTERISATION.md if touching HX711 or weight
4. Execute the design prompt from chat — nothing more, nothing less
5. Update CLAUDE.md: what was built, what was tested, what is the current state

## Every new project checklist

1. Create APP_NAME/CLAUDE.md from the start
2. Reference ~/ArduinoApps/WORKING_CONTRACT.md in it
3. Never hardcode: paths, usernames, hostnames, thresholds, cal factors
4. Never write code without a design prompt from chat
---
