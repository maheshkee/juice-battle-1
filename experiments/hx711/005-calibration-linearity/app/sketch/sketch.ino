#include <Arduino_RouterBridge.h>
#include <climits>
#include <math.h>
#include "hx711.h"
#include "tare.h"
#include "plateau.h"

#define NOISE_N 200

typedef enum {
    STATE_IDLE,
    STATE_TARE_WAIT,
    STATE_TARE_MEASURE,
    STATE_NOISE_COLLECT,
    STATE_STAIRCASE_CAPTURE,
    STATE_ERROR
} AppState;

static AppState      g_state      = STATE_IDLE;
static unsigned long g_state_ms   = 0;
static unsigned long g_next_ms    = 0;
static unsigned long g_blink_ms   = 0;
static bool          g_blink_on   = false;

// Tare results
static long  g_tare_raw    = 0;
static float g_tare_spread = 0.0f;

// Pre-tare stability gate
static int   g_stable_count = 0;
static long  g_prev_raw     = 0;

// Noise collection — Welford online, no large array on stack
static int   g_noise_n       = 0;
static float g_noise_mean    = 0.0f;
static float g_noise_M2      = 0.0f;
static long  g_noise_min_raw = 2000000000L;
static long  g_noise_max_raw = -2000000000L;

// Phase A results — in RAM for Phase B
static long  g_stability_band_raw = 0;
static float g_raw_std            = 0.0f;

// Phase B thresholds (derived, never hardcoded)
static float         g_settle_band  = 0.0f;
static float         g_step_thresh  = 0.0f;
static unsigned long g_blink_end_ms = 0;
static unsigned long g_status_ms    = 0;

// ── LED helpers ───────────────────────────────────────────────────────────────

static void led_red_on()   { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
static void led_green_on() { digitalWrite(LED3_G, LOW);  digitalWrite(LED3_R, HIGH); }
static void led_both_off() { digitalWrite(LED3_R, HIGH); digitalWrite(LED3_G, HIGH); }

// ── setup ─────────────────────────────────────────────────────────────────────

void setup() {
    hx711_init();

    pinMode(LED3_R, OUTPUT);
    pinMode(LED3_G, OUTPUT);
    led_red_on();

    delay(3000);
    Bridge.begin();
    Bridge.notify("log", "005 BOOT sizeof_float=" + String(sizeof(float)));
    Bridge.notify("log", "005 ready. Experiment: calibration-linearity.");

    g_state_ms = millis();
    g_next_ms  = millis();
}

// ── loop ──────────────────────────────────────────────────────────────────────

void loop() {
    if (millis() < g_next_ms) return;
    g_next_ms = millis() + 120;

    switch (g_state) {

    // ── IDLE ──────────────────────────────────────────────────────────────────
    case STATE_IDLE:
        led_red_on();
        if (millis() - g_state_ms >= 3000) {
            g_stable_count = 0;
            g_prev_raw     = 0;
            g_state    = STATE_TARE_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", "TARE: ensure scale is EMPTY");
            Bridge.notify("log", "TARE: waiting for stable empty scale");
        }
        break;

    // ── TARE_WAIT ─────────────────────────────────────────────────────────────
    case STATE_TARE_WAIT: {
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) led_red_on(); else led_both_off();
        }
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        if (g_prev_raw != 0 && labs(r - g_prev_raw) < 300) {
            g_stable_count++;
        } else {
            g_stable_count = 0;
        }
        g_prev_raw = r;
        if (millis() - g_state_ms >= 30000) {
            g_state_ms = millis();
            Bridge.notify("log", "TARE: scale not stable - ensure it is EMPTY");
        }
        if (g_stable_count >= 10) {
            tare_reset();
            g_state    = STATE_TARE_MEASURE;
            g_state_ms = millis();
        }
        break;
    }

    // ── TARE_MEASURE ──────────────────────────────────────────────────────────
    case STATE_TARE_MEASURE: {
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        TareResult result = tare_feed(r);
        if (result.status == TARE_BUSY) break;
        Bridge.notify("log", String(result.message));
        if (result.status == TARE_RETRY) break;
        if (result.status == TARE_SUCCESS || result.status == TARE_DEGRADED) {
            g_tare_raw    = result.tare_raw;
            g_tare_spread = result.spread_raw;
            g_noise_n       = 0;
            g_noise_mean    = 0.0f;
            g_noise_M2      = 0.0f;
            g_noise_min_raw = 2000000000L;
            g_noise_max_raw = -2000000000L;
            g_state    = STATE_NOISE_COLLECT;
            g_state_ms = millis();
            Bridge.notify("log", "NOISE: collecting " + String(NOISE_N) + " samples...");
        }
        if (result.status == TARE_FAILED) {
            g_state    = STATE_ERROR;
            g_state_ms = millis();
        }
        break;
    }

    // ── NOISE_COLLECT ─────────────────────────────────────────────────────────
    case STATE_NOISE_COLLECT: {
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;

        g_noise_n++;
        float x      = (float)(r - g_tare_raw);
        float delta  = x - g_noise_mean;
        g_noise_mean += delta / (float)g_noise_n;
        float delta2  = x - g_noise_mean;
        g_noise_M2   += delta * delta2;

        if (r < g_noise_min_raw) g_noise_min_raw = r;
        if (r > g_noise_max_raw) g_noise_max_raw = r;

        if (g_noise_n % 50 == 0 && g_noise_n < NOISE_N) {
            Bridge.notify("log", "NOISE: " + String(g_noise_n) + "/" + String(NOISE_N));
        }

        if (g_noise_n < NOISE_N) break;

        // All samples collected
        float raw_std = (g_noise_M2 >= 0.0f) ? sqrtf(g_noise_M2 / (float)g_noise_n) : 0.0f;
        long  pp_raw  = g_noise_max_raw - g_noise_min_raw;

        // Phase A stability band (saved for fallback)
        long derived = (raw_std > 0.0f) ? (long)(6.0f * raw_std + 0.5f) : 0;
        if (derived > 0) {
            g_stability_band_raw = derived;
        } else {
            g_stability_band_raw = 300;
            Bridge.notify("log", "STABILITY_BAND: derivation failed, fallback=300");
        }
        g_raw_std = raw_std;

        const char* quality = (g_tare_spread < 300.0f) ? "EXCELLENT"
                            : (g_tare_spread < 600.0f) ? "OK"
                            :                            "DEGRADED";
        String rpt_tare = "TARE_REPORT tare_raw=";
        rpt_tare += String(g_tare_raw);
        rpt_tare += " spread=";
        rpt_tare += String((long)g_tare_spread);
        rpt_tare += " quality=";
        rpt_tare += quality;
        Bridge.notify("log", rpt_tare);

        String rpt_noise = "NOISE_REPORT N=";
        rpt_noise += String(g_noise_n);
        rpt_noise += " std_raw=";
        rpt_noise += String(raw_std, 2);
        rpt_noise += " pp_raw=";
        rpt_noise += String(pp_raw);
        Bridge.notify("log", rpt_noise);

        Bridge.notify("log", "STABILITY_BAND " + String(g_stability_band_raw) + " raw (6x std_raw)");

        // Derive Phase B thresholds from measured noise — no hardcoding
        g_settle_band = 6.0f * (g_raw_std / sqrtf((float)PLATEAU_N));
        g_step_thresh  = 1.5f * g_settle_band;
        if (g_settle_band <= 0.0f) {
            g_settle_band = (float)g_stability_band_raw;
            g_step_thresh  = 1.5f * g_settle_band;
            Bridge.notify("log", "STAIRCASE: settle_band fallback to stability_band");
        }
        plateau_reset(g_settle_band, g_step_thresh);

        Bridge.notify("log",
            "STAIRCASE_THRESHOLDS settle_band=" + String(g_settle_band, 2) +
            " step_thresh=" + String(g_step_thresh, 2));

        led_green_on();
        g_state    = STATE_STAIRCASE_CAPTURE;
        g_state_ms = millis();
        Bridge.notify("log", "STAIRCASE: Phase B active. Add/remove blocks.");
        break;
    }

    // ── STAIRCASE_CAPTURE ─────────────────────────────────────────────────────
    case STATE_STAIRCASE_CAPTURE: {
        // Non-blocking LED blink: restore green after brief off
        if (g_blink_end_ms > 0 && millis() >= g_blink_end_ms) {
            led_green_on();
            g_blink_end_ms = 0;
        }

        long r = hx711_read_raw();
        if (r == LONG_MIN) break;

        PlateauResult result = plateau_feed(r);
        if (result.status == PLATEAU_RECORDED) {
            // Plateau recorded — notify Python with CSV row payload
            String msg = String(result.seq) + ","
                       + String(result.mean_raw, 2) + ","
                       + String(result.spread, 2) + ","
                       + String(result.n_samples);
            Bridge.notify("plateau", msg);
            Bridge.notify("log",
                "PLATEAU seq=" + String(result.seq) +
                " mean_raw=" + String(result.mean_raw, 2) +
                " spread=" + String(result.spread, 2));

            // Brief green blink as bench feedback (active-LOW: off then back on)
            led_both_off();
            g_blink_end_ms = millis() + 80;
        }

        // Periodic status ~1 Hz
        if (millis() - g_status_ms >= 1000) {
            g_status_ms = millis();
            PlateauInfo info = plateau_info();

            const char* label;
            if (!info.window_full) {
                label = "SETTLING...";
            } else if (info.has_last &&
                       fabsf(info.mean - info.last_mean) > info.step_thresh &&
                       info.spread >= info.settle_band) {
                label = "MOVE DETECTED";
            } else if (info.spread < info.settle_band && !info.armed) {
                label = "STABLE - READY";
            } else {
                label = "SETTLING...";
            }

            String s = "STATUS fill=";
            s += String(info.fill);
            s += "/";
            s += String(PLATEAU_N);
            s += " mean=";
            s += String((long)info.mean);
            s += " spread=";
            s += String((long)info.spread);
            s += " plateaus=";
            s += String(info.seq);
            s += " ";
            s += label;
            Bridge.notify("log", s);
        }
        break;
    }

    // ── ERROR ─────────────────────────────────────────────────────────────────
    case STATE_ERROR:
        led_red_on();
        if (millis() - g_state_ms >= 5000) {
            g_state_ms = millis();
            Bridge.notify("log", "ERROR: halted");
        }
        break;

    default:
        break;
    }
}
