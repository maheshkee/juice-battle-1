#pragma once
#include <Arduino.h>

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

void       tare_init();
TareResult tare_update(long raw);
