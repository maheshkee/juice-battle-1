# HX711 — Sensor Family Context

---

## What It Is

24-bit sigma-delta ADC designed for bridge sensors (load cells, strain gauges, pressure sensors). Extremely high gain (128×) makes it suitable for the tiny signals from load cells (±20 mV full scale).

---

## Channels and Gain

| Channel | Gain options |
|---------|-------------|
| A | 128 or 64 |
| B | 32 (fixed) |

Number of gain pulses after 24-bit read selects next channel/gain:
- 1 pulse → Channel A, Gain 128
- 2 pulses → Channel B, Gain 32
- 3 pulses → Channel A, Gain 64

---

## Output Rate

| RATE pin | Rate | Oversampling ratio |
|----------|------|--------------------|
| LOW (0) | 10 Hz | ~100,000:1 |
| HIGH (1) | 80 Hz | ~12,500:1 |

Lower rate = more oversampling = less noise per sample.

---

## Interface

Bit-bang serial only — two pins:
- `DOUT` — data output (open-drain, needs INPUT_PULLUP)
- `PD_SCK` — clock input and power-down control

No SPI, no I2C. Timing is manual, not peripheral-driven.

---

## Key Datasheet Facts

- 100 dB CMRR and PSRR at gain 128, 10 Hz
- 50 nV rms input noise at 10 Hz
- 400 ms settling after power-up or channel/gain change
- DOUT LOW = conversion ready, HIGH = not ready / power down
- PD_SCK HIGH > 60 µs = power down mode

---

## Open Questions (to be answered by experiments)

| Q | Experiment |
|---|-----------|
| Q1: Does HX711 freeze until MCU reads, or refresh autonomously? | 001-freeze-test |
| Q2: What is actual noise floor on our hardware? | 002-noise-baseline |
| Q3: How many samples needed for a stable reading? | 003-averaging + 004-stability |
| Q4: What calibration factor for our 20 kg load cell? | 005-calibration |
