#include "noise.h"
#include <math.h>

#define NOISE_SAMPLES  200

// 3-cell YZC-161A parallel platform, ESP32-C3 SuperMini
// Healthy sigma verified: 4.68-5.33g across boots.
// PASS gate: 8.0g = 1.5x margin above healthy max.
// WARN gate: 15.0g = midpoint between healthy (5g) and open-cell (25g).
// FAIL: sigma >= 15.0g indicates hardware fault (open cell or bad junction).
static const float NOISE_SIGMA_PASS_G = 8.0f;
static const float NOISE_SIGMA_WARN_G = 15.0f;

static float s_samples[NOISE_SAMPLES];
static float s_sum;
static int   s_count;

void noise_init() {
    s_sum   = 0.0f;
    s_count = 0;
}

NoiseResult noise_update(long raw, float tare_raw, float cal_factor) {
    NoiseResult result;
    result.sigma_g      = 0.0f;
    result.threshold_g  = 0.0f;
    result.valid        = false;
    result.diagnosis[0] = '\0';

    float grams;
    if (cal_factor == 0.0f) {
        grams = (float)(raw - (long)tare_raw);
    } else {
        grams = ((float)raw - tare_raw) / cal_factor;
    }
    s_samples[s_count] = grams;
    s_sum += grams;
    s_count++;

    if (s_count < NOISE_SAMPLES) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Noise char: %d/%d", s_count, NOISE_SAMPLES);
        return result;
    }

    /* Pass 1 complete: compute mean */
    float mean = s_sum / (float)NOISE_SAMPLES;

    /* Pass 2: compute variance over stored samples */
    float var_sum = 0.0f;
    for (int i = 0; i < NOISE_SAMPLES; i++) {
        float diff = s_samples[i] - mean;
        var_sum += diff * diff;
    }
    float variance = var_sum / (float)NOISE_SAMPLES;
    float sigma_g  = sqrtf(variance);

    result.sigma_g     = sigma_g;
    result.threshold_g = 4.0f * sigma_g;

    if (sigma_g < 0.5f) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Sigma too low - check wiring");
    } else if (sigma_g >= NOISE_SIGMA_WARN_G) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Sigma too high - check analog connections");
    } else if (sigma_g >= NOISE_SIGMA_PASS_G) {
        result.valid = true;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "WARN Sigma=%.2fg threshold=%.2fg", sigma_g, result.threshold_g);
    } else {
        result.valid = true;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Sigma=%.2fg threshold=%.2fg", sigma_g, result.threshold_g);
    }

    return result;
}

// noise_recompute_sigma() - ASSUMPTION WARNING
// This function assumes s_samples[] contains net raw counts (tare subtracted,
// cal_factor NOT yet applied). This is true only when called immediately after
// the V1 boot sequence where noise characterisation runs before CAL.
// If noise_init() + noise_update() are ever called AFTER cal_factor is known
// (e.g. recalibration flow), s_samples[] will already be in grams and calling
// this function will produce wrong sigma (double-divided by cal_factor).
// For any future recalibration: either add a unit-tracking flag to noise.cpp
// or re-run full noise characterisation with the real cal_factor instead of
// using this recompute path.
float noise_recompute_sigma(float cal_factor) {
    if (s_count < NOISE_SAMPLES) return 0.0f;
    if (cal_factor == 0.0f)      return 0.0f;

    float sum = 0.0f;
    for (int i = 0; i < NOISE_SAMPLES; i++) {
        sum += s_samples[i] / cal_factor;
    }
    float mean = sum / (float)NOISE_SAMPLES;

    float var_sum = 0.0f;
    for (int i = 0; i < NOISE_SAMPLES; i++) {
        float diff = (s_samples[i] / cal_factor) - mean;
        var_sum += diff * diff;
    }
    return sqrtf(var_sum / (float)NOISE_SAMPLES);
}
