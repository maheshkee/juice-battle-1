#include "cal.h"
#include <SPIFFS.h>
#include <ArduinoJson.h>

#define WEIGHT_DETECT_RAW   8000.0f
#define SAMPLE_COUNT        50
#define CAL_MIN             15.0f
#define CAL_MAX             80.0f
#define PROMPT_INTERVAL_MS  5000UL
#define SERIAL_TIMEOUT_MS   30000
#define CONFIG_PATH         "/config.json"
#define JSON_DOC_SIZE       4096

enum CalPhase { CAL_PHASE_WAIT, CAL_PHASE_SAMPLE };

static CalPhase s_phase;
static float    s_tare_raw;
static uint32_t s_last_prompt_ms;
static bool     s_first_prompt;
static float    s_known_weight_g;
static float    s_sample_sum;
static int      s_sample_count;

void cal_init(float tare_raw) {
    s_phase          = CAL_PHASE_WAIT;
    s_tare_raw       = tare_raw;
    s_last_prompt_ms = 0;
    s_first_prompt   = true;
    s_known_weight_g = 0.0f;
    s_sample_sum     = 0.0f;
    s_sample_count   = 0;
}

CalResult cal_update(long raw) {
    CalResult result;
    result.cal_factor   = 0.0f;
    result.status       = CAL_BUSY;
    result.diagnosis[0] = '\0';

    if (s_phase == CAL_PHASE_WAIT) {
        if (s_first_prompt || (millis() - s_last_prompt_ms >= PROMPT_INTERVAL_MS)) {
            Serial.println("[CAL] Place known weight on platform and wait...");
            s_last_prompt_ms = millis();
            s_first_prompt   = false;
        }

        float net = (float)raw - s_tare_raw;
        if (net <= WEIGHT_DETECT_RAW) {
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Waiting for weight on platform");
            return result;
        }

        Serial.println("[CAL] Weight detected. Enter known weight in grams:");
        while (Serial.available()) Serial.read();
        char wbuf[32];
        Serial.setTimeout(SERIAL_TIMEOUT_MS);
        int wlen = Serial.readBytesUntil('\n', wbuf, sizeof(wbuf) - 1);
        Serial.setTimeout(1000);
        wbuf[wlen] = '\0';
        s_known_weight_g = atof(wbuf);

        if (s_known_weight_g <= 0.0f) {
            result.status = CAL_FAILED;
            snprintf(result.diagnosis, sizeof(result.diagnosis),
                     "Invalid weight entered: %.2f", s_known_weight_g);
            return result;
        }

        s_phase        = CAL_PHASE_SAMPLE;
        s_sample_sum   = 0.0f;
        s_sample_count = 0;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Weight detected, collecting...");
        return result;
    }

    /* CAL_PHASE_SAMPLE */
    s_sample_sum += (float)raw;
    s_sample_count++;

    if (s_sample_count < SAMPLE_COUNT) {
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "Sampling: %d/%d", s_sample_count, SAMPLE_COUNT);
        return result;
    }

    float mean_raw   = s_sample_sum / (float)SAMPLE_COUNT;
    float cal_factor = (mean_raw - s_tare_raw) / s_known_weight_g;

    if (cal_factor < CAL_MIN || cal_factor > CAL_MAX) {
        result.status = CAL_FAILED;
        snprintf(result.diagnosis, sizeof(result.diagnosis),
                 "cal_factor %.2f out of range [%.0f,%.0f]",
                 cal_factor, CAL_MIN, CAL_MAX);
        return result;
    }

    result.cal_factor = cal_factor;
    result.status     = CAL_SUCCESS;
    snprintf(result.diagnosis, sizeof(result.diagnosis),
             "cal_factor=%.4f", cal_factor);
    return result;
}

bool cal_save(float cal_factor) {
    StaticJsonDocument<JSON_DOC_SIZE> doc;

    File fr = SPIFFS.open(CONFIG_PATH, "r");
    if (fr) {
        DeserializationError err = deserializeJson(doc, fr);
        fr.close();
        if (err) doc.clear();
    }

    JsonArray history = doc["cal_history"];
    if (history.isNull()) {
        history = doc.createNestedArray("cal_history");
    }

    int boot_num = 1;
    if (history.size() > 0) {
        boot_num = history[history.size() - 1]["boot"].as<int>() + 1;
    }

    JsonObject entry = history.createNestedObject();
    entry["boot"]       = boot_num;
    entry["cal_factor"] = cal_factor;

    File fw = SPIFFS.open(CONFIG_PATH, "w");
    if (!fw) return false;
    serializeJson(doc, fw);
    fw.close();
    return true;
}

float cal_load_last() {
    File f = SPIFFS.open(CONFIG_PATH, "r");
    if (!f) return 0.0f;

    StaticJsonDocument<JSON_DOC_SIZE> doc;
    DeserializationError err = deserializeJson(doc, f);
    f.close();
    if (err) return 0.0f;

    JsonArray history = doc["cal_history"];
    if (history.isNull() || history.size() == 0) return 0.0f;
    return history[history.size() - 1]["cal_factor"].as<float>();
}
