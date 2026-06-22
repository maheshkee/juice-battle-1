#include <Arduino.h>
#include <SPIFFS.h>
#include <string.h>
#include <math.h>
#include "journal.h"
#include "health.h"

static uint16_t  s_seq;
static uint32_t  s_boot_count;
static char      s_prev_quality[12];
static float     s_prev_grams;
static uint32_t  s_last_hb_ms;

uint32_t g_journal_file_bytes = 0;
bool     g_transfer_pending   = false;

#define LOG_PREFIX() Serial.printf("#%04u t=%.1f boot=%lu ", \
    ++s_seq, millis() / 1000.0f, s_boot_count)

static void journal_append(const char* line) {
    File f = SPIFFS.open("/node_journal.log", FILE_APPEND);
    if (!f) return;
    f.print(line);
    f.close();
    uint32_t len = (uint32_t)strlen(line);
    g_journal_file_bytes += len;
    if (g_journal_file_bytes >= JOURNAL_TRANSFER_THRESHOLD_BYTES) {
        g_transfer_pending = true;
    }
}

void journal_init(uint32_t boot_count) {
    s_boot_count      = boot_count;
    s_seq             = 0;
    s_prev_quality[0] = '\0';
    s_prev_grams      = -1.0f;
    s_last_hb_ms      = 0;
    g_journal_file_bytes = 0;
    g_transfer_pending   = false;
    File jf = SPIFFS.open("/node_journal.log", "r");
    if (jf) {
        g_journal_file_bytes = (uint32_t)jf.size();
        jf.close();
    }
    Serial.printf("[DBG] journal_init boot=%lu file_bytes=%u pending=%d\n",
                  (unsigned long)boot_count,
                  g_journal_file_bytes,
                  (int)g_transfer_pending);
}

void journal_boot_start() {
    char _buf[192];
    snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=START fw=1.0\n",
             ++s_seq, millis() / 1000.0f, s_boot_count);
    Serial.print(_buf);
    journal_append(_buf);
}

void journal_phase_complete(const char* phase, const char* result,
                             float duration_s, float extra1, float extra2,
                             float extra3) {
    (void)extra3;
    if (strcmp(phase, "SETTLE") == 0) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=PHASE_COMPLETE phase=SETTLE result=%s s=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count, result, duration_s);
        Serial.print(_buf);
        journal_append(_buf);
    } else if (strcmp(phase, "TARE") == 0) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=PHASE_COMPLETE phase=TARE result=%s mean=%.1f spread=%.1f s=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count, result, extra1, extra2, duration_s);
        Serial.print(_buf);
        journal_append(_buf);
    } else if (strcmp(phase, "NOISE") == 0) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=PHASE_COMPLETE phase=NOISE result=%s s=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count, result, duration_s);
        Serial.print(_buf);
        journal_append(_buf);
    } else if (strcmp(phase, "CAL") == 0) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=PHASE_COMPLETE phase=CAL result=%s cal_factor=%.4f s=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count, result, extra1, duration_s);
        Serial.print(_buf);
        journal_append(_buf);
    }
}

void journal_boot_complete(float total_s, float cal_factor,
                            float sigma, float tare) {
    char _buf[192];
    snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=BOOT_COMPLETE total_s=%.1f cal=%.4f sigma=%.2f tare=%.1f\n",
             ++s_seq, millis() / 1000.0f, s_boot_count, total_s, cal_factor, sigma, tare);
    Serial.print(_buf);
    journal_append(_buf);
}

void journal_run(float grams, float sigma, const HealthResult& health,
                 WeightEvent event, float delta) {
    if (strcmp(health.quality, s_prev_quality) != 0) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [RUN] event=QUALITY_CHANGE from=%s to=%s grams=%.1f sigma=%.2f diagnosis=%s\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count,
                 s_prev_quality[0] ? s_prev_quality : "NONE",
                 health.quality, grams, sigma, health.diagnosis);
        Serial.print(_buf);
        journal_append(_buf);
        strncpy(s_prev_quality, health.quality, sizeof(s_prev_quality) - 1);
        s_prev_quality[sizeof(s_prev_quality) - 1] = '\0';
    }

    if (event == WEIGHT_EVENT_PLACED || event == WEIGHT_EVENT_REMOVED) {
        const char* type = (event == WEIGHT_EVENT_PLACED) ? "PLACED" : "REMOVED";
        char _buf2[192];
        snprintf(_buf2, sizeof(_buf2), "#%04u t=%.1f boot=%lu [RUN] event=WEIGHT_EVENT type=%s grams=%.1f prev=%.1f delta=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count,
                 type, grams, s_prev_grams, delta);
        Serial.print(_buf2);
        journal_append(_buf2);
    }

    s_prev_grams = grams;
}

void journal_heartbeat_tick(float grams, float sigma,
                             const HealthResult& health) {
    if (millis() - s_last_hb_ms >= 30000) {
        char _buf[192];
        snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [HB] event=HEARTBEAT grams=%.1f quality=%s sigma=%.2f uptime=%.1f\n",
                 ++s_seq, millis() / 1000.0f, s_boot_count,
                 grams, health.quality, sigma, millis() / 1000.0f);
        Serial.print(_buf);
        journal_append(_buf);
        s_last_hb_ms = millis();
    }
}

void journal_phase_fail(const char* phase, const char* reason, float value) {
    char _buf[192];
    snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [FAULT] event=PHASE_FAIL phase=%s reason=%s value=%.2f\n",
             ++s_seq, millis() / 1000.0f, s_boot_count, phase, reason, value);
    Serial.print(_buf);
    journal_append(_buf);
}

void journal_tare_wait_result(const char* result) {
    char _buf[192];
    snprintf(_buf, sizeof(_buf), "#%04u t=%.1f boot=%lu [BOOT] event=PHASE_COMPLETE phase=TARE_WAIT result=%s\n",
             ++s_seq, millis() / 1000.0f, s_boot_count, result);
    Serial.print(_buf);
    journal_append(_buf);
}

void journal_tare_check(const char* result, float delta_g) {
    ++s_seq;
    char _buf[256];
    snprintf(_buf, sizeof(_buf),
             "#%04u t=%.1f boot=%lu [BOOT] event=TARE_CHECK result=%s delta=%.1fg\n",
             s_seq, millis() / 1000.0f, (unsigned long)s_boot_count,
             result, delta_g);
    Serial.print(_buf);
    journal_append(_buf);
}

void journal_retare(float new_tare, float old_tare) {
    ++s_seq;
    char _buf[256];
    snprintf(_buf, sizeof(_buf),
             "#%04u t=%.1f boot=%lu [RUN] event=RETARE result=OK"
             " new_tare=%.1f old_tare=%.1f\n",
             s_seq, millis() / 1000.0f, (unsigned long)s_boot_count,
             new_tare, old_tare);
    Serial.print(_buf);
    journal_append(_buf);
}
