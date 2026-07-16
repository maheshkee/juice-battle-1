#include "dht_sensor.h"
#include <DHTesp.h>

static DHTesp    s_dht;
static uint32_t  s_last_ms = 0;
static DHTResult s_last    = {0.0f, false};

void dht_sensor_init() {
    s_dht.setup(DHT_PIN, DHTesp::DHT22);
    Serial.printf("[DHT] DHT22 initialised on GPIO%d\n", DHT_PIN);
}

// Returns cached result if called within 2s of last read (DHT22 minimum period).
// Blocks ~3-5ms when an actual read is performed.
DHTResult dht_sensor_read() {
    uint32_t now = millis();
    if (now - s_last_ms < 2000) return s_last;
    s_last_ms = now;

    TempAndHumidity r = s_dht.getTempAndHumidity();
    if (s_dht.getStatus() != DHTesp::ERROR_NONE) {
        s_last = {0.0f, false};
        Serial.printf("[DHT] read error: %s\n", s_dht.getStatusString());
    } else {
        s_last = {r.temperature, true};
        Serial.printf("[DHT] temp=%.1fC\n", r.temperature);
    }
    return s_last;
}
