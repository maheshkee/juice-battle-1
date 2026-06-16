#pragma once
#include <Arduino.h>

enum CalStatus {
    CAL_BUSY,
    CAL_SUCCESS,
    CAL_FAILED
};

struct CalResult {
    float     cal_factor;
    CalStatus status;
    char      diagnosis[64];
};

void      cal_init(float tare_raw);
CalResult cal_update(long raw);
bool      cal_save(float cal_factor);
float     cal_load_last();
