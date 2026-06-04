#include "delta.h"
#include <string.h>
#include <stdio.h>
#include <math.h>

static long s_window[20];
static int  s_idx  = 0;
static bool s_full = false;

void delta_reset() {
    s_idx  = 0;
    s_full = false;
}

DeltaResult delta_feed(long raw, long tare_raw, float cal_factor, float threshold_g) {
    DeltaResult r;
    memset(&r, 0, sizeof(r));
    r.status = DELTA_BUSY;

    s_window[s_idx % 20] = raw;
    s_idx++;
    if (s_idx >= 20) s_full = true;

    if (!s_full) return r;

    float sum_b = 0.0f, sum_a = 0.0f;
    for (int i = 0; i < 10; i++) {
        sum_b += (float)(s_window[(s_idx - 1  - i + 20) % 20] - tare_raw) / cal_factor;
        sum_a += (float)(s_window[(s_idx - 11 - i + 20) % 20] - tare_raw) / cal_factor;
    }
    float avg_b = sum_b / 10.0f;
    float avg_a = sum_a / 10.0f;
    float delta = avg_a - avg_b;
    int   trig  = (fabsf(delta) > threshold_g) ? 1 : 0;

    r.avg_a   = avg_a;
    r.avg_b   = avg_b;
    r.delta_g = delta;
    r.status  = trig ? DELTA_TRIGGERED : DELTA_IDLE;

    snprintf(r.message, sizeof(r.message),
        "AVG_A=%.4f AVG_B=%.4f DELTA=%.4f THRESHOLD=%.4f TRIGGERED=%d",
        avg_a, avg_b, delta, threshold_g, trig);
    return r;
}
