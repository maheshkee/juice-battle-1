# node/ — ESP32-C3 Sensor Firmware

This directory contains the ESP32-C3 firmware for the gas-cylinder-monitor sensor node.
Status: EMPTY — scaffold only. E-000 bring-up has not been done yet.

---

## What This Node Does

- Reads a 20 kg load cell via HX711 (raw bit-bang, no library)
- Applies corrupt-value filters (LONG_MIN, -1, 0x7FFFFF)
- Averages N samples (N=50 production, N=200 lab)
- Computes grams from raw counts using a self-derived cal_factor
- Characterises noise floor at boot (sigma, peak-to-peak, threshold)
- Sends `{grams, quality, sigma}` to the UNO Q hub over WiFi

**Does NOT:** compute gas %, know steel weight, have a clock, use App Lab or Bridge.

---

## Toolchain

- Arduino IDE or PlatformIO — standard ESP32-C3 support
- NOT App Lab. NOT Bridge. NOT Bridge.notify. Those are UNO Q App Lab patterns.
- Flash via USB

---

## SAFETY GATE (do this before powering)

HX711 VCC = 5V. ESP32-C3 GPIO = 3.3V.

**Verify DOUT/SCK logic-level compatibility with HX711 at 5V VCC before applying power.**
Level-shifting may be needed. This check is E-000 chunk 1.

Do not skip this. Skipping can damage the ESP32-C3 GPIO or produce permanently corrupt reads.

---

## Pins

TBD at E-000 bring-up. The old "DT=D7/SCK=D6 only" rule was an STM32U585 timer-conflict
constraint. It does NOT apply to the ESP32-C3. Pick any two GPIO; validate at E-000.

---

## cal_factor

The STM32 value of 106.7 raw/g is VOID on ESP32-C3. Re-derive from scratch at E-001.
Store to config.json on node. Never hardcode.

---

## Reference

Logic to port (not code): `reference-code/stm32-hx711-modular/`
Read the PORTING_NOTE.md at the top of that folder before using any code from it.
