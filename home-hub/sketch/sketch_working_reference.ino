#include <Arduino_RouterBridge.h>

#define HX711_DT_PIN        7
#define HX711_SCK_PIN       6
#define CALIBRATION_FACTOR  100.0f
#define SAMPLE_COUNT        5
#define TARE_SAMPLE_COUNT   20
#define STABILITY_THRESHOLD 5.0f
#define PUSH_INTERVAL_MS    500

static long g_tare_offset = 0;

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
        if (r == LONG_MIN) { delay(10); continue; }
        if (r == -1)       { delay(10); continue; }
        if (r == 0x7FFFFF) { delay(10); continue; }
        sum += r;
        ok++;
        delay(10);
    }
    return (ok == 0) ? LONG_MIN : (sum / ok);
}

String handle_do_tare() {
    long raw = hx711_read_average(TARE_SAMPLE_COUNT);
    if (raw == LONG_MIN) return String("error");
    g_tare_offset = raw;
    return String("ok");
}

void setup() {
    pinMode(HX711_SCK_PIN, OUTPUT);
    pinMode(HX711_DT_PIN,  INPUT_PULLUP);
    digitalWrite(HX711_SCK_PIN, LOW);

    pinMode(LED3_R, OUTPUT);
    pinMode(LED3_G, OUTPUT);
    digitalWrite(LED3_R, LOW);   // red on = booting
    digitalWrite(LED3_G, HIGH);  // green off

    Bridge.begin();
    Monitor.begin();
    Bridge.provide_safe("do_tare", handle_do_tare);

    delay(500);
    long raw = hx711_read_average(TARE_SAMPLE_COUNT);
    if (raw != LONG_MIN) {
        g_tare_offset = raw;
        Monitor.println("HX711 ready");
    } else {
        Monitor.println("HX711 not detected");
    }

    digitalWrite(LED3_R, HIGH);  // red off
    digitalWrite(LED3_G, LOW);   // green on = ready
}

void loop() {
    static uint32_t last_push = 0;
    if (millis() - last_push < PUSH_INTERVAL_MS) return;
    last_push = millis();

    long raw = hx711_read_average(SAMPLE_COUNT);

    if (raw == LONG_MIN) {
        Bridge.notify("weight_event", String("{\"sensor_ok\":false}"));
        return;
    }

    float grams = (float)(raw - g_tare_offset) / CALIBRATION_FACTOR;
    if (grams < 0.0f) grams = 0.0f;
    float kg = grams / 1000.0f;

    long raw2 = hx711_read_raw();
    bool stable = false;
    if (raw2 != LONG_MIN) {
        float diff = abs((float)(raw2 - raw)) / CALIBRATION_FACTOR;
        stable = (diff < STABILITY_THRESHOLD);
    }

    String j = "{\"grams\":";
    j += String(grams, 1);
    j += ",\"weight_kg\":";
    j += String(kg, 4);
    j += ",\"stable\":";
    j += stable ? "true" : "false";
    j += ",\"sensor_ok\":true}";

    Monitor.println("RAW=" + String(raw) + " TARE=" + String(g_tare_offset));
    Bridge.notify("weight_event", j);
}
