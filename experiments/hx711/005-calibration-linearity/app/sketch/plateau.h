#pragma once
#include <Arduino.h>

#define PLATEAU_N 100

typedef enum { PLATEAU_BUSY, PLATEAU_RECORDED } PlateauStatus;

typedef struct {
    PlateauStatus status;
    int           seq;
    float         mean_raw;
    float         spread;
    int           n_samples;
} PlateauResult;

typedef struct {
    int   fill;
    bool  window_full;
    float mean;
    float spread;
    float settle_band;
    float step_thresh;
    bool  armed;
    bool  has_last;
    float last_mean;
    int   seq;
} PlateauInfo;

void          plateau_reset(float settle_band, float step_thresh);
PlateauResult plateau_feed(long raw);
PlateauInfo   plateau_info(void);
