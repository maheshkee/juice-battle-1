#pragma once
#include <Arduino.h>

enum WeightQuality {
    WEIGHT_GOOD,
    WEIGHT_DEGRADED,
    WEIGHT_FAILED
};

enum WeightEvent { WEIGHT_EVENT_NONE=0, WEIGHT_EVENT_PLACED, WEIGHT_EVENT_REMOVED };

struct WeightResult {
    float         grams;
    WeightQuality quality;
    char          diagnosis[64];
    WeightEvent   event;
    float         delta;
};

void         weight_init();
WeightResult weight_update(long raw, float tare_raw, float cal_factor, float sigma_g);
