# ScaleHX711

Minimal and robust HX711 load-cell helper for Arduino-style environments.

## New Features & Improvements

- **Interrupt Protection:** Bit-banging is wrapped in `noInterrupts()` to ensure timing accuracy.
- **Averaging:** Support for multi-sample averaging to reduce noise.
- **Power Management:** `power_down()` and `power_up()` methods for energy saving.
- **Gain Control:** Support for Gain 128 (Channel A), 64 (Channel A), or 32 (Channel B).
- **Blocking Calibration:** `tare()` and `calibrate()` now average multiple samples for better accuracy.

## Current Behavior

- `begin(dt, sck, gain)` configures the HX711 pins and sets the gain (default 128).
- `update()` is non-blocking. If the HX711 is not ready, it leaves the cached reading unchanged and sets `available()` to `false`.
- `tare(samples)` (blocking) captures the average of `samples` as the zero offset.
- `calibrate(known_weight, samples)` (blocking) averages `samples` to compute the scale factor.
- `read_average(samples)` returns the average raw value over `samples`.
- `get_units(samples)` returns the current weight based on an average of `samples`.
- `power_down()` / `power_up()` controls the HX711 power state.
- `set_gain(gain)` sets the gain for the next conversion (128, 64, or 32).
- `is_stable()` reports whether two consecutive successful readings were within the configured threshold.

## Typical Use

```cpp
#include "ScaleHX711.h"

ScaleHX711 scale;

void setup() {
    Serial.begin(115200);
    scale.begin(3, 2, 128); // DT=3, SCK=2, Gain=128
    scale.set_scale(2280.0f);
    scale.set_stability_threshold(2);
    
    Serial.println("Taring...");
    scale.tare(20); // Average 20 samples for accurate zero
    Serial.println("Ready.");
}

void loop() {
    scale.update();

    if (scale.available()) {
        Serial.print("weight=");
        Serial.print(scale.get_weight(), 3);
        Serial.print(" stable=");
        Serial.println(scale.is_stable() ? "yes" : "no");
    }
    
    // Or get an averaged reading directly:
    // float avg_weight = scale.get_units(10);
}
```

## Gain Settings
- `128`: Channel A, Gain 128 (Default)
- `64`: Channel A, Gain 64
- `32`: Channel B, Gain 32

## Host-Side Tests

```sh
g++ -I. -Itests/fake_arduino tests/test_scale_hx711.cpp ScaleHX711.cpp -o tests/test_scale_hx711
./tests/test_scale_hx711
```
