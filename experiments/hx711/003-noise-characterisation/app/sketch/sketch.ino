#include <Arduino_RouterBridge.h>
#include <climits>
#include <math.h>

#define HX711_DT_PIN  7
#define HX711_SCK_PIN 6

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

static long          g_window[20];
static int           g_window_idx  = 0;
static bool          g_window_full = false;

static float         g_noise_samples[200];
static float         g_noise_min    = 1e9f;
static float         g_noise_max    = -1e9f;
static int           g_noise_count  = 0;

static long          g_cal_sum      = 0;
static int           g_cal_count    = 0;

static long          g_tare_samples[5];
static int           g_tare_ok       = 0;
static int           g_tare_attempt  = 0;
static unsigned long g_tare_retry_ms = 0;

// ── HX711 ────────────────────────────────────────────────────────────────────

static bool hx711_wait_ready(uint32_t timeout_ms) {
    uint32_t t = millis();
    while (digitalRead(HX711_DT_PIN) == HIGH) {
        if ((millis() - t) > timeout_ms) return false;
    }
    return true;
}

static long hx711_read_raw() {
    if (!hx711_wait_ready(400)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 1 gain pulse = gain 128 (Channel A)
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}

// ── LED helpers ───────────────────────────────────────────────────────────────

static void led_red_on()   { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
static void led_green_on() { digitalWrite(LED3_G, LOW);  digitalWrite(LED3_R, HIGH); }
static void led_both_off() { digitalWrite(LED3_R, HIGH); digitalWrite(LED3_G, HIGH); }

// ── setup ─────────────────────────────────────────────────────────────────────

void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    pinMode(HX711_DT_PIN,  INPUT_PULLUP);
    digitalWrite(HX711_SCK_PIN, LOW);

    pinMode(LED3_R, OUTPUT);
    pinMode(LED3_G, OUTPUT);
    led_red_on();

    delay(3000);
    Bridge.begin();
    Bridge.notify("log", "PLATFORM sizeof_double=" + String(sizeof(double))
        + " sizeof_float=" + String(sizeof(float)));
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
            g_state    = STATE_TARE_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("TARE: ensure scale is completely EMPTY"));
            Bridge.notify("log", String("TARE: waiting 10 seconds to settle"));
        }
        break;

    // ── TARE_WAIT ─────────────────────────────────────────────────────────────
    case STATE_TARE_WAIT:
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        if (millis() - g_state_ms >= 10000) {
            g_tare_ok       = 0;
            g_tare_attempt  = 0;
            g_tare_retry_ms = 0;
            g_state    = STATE_TARE_MEASURE;
            g_state_ms = millis();
        }
        break;

    // ── TARE_MEASURE ──────────────────────────────────────────────────────────
    case STATE_TARE_MEASURE: {
        // Wait between retries
        if (g_tare_retry_ms > 0 && millis() < g_tare_retry_ms) break;
        g_tare_retry_ms = 0;

        // Collect one sample per loop() iteration
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        if (r < -5000000L || r > 5000000L) break;

        g_tare_samples[g_tare_ok++] = r;

        if (g_tare_ok < 5) break;  // keep accumulating

        // 5 samples collected — check spread
        long mn = g_tare_samples[0], mx = g_tare_samples[0], sum = 0;
        for (int i = 0; i < 5; i++) {
            sum += g_tare_samples[i];
            if (g_tare_samples[i] < mn) mn = g_tare_samples[i];
            if (g_tare_samples[i] > mx) mx = g_tare_samples[i];
        }
        long spread = mx - mn;

        if (spread < 600) {
            // Accept
            g_tare_raw = sum / 5;
            Bridge.notify("log", "TARE OK = " + String(g_tare_raw) + " spread=" + String(spread));
            g_state    = STATE_CAL_WAIT;
            g_state_ms = millis();
            Bridge.notify("log", String("CAL: place 158g known weight on scale"));
            Bridge.notify("log", String("CAL: waiting 10 seconds to settle"));
        } else {
            // Reject — retry if attempts remain
            g_tare_attempt++;
            Bridge.notify("log", "TARE retry " + String(g_tare_attempt) + " spread=" + String(spread));
            if (g_tare_attempt >= 3) {
                Bridge.notify("log", String("TARE_FAIL: unstable after 3 attempts"));
                g_state    = STATE_ERROR;
                g_state_ms = millis();
            } else {
                g_tare_ok       = 0;
                g_tare_retry_ms = millis() + 2000;
            }
        }
        break;
    }

    // ── CAL_WAIT ──────────────────────────────────────────────────────────────
    case STATE_CAL_WAIT:
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        if (millis() - g_state_ms >= 10000) {
            g_cal_sum   = 0;
            g_cal_count = 0;
            g_state    = STATE_CAL_MEASURE;
            g_state_ms = millis();
        }
        break;

    // ── CAL_MEASURE ───────────────────────────────────────────────────────────
    case STATE_CAL_MEASURE: {
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        if (r < -5000000L || r > 5000000L) break;

        g_cal_sum += r;
        g_cal_count++;

        if (g_cal_count < 20) break;  // keep accumulating

        // 20 samples collected
        long raw_with_weight = g_cal_sum / g_cal_count;
        float cal_factor = (float)(raw_with_weight - g_tare_raw) / 158.0f;

        if (cal_factor < 80.0f || cal_factor > 140.0f) {
            Bridge.notify("log", "CAL_FAIL: cal_factor out of range: " + String(cal_factor, 2));
            g_state    = STATE_ERROR;
            g_state_ms = millis();
            break;
        }
        g_cal_factor = cal_factor;

        String msg = "CAL_FACTOR=";
        msg += String(g_cal_factor, 4);
        msg += " TARE=";
        msg += String(g_tare_raw);
        msg += " RAW_WITH_WEIGHT=";
        msg += String(raw_with_weight);
        msg += " EXPECTED_RANGE=80-140";
        Bridge.notify("cal_result", msg);

        led_green_on();
        delay(200);
        led_both_off();

        g_state    = STATE_NOISE_WAIT;
        g_state_ms = millis();
        Bridge.notify("log", String("NOISE: remove all weight from scale"));
        Bridge.notify("log", String("NOISE: waiting 10 seconds to settle"));
        break;
    }

    // ── NOISE_WAIT ────────────────────────────────────────────────────────────
    case STATE_NOISE_WAIT:
        if (millis() - g_blink_ms >= 500) {
            g_blink_ms = millis();
            g_blink_on = !g_blink_on;
            if (g_blink_on) { digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); }
            else            { led_both_off(); }
        }
        if (millis() - g_state_ms >= 10000) {
            g_noise_min    = 1e9f;
            g_noise_max    = -1e9f;
            g_noise_count  = 0;
            g_state    = STATE_NOISE_MEASURE;
            g_state_ms = millis();
        }
        break;

    // ── NOISE_MEASURE ─────────────────────────────────────────────────────────
    case STATE_NOISE_MEASURE: {
        // One sample per loop() iteration — non-blocking
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        if (r < -5000000L || r > 5000000L) break;
        float g = (float)(r - g_tare_raw) / g_cal_factor;
        if (g < -50.0f || g > 50.0f) break;  // outside physical range for empty scale
        g_noise_samples[g_noise_count] = g;
        if (g < g_noise_min) g_noise_min = g;
        if (g > g_noise_max) g_noise_max = g;
        g_noise_count++;

        if (g_noise_count % 50 == 0) {
            Bridge.notify("log", "NOISE: " + String(g_noise_count) + "/200 samples");
        }
        if (g_noise_count < 200) break;  // keep accumulating

        // All 200 samples collected — compute stats
        // Pass 1: mean — float accumulator only
        float pass1_sum = 0.0f;
        for (int i = 0; i < 200; i++) pass1_sum += g_noise_samples[i];
        float mean_g = pass1_sum / 200.0f;

        // Pass 2: variance from deviations
        float pass2_sum = 0.0f;
        for (int i = 0; i < 200; i++) {
            float dev = g_noise_samples[i] - mean_g;
            pass2_sum += dev * dev;
        }
        float std_g       = sqrtf(pass2_sum / 200.0f);
        float pp_g        = g_noise_max - g_noise_min;
        float window_std  = std_g / sqrtf(10.0f);
        float delta_std   = sqrtf(2.0f) * window_std;
        float threshold_g = delta_std * 4.0f;

        g_threshold_g = threshold_g;

        String msg = "MEAN=";
        msg += String(mean_g, 6);
        msg += " STD=";
        msg += String(std_g, 6);
        msg += " MIN=";
        msg += String(g_noise_min, 4);
        msg += " MAX=";
        msg += String(g_noise_max, 4);
        msg += " PP=";
        msg += String(pp_g, 4);
        msg += " WINDOW_STD=";
        msg += String(window_std, 4);
        msg += " DELTA_STD=";
        msg += String(delta_std, 4);
        msg += " THRESHOLD_G=";
        msg += String(threshold_g, 4);
        Bridge.notify("noise_result", msg);
        Bridge.notify("log", "NOISE: complete. Threshold derived = " + String(threshold_g, 4) + "g");

        led_green_on();

        g_state    = STATE_DELTA_WAIT;
        g_state_ms = millis();
        Bridge.notify("log", String("DELTA: place test weight on scale"));
        Bridge.notify("log", String("DELTA: waiting 5 seconds"));
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
            g_window_idx  = 0;
            g_window_full = false;
            g_state    = STATE_DELTA_RUNNING;
            g_state_ms = millis();
        }
        break;

    // ── DELTA_RUNNING ─────────────────────────────────────────────────────────
    case STATE_DELTA_RUNNING: {
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        if (r < -5000000L || r > 5000000L) break;

        g_window[g_window_idx % 20] = r;
        g_window_idx++;
        if (g_window_idx >= 20) g_window_full = true;

        if (g_window_full) {
            float sum_b = 0.0f, sum_a = 0.0f;
            for (int i = 0; i < 10; i++) {
                sum_b += (float)(g_window[(g_window_idx - 1 - i + 20) % 20] - g_tare_raw) / g_cal_factor;
                sum_a += (float)(g_window[(g_window_idx - 11 - i + 20) % 20] - g_tare_raw) / g_cal_factor;
            }
            float avg_b = sum_b / 10.0f;
            float avg_a = sum_a / 10.0f;
            float delta = avg_a - avg_b;
            int triggered = (fabsf(delta) > g_threshold_g) ? 1 : 0;

            String msg = "AVG_A=";
            msg += String(avg_a, 4);
            msg += " AVG_B=";
            msg += String(avg_b, 4);
            msg += " DELTA=";
            msg += String(delta, 4);
            msg += " THRESHOLD=";
            msg += String(g_threshold_g, 4);
            msg += " TRIGGERED=";
            msg += String(triggered);
            Bridge.notify("delta_reading", msg);

            if (triggered) {
                String det = "DETECTED delta=";
                det += String(delta, 4);
                det += "g threshold=";
                det += String(g_threshold_g, 4);
                det += "g";
                Bridge.notify("detection_event", det);
                led_green_on();
                delay(50);
                led_both_off();
            }
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
