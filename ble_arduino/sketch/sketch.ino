
#include <Arduino_RouterBridge.h>

bool led_state = false;

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    digitalWrite(LED_BUILTIN, HIGH); // HIGH = OFF for built-in LED
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
    Bridge.provide("get_led_state", get_led_state);
}

void loop() {
    // Nothing needed here, Bridge handles everything
}

void set_led_state(bool state) {
    led_state = state;
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}

bool get_led_state() {
    return led_state;
}