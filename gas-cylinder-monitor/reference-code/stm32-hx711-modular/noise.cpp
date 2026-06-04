#include "noise.h"
#include <string.h>
#include <stdio.h>
#include <math.h>

static float s_samples[200];
static float s_min   = 1e9f;
static float s_max   = -1e9f;
static int   s_count = 0;

void noise_reset() {
    s_min   = 1e9f;
    s_max   = -1e9f;
    s_count = 0;
}

NoiseResult noise_feed(long raw, long tare_raw, float cal_factor) {
    NoiseResult r;
    memset(&r, 0, sizeof(r));
    r.status = NOISE_BUSY;

    float g = (float)(raw - tare_raw) / cal_factor;
    if (g < -50.0f || g > 50.0f) return r;

    s_samples[s_count] = g;
    if (g < s_min) s_min = g;
    if (g > s_max) s_max = g;
    s_count++;

    if (s_count % 50 == 0 && s_count < 200) {
        snprintf(r.message, sizeof(r.message), "NOISE: %d/200 samples", s_count);
    }
    if (s_count < 200) return r;

    // 200 samples — compute stats
    float pass1_sum = 0.0f;
    for (int i = 0; i < 200; i++) pass1_sum += s_samples[i];
    float mean_g = pass1_sum / 200.0f;

    float pass2_sum = 0.0f;
    for (int i = 0; i < 200; i++) {
        float dev = s_samples[i] - mean_g;
        pass2_sum += dev * dev;
    }
    float std_g       = sqrtf(pass2_sum / 200.0f);
    float pp_g        = s_max - s_min;
    float window_std  = std_g / sqrtf(10.0f);
    float delta_std   = sqrtf(2.0f) * window_std;
    float threshold_g = delta_std * 4.0f;

    r.status      = NOISE_SUCCESS;
    r.std_g       = std_g;
    r.pp_g        = pp_g;
    r.mean_g      = mean_g;
    r.threshold_g = threshold_g;
    snprintf(r.message, sizeof(r.message),
        "NOISE: complete. Threshold derived = %.4fg", threshold_g);
    return r;
}
