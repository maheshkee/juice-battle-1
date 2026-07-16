#pragma once
#include <Arduino.h>

struct NoiseResult {
    float sigma_g;
    float threshold_g;
    bool  valid;
    char  diagnosis[64];
};

void        noise_init();
NoiseResult noise_update(long raw, float tare_raw, float cal_factor);
float       noise_recompute_sigma(float cal_factor);
