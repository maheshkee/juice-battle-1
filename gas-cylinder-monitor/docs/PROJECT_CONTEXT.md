# PROJECT_CONTEXT.md — Gas Cylinder Monitor
# Updated: 2026-07-03 (Session 62)
# One-screen glance only. Not a copy of other documents.

---

Session: 62 (2026-07-02 evening – 2026-07-03)

State: Session 62 complete. 3E-009 attempt 3 running since 2026-07-03 16:07:59 IST
       (node boot=47, reset=POWERON). 3-night unattended run — result to be evaluated
       at Session 63 start.

Key corrections from Session 62:
- Fix 2 (WiFi power-save) proven durable across hard power-cycle via NM profile +
  dispatcher script; setup.sh patched for zero-hardcode auto-apply.
- G5 Analytics: burn_rate + days_remaining CONFIRMED LIVE in production logs
  (earlier "not built" finding was wrong).
- health.cpp stuck-check: confirmed non-functional since inception (fix specified,
  not flashed — pending variance data from attempt 3).

Authoritative reference: docs/SESSIONS.md Session 62 block

Next action: Evaluate attempt 3 results at Session 63 start, then implement
             config.json atomic writes + UNINSTALLED redesign.
