#pragma once
#include <Arduino.h>

typedef enum { DELTA_BUSY, DELTA_IDLE, DELTA_TRIGGERED } DeltaStatus;

typedef struct {
    DeltaStatus status;
    float       avg_a;
    float       avg_b;
    float       delta_g;
    char        message[128];
} DeltaResult;

void        delta_reset();
DeltaResult delta_feed(long raw, long tare_raw, float cal_factor, float threshold_g);
