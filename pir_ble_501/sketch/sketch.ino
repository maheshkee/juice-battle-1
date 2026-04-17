#include <Arduino_RouterBridge.h>

void setLED(bool motion) {
  digitalWrite(LED3_R, motion ? LOW  : HIGH);
  digitalWrite(LED3_G, motion ? HIGH : LOW);
}

void set_motion_led(bool state) {
  setLED(state);
}

void setup() {
  pinMode(LED3_R, OUTPUT);
  pinMode(LED3_G, OUTPUT);
  setLED(false);
  Bridge.begin();
  Bridge.provide("set_motion_led", set_motion_led);
}

void loop() {}