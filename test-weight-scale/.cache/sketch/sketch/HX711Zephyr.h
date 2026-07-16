#line 1 "/home/arduino/ArduinoApps/test-weight-scale/sketch/HX711Zephyr.h"
#ifndef HX711ZEPHYR_H
#define HX711ZEPHYR_H
#include <Arduino.h>

class HX711Zephyr {
public:
    HX711Zephyr();
    void begin(int dt, int sck);
    void start(int settle_ms = 2000);  // settle + tare
    void setCalFactor(float cal);
    void update();
    float getGrams();
    int32_t getRaw();
    bool isReady();
    bool isFresh();
    bool isStable();

private:
    int _dt, _sck;
    float _cal;
    int32_t _offset;
    int32_t _lastRaw;
    float _lastGrams;
    bool _fresh;
    bool _stable;
    bool _initialized;
    int32_t _stabilityThreshold;
    int32_t readRawOnce();
    int32_t readAverage(int samples);
};
#endif
