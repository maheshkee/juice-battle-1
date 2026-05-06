#include "tare.h"
#include <string.h>
#include <stdio.h>

static long          s_samples[5];
static int           s_count    = 0;
static int           s_attempts = 0;
static unsigned long s_retry_ms = 0;

void tare_reset() {
    s_count    = 0;
    s_attempts = 0;
    s_retry_ms = 0;
}

TareResult tare_feed(long raw) {
    TareResult r;
    memset(&r, 0, sizeof(r));
    r.status   = TARE_BUSY;
    r.attempts = s_attempts;

    if (s_retry_ms > 0 && millis() < s_retry_ms) return r;
    s_retry_ms = 0;

    s_samples[s_count++] = raw;
    if (s_count < 5) return r;

    long mn = s_samples[0], mx = s_samples[0], sum = 0;
    for (int i = 0; i < 5; i++) {
        sum += s_samples[i];
        if (s_samples[i] < mn) mn = s_samples[i];
        if (s_samples[i] > mx) mx = s_samples[i];
    }
    long spread  = mx - mn;
    r.spread_raw = (float)spread;

    if (spread < 600) {
        r.status   = TARE_SUCCESS;
        r.tare_raw = sum / 5;
        s_count    = 0;
        snprintf(r.message, sizeof(r.message), "TARE OK = %ld spread=%ld", r.tare_raw, spread);
    } else {
        s_attempts++;
        r.attempts = s_attempts;
        if (s_attempts >= 3) {
            r.status = TARE_FAILED;
            s_count  = 0;
            snprintf(r.message, sizeof(r.message), "TARE_FAIL: unstable after 3 attempts");
        } else {
            r.status   = TARE_RETRY;
            s_count    = 0;
            s_retry_ms = millis() + 2000;
            snprintf(r.message, sizeof(r.message), "TARE retry %d spread=%ld", s_attempts, spread);
        }
    }
    return r;
}
