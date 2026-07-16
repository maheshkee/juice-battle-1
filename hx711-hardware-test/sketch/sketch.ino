#include "Arduino_RouterBridge.h"

#define HX711_DT_PIN    7
#define HX711_SCK_PIN   6
#define FAIL_THRESHOLD  5     // consecutive corrupt reads before RED on

static int fail_count = 0;

// ── bit-bang verbatim from home-hub ──────────────────────────────────
static bool hx711_wait_ready(uint32_t timeout_ms) {
    uint32_t t = millis();
    while (digitalRead(HX711_DT_PIN) == HIGH) {
        if ((millis() - t) > timeout_ms) return false;
    }
    return true;
}

static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}

void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    digitalWrite(HX711_SCK_PIN, LOW);
    pinMode(HX711_DT_PIN, INPUT_PULLUP);
    pinMode(LED3_G, OUTPUT);
    digitalWrite(LED3_G, HIGH);  // off (active LOW)
    pinMode(LED3_R, OUTPUT);
    digitalWrite(LED3_R, HIGH);    // off (active LOW)

    delay(3000);
    Bridge.begin();
    Bridge.notify("log", String("HX711 hardware test running. GREEN=valid read. RED=consecutive failures."));
}

void loop() {
    long raw = hx711_read_raw();

    bool corrupt = (raw == LONG_MIN || raw == -1 || raw == 0x7FFFFF);

    if (!corrupt) {
        fail_count = 0;
        digitalWrite(LED3_R, HIGH);   // red off
        digitalWrite(LED3_G, LOW);  // green on
        delay(80);
        digitalWrite(LED3_G, HIGH); // green off
    } else {
        fail_count++;
        if (fail_count >= FAIL_THRESHOLD) {
            digitalWrite(LED3_R, LOW); // red on solid
            Bridge.notify("log", String("CONSECUTIVE FAILURES — check wiring"));
            fail_count = 0;
        }
    }
}
