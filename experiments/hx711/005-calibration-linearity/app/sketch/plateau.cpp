#include "plateau.h"
#include <math.h>
#include <string.h>

static float s_window[PLATEAU_N];
static int   s_fill      = 0;
static float s_settle    = 0.0f;
static float s_step      = 0.0f;
static float s_last_mean = 0.0f;
static bool  s_has_last  = false;
static bool  s_armed     = true;   // start armed so the first stable plateau is captured
static int   s_seq       = 0;

void plateau_reset(float settle_band, float step_thresh) {
    memset(s_window, 0, sizeof(s_window));
    s_fill      = 0;
    s_settle    = settle_band;
    s_step      = step_thresh;
    s_last_mean = 0.0f;
    s_has_last  = false;
    s_armed     = true;
    s_seq       = 0;
}

PlateauInfo plateau_info(void) {
    PlateauInfo info;
    info.seq         = s_seq;
    info.armed       = s_armed;
    info.has_last    = s_has_last;
    info.last_mean   = s_last_mean;
    info.settle_band = s_settle;
    info.step_thresh = s_step;

    int count        = (s_fill < PLATEAU_N) ? s_fill : PLATEAU_N;
    info.fill        = count;
    info.window_full = (s_fill >= PLATEAU_N);

    if (count == 0) {
        info.mean   = 0.0f;
        info.spread = 0.0f;
        return info;
    }

    float sum = 0.0f;
    float mn  = s_window[0];
    float mx  = s_window[0];
    for (int i = 0; i < count; i++) {
        sum += s_window[i];
        if (s_window[i] < mn) mn = s_window[i];
        if (s_window[i] > mx) mx = s_window[i];
    }
    info.mean   = sum / (float)count;
    info.spread = mx - mn;
    return info;
}

PlateauResult plateau_feed(long raw) {
    PlateauResult r;
    memset(&r, 0, sizeof(r));
    r.status = PLATEAU_BUSY;

    s_window[s_fill % PLATEAU_N] = (float)raw;
    s_fill++;
    if (s_fill < PLATEAU_N) return r;

    // Compute mean and spread of the full window (float accumulator, never double)
    float sum = 0.0f;
    float mn  = s_window[0];
    float mx  = s_window[0];
    for (int i = 0; i < PLATEAU_N; i++) {
        sum += s_window[i];
        if (s_window[i] < mn) mn = s_window[i];
        if (s_window[i] > mx) mx = s_window[i];
    }
    float mean_w   = sum / (float)PLATEAU_N;
    float spread_w = mx - mn;

    if (spread_w < s_settle) {
        // Window is quiet — candidate plateau
        if (s_armed) {
            if (!s_has_last || fabsf(mean_w - s_last_mean) > s_step) {
                s_seq++;
                s_last_mean = mean_w;
                s_has_last  = true;
                s_armed     = false;

                r.status    = PLATEAU_RECORDED;
                r.seq       = s_seq;
                r.mean_raw  = mean_w;
                r.spread    = spread_w;
                r.n_samples = PLATEAU_N;
            }
        }
    } else {
        // Window is moving — arm when it has shifted far enough from last plateau
        if (s_has_last && fabsf(mean_w - s_last_mean) > s_step) {
            s_armed = true;
        }
    }
    return r;
}
