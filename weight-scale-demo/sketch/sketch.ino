#include "Arduino_RouterBridge.h"
#include "HX711.h"

#define DOUT 4
#define SCK 3

HX711 scale;
float calibration_factor = -7050;

void setup() {
  scale.begin(DOUT, SCK);
  scale.set_scale(calibration_factor);
  scale.tare();

  Bridge.begin();
  Bridge.provide("get_weight", get_weight);
}

void loop() {
  Bridge.process();  // VERY IMPORTANT
}

void get_weight() {
  float w = scale.get_units(5);
  Bridge.write(w);   // send to Python
}