# HARDWARE MANIFEST — Juice Battle
# Status: current as of 2026-08-20. Replaces the Phase 0 pre-hardware-arrival
# stub — all values below are VERIFIED on real hardware unless marked DERIVED.

All values must be marked: VERIFIED (tested on real hardware) or DERIVED
(calculated/inferred). Never carry values forward without re-verification.

---

## Unit inventory

| Component | Qty | Status |
|---|---|---|
| Arduino UNO Q | 1 | Deployed — hub, hostname `AQ3`, IP `192.168.88.25` |
| ESP32-C3 SuperMini | 2 | Deployed — JB-0, JB-1 (JB-1 chip physically replaced 2026-08-13) |
| CZL601 load cell | 2 | Deployed — 40kg rated, single-point |
| ADS1232 ADC board | 2 | Deployed — TI ADS1232, 24-bit, differential |

---

## ADS1232 — VERIFIED specs

| Parameter | Value | Source |
|---|---|---|
| Resolution | 24-bit | VERIFIED |
| Interface | Bit-bang, SCLK/DOUT shared with DRDY | VERIFIED |
| Data rate | 10 SPS (`SPEED` pin → GND) | VERIFIED |
| Gain | 128 (hardware-set on WCMCU breakout) | VERIFIED |
| DRDY behavior | DOUT goes LOW when new data ready | VERIFIED |
| Settling pulse | One extra SCLK HIGH/LOW after the 24th data bit is **mandatory** — without it, the next read catches DOUT mid-transition, reads all-1s, corrupts noise calc (σ balloons to ~800g) | VERIFIED, S002 |
| GPIO timing | `delayMicroseconds(2)` on every edge; `(1)` is at the edge of reliability on ESP32-C3 @160MHz | VERIFIED |
| Read integrity | `noInterrupts()`/`interrupts()` must wrap the full 24-bit read — BLE/WiFi handlers corrupt timing otherwise | VERIFIED |

### Pinout (ESP32-C3 → ADS1232) — VERIFIED, both nodes
| Signal | ESP32-C3 GPIO | ADS1232 Pin | Note |
|---|---|---|---|
| SCLK | GPIO4 | SCLK | Clock output |
| DOUT | GPIO5 | DOUT/DRDY | Data + ready signal |
| PDWN | GPIO6 | PDWN | Power down (HIGH=active) |
| A0 | GPIO7 | A0 | Channel select (LOW=ch1) |
| GND | GND | SPEED | 10 SPS mode |
| 5V | 5V | REFP | Reference voltage |
| CLKIN | — | GND | Mandatory tie |

### Signal polarity — VERIFIED but with an open question as of 2026-08-20
`ads1232_read_raw()` (`firmware/node/ads1232.cpp`) hardcodes `return -data;`
to compensate for green/white excitation wires being physically swapped at
ADS1232 INNA+/INNA− — documented since the original S003 hardware bring-up.
This negation is shared identically by both nodes (no per-node branching).
JB-1's replacement chip (fitted 2026-08-13) measures a very different
counts/gram ratio (~98 vs JB-0's ~54), which is consistent with — but does
not conclusively prove — different native ADC polarity between the two
physical chips. **Whether the shared negation is still correct for both
nodes today is not resolved.** See `RESEARCH.md` and root `CLAUDE.md` for
the live status of this investigation. The physical wire swap has
deliberately never been done (`docs/BACKLOG.md` D08) specifically to avoid
compounding an already-uncertain polarity chain — do not swap wires without
first re-reading that backlog item's reasoning.

---

## CZL601 Load Cell — VERIFIED

| Parameter | Value | Source |
|---|---|---|
| Type | Single-point, 40kg rated | VERIFIED |
| Wires | Red=E+, Black=E−, White=S+, Green=S− (S+/S− are the pair affected by the polarity note above) | VERIFIED |
| Nonlinearity | ~1.2% across 0–5000g range on JB-0's original chip (S003) — corrected via 3-point piecewise calibration, not assumed linear | VERIFIED |

---

## ESP32-C3 SuperMini — DERIVED (datasheet)

| Parameter | Value |
|---|---|
| CPU | RISC-V 32-bit, 160MHz |
| Flash | 4MB |
| GPIO voltage | 3.3V |
| Bluetooth | BLE 5.0 (NimBLE stack) |

---

## Arduino UNO Q (hub, `AQ3`) — VERIFIED

| Parameter | Value |
|---|---|
| MPU | Cortex-A53, Debian Linux |
| MCU | STM32, Zephyr + Arduino Core — **not used in this project's sensor path**; both ESP32-C3 nodes are external boards talking BLE directly to the MPU's Linux side, bypassing the UNO Q's own MCU entirely |
| MCU GPIO voltage | 3.3V |
| JCTL / JMISC voltage | **1.8V ONLY** — applying 3.3V causes permanent hardware damage. Not relevant to this project's own wiring (nothing here uses those headers), but flag before ever touching them |
| Hostname / IP | `AQ3` / `192.168.88.25` |

---

## Calibration reference points

Node calibration (`raw_zero`, `raw_500`, `raw_1000`, `raw_5000`) is stored
per-node in ESP32 NVS via `cal.cpp`'s `cal_run()` — **not duplicated in this
document**, because a static snapshot here would immediately go stale again
the way the old Phase 0 stub did. To read a node's current calibration,
either check its boot serial output (`[CAL] Loaded from NVS:`) or see
`docs/RESEARCH.md` for the last-known-verified values and their date, clearly
marked as point-in-time.

Reference weights required for a fresh calibration: **500g, 1000g, 5000g**,
placed in that order on a tared platform. See `docs/INTERFACE_CONTRACTS.md`
and `firmware/node/cal.cpp` for the full procedure — it is entirely a wired
USB serial console operation (115200 baud), not triggerable over BLE or from
the hub.
