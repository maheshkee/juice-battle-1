#include <Arduino_RouterBridge.h>
#include "ScaleHX711.h"

#define DT_PIN              4       // PA12 — no PWM timer mux conflict
#define SCK_PIN             3       // PB0
#define CAL_FACTOR          1.0f    // TEMP for calibration
#define STABILITY_THRESHOLD 50

#define LED_RED   LED3_R  // active LOW — PH10 on UNO Q variant
#define LED_GREEN LED3_G  // active LOW — PH11 on UNO Q variant

ScaleHX711 scale;

String read_weight_packet() {
    unsigned long t = millis();
    while (digitalRead(DT_PIN) != LOW && (millis() - t < 300)) { delay(5); }
    scale.update();

    float   weight_kg       = scale.get_weight();
    int32_t raw_kg          = scale.get_raw();
    bool    stable          = scale.is_stable();
    bool    post_read_ready = scale.fresh();
    bool    sensor_ok       = scale.available() && scale.fresh();

    digitalWrite(LED_GREEN, LOW);
    delayMicroseconds(300);
    digitalWrite(LED_GREEN, HIGH);

    String json = "{";
    json += "\"weight_kg\":"       + String(weight_kg, 3)                    + ",";
    json += "\"raw_kg\":"          + String(raw_kg)                          + ",";
    json += "\"stable\":"          + String(stable          ? "true":"false") + ",";
    json += "\"sensor_ok\":"       + String(sensor_ok       ? "true":"false") + ",";
    json += "\"post_read_ready\":" + String(post_read_ready ? "true":"false");
    json += "}";
    return json;
}

void setup() {
    pinMode(LED_RED,   OUTPUT);
    pinMode(LED_GREEN, OUTPUT);
    digitalWrite(LED_RED,   HIGH);  // off
    digitalWrite(LED_GREEN, HIGH);  // off

    Bridge.begin();
    Monitor.begin();

    Monitor.println("[SCALE] Initializing HX711...");
    scale.begin(DT_PIN, SCK_PIN, 128);
    scale.set_scale(CAL_FACTOR);
    scale.set_stability_threshold(STABILITY_THRESHOLD);

    Monitor.println("[SCALE] Taring (keep scale empty)...");
    digitalWrite(LED_RED, LOW);   // red on during tare
    Monitor.println("[SCALE] Settling HX711 before tare...");
    delay(2000);
    scale.tare(20);
    digitalWrite(LED_RED, HIGH);  // red off

    Bridge.provide_safe("read_weight_packet", read_weight_packet);
    Monitor.println("[SCALE] Ready.");
    digitalWrite(LED_GREEN, LOW);  // green on — ready
}

void loop() {
}
