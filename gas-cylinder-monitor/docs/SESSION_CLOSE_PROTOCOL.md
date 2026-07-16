# Session close protocol
# How every session ends. Follow this sequence without skipping steps.
# Version 2 — rewritten 2026-07-02, Session 61.
# Supersedes the 2026-06-04 version. That version is retained in git history only.

---

## Why this document exists

Every session produces knowledge, measured outputs, and code. If not saved correctly,
context is lost between sessions and the next chat starts blind. This protocol ensures
nothing is lost and every document stays current and trustworthy.

**Why version 2 exists:** the original protocol's own documents — `CLAUDE.md`,
`SESSIONS.md`, `PROJECT_CONTEXT.md`, `RESEARCH.md` — drifted silently stale between
early June and July, undetected until a full-week audit on 2026-07-02. Two specific
failures caused this: (1) `PROJECT_CONTEXT.md` and `RESEARCH.md` stopped being updated
with no one deciding to stop, and (2) nothing ever re-checked whether older sections of
any living document were still true. Version 2 closes both gaps directly — see
"Master reference update discipline" below.

---

## Document roles — one job each, no overlap

Overlapping documents is the root failure mode this version is designed against. Two
documents saying the same thing WILL drift apart the moment one gets updated and the
other doesn't. Each document below has a job the others do not do.

| Document | Job | Owner | Updated by |
|---|---|---|---|
| `CLAUDE.md` | Rules, non-negotiables, read-this-first | CLI | Every session, if rules/context changed |
| `PROJECT_CONTEXT.md` | One-screen orientation: session #, one-line state, pointer to the master reference section that's authoritative, single next action | CLI | Every session |
| `SESSIONS.md` | Permanent append-only log of real hardware outputs per session | CLI | Every session |
| `LEARNINGS_AND_INSIGHTS.md` | Permanent append-only WHY — root causes, derivations, rules with reasoning | CLI | Every session that produces insight |
| `RESEARCH.md` | Pure hardware-verified facts, table form, no narrative — pin assignments, voltage behaviour, cal_factor ranges, toolchain versions | CLI | Only when new hardware facts are confirmed on real hardware this session |
| Master reference (`HANDOFF_..._MASTER_REFERENCE.md`) | The single living source of truth — architecture, current state, all fixes, experiment program, build backlog | Claude (chat) | Every session — targeted sections only, see below |
| `HANDOFF_YYYY_MM_DD_FINAL_[N].md` | Short next-chat entry point — one line of state + pointer to master reference | Claude (chat) | Every session — new file, N increments, never overwrite |

No separate per-session `HANDOFF_SESSIONN_DESCRIPTION.md` file anymore. That role is
now served by a targeted master reference update plus its changelog line — one document
instead of two saying almost the same thing.

---

## Master reference update discipline

This is new in version 2, added specifically because "update it every session" was
identified as a plausible next staleness vector.

1. **Targeted section edits only.** Touch only the Parts actually affected by this
   session. If architecture didn't change, Part 1 doesn't get touched. If the fix
   status table changed, only that table gets touched.
2. **One-line changelog at the top of the document**, above Part 1: session number,
   date, and a one-line summary of what moved. Never delete old changelog lines —
   append above the previous entry, most recent first. This gives anyone opening the
   doc a diff-free view of what changed without reading all 600+ lines.
3. **Full audit, not full rewrite, every 5 sessions or at a phase gate** — whichever
   comes first (V1 ship, Phase 2 start, or session count, whichever arrives first).
   Read the entire document end-to-end. Verify every claim still holds against live
   board state. Rewrite only the sections found stale. Log the audit itself as a
   changelog line ("Session NN: full audit, no drift found" or "...corrected Parts
   X, Y").

---

## End-of-session sequence — follow in order

### Step 1 — Claude Code CLI: fact-gathering only
CLI runs read-only commands to establish ground truth for this session's close:
`git log --oneline`, current `config.json`, relevant file listings, line counts,
service status. CLI does **not** author any handoff, session-summary, or master
reference content — it has no visibility into the session's design conversation or
reasoning. It gathers facts; Claude (chat) writes the narrative.

### Step 2 — CLI updates `CLAUDE.md`
Current position, what completed this session (gate result), what's next, any newly
locked values, any new rules discovered.

### Step 3 — CLI updates `PROJECT_CONTEXT.md`
Session number, one-line current state, pointer to the master reference part that's
authoritative right now, single next action. Fifteen lines max — this is a glance,
not a document.

### Step 4 — CLI appends `SESSIONS.md`
New session block at the bottom. Never overwrite. Session number, date, goal, real
measured outputs, gate result, what was built.

### Step 5 — CLI appends `LEARNINGS_AND_INSIGHTS.md`
New `L-XXX` entries, incrementing from the last entry (check the last entry number
before writing — do not guess). WHY explained from first principles, verified against
real measurement where applicable.

### Step 6 — CLI appends `RESEARCH.md` — only if applicable
Only if new hardware-specific facts were confirmed on real hardware this session.
Skip this step entirely on sessions with no new hardware findings — do not pad it.

### Step 7 — Claude (chat) updates the master reference
Per "Master reference update discipline" above — targeted sections plus one changelog
line. Full audit only on the 5-session/phase-gate cadence.

### Step 8 — Claude (chat) writes `HANDOFF_YYYY_MM_DD_FINAL_[N].md`
New file. N increments if multiple finals land the same day. Never overwrite a prior
FINAL. Contents: one-line current position, pointer to master reference, first five
actions for next session, anything DO-NOT-DO critical for immediate safety
(e.g. don't tare with weight on platform).

### Step 9 — Git commit and push
Commit message format (no author names, no tool names):
```
First line: type(scope): short description of what changed
Body: bullet list of exactly what was added/updated
Types: feat / fix / docs / refactor
Scope: experiment name or area (e.g. hub, node, docs, 3E-009)
```
Commands:
```bash
git add -A
git commit -m "your message"
git push
```
If push rejected (collaborator pushed): `git pull --rebase && git push`

### Step 10 — SCP the chat-authored documents to AQ3
Only the master reference and the new FINAL need transferring — everything else in
Steps 2–6 was written directly on the board by the CLI already.
```bash
scp HANDOFF_..._MASTER_REFERENCE.md HANDOFF_..._FINAL_[N].md \
    arduino@AQ3:~/ArduinoApps/gas-cylinder-monitor/docs/
```

### Step 11 — Verify `DISABLE_AUTOUPDATER=1`
```bash
grep DISABLE_AUTOUPDATER ~/.bashrc
```
If missing, add it back before ending the session. Claude Code CLI pinned at
v2.1.129 — v2.1.131+ causes a Bus error on Cortex-A53.

### Step 12 — Claude (chat) generates the next-session opening prompt
Short prompt for the next chat, referencing the new FINAL file by name and stating
the one-line current position.

---

## Verification before considering the close complete

```bash
ls docs/HANDOFF_*_FINAL_*.md          # new FINAL exists, correctly numbered
tail -5 docs/SESSIONS.md              # new session block visible
tail -5 docs/LEARNINGS_AND_INSIGHTS.md # new L-XXX visible
head -20 CLAUDE.md                    # current position updated
cat docs/PROJECT_CONTEXT.md           # matches this session's actual end state
git log --oneline -3                  # commit landed
```
If any check fails, fix before ending the session — not next time.

---

## What never goes in any document

- Usernames or hostnames hardcoded. Use `arduino@AQ3` (hostname via mDNS/Avahi) —
  never a static IP. IPs change; the hostname does not.
- Tool names in git commit messages
- Estimated or assumed values presented as verified — always mark DERIVED vs VERIFIED
- Values carried forward from a prior hardware platform without a re-derivation note
- Architecture decisions mixed into `LEARNINGS_AND_INSIGHTS.md` — that belongs in the
  master reference's architecture section
- The same fact maintained in two documents — pick the one document whose job it is

---

## Note on relocated content

The original protocol's "Modular sketch principle" section (orchestrator/module
contract rules for firmware structure) has been removed from this document. It is a
code-architecture rule, not a session-close procedure, and belongs in the master
reference's architecture section instead. If it isn't there yet, move it — don't
duplicate it here.

---

## Key principle, restated

Real measured numbers belong in `SESSIONS.md`.
The WHY behind them belongs in `LEARNINGS_AND_INSIGHTS.md`.
Pure hardware facts belong in `RESEARCH.md`.
The one-screen glance belongs in `PROJECT_CONTEXT.md`.
Everything else current belongs in the master reference.
The next session's entry point belongs in `HANDOFF_FINAL`.
Never mix these. Each document has exactly one job.

---

*Version 2. Rewritten 2026-07-02, Session 61, following a full-week audit that found
`PROJECT_CONTEXT.md` and `RESEARCH.md` silently abandoned and the master reference
concept undocumented. Update this file if the process improves — it is a living
document, but changes to it should themselves follow Step 7's discipline: targeted
edits with a reason, not a silent rewrite.*
