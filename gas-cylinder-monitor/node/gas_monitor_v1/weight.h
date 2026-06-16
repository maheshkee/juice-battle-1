#pragma once
#include <Arduino.h>

enum WeightQuality {
    WEIGHT_GOOD,
    WEIGHT_DEGRADED,
    WEIGHT_FAILED
};

struct WeightResult {
    float         grams;
    WeightQuality quality;
    char          diagnosis[64];
};

void         weight_init();
WeightResult weight_update(long raw, float tare_raw, float cal_factor);
