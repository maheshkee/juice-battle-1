// hw_test.ino — standalone hardware diagnostic for 3-cell ESP32-C3 + HX711
// Required: ArduinoJson by Benoit Blanchon
// Board: ESP32C3 Dev Module, esp32 by Espressif v3.0.7, USB CDC On Boot: ENABLED
// No dependency on gas_monitor_v1 modules. Single file only.

#include <SPIFFS.h>
#include <ArduinoJson.h>
#include <cstdio>
#include <math.h>

// ---- Constants ----
#define PIN_DOUT             4
#define PIN_SCK              3
#define HX711_TIMEOUT_MS     200
#define ADC_READS            100
#define NOISE_READS          100
#define TARE_READS           200
#define ACCURACY_READS       50
#define CAL_MIN              30.0f
#define CAL_MAX              45.0f
#define CAL_FALLBACK         36.0f
#define SIGMA_PASS_G         6.0f
#define SIGMA_WARN_G         8.0f
#define DRIFT_PASS_G         5.0f
#define DRIFT_WARN_G         15.0f
#define ACCURACY_PASS_PCT    5.0f
#define ACCURACY_WARN_PCT    10.0f
#define CORRUPT_RATE_LIMIT   0.05f
#define CREEP_SETTLE_MS      3000UL
#define SERIAL_TIMEOUT_MS    30000UL
#define DOTS_PER_LINE        20
#define RATIO_1CELL_LO       0.45f
#define RATIO_1CELL_HI       0.55f
#define RATIO_2CELL_LO       0.60f
#define RATIO_2CELL_HI       0.72f
#define RATIO_MECH_HI        1.15f

#define STATUS_PASS 0
#define STATUS_WARN 1
#define STATUS_FAIL 2

struct PhaseResult { uint8_t status; char msg[128]; };

enum DiagState {
    STATE_BANNER,
    STATE_P1_ADC,
    STATE_P2_NOISE,
    STATE_P3_TARE,
    STATE_P4_INPUT,
    STATE_P4_SETTLE,
    STATE_P4_MEASURE,
    STATE_REPORT
};

static DiagState   g_state      = STATE_BANNER;
static float       g_cal_factor = CAL_FALLBACK;
static float       g_tare_raw   = 0.0f;
static float       g_known_g    = 0.0f;
static PhaseResult g_r1, g_r2, g_r3, g_r4;

// ---- HX711 bit-bang ----
static long hx711_read_raw() {
    uint32_t t0 = millis();
    while (digitalRead(PIN_DOUT) == HIGH) {
        if (millis() - t0 >= HX711_TIMEOUT_MS) return LONG_MIN;
    }
    long val = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(PIN_SCK, HIGH);
        delayMicroseconds(1);
        val = (val << 1) | digitalRead(PIN_DOUT);
        digitalWrite(PIN_SCK, LOW);
        delayMicroseconds(1);
    }
    // 25th pulse — Channel A Gain 128
    digitalWrite(PIN_SCK, HIGH);
    delayMicroseconds(1);
    digitalWrite(PIN_SCK, LOW);
    delayMicroseconds(1);
    interrupts();
    if (val & 0x800000L) val |= 0xFF000000L;  // sign-extend bit 23
    return val;
}

static bool is_corrupt(long v) {
    return v == LONG_MIN || v == -1L || v == 0x7FFFFFL;
}

// ---- SPIFFS cal load ----
static float load_cal_spiffs() {
    File f = SPIFFS.open("/config.json", "r");
    if (!f) return -1.0f;
    StaticJsonDocument<4096> doc;
    DeserializationError err = deserializeJson(doc, f);
    f.close();
    if (err) return -1.0f;
    JsonArray arr = doc["cal_history"].as<JsonArray>();
    if (!arr || arr.size() == 0) return -1.0f;
    float v = arr[arr.size() - 1].as<float>();
    return (v >= CAL_MIN && v <= CAL_MAX) ? v : -1.0f;
}

// ---- Dot progress ----
static void dot(int n) {
    Serial.print('.');
    if ((n + 1) % DOTS_PER_LINE == 0) Serial.println();
}

// ---- Setup ----
void setup() {
    Serial.begin(115200);
    delay(200);
    SPIFFS.begin(true);
    pinMode(PIN_DOUT, INPUT_PULLUP);
    pinMode(PIN_SCK, OUTPUT);
    digitalWrite(PIN_SCK, LOW);
    float c = load_cal_spiffs();
    if (c > 0.0f) g_cal_factor = c;
}

// ---- Main loop ----
void loop() {
    switch (g_state) {

    // ---- Banner ----
    case STATE_BANNER: {
        Serial.println();
        Serial.println("========================================");
        Serial.println(" HW_TEST  3-cell ESP32-C3 + HX711");
        Serial.println("========================================");
        Serial.printf(" cal: %.2f raw/g (%s)\n", g_cal_factor,
                      g_cal_factor == CAL_FALLBACK ? "fallback" : "SPIFFS");
        Serial.println(" DOUT=GPIO4  SCK=GPIO3");
        Serial.println();
        Serial.println(" P1 ADC quality    — no weight needed");
        Serial.println(" P2 Noise floor    — no weight needed");
        Serial.println(" P3 Tare stability — no weight needed (~20s)");
        Serial.println(" P4 Accuracy       — known weight required");
        Serial.println("----------------------------------------");
        g_state = STATE_P1_ADC;
        break;
    }

    // ---- P1: ADC quality ----
    case STATE_P1_ADC: {
        static int    n        = 0;
        static int    corrupt  = 0;
        static long   first_v  = LONG_MIN;
        static bool   all_same = true;
        static long   vmin     = LONG_MAX;
        static long   vmax     = LONG_MIN;
        static double vsum     = 0.0;
        static int    vvalid   = 0;
        static bool   hdr      = false;

        if (!hdr) { hdr = true; Serial.print("[P1] ADC quality: "); }

        if (n >= ADC_READS) {
            Serial.println();
            float rate  = (float)corrupt / ADC_READS;
            float vmean = vvalid ? (float)(vsum / vvalid) : 0.0f;
            bool  stuck = all_same && vvalid > 1;
            bool  ok    = (rate < CORRUPT_RATE_LIMIT) && !stuck;
            g_r1.status = ok ? STATUS_PASS : STATUS_FAIL;
            snprintf(g_r1.msg, sizeof(g_r1.msg),
                "corrupt=%.1f%% stuck=%s min=%ld max=%ld mean=%.0f",
                rate * 100.0f, stuck ? "YES" : "NO", vmin, vmax, vmean);
            Serial.printf("[P1] %s  %s\n\n", ok ? "PASS" : "FAIL", g_r1.msg);
            g_state = STATE_P2_NOISE;
            break;
        }

        long v = hx711_read_raw();
        dot(n); n++;
        if (is_corrupt(v)) { corrupt++; break; }
        if (first_v == LONG_MIN) first_v = v;
        else if (v != first_v)   all_same = false;
        if (v < vmin) vmin = v;
        if (v > vmax) vmax = v;
        vsum += v; vvalid++;
        break;
    }

    // ---- P2: Noise floor ----
    case STATE_P2_NOISE: {
        static int    n     = 0;
        static int    valid = 0;
        static double wn    = 0.0, wmean = 0.0, wM2 = 0.0;
        static long   rmin  = LONG_MAX;
        static long   rmax  = LONG_MIN;
        static bool   hdr   = false;

        if (!hdr) { hdr = true; Serial.print("[P2] Noise floor: "); }

        if (valid >= NOISE_READS) {
            Serial.println();
            float sigma_raw = (wn > 1) ? sqrtf((float)(wM2 / wn)) : 0.0f;
            float sigma_g   = sigma_raw / g_cal_factor;
            float pp_g      = (float)(rmax - rmin) / g_cal_factor;

            const char* v   = "PASS";
            g_r2.status     = STATUS_PASS;
            if      (sigma_g >= SIGMA_WARN_G) { v = "FAIL"; g_r2.status = STATUS_FAIL; }
            else if (sigma_g >= SIGMA_PASS_G) { v = "WARN"; g_r2.status = STATUS_WARN; }
            snprintf(g_r2.msg, sizeof(g_r2.msg), "sigma=%.2fg pp=%.1fg%s",
                sigma_g, pp_g,
                sigma_g >= SIGMA_PASS_G ? " [BLE off? vibrations?]" : "");
            Serial.printf("[P2] %s  %s\n\n", v, g_r2.msg);
            g_state = STATE_P3_TARE;
            break;
        }

        long r = hx711_read_raw();
        dot(n); n++;
        if (is_corrupt(r)) break;
        // Welford online variance — numerically stable
        wn++;
        double delta = (double)r - wmean;
        wmean += delta / wn;
        wM2   += delta * ((double)r - wmean);
        if (r < rmin) rmin = r;
        if (r > rmax) rmax = r;
        valid++;
        break;
    }

    // ---- P3: Tare stability ----
    case STATE_P3_TARE: {
        static int    n     = 0;
        static int    valid = 0;
        static double sum1  = 0.0;
        static double sum2  = 0.0;
        static bool   hdr   = false;

        if (!hdr) { hdr = true; Serial.print("[P3] Tare stability: "); }

        if (valid >= TARE_READS) {
            Serial.println();
            float h1    = (float)(sum1 / (TARE_READS / 2));
            float h2    = (float)(sum2 / (TARE_READS / 2));
            float drift = fabsf(h2 - h1) / g_cal_factor;
            g_tare_raw  = (float)((sum1 + sum2) / TARE_READS);

            const char* v   = "PASS";
            g_r3.status     = STATUS_PASS;
            if      (drift >= DRIFT_WARN_G) { v = "FAIL"; g_r3.status = STATUS_FAIL; }
            else if (drift >= DRIFT_PASS_G) { v = "WARN"; g_r3.status = STATUS_WARN; }
            snprintf(g_r3.msg, sizeof(g_r3.msg),
                "tare=%.0f drift=%.2fg (h1=%.0f h2=%.0f)",
                g_tare_raw, drift, h1, h2);
            Serial.printf("[P3] %s  %s\n\n", v, g_r3.msg);
            g_state = STATE_P4_INPUT;
            break;
        }

        long r = hx711_read_raw();
        dot(n); n++;
        if (is_corrupt(r)) break;
        if (valid < TARE_READS / 2) sum1 += r;
        else                         sum2 += r;
        valid++;
        break;
    }

    // ---- P4a: Wait for user input ----
    case STATE_P4_INPUT: {
        static bool     hdr = false;
        static uint32_t t0  = 0;

        if (!hdr) {
            hdr = true;
            t0  = millis();
            Serial.println("[P4] Accuracy test.");
            Serial.println("     Place known weight on empty platform.");
            Serial.println("     Type mass in grams then Enter (30s timeout):");
        }

        if (millis() - t0 >= SERIAL_TIMEOUT_MS) {
            g_r4.status = STATUS_FAIL;
            snprintf(g_r4.msg, sizeof(g_r4.msg), "timeout — no serial input");
            Serial.println("\n[P4] FAIL  timeout");
            g_state = STATE_REPORT;
            break;
        }

        if (!Serial.available()) break;

        String line = Serial.readStringUntil('\n');
        line.trim();
        float val = line.toFloat();
        if (val <= 0.0f) {
            Serial.println("     Invalid — enter positive grams (e.g. 1000.0):");
            break;
        }
        g_known_g = val;
        Serial.printf("     known=%.1fg — settling %lus...\n",
                      g_known_g, (unsigned long)(CREEP_SETTLE_MS / 1000));
        g_state = STATE_P4_SETTLE;
        break;
    }

    // ---- P4b: Creep settle delay ----
    case STATE_P4_SETTLE: {
        static uint32_t t0  = 0;
        static bool     set = false;
        if (!set) { set = true; t0 = millis(); }
        if (millis() - t0 >= CREEP_SETTLE_MS) {
            Serial.print("[P4] Measuring: ");
            g_state = STATE_P4_MEASURE;
        }
        break;
    }

    // ---- P4c: Accuracy measurement ----
    case STATE_P4_MEASURE: {
        static int    n     = 0;
        static int    valid = 0;
        static double sum   = 0.0;

        if (valid >= ACCURACY_READS) {
            Serial.println();
            float raw_mean    = (float)(sum / valid);
            float net_raw     = raw_mean - g_tare_raw;
            float measured_g  = net_raw / g_cal_factor;
            float error_pct   = fabsf(measured_g - g_known_g) / g_known_g * 100.0f;
            float derived_cal = (g_known_g > 0.0f) ? (net_raw / g_known_g) : 0.0f;
            bool  cal_ok      = (derived_cal >= CAL_MIN && derived_cal <= CAL_MAX);

            const char* v   = "PASS";
            g_r4.status     = STATUS_PASS;
            if (error_pct >= ACCURACY_WARN_PCT || !cal_ok)
                { v = "FAIL"; g_r4.status = STATUS_FAIL; }
            else if (error_pct >= ACCURACY_PASS_PCT)
                { v = "WARN"; g_r4.status = STATUS_WARN; }

            char diag[64] = "";
            if (!cal_ok) {
                float ratio = (g_cal_factor > 0.0f) ? derived_cal / g_cal_factor : 0.0f;
                if      (ratio >= RATIO_1CELL_LO && ratio <= RATIO_1CELL_HI)
                    snprintf(diag, sizeof(diag), " [1-cell open?]");
                else if (ratio >= RATIO_2CELL_LO && ratio <= RATIO_2CELL_HI)
                    snprintf(diag, sizeof(diag), " [2-cell open?]");
                else if (ratio > RATIO_MECH_HI)
                    snprintf(diag, sizeof(diag), " [mechanical constraint?]");
                else
                    snprintf(diag, sizeof(diag), " [cal=%.1f not in %.0f-%.0f]",
                             derived_cal, CAL_MIN, CAL_MAX);
            }
            snprintf(g_r4.msg, sizeof(g_r4.msg),
                "known=%.1fg measured=%.1fg err=%.1f%% cal=%.2f%s",
                g_known_g, measured_g, error_pct, derived_cal, diag);
            Serial.printf("[P4] %s  %s\n\n", v, g_r4.msg);
            g_state = STATE_REPORT;
            break;
        }

        long r = hx711_read_raw();
        dot(n); n++;
        if (is_corrupt(r)) break;
        sum += r; valid++;
        break;
    }

    // ---- Final report ----
    case STATE_REPORT: {
        static bool done = false;
        if (done) break;
        done = true;

        PhaseResult* results[] = { &g_r1, &g_r2, &g_r3, &g_r4 };
        const char*  labels[]  = { "P1 ADC   ", "P2 Noise ", "P3 Tare  ", "P4 Accy  " };
        int fails = 0, warns = 0;
        for (int i = 0; i < 4; i++) {
            if      (results[i]->status == STATUS_FAIL) fails++;
            else if (results[i]->status == STATUS_WARN) warns++;
        }

        Serial.println("========================================");
        Serial.println(" DIAGNOSTIC SUMMARY");
        Serial.println("========================================");
        for (int i = 0; i < 4; i++) {
            const char* s = results[i]->status == STATUS_PASS ? "PASS" :
                            results[i]->status == STATUS_WARN ? "WARN" : "FAIL";
            Serial.printf(" [%s] %s %s\n", s, labels[i], results[i]->msg);
        }
        Serial.println("----------------------------------------");
        Serial.printf(" fails=%d  warns=%d\n", fails, warns);
        if (fails == 0) Serial.println(" *** HARDWARE PASS ***");
        else            Serial.println(" *** HARDWARE FAIL ***");
        Serial.println("========================================");
        Serial.println(" Halted. Reset device to run again.");
        while (true) delay(1000);
        break;
    }

    }
}
