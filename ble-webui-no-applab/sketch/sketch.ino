#include <Arduino_RouterBridge.h>

bool led_state = false;

bool on_set_led(bool state) {
    led_state = state;
    digitalWrite(LED3_G, state ? LOW : HIGH);
    return led_state;
}

bool on_get_led() {
    return led_state;
}

void setup() {
    pinMode(LED3_G, OUTPUT);
    digitalWrite(LED3_G, HIGH);
    Bridge.begin();
    Bridge.provide("set_led", on_set_led);
    Bridge.provide("get_led", on_get_led);
}

void loop() {
}
