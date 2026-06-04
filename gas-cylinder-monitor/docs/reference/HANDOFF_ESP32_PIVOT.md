# HANDOFF — ESP32-C3 Architecture Pivot
# Gas Cylinder Weight Monitor — Major Design Change
# Created: 2026-06-02
# Purpose: Paste into the next chat session to brainstorm the new architecture from full context.

---

## 0. How to use this document

This is a brainstorming handoff, NOT an implementation handoff. The next session is for
DESIGNING the new architecture — possibilities, transports, tradeoffs, tech choices — before
any code. Working mode still applies: design/plan/brainstorm in Claude chat; implementation
goes to Claude Code CLI only, in verified chunks.

---

## 1. THE PIVOT — what changed today (2026-06-02 boss meeting)

### Old architecture (everything built so far assumed this)
```
Load cell -> HX711 -> Arduino UNO Q STM32U585 MCU (reads weight, bit-bang)
                       |
                       Bridge RPC to QRB2210 Linux side -> Python -> dashboard
```
The UNO Q's own MCU read the load cell directly. Single board, single device.

### New proposed architecture (what we now brainstorm)
```
Load cell -> HX711 -> ESP32-C3 (NEW MCU role: reads weight from HX711)
                        |
                        (transport TBD) --> Arduino UNO Q (now a HUB)
                                              |
                                              1. store data on-device for LOCAL inference
                                                 AND / OR send data to CLOUD
                                              2. send insights + data to a COMPANION APP
                                                 connected to the UNO Q
```

### What this means structurally
- The ESP32-C3 becomes the sensor node / edge MCU. It owns the HX711.
- The UNO Q stops being the sensor reader and becomes the **aggregation + intelligence + connectivity hub**.
- A NEW transport link is required between ESP32-C3 and UNO Q — this did not exist before and is the
  central new design question.
- The UNO Q's QRB2210 Linux side (Debian, Python, BLE/WiFi) becomes the workhorse: storage,
  inference, cloud sync, companion-app serving.

### Open ambiguities to resolve in next session (flagged, NOT yet decided)
- Is the ESP32-C3 ONE sensor node or the first of MANY (multi-cylinder / fleet)?
- Does the UNO Q's own STM32 MCU now do anything, or is it idle in this design?
- "Companion app" — phone app? web app? Native? Which transport to it (BLE? WiFi/LAN? cloud round-trip)?
- Cloud: which provider, what data model, online-only or store-and-forward?
- Local vs cloud inference split — what runs where?

---

## 2. WHAT CARRIES OVER (proven work that is NOT wasted)

All of this is MCU-agnostic and ports from STM32U585 to ESP32-C3. The physics, the
calibration math, and the experiment findings do not care which MCU clocks the HX711.

### HX711 read logic (ports directly, pin numbers change)
- Raw bit-bang, NO external library. 24-bit read + 25th gain pulse (gain 128, channel A).
- Three corrupt-value filters mandatory: LONG_MIN, -1, 0x7FFFFF.
- Sign extension: if (value & 0x800000) value |= 0xFF000000.
- wait_ready: poll DOUT LOW before clocking; timeout returns LONG_MIN.
- noInterrupts() around the 24-bit clocking loop; delayMicroseconds(1) on each edge.
- NOTE: pin assignments (was DT=D7/SCK=D6 on STM32) must be re-chosen for ESP32-C3 GPIO.
  The "DT=D7/SCK=D6 only" rule was an STM32U585 timer-conflict constraint — it does NOT
  apply to ESP32-C3. New pins must be validated on ESP32-C3.
- HX711 powered at 5V (not 3.3V) for full-scale excitation. ESP32-C3 is a 3.3V part —
  CRITICAL new concern: HX711 DOUT/SCK logic levels vs ESP32-C3 3.3V GPIO must be checked.
  On the UNO Q, D7/D6 were 5V-tolerant. ESP32-C3 GPIO tolerance must be verified — possible
  level-shifting needed. FLAG THIS EARLY.

### Calibration architecture (ports fully — it's math, not hardware)
- cal_factor NEVER hardcoded — computed on boot or from config.
- Multi-point cal_factor (slope of a line fit) preferred over single-point.
- tare is setup-time + every cylinder replacement, read from config on normal boot.
- Indian LPG: 14,200g net gas fixed by regulation; brands vary ~700g in empty weight.
- cal_factor varies ~6.5% from temperature / mechanical creep / mounting (~923g error on full).
- 30-day self-derived cal_factor via trend-line extrapolation (immune to cylinder variation);
  trend slope = personalised burn rate.
- Bootstrap-then-refine: brand-average day 0, precise cal from first full cycle.

### Noise / detection findings (port fully)
- Self-characterisation per boot is mandatory — noise STD varies run to run on SAME hardware.
- N=200 for experiments, N=50 for production boot (10% STD error, 2x detection margin).
- Sliding-window delta detector (two windows, 4-sigma) beats single-sample thresholding.
- Averaged-plateau capture (N samples) cuts effective noise by sqrt(N) — used to beat the
  jumper-wire noise floor (see Section 4).

### Module / engineering principles (port fully)
- Modular result-struct contract: every module returns {value, quality(GOOD/DEGRADED/FAILED), diagnosis}.
- Modules receive raw readings injected by orchestrator — never call HX711 directly. Enables
  multi-cell scaling AND now enables swapping the MCU underneath cleanly.
- float only (this was an STM32U585 double-is-broken bug — RE-VERIFY on ESP32-C3, double may
  be fine there, but float is a safe default).
- Non-blocking, one-sample-per-loop, millis() pacing at top of loop.
- Adaptive retry (2s/10s/30s/60s backoff) + degraded operation, never halt in production.

### Data-intelligence roadmap (now MORE relevant — UNO Q is the hub)
- v0.3 statistical: trend line, personalised burn rate, precise cal_factor.
- v1.0 patterns: session counts, peak hours, anomaly detection, confidence intervals.
- v2.0 ML: TFLite on QRB2210 4x Cortex-A53, Kalman filter, predictive refill.
- v3.0 agent: LLM, natural-language queries, gas-ordering API, multi-cylinder fleet.
- Rule: store everything raw, never discard history.

---

## 3. THE NEW DESIGN SPACE (what to brainstorm next session)

### A. ESP32-C3 -> UNO Q transport (the central question)
Candidate links, each with tradeoffs to weigh:
- BLE: ESP32-C3 advertises/GATT, UNO Q QRB2210 BlueZ/D-Bus on Linux side scans/connects.
  (UNO Q BLE lives on Linux MPU via BlueZ — relevant prior experience: motion-sensor-webui BLE work,
  BLE scan must use 'le' transport only, auto transport kills the QRB2210 BT adapter — hardware bug.)
- WiFi / LAN: both on a network; MQTT, HTTP, WebSocket, or raw TCP/UDP. ESP32-C3 has WiFi.
- Wired serial/UART: ESP32-C3 TX/RX to UNO Q. Simplest, but tethers the two physically —
  may defeat the purpose of a separate sensor node.
- ESP-NOW: ESP32-to-ESP32 low-power protocol — only if UNO Q side can speak it (it can't natively;
  would need an ESP companion). Probably out, but worth a mention.

Decision drivers: range, power (is the ESP32-C3 battery powered at the cylinder?), reliability,
duty cycle (6-hour snapshots vs continuous), number of nodes, security/pairing.

### B. UNO Q as hub — responsibilities to design
- Ingest from ESP32-C3 (the transport above).
- Local storage (dbstorage brick? sqlite? flat files?) — "store everything raw" rule.
- Local inference (the v0.3+ intelligence stack runs here on Linux/Python/TFLite).
- Cloud sync — store-and-forward vs online-only; provider TBD; data model TBD.
- Companion app serving — the second new transport (UNO Q <-> phone/web app).

### C. Companion app (new surface)
- Phone app vs web app vs PWA.
- Transport to it: BLE direct? LAN web UI (WebUI brick + Socket.IO — prior experience exists)?
  Cloud round-trip?
- What it shows: live weight, days-remaining, usage patterns, refill alerts, ordering.

### D. Where does inference run — edge vs hub vs cloud
- ESP32-C3: too small for real ML; can do thresholding / event detection / pre-filtering.
- UNO Q QRB2210: TFLite, statistical models, the real local inference.
- Cloud: heavy training, fleet aggregation, LLM agent.
- Design the split deliberately.

### E. Duty cycle / power
- Old design assumed 6-hour snapshot cycles. Does the ESP32-C3 sleep between reads?
  Battery vs mains at the cylinder? This drives the transport choice heavily.

---

## 4. CURRENT HARDWARE REALITY (carry forward — unresolved)

- Active board this session: AQ3 at 192.168.1.161 (UNO Q). Collaborator has AQ1 + an ESP32-C3
  already (per project memory) — so the ESP32-C3 hardware may already be on hand.
- Load cell: YZC-161A 20kg, GISLAB HX711 clone module.
- OPEN PROBLEM — analog wiring noise: HX711-to-everything is on JUMPER WIRES. Empty-scale
  per-sample noise drifted 100 -> 587 raw across runs (~1g to ~5.6g), NOT stable, trending up.
  Tare DC is rock-solid (spread 41-148, EXCELLENT) so the cell is fine — this is signal-path
  contact noise on the millivolt analog hop (load cell -> HX711), amplified 128x.
  RECOMMENDATION CARRIED FORWARD: harden those 4 analog connections (solder / screw terminal,
  short leads) before trusting fine measurements. This problem MOVES WITH the HX711 to the
  ESP32-C3 — same wiring discipline applies on the new MCU.

---

## 5. WHERE EXPERIMENT 005 WAS LEFT (now likely deprioritised by the pivot)

Experiment 005 = calibration linearity (does cal_factor hold across the weight range; build a
multi-point cal_factor; measure low-range linearity + hysteresis). Status at pivot:
- Phase A (tare + N=200 noise + derived stability band): WORKING on UNO Q STM32.
- Phase B (block staircase, averaged-plateau capture, N=100): code deployed and RUNNING; the
  staircase thresholds now print (settle_band/step_thresh). Live-status-feedback patch was being
  added (so the user can see SETTLING / STABLE-READY / MOVE DETECTED / CAPTURED) when the pivot
  landed. Last blocker before pivot: Claude Code CLI threw a session-state error
  (previous_message_id 400) — fix is /clear or restart the CLI session.
- Phases C (coarse ladder 82->481g) and D (line fit -> cal_factor + residuals): NOT built.

IMPLICATION OF PIVOT: 005's findings (linearity, cal_factor, hysteresis) are still wanted and
still port to the ESP32-C3 — but the experiment now needs to be REDONE (or finished) on the
ESP32-C3 + HX711, not the UNO Q STM32, since that's the new sensor node. Decide in next session
whether to finish 005 on the UNO Q first (cheap, validates the method) or restart it on ESP32-C3.

Test weights on hand: six identical 10g blocks, 82g adapter, 112g container (powder), 227g
speaker. (158g reference is GONE.) Kitchen-scale masses are +-1-2g; the identical 10g blocks
enable reference-free linearity testing.

---

## 6. WORKING MODE (unchanged — reiterate to next session)

- First principles: WHY before HOW, nothing floats in isolation, no "it just works".
- Small -> verify -> compound. One chunk at a time, gated by understanding. Never firehose.
- Claude chat = design/plan/brainstorm/understand. Claude Code CLI = implementation only.
  Claude generates precise CLI prompts; never raw code dumped in chat.
- No hardcoding: derive paths/names dynamically; constants named, never buried; cal_factor
  and thresholds always derived, never hardcoded.
- float-only and non-blocking patterns in MCU sketches (re-verify float necessity on ESP32-C3).
- Visuals welcome when they clarify faster than text.
- Maintain proven / derived / reasoned / pending distinction on every documented value.

---

## 7. SUGGESTED OPENING FOR NEXT SESSION

"We're pivoting the gas monitor: HX711 moves to an ESP32-C3 sensor node, UNO Q becomes the
storage/inference/cloud/companion-app hub. I want to brainstorm the full design space —
especially the ESP32-C3 to UNO Q transport — before any implementation. Start by helping me
map the transport options and their tradeoffs against our constraints (duty cycle, power,
range, node count, security)."

First thing worth nailing down: the ESP32-C3 <-> UNO Q transport, because it cascades into
power, app design, and inference-location decisions. Second: confirm the open ambiguities in
Section 1 (single node vs fleet, companion-app type, cloud provider/model).
