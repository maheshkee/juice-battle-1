#include <Arduino_RouterBridge.h>
#include <climits>
#include <math.h>
#include "hx711.h"
#include "tare.h"
#include "cal.h"
#include "noise.h"
#include "delta.h"

typedef enum {
    STATE_IDLE,
    STATE_TARE_WAIT,
    STATE_TARE_MEASURE,
    STATE_CAL_WAIT,
    STATE_CAL_MEASURE,
    STATE_NOISE_WAIT,
    STATE_NOISE_MEASURE,
    STATE_DELTA_WAIT,
    STATE_DELTA_RUNNING,
    STATE_DONE,
    STATE_ERROR
} AppState;

static AppState      g_state       = STATE_IDLE;
static unsigned long g_state_ms    = 0;
static unsigned long g_blink_ms    = 0;
static bool          g_blink_on    = false;
static unsigned long g_next_ms     = 0;

static long          g_tare_raw    = 0;
static float         g_cal_factor  = 0.0f;
static float         g_threshold_g = 0.0f;
static int           g_stable_count = 0;
static int           g_weight_count = 0;
static long          g_prev_raw     = 0;

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
    Bridge.notify("log", "PLATFORM sizeof_float=" + String(sizeof(float)));
    Bridge.notify("log", String("MCU ready."));

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
            Bridge.notify("log", String("TARE: ensure scale is completely EMPTY"));
            Bridge.notify("log", String("TARE: waiting for stable empty scale"));
        }
        break;

    // ── TARE_WAIT ─────────────────────────────────────────────────────────────
    case STATE_TARE_WAIT: {
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
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
            Bridge.notify("log", String("TARE: scale not stable - ensure it is EMPTY"));
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
        if (result.status == TARE_SUCCESS) {
            g_tare_raw = result.tare_raw;
            g_weight_count = 0;
            cal_reset();
            g_state    = STATE_CAL_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("CAL: place 158g known weight on scale"));
            Bridge.notify("log", String("CAL: waiting 10 seconds to settle"));
        }
        if (result.status == TARE_DEGRADED) {
            g_tare_raw = result.tare_raw;
            Bridge.notify("log", String("TARE: degraded - using best available reading"));
            g_weight_count = 0;
            cal_reset();
            g_state    = STATE_CAL_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("CAL: place 158g known weight on scale"));
            Bridge.notify("log", String("CAL: waiting 10 seconds to settle"));
        }
        if (result.status == TARE_FAILED) {
            g_state    = STATE_ERROR;
            g_state_ms = millis();
        }
        break;
    }

    // ── CAL_WAIT ──────────────────────────────────────────────────────────────
    case STATE_CAL_WAIT: {
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        long delta = r - g_tare_raw;
        if (delta > 8000) { g_weight_count++; } else { g_weight_count = 0; }
        if (millis() - g_state_ms >= 5000) {
            g_state_ms = millis();
            Bridge.notify("log", String("CAL: waiting for weight - place 158g on scale"));
        }
        if (g_weight_count >= 5) {
            g_state    = STATE_CAL_MEASURE;
            g_state_ms = millis();
        }
        break;
    }

    // ── CAL_MEASURE ───────────────────────────────────────────────────────────
    case STATE_CAL_MEASURE: {
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        CalResult result = cal_feed(r, g_tare_raw, 158.0f);
        if (result.status == CAL_BUSY) break;
        if (result.status == CAL_SUCCESS) {
            g_cal_factor = result.cal_factor;
            String msg = "CAL_FACTOR=";
            msg += String(result.cal_factor, 4);
            msg += " TARE=";
            msg += String(g_tare_raw);
            msg += " RAW_DELTA=";
            msg += String((long)result.raw_delta);
            msg += " EXPECTED_RANGE=80-140";
            Bridge.notify("cal_result", msg);
            led_green_on();
            delay(200);
            led_both_off();
            g_stable_count = 0;
            noise_reset();
            g_state    = STATE_NOISE_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("NOISE: remove all weight from scale"));
            Bridge.notify("log", String("NOISE: waiting 10 seconds to settle"));
        }
        if (result.status == CAL_OUT_OF_RANGE || result.status == CAL_FAILED) {
            Bridge.notify("log", String(result.message));
            g_state    = STATE_ERROR;
            g_state_ms = millis();
        }
        break;
    }

    // ── NOISE_WAIT ────────────────────────────────────────────────────────────
    case STATE_NOISE_WAIT: {
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        if (labs(r - g_tare_raw) < 300) { g_stable_count++; } else { g_stable_count = 0; }
        if (millis() - g_state_ms >= 30000) {
            g_state_ms = millis();
            Bridge.notify("log", String("NOISE: scale not stable - ensure it is EMPTY"));
        }
        if (g_stable_count >= 10) {
            g_state    = STATE_NOISE_MEASURE;
            g_state_ms = millis();
        }
        break;
    }

    // ── NOISE_MEASURE ─────────────────────────────────────────────────────────
    case STATE_NOISE_MEASURE: {
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        NoiseResult result = noise_feed(r, g_tare_raw, g_cal_factor);
        if (result.message[0]) Bridge.notify("log", String(result.message));
        if (result.status == NOISE_BUSY) break;
        if (result.status == NOISE_SUCCESS) {
            g_threshold_g = result.threshold_g;
            String msg = "MEAN=";
            msg += String(result.mean_g, 6);
            msg += " STD=";
            msg += String(result.std_g, 6);
            msg += " PP=";
            msg += String(result.pp_g, 4);
            msg += " THRESHOLD_G=";
            msg += String(result.threshold_g, 4);
            Bridge.notify("noise_result", msg);
            led_green_on();
            delta_reset();
            g_state    = STATE_DELTA_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("DELTA: place test weight on scale"));
            Bridge.notify("log", String("DELTA: waiting 5 seconds"));
        }
        if (result.status == NOISE_FAILED) {
            g_state    = STATE_ERROR;
            g_state_ms = millis();
        }
        break;
    }

    // ── DELTA_WAIT ────────────────────────────────────────────────────────────
    case STATE_DELTA_WAIT:
        if (millis() - g_blink_ms >= 200) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        if (millis() - g_state_ms >= 5000) {
            g_state    = STATE_DELTA_RUNNING;
            g_state_ms = millis();
        }
        break;

    // ── DELTA_RUNNING ─────────────────────────────────────────────────────────
    case STATE_DELTA_RUNNING: {
        long r = hx711_read_raw();
        if (r == LONG_MIN) break;
        DeltaResult result = delta_feed(r, g_tare_raw, g_cal_factor, g_threshold_g);
        if (result.status == DELTA_BUSY) break;
        Bridge.notify("delta_reading", String(result.message));
        if (result.status == DELTA_TRIGGERED) {
            String det = "DETECTED delta=";
            det += String(result.delta_g, 4);
            det += "g threshold=";
            det += String(g_threshold_g, 4);
            det += "g";
            Bridge.notify("detection_event", det);
            led_green_on();
            delay(50);
            led_both_off();
        }
        break;
    }

    // ── ERROR ─────────────────────────────────────────────────────────────────
    case STATE_ERROR:
        led_red_on();
        if (millis() - g_state_ms >= 5000) {
            g_state_ms = millis();
            Bridge.notify("log", String("ERROR: halted"));
        }
        break;

    default:
        break;
    }
}
