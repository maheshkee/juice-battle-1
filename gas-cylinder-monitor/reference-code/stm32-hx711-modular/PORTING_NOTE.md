# PORTING_NOTE.md — stm32-hx711-modular
# Created: 2026-06-04

This is STM32U585 code written for the UNO Q Board (App Lab / Bridge architecture).
**PORT THE LOGIC, NOT THE CODE.** The ESP32-C3 is the new target.

---

## What carries to ESP32-C3

| Item | Status |
|------|--------|
| 24-bit HX711 read + 25th gain pulse (gain 128, channel A) | PORT |
| Sign extension: `if (v & 0x800000) v |= 0xFF000000` | PORT |
| `wait_ready`: poll DOUT LOW, timeout → LONG_MIN | PORT |
| `noInterrupts()` around the 24-bit clocking loop | PORT |
| `delayMicroseconds(1)` per GPIO edge (HIGH and LOW) | PORT |
| Three corrupt filters: LONG_MIN, -1, 0x7FFFFF | PORT (required always) |
| Module result-struct contract: {value, quality, diagnosis} | PORT |
| Modules receive raw readings from orchestrator — never call HX711 directly | PORT |
| One sample per loop() iteration, millis() pacing at TOP of loop() | PORT |
| Adaptive retry (2s/10s/30s/60s backoff) + degraded operation | PORT |

---

## What does NOT carry to ESP32-C3

| Item | Why VOID |
|------|---------|
| `#define HX711_DT_PIN 7` (D7) | STM32U585 timer-conflict constraint only |
| `#define HX711_SCK_PIN 6` (D6) | STM32U585 timer-conflict constraint only |
| `Bridge.notify()` / `Bridge.provide()` | App Lab Bridge — ESP32 uses WiFi |
| `bridge_util.h`, `sketch.yaml` (Arduino RouterBridge) | App Lab infrastructure only |
| `cal_factor = 106.7` | STM32U585-specific, VOID on ESP32-C3. Re-derive. |
| `wait_ready timeout = 400ms` | Tuned for Bridge load on UNO Q. Re-tune on ESP32. |
| `float`-only assumption | The double-broken bug is STM32U585-specific. Re-verify on ESP32. |
| `delay(3000) + Bridge.begin()` in setup() | App Lab container startup only |
| `Monitor.begin()` | Hangs MCU if Python handler missing — App Lab only |

---

## Bring-up gate before using any of this logic

**3.3V safety gate:** HX711 VCC = 5V. ESP32-C3 GPIO = 3.3V. The STM32's D7/D6 were
5V-tolerant. ESP32-C3 GPIO tolerance vs HX711 DOUT/SCK levels must be verified before
applying power. Level-shift if needed. This is E-000 chunk 1 — do not skip it.
