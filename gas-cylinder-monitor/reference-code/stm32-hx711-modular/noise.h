#pragma once
#include <Arduino.h>

typedef enum { NOISE_BUSY, NOISE_SUCCESS, NOISE_FAILED } NoiseStatus;

typedef struct {
    NoiseStatus status;
    float       std_g;
    float       pp_g;
    float       mean_g;
    float       threshold_g;
    char        message[128];
} NoiseResult;

void        noise_reset();
NoiseResult noise_feed(long raw, long tare_raw, float cal_factor);
