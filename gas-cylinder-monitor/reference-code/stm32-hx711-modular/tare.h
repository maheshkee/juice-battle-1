#pragma once
#include <Arduino.h>

typedef enum { TARE_BUSY, TARE_RETRY, TARE_DEGRADED, TARE_SUCCESS, TARE_FAILED } TareStatus;

typedef struct {
    TareStatus status;
    long       tare_raw;
    float      spread_raw;
    int        attempts;
    char       message[64];
} TareResult;

void       tare_reset();
TareResult tare_feed(long raw);
