#include "cal.h"
#include <string.h>
#include <stdio.h>

static long s_sum   = 0;
static int  s_count = 0;

void cal_reset() {
    s_sum   = 0;
    s_count = 0;
}

CalResult cal_feed(long raw, long tare_raw, float known_weight_g) {
    CalResult r;
    memset(&r, 0, sizeof(r));
    r.status = CAL_BUSY;

    s_sum += raw;
    s_count++;
    if (s_count < 20) return r;

    long  avg_raw    = s_sum / s_count;
    float raw_delta  = (float)(avg_raw - tare_raw);
    float cal_factor = raw_delta / known_weight_g;

    r.raw_delta = raw_delta;

    if (cal_factor < 80.0f || cal_factor > 140.0f) {
        r.status = CAL_OUT_OF_RANGE;
        snprintf(r.message, sizeof(r.message),
            "CAL_FAIL: cal_factor out of range: %.2f", cal_factor);
        return r;
    }

    r.status     = CAL_SUCCESS;
    r.cal_factor = cal_factor;
    snprintf(r.message, sizeof(r.message),
        "CAL_FACTOR=%.4f TARE=%ld", cal_factor, tare_raw);
    return r;
}
