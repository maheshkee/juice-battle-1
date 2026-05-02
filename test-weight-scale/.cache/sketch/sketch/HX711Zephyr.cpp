#line 1 "/home/arduino/ArduinoApps/test-weight-scale/sketch/HX711Zephyr.cpp"
#include "HX711Zephyr.h"
#include <math.h>

HX711Zephyr::HX711Zephyr()
    : _dt(0), _sck(0), _cal(1.0f), _offset(0),
      _lastRaw(0), _lastGrams(0.0f), _fresh(false),
      _stable(false), _initialized(false), _stabilityThreshold(500) {}

void HX711Zephyr::begin(int dt, int sck) {
    _dt = dt;
    _sck = sck;
    pinMode(_dt,  INPUT_PULLUP);
    pinMode(_sck, OUTPUT);
    digitalWrite(_sck, LOW);
    _initialized = true;
    delay(10);
}

void HX711Zephyr::start(int settle_ms) {
    delay(settle_ms);
    _offset    = readAverage(20);
    _lastRaw   = _offset;
    _lastGrams = 0.0f;
    _fresh     = false;
    _stable    = false;
}

void HX711Zephyr::setCalFactor(float cal) {
    if (cal == 0.0f || isnan(cal)) return;
    _cal = cal;
}

bool HX711Zephyr::isReady() {
    if (!_initialized) return false;
    return digitalRead(_dt) == LOW;
}

int32_t HX711Zephyr::readRawOnce() {
    uint32_t value = 0;

    noInterrupts();

    for (int i = 0; i < 24; ++i) {
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        value <<= 1;
        if (digitalRead(_dt)) value |= 1;
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }

    // 1 gain pulse — channel A, gain 128
    digitalWrite(_sck, HIGH);
    delayMicroseconds(1);
    digitalWrite(_sck, LOW);
    delayMicroseconds(1);

    interrupts();

    if (value & 0x800000UL) value |= 0xFF000000UL;
    return static_cast<int32_t>(value);
}

int32_t HX711Zephyr::readAverage(int samples) {
    if (samples < 1) samples = 1;
    int64_t sum  = 0;
    int     count = 0;

    unsigned long t = millis();
    while (!isReady() && (millis() - t < 1000)) { yield(); }

    for (int i = 0; i < samples; ++i) {
        unsigned long ts = millis();
        while (!isReady() && (millis() - ts < 500)) { yield(); }
        if (!isReady()) break;
        sum += readRawOnce();
        delay(2);
        count++;
    }
    return count > 0 ? static_cast<int32_t>(sum / count) : 0;
}

void HX711Zephyr::update() {
    _fresh = false;
    if (!isReady()) return;

    int32_t raw   = readRawOnce();
    int32_t delta = raw - _lastRaw;
    if (delta < 0) delta = -delta;

    _stable  = (delta <= _stabilityThreshold);
    _lastRaw = raw;

    if (_cal != 0.0f) {
        _lastGrams = (float)(raw - _offset) / _cal * 1000.0f;
    } else {
        _lastGrams = (float)(raw - _offset);
    }

    _fresh = true;
}

float   HX711Zephyr::getGrams()  { return _lastGrams; }
int32_t HX711Zephyr::getRaw()    { return _lastRaw; }
bool    HX711Zephyr::isFresh()   { return _fresh; }
bool    HX711Zephyr::isStable()  { return _stable; }
