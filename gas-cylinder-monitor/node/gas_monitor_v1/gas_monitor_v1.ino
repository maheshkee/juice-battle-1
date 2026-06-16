// gas_monitor_v1 - Gas Cylinder Monitor Node Sketch
// Required Arduino libraries (install via Library Manager before compiling):
//   NimBLE-Arduino by h2zero      - BLE GATT server
//   ArduinoJson by Benoit Blanchon - config.json SPIFFS read/write
// Board: ESP32C3 Dev Module, esp32 by Espressif v3.0.7, USB CDC On Boot: ENABLED

#include <SPIFFS.h>
#include "hx711.h"
#include "tare.h"
#include "noise.h"
#include "cal.h"
#include "weight.h"
#include "ble.h"
#include "health.h"

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
    Serial.println("[BOOT] Gas monitor starting");
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
            Serial.println("[BOOT] phase=SETTLE complete");
            uint32_t settle_ms = millis() - phase_start_ms;
            Serial.printf("[BOOT] phase=SETTLE s=%.1f\n", settle_ms / 1000.0f);
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
            Serial.print("[BOOT] phase=TARE result=");
            Serial.println(tr.diagnosis);
            uint32_t tare_ms = millis() - phase_start_ms;
            Serial.printf("[BOOT] phase=TARE s=%.1f\n", tare_ms / 1000.0f);
            noise_init();
            g_state = STATE_NOISE;
            phase_start_ms = millis();
        } else if (tr.status == TARE_FAILED) {
            Serial.println("[BOOT] phase=TARE FAILED - halting");
            while (true) delay(1000);
        }
        break;
    }

    case STATE_NOISE: {
        NoiseResult nr = noise_update(r.value, g_tare_raw, g_cal_factor);
        if (nr.valid) {
            g_sigma_g = nr.sigma_g;
            Serial.print("[BOOT] phase=NOISE result=");
            Serial.println(nr.diagnosis);
            uint32_t noise_ms = millis() - phase_start_ms;
            Serial.printf("[BOOT] phase=NOISE s=%.1f\n", noise_ms / 1000.0f);
            cal_init(g_tare_raw);
            g_state = STATE_CAL;
            phase_start_ms = millis();
        } else if (strstr(nr.diagnosis, "too high") || strstr(nr.diagnosis, "too low")) {
            Serial.print("[BOOT] phase=NOISE WARNING: ");
            Serial.println(nr.diagnosis);
            g_sigma_g = nr.sigma_g;
            uint32_t noise_ms = millis() - phase_start_ms;
            Serial.printf("[BOOT] phase=NOISE s=%.1f\n", noise_ms / 1000.0f);
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
            Serial.print("[BOOT] sigma recomputed in grams: ");
            Serial.println(g_sigma_g);
            Serial.print("[BOOT] phase=CAL result=");
            Serial.println(cr.diagnosis);
            uint32_t cal_ms = millis() - phase_start_ms;
            Serial.printf("[BOOT] phase=CAL s=%.1f\n", cal_ms / 1000.0f);
            weight_init();
            g_state = STATE_RUNNING;
            phase_start_ms = millis();
            Serial.println("[BOOT] RUNNING");
        } else if (cr.status == CAL_FAILED) {
            Serial.print("[BOOT] phase=CAL FAILED: ");
            Serial.println(cr.diagnosis);
            cal_init(g_tare_raw);
        }
        break;
    }

    case STATE_RUNNING: {
        static uint32_t tick_start_ms = 0;
        tick_start_ms = millis();
        WeightResult wr = weight_update(r.value, g_tare_raw, g_cal_factor);
        g_health = health_check(
            g_sigma_g,          // runtime sigma from this boot's noise char
            g_prev_sigma_g,     // historical baseline from config.json (-1.0f = first boot)
            g_tare_variance_raw,// tare window variance (0.0f until tare.h updated)
            g_cal_factor,       // cal_factor derived this boot
            g_prev_cal_factor,  // cal_factor from previous boot (-1.0f = first boot)
            wr.grams,           // current gross weight reading
            g_prev_gross_g,     // previous gross weight (-1.0f = first tick)
            0.20f,              // cal_tolerance: 20% drift threshold (placeholder - move to config.json later)
            3.0f                // sigma_tolerance: flag if runtime sigma > 3x historical baseline (placeholder)
        );
        g_prev_gross_g = wr.grams;
        Serial.printf("[HEALTH] quality=%s diagnosis=%s checks=0x%02X\n",
                      g_health.quality, g_health.diagnosis, g_health.checks_passed);
        ble_notify(wr.grams, g_health.quality, g_sigma_g);
        uint32_t tick_ms = millis() - tick_start_ms;
        Serial.printf("[RUN] grams=%.1f quality=%s sigma=%.2f tick_ms=%lu\n",
                      wr.grams, g_health.quality, g_sigma_g, tick_ms);
        break;
    }

    }
}
