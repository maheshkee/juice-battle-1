#include "Arduino_RouterBridge.h"

#define DT  7
#define SCK 6

static long hx711_read_raw() {
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(DT);
        digitalWrite(SCK, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(SCK, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}

long handle_take_reading() {
    long sum = 0;
    for (int i = 0; i < 20; i++) {
        while (digitalRead(DT) == HIGH) {}
        sum += hx711_read_raw();
        delay(100);
    }
    return sum / 20;
}

void setup() {
    pinMode(SCK, OUTPUT);
    digitalWrite(SCK, LOW);
    pinMode(DT, INPUT_PULLUP);

    delay(3000);
    Bridge.begin();
    Bridge.provide_safe("take_reading", handle_take_reading);
}

void loop() {
    Bridge.notify("log", String("MCU ready. Awaiting trigger."));
    delay(5000);
}
