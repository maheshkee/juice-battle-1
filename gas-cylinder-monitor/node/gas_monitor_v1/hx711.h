#pragma once
#include <Arduino.h>

#define HX711_DT  4
#define HX711_SCK 3

struct HX711Result {
    long value;
    bool valid;
};

void        hx711_init();
HX711Result hx711_read();
