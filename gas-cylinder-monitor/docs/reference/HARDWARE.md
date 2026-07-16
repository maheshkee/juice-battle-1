# HARDWARE.md — Pin and Voltage Reference | AQ3

---

## Voltage Domains

| Domain | Voltage | Notes |
|--------|---------|-------|
| MCU Arduino headers | 3.3V logic | 5V tolerant EXCEPT A0 and A1 |
| A0, A1 pins | 3.3V max | NOT 5V tolerant — damage if exceeded |
| JCTL header (MPU pins) | 1.8V ONLY | 3.3V = hardware damage — no exceptions |
| JMISC MPU pins | 1.8V ONLY | Same domain as JCTL |

---

## HX711 Pin Constraints

| Signal | Pin | Reason |
|--------|-----|--------|
| DT (DOUT) | D7 ONLY | Only conflict-free INPUT pin |
| SCK (PD_SCK) | D6 ONLY | Only conflict-free OUTPUT pin |
| Forbidden | D2 | TIM2_CH2 mux conflict |
| Forbidden | D3 | TIM3_CH3 mux conflict |
| Forbidden | D4 | Timer mux conflict |
| Forbidden | D5 | Timer mux conflict |

**Symptom of wrong pin**: raw value stuck at `0x7FFFFF` or `0x800000`.

---

## HX711 Load Cell Wiring (confirmed working)

| HX711 terminal | Load cell wire |
|----------------|---------------|
| E+ | Red |
| E- | Black |
| A+ | Green |
| A- | White |

Wire colors may vary by manufacturer — verify against your load cell datasheet.

HX711 VCC → 5V pin (NOT 3.3V — green PCB clones require 5V AVDD)
HX711 GND → GND

---

## BLE

- Stack: BlueZ 5.82
- Interface: hci0
- Transport: `le` only — `auto` triggers Classic BT inquiry, kills adapter permanently
- Recovery from wrong transport: `sudo reboot` (no softer fix)

---

## Bridge UART

| Name | Maps to |
|------|---------|
| `Serial2` in sketch | LPUART1 — the bridge UART |
| `Serial` in sketch | USB CDC to MPU (not directly to host terminal) |
| `Monitor.println()` | Correct path for MCU → app log output |
| `Serial.println()` | Wrong — goes to MPU CDC, not to app logs |

---

## Load Cell Mounting (critical)

- One end FIXED (clamped or screwed to rigid surface)
- Other end FREE (hangs over edge, nothing else touching it)
- Weight placed on free end only
- If both ends rest on a surface → corrupt readings (0.0 / 4.6 / 25.1 cycling)
