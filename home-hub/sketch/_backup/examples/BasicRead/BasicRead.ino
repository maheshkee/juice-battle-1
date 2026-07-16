#include "ScaleHX711.h"

ScaleHX711 scale;

void setup() {
    Serial.begin(115200);

    scale.begin(3, 2);
    scale.set_scale(2280.0f);
    // stability_threshold defaults to 10 counts; tighten or loosen as needed
    scale.set_stability_threshold(2);
}

void loop() {
    scale.update();

    // fresh() is true only when update() captured a new reading this call.
    // available() is true once any reading has been stored and stays true.
    if (scale.fresh()) {
        Serial.print("raw: ");
        Serial.print(scale.get_raw());
        Serial.print("  weight: ");
        Serial.print(scale.get_weight(), 3);
        Serial.print("  stable: ");
        Serial.println(scale.is_stable() ? "yes" : "no");
    }

    delay(100);
}
