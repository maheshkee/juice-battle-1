#include "Arduino_RouterBridge.h"
#include <math.h>

#define HX711_DT_PIN      7
#define HX711_SCK_PIN     6
#define CAL_FACTOR        106.7f
#define TARE_SAMPLES      5
#define TARE_STABILITY    600
#define TARE_MAX_RETRIES  3
#define TARE_RETRY_MS     2000
#define P1_COUNT          200
#define P2_GROUPS         200
#define P2_GROUP_SIZE     5
#define P3_GROUPS         100
#define P3_GROUP_SIZE     20
#define SETTLE_MS         3000

enum State {
    TARE, TARE_RETRY, SETTLE, PHASE1, PHASE1_DONE,
    PHASE2, PHASE2_DONE, PHASE3, PHASE3_DONE, DONE
};

long tare = 0;
int tare_sample_count = 0;
long tare_samples[TARE_SAMPLES];
int tare_retry_count = 0;
unsigned long settle_start = 0;
unsigned long retry_start = 0;
State state = TARE;
unsigned long next_read_ms = 0;

// phase 1 — single samples
float p1_samples[P1_COUNT];
int p1_count = 0;

// phase 2 — groups of 5 averaged
float p2_samples[P2_GROUPS];
int p2_count = 0;
float p2_group_buf[P2_GROUP_SIZE];
int p2_group_pos = 0;

// phase 3 — groups of 20 averaged
float p3_samples[P3_GROUPS];
int p3_count = 0;
float p3_group_buf[P3_GROUP_SIZE];
int p3_group_pos = 0;

struct Stats {
    float mean;
    float std_dev;
    float min_val;
    float max_val;
    float peak_to_peak;
};

Stats compute_stats(float* arr, int n) {
    Stats s;
    float sum = 0.0f;
    s.min_val = arr[0];
    s.max_val = arr[0];
    for (int i = 0; i < n; i++) {
        sum += arr[i];
        if (arr[i] < s.min_val) s.min_val = arr[i];
        if (arr[i] > s.max_val) s.max_val = arr[i];
    }
    s.mean = sum / n;
    float sq_sum = 0.0f;
    for (int i = 0; i < n; i++) {
        float d = arr[i] - s.mean;
        sq_sum += d * d;
    }
    s.std_dev = sqrt(sq_sum / n);
    s.peak_to_peak = s.max_val - s.min_val;
    return s;
}

void log_stats(const char* label, Stats s) {
    char buf[220];
    snprintf(buf, sizeof(buf),
        "%s mean=%.2f std=%.2f min=%.2f max=%.2f pp=%.2f noise_g=%.3f safe_threshold_g=%.3f",
        label, s.mean, s.std_dev, s.min_val, s.max_val, s.peak_to_peak,
        s.std_dev, 3.0f * s.std_dev);
    Bridge.notify("log", buf);
}

static bool hx711_wait_ready(uint32_t timeout_ms) {
    uint32_t t = millis();
    while (digitalRead(HX711_DT_PIN) == HIGH) {
        if ((millis() - t) > timeout_ms) return false;
    }
    return true;
}

static long hx711_read_raw() {
    if (!hx711_wait_ready(500)) return LONG_MIN;
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(HX711_SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(HX711_DT_PIN);
        digitalWrite(HX711_SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(HX711_SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(HX711_SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}

static bool is_corrupt(long raw) {
    return (raw == LONG_MIN || raw == -1 || raw == 0x7FFFFF);
}

void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    digitalWrite(HX711_SCK_PIN, LOW);
    pinMode(HX711_DT_PIN, INPUT_PULLUP);
    pinMode(LED3_R, OUTPUT);
    digitalWrite(LED3_R, HIGH);
    pinMode(LED3_G, OUTPUT);
    digitalWrite(LED3_G, HIGH);
    delay(3000);
    Bridge.begin();
    digitalWrite(LED3_R, LOW);  // red on during tare
    Bridge.notify("log", "=== 002 noise baseline started ===");
    Bridge.notify("log", "Scale must be EMPTY and UNTOUCHED for entire run");
}

void loop() {
    if (millis() < next_read_ms) return;

    switch (state) {

    case TARE: {
        long r = hx711_read_raw();
        next_read_ms = millis() + 120;
        if (is_corrupt(r)) break;
        tare_samples[tare_sample_count++] = r;
        if (tare_sample_count < TARE_SAMPLES) break;

        long mn = tare_samples[0], mx = tare_samples[0], sum = 0;
        for (int i = 0; i < TARE_SAMPLES; i++) {
            if (tare_samples[i] < mn) mn = tare_samples[i];
            if (tare_samples[i] > mx) mx = tare_samples[i];
            sum += tare_samples[i];
        }
        long spread = mx - mn;

        if (spread < TARE_STABILITY) {
            tare = sum / TARE_SAMPLES;
            char buf[64];
            snprintf(buf, sizeof(buf), "TARE OK=%ld spread=%ld", tare, spread);
            Bridge.notify("log", buf);
            digitalWrite(LED3_R, HIGH);
            digitalWrite(LED3_G, LOW);   // green on = running
            settle_start = millis();
            state = SETTLE;
        } else {
            tare_retry_count++;
            if (tare_retry_count >= TARE_MAX_RETRIES) {
                Bridge.notify("log", "TARE FAILED");
                state = DONE;
            } else {
                char buf[48];
                snprintf(buf, sizeof(buf), "Tare unstable retry %d", tare_retry_count);
                Bridge.notify("log", buf);
                retry_start = millis();
                state = TARE_RETRY;
            }
        }
        break;
    }

    case TARE_RETRY: {
        hx711_read_raw();  // keep reading to prevent HX711 freeze
        next_read_ms = millis() + 120;
        if (millis() - retry_start >= TARE_RETRY_MS) {
            tare_sample_count = 0;
            state = TARE;
        }
        break;
    }

    case SETTLE: {
        hx711_read_raw();  // keep reading to prevent HX711 freeze
        next_read_ms = millis() + 120;
        if (millis() - settle_start >= SETTLE_MS) {
            Bridge.notify("log", "--- PHASE 1: single samples (n=200) ---");
            state = PHASE1;
        }
        break;
    }

    case PHASE1: {
        long r = hx711_read_raw();
        next_read_ms = millis() + 120;
        if (is_corrupt(r)) break;
        float g = (float)(r - tare) / CAL_FACTOR;
        p1_samples[p1_count++] = g;
        if (p1_count == P1_COUNT) state = PHASE1_DONE;
        break;
    }

    case PHASE1_DONE: {
        Stats s = compute_stats(p1_samples, P1_COUNT);
        log_stats("P1-single", s);
        Bridge.notify("log", "--- PHASE 2: 5-sample averages (n=200 groups) ---");
        state = PHASE2;
        break;
    }

    case PHASE2: {
        long r = hx711_read_raw();
        next_read_ms = millis() + 120;
        if (is_corrupt(r)) break;
        float g = (float)(r - tare) / CAL_FACTOR;
        p2_group_buf[p2_group_pos++] = g;
        if (p2_group_pos == P2_GROUP_SIZE) {
            float sum = 0.0f;
            for (int i = 0; i < P2_GROUP_SIZE; i++) sum += p2_group_buf[i];
            p2_samples[p2_count++] = sum / P2_GROUP_SIZE;
            p2_group_pos = 0;
        }
        if (p2_count == P2_GROUPS) state = PHASE2_DONE;
        break;
    }

    case PHASE2_DONE: {
        Stats s = compute_stats(p2_samples, P2_GROUPS);
        log_stats("P2-avg5", s);
        Bridge.notify("log", "--- PHASE 3: 20-sample averages (n=100 groups) ---");
        state = PHASE3;
        break;
    }

    case PHASE3: {
        long r = hx711_read_raw();
        next_read_ms = millis() + 120;
        if (is_corrupt(r)) break;
        float g = (float)(r - tare) / CAL_FACTOR;
        p3_group_buf[p3_group_pos++] = g;
        if (p3_group_pos == P3_GROUP_SIZE) {
            float sum = 0.0f;
            for (int i = 0; i < P3_GROUP_SIZE; i++) sum += p3_group_buf[i];
            p3_samples[p3_count++] = sum / P3_GROUP_SIZE;
            p3_group_pos = 0;
        }
        if (p3_count == P3_GROUPS) state = PHASE3_DONE;
        break;
    }

    case PHASE3_DONE: {
        Stats p3_stats = compute_stats(p3_samples, P3_GROUPS);
        log_stats("P3-avg20", p3_stats);
        Bridge.notify("log", "=== FINAL REPORT ===");
        Bridge.notify("log", "CAL_FACTOR used: 106.7 raw/g");
        char buf[64];
        snprintf(buf, sizeof(buf), "Recommended production threshold: %.3fg",
            3.0f * p3_stats.std_dev);
        Bridge.notify("log", buf);
        Bridge.notify("log", "Current threshold in 007: 6g");
        Bridge.notify("log", "=== 002 complete ===");
        digitalWrite(LED3_G, HIGH);  // green off
        state = DONE;
        break;
    }

    case DONE:
        delay(1000);
        break;
    }
}
