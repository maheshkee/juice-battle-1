#include "weight.h"

#define BUF_SIZE    40
#define FAIL_LOW    -500.0f
#define FAIL_HIGH   50000.0f

static float s_buf[BUF_SIZE];
static int   s_idx;
static int   s_count;
static float s_ref_buf[BUF_SIZE];
static int   s_ref_idx;
static int   s_ref_count;
static bool  s_event_pending;

void weight_init() {
    s_idx   = 0;
    s_count = 0;
    for (int i = 0; i < BUF_SIZE; i++) s_buf[i] = 0.0f;
    s_ref_idx       = 0;
    s_ref_count     = 0;
    s_event_pending = false;
    for (int i = 0; i < BUF_SIZE; i++) s_ref_buf[i] = 0.0f;
}

WeightResult weight_update(long raw, float tare_raw, float cal_factor, float sigma_g) {
    WeightResult result;
    result.grams        = 0.0f;
    result.quality      = WEIGHT_DEGRADED;
    result.diagnosis[0] = '\0';
    result.event        = WEIGHT_EVENT_NONE;
    result.delta        = 0.0f;

    float grams_sample = ((float)raw - tare_raw) / cal_factor;
    s_buf[s_idx] = grams_sample;
    s_idx = (s_idx + 1) % BUF_SIZE;
    if (s_count < BUF_SIZE) s_count++;

    if (s_count < BUF_SIZE) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Filling buffer: %d/%d", s_count, BUF_SIZE);
        return result;
    }

    float sum = 0.0f;
    for (int i = 0; i < BUF_SIZE; i++) sum += s_buf[i];
    float mean = sum / (float)BUF_SIZE;

    if (mean < FAIL_LOW || mean > FAIL_HIGH) {
        result.quality = WEIGHT_FAILED;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Out of range: %.1fg", mean);
        return result;
    }

    if (mean < 0.0f) {
        result.grams   = mean;
        result.quality = WEIGHT_DEGRADED;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Zero drift: %.1fg", mean);
        return result;
    }

    // update delay line
    float reference = s_ref_buf[s_ref_idx];
    s_ref_buf[s_ref_idx] = mean;
    s_ref_idx = (s_ref_idx + 1) % BUF_SIZE;

    // guard: delay line not yet primed — no detection for first BUF_SIZE ticks
    if (s_ref_count < BUF_SIZE) {
        s_ref_count++;
    } else {
        float threshold = 4.0f * sigma_g;
        float d = mean - reference;
        if (!s_event_pending && fabsf(d) > threshold) {
            result.event = (d > 0.0f) ? WEIGHT_EVENT_PLACED : WEIGHT_EVENT_REMOVED;
            result.delta = d;
            s_event_pending = true;
        } else if (s_event_pending && fabsf(d) < threshold) {
            s_event_pending = false;
        }
    }

    result.grams   = mean;
    result.quality = WEIGHT_GOOD;
    snprintf(result.diagnosis, sizeof(result.diagnosis),
             "grams=%.1f", mean);
    return result;
}
