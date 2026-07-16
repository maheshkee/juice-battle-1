#include <Arduino_RouterBridge.h>
#include "HX711.h"

#define DT_PIN  2
#define SCK_PIN 3

HX711 scale;
float cal = 420.0;

float get_weight() {
  if (scale.is_ready()) {
    return scale.get_units(5);
  }
  return -1.0;
}

void setup() {
  Bridge.begin();
  scale.begin(DT_PIN, SCK_PIN);
  scale.set_scale(cal);
  scale.tare();
  Bridge.provide("get_weight", get_weight);
}

void loop() {
  delay(500);
}
