#include "hx711.h"

void hx711_init() {
    pinMode(HX711_DT,  INPUT_PULLUP);
    pinMode(HX711_SCK, OUTPUT);
    digitalWrite(HX711_SCK, LOW);
}

HX711Result hx711_read() {
    HX711Result result = {0, false};

    uint32_t deadline = millis() + 400;
    while (digitalRead(HX711_DT) == HIGH) {
        if (millis() >= deadline) {
            return result;
        }
    }

    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT);
        digitalWrite(HX711_SCK, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(HX711_SCK, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK, LOW);
    delayMicroseconds(1);
    interrupts();

    if (value & 0x800000) value |= 0xFF000000;

    if (value == LONG_MIN || value == -1L || value == 0x7FFFFF) {
        return result;
    }

    result.value = value;
    result.valid = true;
    return result;
}
