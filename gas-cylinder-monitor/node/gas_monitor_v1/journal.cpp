#include <Arduino.h>
#include <string.h>
#include <math.h>
#include "journal.h"
#include "health.h"

static uint16_t  s_seq;
static uint32_t  s_boot_count;
static char      s_prev_quality[12];
static float     s_prev_grams;
static uint32_t  s_last_hb_ms;

#define LOG_PREFIX() Serial.printf("#%04u t=%.1f boot=%lu ", \
    ++s_seq, millis() / 1000.0f, s_boot_count)

void journal_init(uint32_t boot_count) {
    s_boot_count      = boot_count;
    s_seq             = 0;
    s_prev_quality[0] = '\0';
    s_prev_grams      = -1.0f;
    s_last_hb_ms      = 0;
}

void journal_boot_start() {
    LOG_PREFIX();
    Serial.println("[BOOT] event=START fw=1.0");
}

void journal_phase_complete(const char* phase, const char* result,
                             float duration_s, float extra1, float extra2,
                             float extra3) {
    (void)extra3;
    if (strcmp(phase, "SETTLE") == 0) {
        LOG_PREFIX();
        Serial.printf("[BOOT] event=PHASE_COMPLETE phase=SETTLE result=%s s=%.1f\n",
                      result, duration_s);
    } else if (strcmp(phase, "TARE") == 0) {
        LOG_PREFIX();
        Serial.printf("[BOOT] event=PHASE_COMPLETE phase=TARE result=%s mean=%.1f spread=%.1f s=%.1f\n",
                      result, extra1, extra2, duration_s);
    } else if (strcmp(phase, "NOISE") == 0) {
        LOG_PREFIX();
        Serial.printf("[BOOT] event=PHASE_COMPLETE phase=NOISE result=%s s=%.1f\n",
                      result, duration_s);
    } else if (strcmp(phase, "CAL") == 0) {
        LOG_PREFIX();
        Serial.printf("[BOOT] event=PHASE_COMPLETE phase=CAL result=%s cal_factor=%.4f s=%.1f\n",
                      result, extra1, duration_s);
    }
}

void journal_boot_complete(float total_s, float cal_factor,
                            float sigma, float tare) {
    LOG_PREFIX();
    Serial.printf("[BOOT] event=BOOT_COMPLETE total_s=%.1f cal=%.4f sigma=%.2f tare=%.1f\n",
                  total_s, cal_factor, sigma, tare);
}

void journal_run(float grams, float sigma, const HealthResult& health) {
    if (strcmp(health.quality, s_prev_quality) != 0) {
        LOG_PREFIX();
        Serial.printf("[RUN] event=QUALITY_CHANGE from=%s to=%s grams=%.1f sigma=%.2f diagnosis=%s\n",
                      s_prev_quality[0] ? s_prev_quality : "NONE",
                      health.quality, grams, sigma, health.diagnosis);
        strncpy(s_prev_quality, health.quality, sizeof(s_prev_quality) - 1);
        s_prev_quality[sizeof(s_prev_quality) - 1] = '\0';
    }

    if (s_prev_grams >= 0.0f && fabsf(grams - s_prev_grams) > 4.0f * sigma) {
        float delta = grams - s_prev_grams;
        const char* type = delta > 0.0f ? "PLACED" : "REMOVED";
        LOG_PREFIX();
        Serial.printf("[RUN] event=WEIGHT_EVENT type=%s grams=%.1f prev=%.1f delta=%.1f\n",
                      type, grams, s_prev_grams, delta);
    }

    s_prev_grams = grams;
}

void journal_heartbeat_tick(float grams, float sigma,
                             const HealthResult& health) {
    if (millis() - s_last_hb_ms >= 30000) {
        LOG_PREFIX();
        Serial.printf("[HB] event=HEARTBEAT grams=%.1f quality=%s sigma=%.2f uptime=%.1f\n",
                      grams, health.quality, sigma, millis() / 1000.0f);
        s_last_hb_ms = millis();
    }
}

void journal_phase_fail(const char* phase, const char* reason, float value) {
    LOG_PREFIX();
    Serial.printf("[FAULT] event=PHASE_FAIL phase=%s reason=%s value=%.2f\n",
                  phase, reason, value);
}
