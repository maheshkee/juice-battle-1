#pragma once
#include <Arduino.h>

typedef enum { CAL_BUSY, CAL_SUCCESS, CAL_FAILED, CAL_OUT_OF_RANGE } CalStatus;

typedef struct {
    CalStatus status;
    float     cal_factor;
    float     raw_delta;
    char      message[64];
} CalResult;

void      cal_reset();
CalResult cal_feed(long raw, long tare_raw, float known_weight_g);
