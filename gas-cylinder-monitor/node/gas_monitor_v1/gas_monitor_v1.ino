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

enum BootState {
    STATE_SETTLE,
    STATE_TARE,
    STATE_NOISE,
    STATE_CAL,
    STATE_RUNNING
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
            tare_init();
            g_state = STATE_TARE;
            phase_start_ms = millis();
        }
        break;

    case STATE_TARE: {
        TareResult tr = tare_update(r.value);
        if (tr.status == TARE_SUCCESS || tr.status == TARE_DEGRADED) {
            g_tare_raw = tr.tare_raw;
            // g_tare_variance_raw stays 0.0f — TareResult has no variance field yet
            // (see TODO 1B-stuck comment in globals)
            // NOTE: tr.tare_raw used as mean (it IS the mean, see tare.cpp:107).
            // spread is not exposed by TareResult; extra2=0.0f until tare.h adds it.
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
        CalResult cr = cal_update(r.value);
        if (cr.status == CAL_SUCCESS) {
            g_cal_factor = cr.cal_factor;
            cal_save(g_cal_factor);
            g_sigma_g = noise_recompute_sigma(g_cal_factor);
            // persist for health_check() boot-to-boot comparison
            g_prev_cal_factor = g_cal_factor;
            g_prev_sigma_g    = g_sigma_g;
            // TODO 1B-persistence: g_prev_cal_factor and g_prev_sigma_g are set from
            // the current boot only. This means the cal drift and erratic checks always
            // compare cur against cur - drift is always 0%, checks always pass this boot.
            // True boot-to-boot detection requires reading prev values FROM config.json
            // at startup before STATE_SETTLE, and writing cur values TO config.json
            // after CAL_SUCCESS. Until that is implemented, these checks only catch
            // failures that develop mid-session, not failures that persist across reboots.
            uint32_t cal_ms = millis() - phase_start_ms;
            journal_phase_complete("CAL", "OK", cal_ms / 1000.0f, g_cal_factor, 0, 0);
            weight_init();
            g_state = STATE_RUNNING;
            phase_start_ms = millis();
            journal_boot_complete(millis() / 1000.0f, g_cal_factor, g_sigma_g, (float)g_tare_raw);
        } else if (cr.status == CAL_FAILED) {
            journal_phase_fail("CAL", cr.diagnosis, cr.cal_factor);
            cal_init(g_tare_raw);
        }
        break;
    }

    case STATE_RUNNING: {
        WeightResult wr = weight_update(r.value, g_tare_raw, g_cal_factor);
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
        journal_run(wr.grams, g_sigma_g, g_health);
        journal_heartbeat_tick(wr.grams, g_sigma_g, g_health);
        break;
    }

    }
}
