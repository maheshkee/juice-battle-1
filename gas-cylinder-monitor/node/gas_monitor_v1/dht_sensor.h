#pragma once
#include <Arduino.h>

// DHTesp library by Beegee-Tokyo — ESP32-specific, handles FreeRTOS preemption
// Install via Arduino Library Manager: "DHTesp" by Beegee-Tokyo
// Required Arduino libraries (add to sketch header comment):
//   DHTesp by Beegee-Tokyo — DHT22 on ESP32

#define DHT_PIN 5  // GPIO5 — free on ESP32-C3 (GPIO3=SCK, GPIO4=DT for HX711)

struct DHTResult {
    float temp_c;
    bool  valid;
};

void      dht_sensor_init();
DHTResult dht_sensor_read();
