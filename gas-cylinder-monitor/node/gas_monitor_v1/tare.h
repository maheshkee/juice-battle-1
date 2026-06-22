#pragma once
#include <Arduino.h>

#define TARE_CHECK_THRESHOLD_G 5000.0f

enum TareCheckResult {
    TARE_CHECK_CLEAN  = 0,
    TARE_CHECK_SUSPECT = 1,
    TARE_CHECK_NO_REF  = 2
};

enum TareStatus {
    TARE_BUSY,
    TARE_SUCCESS,
    TARE_DEGRADED,
    TARE_FAILED
};

struct TareResult {
    float      tare_raw;
    TareStatus status;
    char       diagnosis[64];
};

void            tare_init();
TareResult      tare_update(long raw);
bool            tare_save_to_spiffs(float tare_raw);
bool            tare_load_from_spiffs(float* tare_raw_out);
TareCheckResult tare_self_check(float fresh_tare_raw, float saved_tare_raw, float cal_factor);
