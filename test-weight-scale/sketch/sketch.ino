#include <Arduino_RouterBridge.h>
#include "HX711Zephyr.h"

#define DT_PIN    4    // PA12
#define SCK_PIN   5
#define LED_RED   LED3_R
#define LED_GREEN LED3_G
// CAL_FACTOR = 1.0f for now — raw counts mode for calibration
#define CAL_FACTOR 1.0f

HX711Zephyr scale;

String read_weight_packet() {
    // Wait up to 300ms for HX711 ready
    unsigned long t = millis();
    while (digitalRead(DT_PIN) != LOW && (millis() - t < 300)) { delay(5); }
    scale.update();

    float   grams  = scale.getGrams();
    int32_t raw    = scale.getRaw();
    bool    stable = scale.isStable();
    bool    ok     = scale.isFresh();

    // Brief green blink — visual confirmation of each read
    digitalWrite(LED_GREEN, HIGH);
    delayMicroseconds(300);
    digitalWrite(LED_GREEN, LOW);

    String json = "{";
    json += "\"grams\":"  + String(grams, 1)              + ",";
    json += "\"raw\":"    + String(raw)                   + ",";
    json += "\"stable\":" + String(stable ? "true":"false") + ",";
    json += "\"ok\":"     + String(ok     ? "true":"false");
    json += "}";
    return json;
}

void setup() {
    pinMode(LED_RED,   OUTPUT); digitalWrite(LED_RED,   HIGH);
    pinMode(LED_GREEN, OUTPUT); digitalWrite(LED_GREEN, HIGH);

    Bridge.begin();
    Monitor.begin();

    scale.begin(DT_PIN, SCK_PIN);
    scale.setCalFactor(CAL_FACTOR);

    Monitor.println("[SCALE] Taring — keep scale empty...");
    digitalWrite(LED_RED, LOW);   // red on = taring
    scale.start(2000);            // 2s settle + tare
    digitalWrite(LED_RED, HIGH);  // red off

    Bridge.provide_safe("read_weight_packet", read_weight_packet);

    Monitor.println("[SCALE] Ready. CAL=" + String(CAL_FACTOR));
    digitalWrite(LED_GREEN, LOW); // green on = ready
}

void loop() {}
