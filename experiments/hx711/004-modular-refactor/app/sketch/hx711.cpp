#include "hx711.h"

#define HX711_DT_PIN  7
#define HX711_SCK_PIN 6

static bool hx711_wait_ready(uint32_t timeout_ms) {
    uint32_t t = millis();
    while (digitalRead(HX711_DT_PIN) == HIGH) {
        if ((millis() - t) > timeout_ms) return false;
    }
    return true;
}

void hx711_init() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    pinMode(HX711_DT_PIN,  INPUT_PULLUP);
    digitalWrite(HX711_SCK_PIN, LOW);
}

long hx711_read_raw() {
    if (!hx711_wait_ready(400)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 1 gain pulse = gain 128 (Channel A)
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    if (value == LONG_MIN)                     return LONG_MIN;
    if (value == -1L)                          return LONG_MIN;
    if (value == 0x7FFFFF)                     return LONG_MIN;
    if (value < -5000000L || value > 5000000L) return LONG_MIN;
    return value;
}
