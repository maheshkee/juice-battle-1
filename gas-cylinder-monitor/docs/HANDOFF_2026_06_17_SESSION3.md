# SESSION HANDOFF — 2026-06-17 SESSION3
# Gas Cylinder Monitor V1
# Experiment: 3E-007B false positive rate + disturbance analysis

---

## Session goal
Run 3E-007B: measure the false positive rate of the delay-line weight event
detector on a static load. Understand disturbance behaviour.

---

## Experiment results — 3E-007B (false positive rate)

sigma: 5.12g | threshold: 4 × 5.12 = 20.5g
Observation window: 38.4 minutes (2304 seconds) on static load

| Metric | Target | Result | Status |
|---|---|---|---|
| False WEIGHT_EVENT triggers | < 2/hr | 0 | ✅ PASS |
| Slow drift immunity | Must not trigger | 190g drift — zero events | ✅ PASS |
| Observation duration | > 30 min | 38.4 min | ✅ |

Gate: 3E-007B COMPLETE. Delay-line detector validated. PASS ✅

---

## Disturbance analysis

Moving the platform base (with or without cylinder) shifts the zero reference silently.

**Case A — cylinder removed, platform moved, cylinder replaced:**
- Hub can detect: WEIGHT_EVENT type=REMOVED ∧ grams≈0 → hub knows platform is empty
- Hub can command retare: send RETARE command to node via BLE write characteristic
- Node executes new STATE_TARE, confirms via next heartbeat ≈ 0g
- Requires: new writable BLE GATT characteristic on node → HUB-001

**Case B — platform moved while cylinder present:**
- No WEIGHT_EVENT fires — weight unchanged, zero reference shifted
- Hub detects: sudden heartbeat grams step with no WEIGHT_EVENT in window
- Flag DISTURBANCE, mark readings UNRELIABLE until retare confirmed
- Requires: burn rate estimate (Group 5 prerequisite) → HUB-002

---

## HUB-001 design (new backlog item)

Trigger: hub receives WEIGHT_EVENT type=REMOVED with grams≈0.
Flow: monitor heartbeats → when |grams[n]−grams[n−1]| < 2σ for 2 consecutive
      heartbeats → platform stable → send RETARE command to node → confirm.
Node requirement: writable BLE GATT characteristic (separate UUID from notify char).
Command: RETARE (0x01). Format TBD in chat.
Priority: high — required for correct operation after any cylinder change.

---

## HUB-002 design (new backlog item)

Trigger: consecutive heartbeat grams step > 5× expected_consumption_in_interval,
         AND no WEIGHT_EVENT in that window.
Action: flag DISTURBANCE, mark readings UNRELIABLE until next retare confirmed.
Prerequisite: Group 5 burn rate estimate required.
Priority: medium — not blocking V1.

---

## Drift observation

190g peak-to-trough over 38 minutes on static load.
This is real slow drift — not noise. Candidates: thermal or mechanical creep.
Must be characterised in 3E-009 (24hr long-run stability soak).
Will corrupt gas% readings over multi-hour cycles if not corrected.
Do NOT interpret raw heartbeat trend as gas consumption without drift correction.

---

## Files changed this session
None — observation and analysis session only.
Node sketch unchanged. Hub unchanged.

---

## Next
3E-008 — temperature drift characterisation. Design in chat first.
