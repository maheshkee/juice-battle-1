# HANDOFF — 2026-07-02 · Session 61 · FINAL_1
> Load HANDOFF_2026_07_01_SESSION60_MASTER_REFERENCE.md for full project context.
> (Filename retained from creation date — this is the living master reference, updated
> in place each session per SESSION_CLOSE_PROTOCOL.md v2. Its own header confirms
> "Session 61" as the last update.)

---

## ONE-LINE STATE

Fixes 1–4 all deployed and verified. 3E-009 attempt #2 deliberately deferred — running a
2–3 attempt stability campaign before trusting a single run. UNINSTALLED/CYLINDER_ABSENT
redesign is fully designed but blocked on one product decision.

---

## FIRST ACTIONS NEXT SESSION, IN ORDER

1. **Answer this question before anything else**: for a typical cylinder removal, is the
   common case a quick lift (seconds to a minute — cleaning, moving, checking) or an
   extended absence (hours — refill, lending, swap)? This unblocks the UNINSTALLED
   redesign — it's been raised twice (2026-06-29, 2026-07-02) without an answer.
2. Verify hub `config.json` tare_raw is in sync with the node's fresh Session 61 SPIFFS
   tare (`-96218.4`) — this was not confirmed either way at Session 61 close.
3. Implement config.json atomic writes (spec fully written, Part 5 of master reference)
4. Implement the UNINSTALLED/CYLINDER_ABSENT state machine, once #1 is answered
5. Launch 3E-009 attempt #2 — first of the stability campaign, 65h run, walk away

---

## DO NOT

- Do not launch 3E-009 attempt #2 before confirming node boot is stable post-Fix-4
- Do not tare the hub while any weight is on the platform
- Do not assume G5 Analytics or G7 WebUI exist — confirmed NOT built, source-verified 2026-07-02
- Do not treat `reset=OTHER` in the node journal as a fault if it appears right after a
  fresh flash — that's the expected USB/esptool reset path, not a problem
- Do not run `claude` without confirming `DISABLE_AUTOUPDATER=1` in `~/.bashrc`
- Do not upgrade Claude Code (pinned v2.1.129 — Cortex-A53 Bus error on newer)
- Do not trust project-knowledge-mounted docs over live board state without checking —
  several were found stale by a full month this session

---

*Session 61 · Gratian Technologies · Project 13*
