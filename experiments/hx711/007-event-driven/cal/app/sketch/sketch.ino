#include "Arduino_RouterBridge.h"

#define HX711_DT_PIN      7
#define HX711_SCK_PIN     6
#define TARE_SAMPLES      5
#define TARE_STABILITY    600
#define TARE_MAX_RETRIES  3
#define TARE_RETRY_MS     2000
#define WEIGHT_SAMPLES    20
#define KNOWN_WEIGHT_G    158
#define SETTLE_MS         10000

enum State { TARE, TARE_RETRY, SETTLING, WEIGHT, DONE };
static State state = TARE;

static long     tare_samples[TARE_SAMPLES];
static int      tare_count        = 0;
static int      tare_retry_count  = 0;
static long     tare              = 0;
static uint32_t retry_start       = 0;
static uint32_t settle_start      = 0;

static long     weight_samples[WEIGHT_SAMPLES];
static int      weight_count      = 0;

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

static long hx711_read_average(int n) {
    long sum = 0;
    int  ok  = 0;
    for (int i = 0; i < n; i++) {
        long r = hx711_read_raw();
        if (r == LONG_MIN)  { delay(10); continue; }
        if (r == -1)        { delay(10); continue; }
        if (r == 0x7FFFFF)  { delay(10); continue; }
        sum += r;
        ok++;
        delay(10);
    }
    return (ok == 0) ? LONG_MIN : (sum / ok);
}

// ── setup ─────────────────────────────────────────────────────────────
void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    pinMode(HX711_DT_PIN,  INPUT_PULLUP);
    digitalWrite(HX711_SCK_PIN, LOW);

    delay(3000);
    Bridge.begin();

    Bridge.notify("log", String("=== 007-cal started ==="));
}

// ── loop: state machine ───────────────────────────────────────────────
void loop() {
    switch (state) {

    case TARE: {
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        tare_samples[tare_count++] = r;
        if (tare_count < TARE_SAMPLES) break;

        long mn = tare_samples[0], mx = tare_samples[0], sum = 0;
        for (int i = 0; i < TARE_SAMPLES; i++) {
            if (tare_samples[i] < mn) mn = tare_samples[i];
            if (tare_samples[i] > mx) mx = tare_samples[i];
            sum += tare_samples[i];
        }
        long spread = mx - mn;

        if (spread < TARE_STABILITY) {
            tare = sum / TARE_SAMPLES;
            Bridge.notify("log", String("TARE OK = ") + String(tare)
                + String(" spread=") + String(spread));
            Bridge.notify("log", String("Place 158g into cup already on scale"));
            settle_start = millis();
            state = SETTLING;
        } else {
            tare_retry_count++;
            if (tare_retry_count >= TARE_MAX_RETRIES) {
                Bridge.notify("log", String("TARE FAILED after retries — check wiring"));
                state = DONE;
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
            tare_count = 0;
            state = TARE;
        }
        break;
    }

    case SETTLING: {
        hx711_read_raw();
        if (millis() - settle_start >= SETTLE_MS) {
            Bridge.notify("log", String("Taking weight reading..."));
            state = WEIGHT;
        }
        break;
    }

    case WEIGHT: {
        long r = hx711_read_raw();
        if (r == LONG_MIN || r == -1 || r == 0x7FFFFF) break;
        weight_samples[weight_count++] = r;
        if (weight_count < WEIGHT_SAMPLES) break;

        long sum = 0;
        for (int i = 0; i < WEIGHT_SAMPLES; i++) sum += weight_samples[i];
        long weight_raw = sum / WEIGHT_SAMPLES;
        long delta      = weight_raw - tare;
        float cal       = (float)delta / (float)KNOWN_WEIGHT_G;

        Bridge.notify("log", String("WEIGHT_RAW = ") + String(weight_raw));
        Bridge.notify("log", String("DELTA = ") + String(delta));
        Bridge.notify("log", String("CAL_FACTOR = ") + String(cal, 4) + String(" raw/g"));
        Bridge.notify("log", String("Expected range: 94-105 raw/g"));
        if (cal >= 94.0f && cal <= 112.0f) {
            Bridge.notify("log", String("RESULT: PASS"));
        } else {
            Bridge.notify("log", String("RESULT: FAIL — check wiring or rerun"));
        }
        state = DONE;
        break;
    }

    case DONE:
        delay(1000);
        break;
    }
}
