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

void setup() {
    Serial.begin(115200);
    SPIFFS.begin(true);
    hx711_init();
    ble_init();
    g_state           = STATE_SETTLE;
    g_settle_start_ms = millis();
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
            tare_init();
            g_state = STATE_TARE;
        }
        break;

    case STATE_TARE: {
        TareResult tr = tare_update(r.value);
        if (tr.status == TARE_SUCCESS || tr.status == TARE_DEGRADED) {
            g_tare_raw = tr.tare_raw;
            Serial.print("[BOOT] phase=TARE result=");
            Serial.println(tr.diagnosis);
            noise_init();
            g_state = STATE_NOISE;
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
            cal_init(g_tare_raw);
            g_state = STATE_CAL;
        } else if (strstr(nr.diagnosis, "too high") || strstr(nr.diagnosis, "too low")) {
            Serial.print("[BOOT] phase=NOISE WARNING: ");
            Serial.println(nr.diagnosis);
            g_sigma_g = nr.sigma_g;
            cal_init(g_tare_raw);
            g_state = STATE_CAL;
        }
        break;
    }

    case STATE_CAL: {
        CalResult cr = cal_update(r.value);
        if (cr.status == CAL_SUCCESS) {
            g_cal_factor = cr.cal_factor;
            cal_save(g_cal_factor);
            g_sigma_g = noise_recompute_sigma(g_cal_factor);
            Serial.print("[BOOT] sigma recomputed in grams: ");
            Serial.println(g_sigma_g);
            Serial.print("[BOOT] phase=CAL result=");
            Serial.println(cr.diagnosis);
            weight_init();
            g_state = STATE_RUNNING;
            Serial.println("[BOOT] RUNNING");
        } else if (cr.status == CAL_FAILED) {
            Serial.print("[BOOT] phase=CAL FAILED: ");
            Serial.println(cr.diagnosis);
            cal_init(g_tare_raw);
        }
        break;
    }

    case STATE_RUNNING: {
        WeightResult wr = weight_update(r.value, g_tare_raw, g_cal_factor);
        const char* quality_str;
        switch (wr.quality) {
        case WEIGHT_GOOD:     quality_str = "GOOD";     break;
        case WEIGHT_DEGRADED: quality_str = "DEGRADED"; break;
        default:              quality_str = "FAILED";   break;
        }
        ble_notify(wr.grams, quality_str, g_sigma_g);
        char line[80];
        snprintf(line, sizeof(line), "[RUN] grams=%.1f quality=%s sigma=%.2f",
                 wr.grams, quality_str, g_sigma_g);
        Serial.println(line);
        break;
    }

    }
}
