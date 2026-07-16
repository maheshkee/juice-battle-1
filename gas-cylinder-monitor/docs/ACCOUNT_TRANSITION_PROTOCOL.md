# ACCOUNT_TRANSITION_PROTOCOL.md
# How work moves from this Claude account to the new one, given a split timeline.
# Written 1 Jul 2026. Companion to SESSION_CLOSE_PROTOCOL.md — does not replace it.

---

## Why this document exists

The migration isn't a single cutover — it's split across a timeline with a dead
zone in the middle:

```
Now ──── 7-day window ──── new account goes dormant ──── rest of July ──── 1 Aug
(seed         (new account            (new account          (this account    (new account
 new           accessible,             paused, no             stays the        wakes up,
 account)      not yet Pro)            access at all)         working one)     full Pro)
```

Working here through July and seeding the new account within its 7-day window
are two independent tracks. Confusing them — e.g. trying to work daily inside
the new account before Pro activates, or forgetting the new account goes dark
after day 7 — is the actual risk here, more than losing any specific file.

---

## The three phases

### Phase 1 — right now, inside the 7-day window

Goal: get the new account fully seeded with everything that exists as of today,
before it pauses. This is a one-time push, not a recurring task.

Checklist:
- [ ] Confirm the new account's plan tier during these 7 days (Skills and full
      Project knowledge capacity may require Pro — if the 7-day window runs on
      a lower tier, some steps below may need to wait for August)
- [ ] Download all 5 migration kit files to laptop (if not already done)
- [ ] New account: create the new Project
- [ ] New account: Settings → Capabilities → enable Code execution and file
      creation → upload both skill zips → toggle on
- [ ] New account: home screen → "Import memory to Claude" → paste
      `MEMORY_EXPORT_FOR_NEW_ACCOUNT.md`
- [ ] New account: Project → custom instructions → paste the philosophy/
      working-mode block
- [ ] New account: upload the unzipped `project_knowledge_backup.zip` contents
      to the new Project's knowledge
- [ ] New account: open one test chat, confirm memory + knowledge landed
      correctly, then leave it alone until August

Once this checklist is done, Phase 1 is closed. Nothing else happens in the
new account until August — it will be inaccessible anyway.

### Phase 2 — rest of July, working here as normal

Goal: don't lose the one category of file that never makes it into git —
without turning this into a daily export chore.

**Two lines added to SESSION_CLOSE_PROTOCOL.md, nothing else changes:**

> 1. Whenever a session produces a Claude-only artifact (a `.docx` write-up,
>    an `.html` mockup, a `.png` diagram, or a loose text snippet added to
>    Project knowledge) — download it and commit it into
>    `docs/claude_artifacts/` in that same session's commit.
> 2. Whenever a session involves substantial design/decision discussion (not
>    just routine CLI work) — export the full chat transcript as a `.md` file
>    and save it alongside the handoff docs. This closes the fact that Claude
>    has no native chat-history import between accounts — a manually exported
>    transcript is the only thing that actually carries full conversational
>    reasoning forward, not just the distilled conclusions.

Why these are the only new habits needed: memory content (philosophy, working
rules, preferences) barely changes day to day, and a project-knowledge zip is
regenerable in one shot at any moment — daily snapshots of either would be
pure redundant effort. The `.docx`/`.html`/`.png` layer and full transcripts
are the only things genuinely lost if not captured, because they're the only
things that live nowhere except this Claude account.

Everything else about July stays exactly as documented in
SESSION_CLOSE_PROTOCOL.md — CLAUDE.md, SESSIONS.md, LEARNINGS_AND_INSIGHTS.md,
HANDOFF files, git commits, unchanged.

**One operational rule, discovered the hard way during Phase 1 seeding:**
never run live, hands-on AQ3 verification or control commands (tare, restart,
launch) from two chats at once, even across two accounts. Pick one chat as
the driver for any given piece of live work. Cross-referencing documents
between chats is fine; issuing commands to the same real hardware from two
places at once is how a stale assumption in one chat silently contradicts
real state changed by the other.

### Phase 3 — 1 August, new account reactivates

Goal: top up the new account with July's delta — not a from-scratch migration,
since Phase 1 already covers everything through 1 Jul.

Steps:
1. Ask for the migration kit to be regenerated, scoped to "July's delta only"
2. Updated memory export — only what changed since 1 Jul (new
   projects/decisions/preferences, if any)
3. Fresh project-knowledge zip — only new or changed files since 1 Jul
   (the `docs/claude_artifacts/` folder from Phase 2 makes this a git `diff`,
   not a guessing exercise)
4. Re-run the same import/upload steps as Phase 1, applied to the delta only
5. From this point, the new account is the sole working account going forward

---

## What never needs repeating

- Nothing on AQ3/AQ2 is affected by any of this at any phase — git repo,
  running hub/node code, SQLite data, all untouched regardless of which
  Claude account is talking to them
- SESSION_CLOSE_PROTOCOL.md's existing steps (CLAUDE.md, SESSIONS.md,
  LEARNINGS_AND_INSIGHTS.md, HANDOFF_FINAL, git commit) do not change in any
  phase — this document only adds the one artifact-commit line in Phase 2

---

*This protocol should be committed to git alongside SESSION_CLOSE_PROTOCOL.md
so it survives independently of any single chat or account.*
