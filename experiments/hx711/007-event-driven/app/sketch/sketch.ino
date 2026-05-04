#include "Arduino_RouterBridge.h"

#define HX711_DT_PIN      7
#define HX711_SCK_PIN     6
#define CAL_FACTOR        106.7f
#define THRESHOLD_G       6.0f
#define TARE_SAMPLES      5
#define TARE_STABILITY    600
#define TARE_MAX_RETRIES  3
#define TARE_RETRY_MS     2000
#define WEIGHT_SAMPLES    20

enum State { TARE, TARE_RETRY, RUNNING, FAULT };
static State state = TARE;

static float    tare              = 0.0f;
static float    last_weight_g     = 0.0f;
static int      tare_retry_count  = 0;
static uint32_t retry_start       = 0;
static int      tare_sample_count = 0;
static long     tare_samples[TARE_SAMPLES];

static int      weight_sample_count = 0;
static long     weight_samples[WEIGHT_SAMPLES];

static bool is_corrupt(long raw) {
    return (raw == LONG_MIN || raw == -1 || raw == 0x7FFFFF);
}

// ── bit-bang verbatim from home-hub ──────────────────────────────────
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

void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    digitalWrite(HX711_SCK_PIN, LOW);
    pinMode(HX711_DT_PIN, INPUT_PULLUP);
    pinMode(LED3_R, OUTPUT);
    digitalWrite(LED3_R, HIGH);  // off
    pinMode(LED3_G, OUTPUT);
    digitalWrite(LED3_G, HIGH);  // off

    delay(3000);
    Bridge.begin();

    digitalWrite(LED3_R, LOW);   // red on during tare
    Bridge.notify("log", String("Starting tare..."));
}

void loop() {
    switch (state) {

    case TARE: {
        long r = hx711_read_raw();
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
            tare = (float)sum / TARE_SAMPLES;
            last_weight_g = 0.0f;
            Bridge.notify("log", String("TARE OK=") + String((long)tare)
                + String(" spread=") + String(spread));
            digitalWrite(LED3_R, HIGH);  // red off
            digitalWrite(LED3_G, LOW);   // green on = ready
            state = RUNNING;
        } else {
            tare_retry_count++;
            if (tare_retry_count >= TARE_MAX_RETRIES) {
                Bridge.notify("log", String("TARE FAILED — check wiring"));
                digitalWrite(LED3_R, LOW);  // red solid
                state = FAULT;
            } else {
                Bridge.notify("log", String("Tare unstable spread=") + String(spread)
                    + String(" retry ") + String(tare_retry_count)
                    + String("/") + String(TARE_MAX_RETRIES));
                retry_start = millis();
                state = TARE_RETRY;
            }
        }
        break;
    }

    case TARE_RETRY: {
        hx711_read_raw();
        if (millis() - retry_start >= TARE_RETRY_MS) {
            tare_sample_count = 0;
            state = TARE;
        }
        break;
    }

    case RUNNING: {
        long r = hx711_read_raw();
        if (is_corrupt(r)) break;
        weight_samples[weight_sample_count++] = r;
        if (weight_sample_count < WEIGHT_SAMPLES) break;

        long sum = 0;
        for (int i = 0; i < WEIGHT_SAMPLES; i++) sum += weight_samples[i];
        float weight_g = ((float)sum / WEIGHT_SAMPLES - tare) / CAL_FACTOR;
        weight_sample_count = 0;

        float delta_g = weight_g - last_weight_g;
        if (delta_g < 0.0f) delta_g = -delta_g;
        if (delta_g >= THRESHOLD_G) {
            Bridge.notify("weight_event", String(weight_g, 1));
            last_weight_g = weight_g;
            digitalWrite(LED3_G, HIGH);  // brief blink off
            delay(50);
            digitalWrite(LED3_G, LOW);   // back on
        }
        break;
    }

    case FAULT:
        delay(1000);
        break;
    }
}
