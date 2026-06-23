// gas_monitor_v1 - Gas Cylinder Monitor Node Sketch
// Required Arduino libraries (install via Library Manager before compiling):
//   NimBLE-Arduino by h2zero      - BLE GATT server
//   ArduinoJson by Benoit Blanchon - config.json SPIFFS read/write
// Board: ESP32C3 Dev Module, esp32 by Espressif v3.0.7, USB CDC On Boot: ENABLED

#include <SPIFFS.h>
#include <ArduinoJson.h>
#include "hx711.h"
#include "tare.h"
#include "noise.h"
#include "cal.h"
#include "weight.h"
#include "ble.h"
#include "health.h"
#include "journal.h"
#include "log_transfer.h"

enum BootState {
    STATE_SETTLE,
    STATE_TARE_WAIT,
    STATE_TARE,
    STATE_NOISE,
    STATE_CAL,
    STATE_RUNNING,
    STATE_RETARE
};

static float     g_tare_raw        = 0.0f;
static float     g_cal_factor      = 0.0f;
static float     g_sigma_g         = 0.0f;
static BootState g_state           = STATE_SETTLE;
static uint32_t  g_last_tick       = 0;
static uint32_t  g_settle_start_ms = 0;
static uint32_t  g_boot_count      = 0;
// 1C timing globals
static uint32_t  phase_start_ms    = 0;

// 1B health module globals
static HealthResult g_health;
// -1.0f sentinel: 0.0f is a valid gross weight (empty platform reads ~0g),
// so 0.0f cannot be used to mean "no previous reading". -1.0f is physically
// impossible for a gross weight and is unambiguous as a first-tick marker.
static float g_prev_gross_g      = -1.0f;
// -1.0f sentinel: 0.0f could appear in a corrupt config.json. cal_factor is
// always a large positive number (~37 raw/g), so -1.0f is impossible and safe.
static float g_prev_cal_factor   = -1.0f;
// -1.0f sentinel: same reasoning as g_prev_cal_factor. sigma is always >= 0.
// A corrupt config.json could produce 0.0f; -1.0f cannot occur naturally.
static float g_prev_sigma_g      = -1.0f;
// Tare window variance in raw counts. Feeds the stuck check in health_check().
// TODO 1B-stuck: tare module does not yet expose variance - stuck check will
// always pass until tare.h is updated to include variance in TareResult.
static float g_tare_variance_raw = 0.0f;

// BLE command flags — set by BLE callback, read and cleared by orchestrator
volatile bool  g_cmd_tare_pending      = false;
volatile bool  g_cmd_skip_tare_pending = false;
volatile bool  g_cmd_set_cal_pending   = false;
volatile float g_cmd_cal_value         = 0.0f;
volatile bool  g_cmd_retare_pending    = false;
volatile bool  g_cmd_dump_log_pending  = false;
volatile bool  g_cmd_clear_log_pending = false;

static const uint32_t TARE_WAIT_TIMEOUT_MS = 60000UL;
// Carries TARE_WAIT decision into STATE_TARE
static bool s_tare_from_spiffs = false;

void setup() {
    Serial.begin(115200);
    SPIFFS.begin(true);
    hx711_init();
    ble_init();
    g_state           = STATE_SETTLE;
    g_settle_start_ms = millis();
    phase_start_ms    = millis();
    {
        StaticJsonDocument<4096> doc;
        File fr = SPIFFS.open("/config.json", "r");
        if (fr) {
            deserializeJson(doc, fr);
            fr.close();
        }
        g_boot_count = doc["boot_count"] | (uint32_t)0;
        g_boot_count++;
        doc["boot_count"] = g_boot_count;
        File fw = SPIFFS.open("/config.json", "w");
        if (fw) {
            serializeJson(doc, fw);
            fw.close();
        }
    }
    journal_init(g_boot_count);
    journal_boot_start();
}

void loop() {
    uint32_t now = millis();
    if (now - g_last_tick < 100) return;
    g_last_tick = now;

    HX711Result r = hx711_read();
    if (!r.valid) return;

    switch (g_state) {

    case STATE_SETTLE:
        if (now - g_settle_start_ms >= 2000) {
            uint32_t settle_ms = millis() - phase_start_ms;
            journal_phase_complete("SETTLE", "OK", settle_ms / 1000.0f, 0, 0, 0);
            g_state = STATE_TARE_WAIT;
            phase_start_ms = millis();
        }
        break;

    case STATE_TARE_WAIT: {
        static bool     s_entered    = false;
        static uint32_t s_wait_start = 0;
        if (!s_entered) {
            s_entered    = true;
            s_wait_start = millis();
            Serial.println("[BOOT] Waiting for hub TARE or SKIP_TARE command (60s timeout)");
        }

        if (g_cmd_tare_pending) {
            g_cmd_tare_pending = false;
            journal_tare_wait_result("CMD_TARE");
            s_tare_from_spiffs = false;
            tare_init();
            g_state = STATE_TARE;
            phase_start_ms = millis();
        } else if (g_cmd_skip_tare_pending) {
            g_cmd_skip_tare_pending = false;
            journal_tare_wait_result("CMD_SKIP_TARE");
            s_tare_from_spiffs = true;
            g_state = STATE_TARE;
            phase_start_ms = millis();
        } else if (millis() - s_wait_start >= TARE_WAIT_TIMEOUT_MS) {
            journal_tare_wait_result("TIMEOUT");
            s_tare_from_spiffs = false;
            tare_init();
            g_state = STATE_TARE;
            phase_start_ms = millis();
        }
        delay(10);  // yield to FreeRTOS IDLE task — prevents watchdog starvation during 60s wait
        break;
    }

    case STATE_TARE: {
        // Load saved tare once for N-TARE-CHECK (fresh-tare path only)
        static float s_saved_tare_raw    = -1.0f;
        static bool  s_saved_tare_loaded = false;

        // SPIFFS fast-load path — one-shot on first tick when hub sent SKIP_TARE
        static bool s_spiffs_attempted = false;
        if (!s_spiffs_attempted && s_tare_from_spiffs) {
            s_spiffs_attempted = true;
            float loaded;
            if (tare_load_from_spiffs(&loaded)) {
                g_tare_raw = loaded;
                uint32_t tare_ms = millis() - phase_start_ms;
                journal_phase_complete("TARE", "OK", tare_ms / 1000.0f, g_tare_raw, 0.0f, 0);
                noise_init();
                g_state = STATE_NOISE;
                phase_start_ms = millis();
                break;
            }
            Serial.println("[TARE] SPIFFS load failed — running fresh tare");
            s_tare_from_spiffs = false;
            tare_init();
        }

        if (!s_saved_tare_loaded) {
            s_saved_tare_loaded = true;
            float sv;
            if (!tare_load_from_spiffs(&sv)) sv = -1.0f;
            s_saved_tare_raw = sv;
        }

        TareResult tr = tare_update(r.value);
        if (tr.status == TARE_SUCCESS || tr.status == TARE_DEGRADED) {
            g_tare_raw = tr.tare_raw;
            // g_tare_variance_raw stays 0.0f — TareResult has no variance field yet
            // (see TODO 1B-stuck comment in globals)
            tare_save_to_spiffs(g_tare_raw);

            {
                TareCheckResult tc = tare_self_check(g_tare_raw, s_saved_tare_raw, g_cal_factor);
                if (tc == TARE_CHECK_CLEAN) {
                    float delta_g = fabsf(g_tare_raw - s_saved_tare_raw) / g_cal_factor;
                    journal_tare_check("CLEAN", delta_g);
                } else if (tc == TARE_CHECK_SUSPECT) {
                    float delta_g = fabsf(g_tare_raw - s_saved_tare_raw) / g_cal_factor;
                    journal_tare_check("SUSPECT", delta_g);
                    strncpy(g_health.quality, "DEGRADED", sizeof(g_health.quality));
                } else {
                    journal_tare_check("NO_REF", 0.0f);
                }
            }

            uint32_t tare_ms = millis() - phase_start_ms;
            journal_phase_complete("TARE", "OK", tare_ms / 1000.0f, tr.tare_raw, 0.0f, 0);
            noise_init();
            g_state = STATE_NOISE;
            phase_start_ms = millis();
        } else if (tr.status == TARE_FAILED) {
            journal_phase_fail("TARE", "halting", 0);
            while (true) delay(1000);
        }
        break;
    }

    case STATE_NOISE: {
        // Load saved cal_factor before NOISE so sigma is in grams not raw counts.
        // g_cal_factor=0.0f during first boot NOISE phase (CAL not yet run).
        // Without this, noise_update divides by 0 path → sigma in raw counts → always WARN.
        if (g_cal_factor == 0.0f) { float _sc = cal_load_last(); if (_sc > 0.0f) g_cal_factor = _sc; }
        NoiseResult nr = noise_update(r.value, g_tare_raw, g_cal_factor);
        if (nr.valid) {
            g_sigma_g = nr.sigma_g;
            uint32_t noise_ms = millis() - phase_start_ms;
            journal_phase_complete("NOISE", "OK", noise_ms / 1000.0f, 0, 0, 0);
            cal_init(g_tare_raw);
            g_state = STATE_CAL;
            phase_start_ms = millis();
        } else if (strstr(nr.diagnosis, "too high") || strstr(nr.diagnosis, "too low")) {
            g_sigma_g = nr.sigma_g;
            uint32_t noise_ms = millis() - phase_start_ms;
            journal_phase_complete("NOISE", "WARN", noise_ms / 1000.0f, 0, 0, 0);
            cal_init(g_tare_raw);
            g_state = STATE_CAL;
            phase_start_ms = millis();
        }
        break;
    }

    case STATE_CAL: {
        // Hub SET_CAL command takes priority — skip all other CAL logic
        if (g_cmd_set_cal_pending) {
            g_cmd_set_cal_pending = false;
            g_cal_factor      = g_cmd_cal_value;
            g_sigma_g         = noise_recompute_sigma(g_cal_factor);
            g_prev_cal_factor = g_cal_factor;
            g_prev_sigma_g    = g_sigma_g;
            uint32_t cal_ms   = millis() - phase_start_ms;
            journal_phase_complete("CAL", "OK", cal_ms / 1000.0f, g_cal_factor, 0, 0);
            weight_init();
            g_state = STATE_RUNNING;
            phase_start_ms = millis();
            journal_boot_complete(millis() / 1000.0f, g_cal_factor,
                                  g_sigma_g, (float)g_tare_raw);
            Serial.printf("[CAL] Loaded cal_factor=%.4f via SET_CAL command\n",
                          g_cal_factor);
            break;
        }

        // Try to load saved cal_factor from SPIFFS on first entry.
        // s_cal_attempted is a static bool, false until first tick of STATE_CAL.
        // On first tick: attempt cal_load_last(). If valid (> 0), use it and
        // transition to STATE_RUNNING immediately — no interactive CAL needed.
        // If not valid, fall through to interactive cal_update() as before.
        static bool s_cal_attempted = false;
        if (!s_cal_attempted) {
            s_cal_attempted = true;
            float saved_cal = cal_load_last();
            if (saved_cal > 0.0f) {
                g_cal_factor = saved_cal;
                g_sigma_g    = noise_recompute_sigma(saved_cal);
                g_prev_cal_factor = saved_cal;
                g_prev_sigma_g    = g_sigma_g;
                uint32_t cal_ms = millis() - phase_start_ms;
                journal_phase_complete("CAL", "OK", cal_ms / 1000.0f,
                                       g_cal_factor, 0, 0);
                weight_init();
                g_state = STATE_RUNNING;
                phase_start_ms = millis();
                journal_boot_complete(millis() / 1000.0f, g_cal_factor,
                                      g_sigma_g, (float)g_tare_raw);
                Serial.printf("[CAL] Loaded saved cal_factor=%.4f from SPIFFS\n",
                              saved_cal);
                break;
            }
            Serial.println("[CAL] No saved cal_factor — running interactive CAL");
            cal_init(g_tare_raw);
        }

        CalResult cr = cal_update(r.value);
        if (cr.status == CAL_SUCCESS) {
            g_cal_factor = cr.cal_factor;
            cal_save(g_cal_factor);
            g_sigma_g = noise_recompute_sigma(g_cal_factor);
            g_prev_cal_factor = g_cal_factor;
            g_prev_sigma_g    = g_sigma_g;
            uint32_t cal_ms = millis() - phase_start_ms;
            journal_phase_complete("CAL", "OK", cal_ms / 1000.0f,
                                   g_cal_factor, 0, 0);
            weight_init();
            g_state = STATE_RUNNING;
            phase_start_ms = millis();
            journal_boot_complete(millis() / 1000.0f, g_cal_factor,
                                  g_sigma_g, (float)g_tare_raw);
        } else if (cr.status == CAL_FAILED) {
            journal_phase_fail("CAL", cr.diagnosis, cr.cal_factor);
            cal_init(g_tare_raw);
            s_cal_attempted = false;
        }
        break;
    }

    case STATE_RUNNING: {
        if (g_cmd_retare_pending) {
            g_cmd_retare_pending = false;
            tare_init();
            g_state = STATE_RETARE;
            phase_start_ms = millis();
            break;
        }
        if (g_cmd_dump_log_pending) {
            g_cmd_dump_log_pending = false;
            log_transfer_start();
        }
        if (g_transfer_pending && g_lt_state == LT_IDLE) {
            // 25KB threshold crossed - auto-push without waiting for hub DUMP_LOG
            log_transfer_start();
        }
        if (g_cmd_clear_log_pending) {
            g_cmd_clear_log_pending = false;
            log_transfer_clear();
        }

        WeightResult wr = weight_update(r.value, g_tare_raw, g_cal_factor, g_sigma_g);
        g_health = health_check(
            g_sigma_g,
            g_prev_sigma_g,
            g_tare_variance_raw,
            g_cal_factor,
            g_prev_cal_factor,
            wr.grams,
            g_prev_gross_g,
            0.20f,
            3.0f
        );
        g_prev_gross_g = wr.grams;
        ble_notify(wr.grams, g_health.quality, g_sigma_g);
        log_transfer_tick();
        journal_run(wr.grams, g_sigma_g, g_health, wr.event, wr.delta);
        journal_heartbeat_tick(wr.grams, g_sigma_g, g_health);
        break;
    }

    case STATE_RETARE: {
        TareResult tr = tare_update(r.value);
        if (tr.status == TARE_SUCCESS || tr.status == TARE_DEGRADED) {
            float old_tare = g_tare_raw;
            g_tare_raw = tr.tare_raw;
            tare_save_to_spiffs(g_tare_raw);
            g_prev_gross_g = -1.0f;
            weight_init();
            journal_retare(g_tare_raw, old_tare);
            g_state = STATE_RUNNING;
            phase_start_ms = millis();
        } else if (tr.status == TARE_FAILED) {
            journal_phase_fail("RETARE", "halting", 0);
            while (true) delay(1000);
        }
        break;
    }

    }
}
