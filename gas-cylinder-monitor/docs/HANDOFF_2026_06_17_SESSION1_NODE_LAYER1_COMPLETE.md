# SESSION HANDOFF — 2026-06-17 SESSION1
# Gas Cylinder Monitor V1 — Session record
# Node Layer 1 complete: 1C timing + 1D journal

---

## Session goal
Complete Node Layer 1: timing instrumentation (1C) and structured event journal (1D).

## Hardware used
- ESP32-C3 SuperMini — sensor node
- GISLAB HX711 — 3V3 VCC, GPIO4=DT, GPIO3=SCK
- 3× YZC-161A 20kg in parallel — direct soldered wiring
- Arduino UNO Q AQ3 — hub (hub skeleton only, no gas logic)

## Wiring locked
ESP32-C3 → HX711: GPIO4=DT, GPIO3=SCK, 3V3=VDD, GND=GND
Load cells: all red→E+, all black→E−, all green→A+, all white→A−

## What was built
| Item | File | Status |
|---|---|---|
| 1C timing | gas_monitor_v1.ino | phase_start_ms global, durations in seconds |
| 1D journal | journal.h / journal.cpp | Service module, 7 event types, boot counter |

## Real hardware outputs
Boot timing verified:
SETTLE=2.1s, TARE=21.1s, NOISE=20.1s, CAL=variable, Total~60s

Journal verified:
#0001 t=0.2 boot=1 [BOOT] event=START fw=1.0
#0006 t=64.3 boot=1 [BOOT] event=BOOT_COMPLETE total_s=64.3 cal=35.9664 sigma=3.65
#0007 t=64.4 boot=1 [RUN] event=QUALITY_CHANGE from=NONE to=DEGRADED
#0008 t=64.4 boot=1 [HB] event=HEARTBEAT grams=0.0 quality=DEGRADED uptime=64.4
#0009 t=66.3 boot=1 [RUN] event=WEIGHT_EVENT type=PLACED grams=406.3 delta=406.3

## Gate result
Node Layer 1: COMPLETE. 1A + 1B + 1C + 1D all verified on hardware.

## Known TODOs (deferred)
- TODO 1B-stuck: tare_variance_raw=0.0f — fix when TareResult struct updated
- TODO 1B-persistence: prev values not persisted — fix later

## Next session
3E-006B — minimum detectable removal experiment.
What is the smallest weight removal the system reliably detects?
Needs water container + measuring cup.
Design in chat first, then implement via Claude Code CLI.
