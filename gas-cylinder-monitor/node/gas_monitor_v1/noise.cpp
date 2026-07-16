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

    /* Store raw counts, not grams — cal_factor applied exactly once at sigma
       conversion. Storing grams caused double-division when noise_recompute_sigma()
       ran after CAL, shrinking sigma to ~0.09g and generating false WEIGHT_EVENTs. */
    float net_raw = (float)raw - tare_raw;
    s_samples[s_count] = net_raw;
    s_sum += net_raw;
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
    /* cal_factor > 0 guaranteed: loaded from SPIFFS before STATE_NOISE.
       Fallback to raw counts if somehow still 0. */
    float sigma_raw = sqrtf(variance);
    float sigma_g   = (cal_factor > 0.0f) ? (sigma_raw / cal_factor) : sigma_raw;

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

// noise_recompute_sigma() — correct after CHANGE 1.
// s_samples[] now holds net raw counts (tare subtracted, no cal_factor) per CHANGE 1.
// Dividing by cal_factor here is intentional and correct: first and only application
// of cal_factor to these samples. Limitation: only valid on the standard single-boot
// sequence where noise runs before CAL. Any future recalibration flow that re-runs
// noise_update() after cal_factor is known must not call this function.
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
