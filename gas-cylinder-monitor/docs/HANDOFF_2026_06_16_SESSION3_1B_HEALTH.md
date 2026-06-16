# SESSION HANDOFF - 2026-06-16 Session 3
# Gas Cylinder Monitor V1 - 1B Load Cell Health Detection Module
# Reference document for this session's work.

---

## Session goal

Design and implement the load cell health detection module (health.h / health.cpp) and wire it into the production sketch.

---

## Gate result

PASSED - health module compiles, flashes, runs on real hardware. Runtime jump detection verified. Stuck detection firing correctly (expected false positive pending tare.h update).

---

## What was built

| File | Description |
|---|---|
| node/gas_monitor_v1/health.h | HealthResult struct + health_check() declaration (9 parameters) |
| node/gas_monitor_v1/health.cpp | Pure function implementation. 4 checks. Bitmask output. dpos pattern for diagnosis string. |
| node/gas_monitor_v1/gas_monitor_v1.ino | Updated: health.h included, health_check() wired in STATE_RUNNING, 4 new globals added |

---

## Design decisions locked this session

| Decision | Reasoning |
|---|---|
| health_check() is pure function | Orchestrator must own all state. Hidden static breaks reset-after-tare, breaks testability. |
| Orchestrator owns prev_gross_g | Health module has one job: judge. State management is orchestrator's job. |
| Sentinel = -1.0f not 0.0f | 0.0f is a valid gross weight (empty platform). -1.0f is physically impossible. |
| Diagnosis uses pipe separator | Multi-failure string reads "stuck:\|jump:1009g" not "stuck:jump:1009g" |
| DEGRADED = 1 fail, FAILED = 2+ fails | Single failure may be transient. Two simultaneous failures is a strong signal. |
| #include <cstdio> required | snprintf not available from <math.h> alone on ESP32 Arduino toolchain. |

---

## Real hardware outputs

| Measurement | Value |
|---|---|
| cal_factor this boot | 35.84 raw/g |
| sigma recomputed | 3.44g |
| Empty platform quality | DEGRADED |
| Empty platform checks | 0x0D (stuck bit clear, others set) |
| 1kg placement - jump delta | 1009g |
| 1kg placement - quality | FAILED |
| 1kg placement - checks | 0x05 (stuck + jump bits clear) |
| Steady load quality | DEGRADED (stuck only) |

---

## Known limitations carried forward

| ID | Description | Fix needed |
|---|---|---|
| TODO 1B-stuck | tare_variance_raw always 0.0f. Stuck check (bit 1) always fails. | Update TareResult struct to expose variance field. Wire in orchestrator. |
| TODO 1B-persistence | prev_cal_factor and prev_sigma_g set from current boot only. Cal drift and erratic checks skip every boot. | Read prev values from config.json at startup. Write cur values after CAL_SUCCESS. |

---

## Wiring - unchanged, locked

### ESP32-C3 → HX711

| ESP32-C3 pin | HX711 pin | Rule |
|---|---|---|
| 3V3 | VDD | NEVER 5V |
| GND | GND | |
| GPIO4 | SDO (DOUT) | INPUT_PULLUP mandatory |
| GPIO3 | SCK | OUTPUT |

### 3-cell parallel

All 3 red → E+ | All 3 black → E- | All 3 green → A+ | All 3 white → A-

---

## Toolchain - unchanged, locked

- Arduino IDE v3.0.7 on Windows
- esp32 by Espressif v3.0.7
- Board: ESP32C3 Dev Module
- Port: COM11
- USB CDC On Boot: ENABLED
- Required libraries: NimBLE-Arduino by h2zero, ArduinoJson by Benoit Blanchon

---

## Next session: 1C - Timing instrumentation

Add millis() timestamps to each boot phase. Emit durations in structured Serial journal.

Phases to instrument:
- Phase 0 (SETTLE): settle_ms
- Phase 1 (NOISE): noise_ms
- Phase 2 (TARE): tare_ms
- Phase 3 (CAL): cal_ms
- STATE_RUNNING tick: tick_ms

Output format (per phase):
```
[BOOT] phase=SETTLE ms=1823
[BOOT] phase=NOISE ms=412
[BOOT] phase=TARE ms=2104
[BOOT] phase=CAL ms=8341
[RUN] tick_ms=103
```

No RTC. Durations only - not wall clock timestamps.

---

*End of session 3 handoff.*
