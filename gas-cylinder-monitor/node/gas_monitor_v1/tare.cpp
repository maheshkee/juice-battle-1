#include "tare.h"
#include <SPIFFS.h>
#include <ArduinoJson.h>

#define WINDOW_SIZE        10
#define SPREAD_GOOD        500L
#define SPREAD_DEGRADED    2000L
#define PHASE2_SAMPLES     200
#define PHASE1_TIMEOUT_MS  30000UL

enum TarePhase { PHASE1, PHASE2 };

static TarePhase s_phase;
static long      s_window[WINDOW_SIZE];
static int       s_w_idx;
static int       s_w_count;
static float     s_p2_sum;
static int       s_p2_count;
static float     s_p1_spread;
static bool      s_degraded;
static uint32_t  s_p1_start_ms;

void tare_init() {
    s_phase       = PHASE1;
    s_w_idx       = 0;
    s_w_count     = 0;
    s_p2_sum      = 0.0f;
    s_p2_count    = 0;
    s_p1_spread   = 0.0f;
    s_degraded    = false;
    s_p1_start_ms = millis();
    for (int i = 0; i < WINDOW_SIZE; i++) s_window[i] = 0;
}

static long window_spread() {
    long wmin = s_window[0];
    long wmax = s_window[0];
    for (int i = 1; i < WINDOW_SIZE; i++) {
        if (s_window[i] < wmin) wmin = s_window[i];
        if (s_window[i] > wmax) wmax = s_window[i];
    }
    return wmax - wmin;
}

TareResult tare_update(long raw) {
    TareResult result;
    result.tare_raw     = 0.0f;
    result.status       = TARE_BUSY;
    result.diagnosis[0] = '\0';

    if (s_phase == PHASE1) {
        s_window[s_w_idx] = raw;
        s_w_idx = (s_w_idx + 1) % WINDOW_SIZE;
        if (s_w_count < WINDOW_SIZE) s_w_count++;

        if (s_w_count < WINDOW_SIZE) {
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Settling: filling %d/%d", s_w_count, WINDOW_SIZE);
            return result;
        }

        if (millis() - s_p1_start_ms >= PHASE1_TIMEOUT_MS) {
            result.status = TARE_FAILED;
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Settle timeout");
            return result;
        }

        long spread = window_spread();

        if (spread < SPREAD_GOOD) {
            s_p1_spread = (float)spread;
            s_degraded  = false;
            s_phase     = PHASE2;
            s_p2_sum    = 0.0f;
            s_p2_count  = 0;
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Settling: spread=%ld", spread);
            return result;
        }

        if (spread < SPREAD_DEGRADED) {
            s_p1_spread = (float)spread;
            s_degraded  = true;
            s_phase     = PHASE2;
            s_p2_sum    = 0.0f;
            s_p2_count  = 0;
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Settling: spread=%ld", spread);
            return result;
        }

        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Settling: spread=%ld", spread);
        return result;
    }

    /* PHASE2 */
    s_p2_sum += (float)raw;
    s_p2_count++;

    if (s_p2_count < PHASE2_SAMPLES) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Collecting: %d/%d", s_p2_count, PHASE2_SAMPLES);
        return result;
    }

    float mean      = s_p2_sum / (float)PHASE2_SAMPLES;
    result.tare_raw = mean;
    result.status   = s_degraded ? TARE_DEGRADED : TARE_SUCCESS;

    if (s_degraded) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Degraded: spread=%.0f - noisy environment", s_p1_spread);
    } else {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Tare OK: mean=%.1f spread=%.0f", mean, s_p1_spread);
    }

    return result;
}

bool tare_save_to_spiffs(float tare_raw) {
    StaticJsonDocument<4096> doc;
    File fr = SPIFFS.open("/config.json", "r");
    if (fr) {
        deserializeJson(doc, fr);
        fr.close();
    }
    doc["tare_raw"] = tare_raw;
    File fw = SPIFFS.open("/config.json", "w");
    if (!fw) return false;
    serializeJson(doc, fw);
    fw.close();
    Serial.printf("[TARE] Saved tare_raw=%.1f to SPIFFS\n", tare_raw);
    return true;
}

bool tare_load_from_spiffs(float* tare_raw_out) {
    File f = SPIFFS.open("/config.json", "r");
    if (!f) return false;
    StaticJsonDocument<4096> doc;
    DeserializationError err = deserializeJson(doc, f);
    f.close();
    if (err) return false;
    if (!doc.containsKey("tare_raw")) return false;
    float v = doc["tare_raw"].as<float>();
    // Sanity: 3-cell raw tare is a large negative value (platform at zero reads ~ -100k to -200k raw)
    if (v < -200000.0f || v > -50000.0f) return false;
    *tare_raw_out = v;
    Serial.printf("[TARE] Loaded tare_raw=%.1f from SPIFFS\n", *tare_raw_out);
    return true;
}
