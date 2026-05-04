/*
 * ScaleHX711 — Zephyr RTOS Safe HX711 Driver
 * Arduino UNO Q (STM32U585) — home-hub project
 *
 * Zephyr-specific notes:
 * - DT pin must be D4 (PA12) — D2/D3 have PWM timer mux conflicts
 * - noInterrupts() wraps full read including gain pulses
 * - INPUT_PULLUP required — HX711 DOUT is open-drain
 * - delayMicroseconds(1) required — 160MHz MCU is faster than HX711 min timing
 */

#include "ScaleHX711.h"
#include <math.h>

namespace {
const float kMinAbsScale = 0.000001f;
const int kMaxSamples = 100;
}

// Fix: default constructor zero-initializes all members so stack-allocated
// instances don't have undefined _initialized state.
ScaleHX711::ScaleHX711()
    : _dt(0), _sck(0), _gain(1), _offset(0), _scale(1.0f),
      _lastRaw(0), _lastWeight(0.0f), _stable(false),
      _available(false), _fresh(false), _initialized(false),
      _lastReadTime(0), _stabilityThreshold(10) {}

void ScaleHX711::begin(int dt, int sck, uint8_t gain) {
    _dt = dt;
    _sck = sck;
    _offset = 0;
    _scale = 1.0f;
    _lastRaw = 0;
    _lastWeight = 0.0f;
    _stable = false;
    _available = false;
    _fresh = false;
    _lastReadTime = 0;
    _stabilityThreshold = 10;

    pinMode(_dt, INPUT_PULLUP);
    pinMode(_sck, OUTPUT);
    digitalWrite(_sck, LOW);

    // Fix: mark initialized before set_gain so is_ready() works inside it,
    // and delay before set_gain so the chip has settled for the first read.
    _initialized = true;
    delay(10);
    set_gain(gain);
}

void ScaleHX711::set_gain(uint8_t gain) {
    switch (gain) {
        case 128: _gain = 1; break;
        case 64:  _gain = 3; break;
        case 32:  _gain = 2; break;
        default:  _gain = 1; break;
    }

    digitalWrite(_sck, LOW);

    // Fix: wait for the chip to be ready before clocking gain-config pulses.
    // Clocking while DT is HIGH (mid-conversion) can corrupt that conversion.
    unsigned long t = millis();
    while (!is_ready() && (millis() - t < 500)) { yield(); }
    read_raw_internal();
}

void ScaleHX711::update() {
    if (!_initialized) return;

    // Fix: clear fresh each call; only set it when a new reading is captured.
    // _available is NOT cleared here — it signals "has valid cached data" and
    // stays true once set. Use fresh() to detect a new reading this call.
    _fresh = false;

    if (!is_ready()) return;

    int32_t previousRaw = _lastRaw;
    bool hadPreviousSample = _available;
    int32_t raw = read_raw_internal();

    _lastRaw = raw;

    if (!is_valid_nonzero(_scale)) {
        _lastWeight = 0.0f;
    } else {
        _lastWeight = (raw - _offset) / _scale;
    }

    int32_t delta = raw - previousRaw;
    if (delta < 0) delta = -delta;

    _stable = hadPreviousSample && (delta <= _stabilityThreshold);
    _available = true;
    _fresh = true;
    _lastReadTime = millis();
}

void ScaleHX711::tare(int samples) {
    if (!_initialized) return;

    _offset = read_average(samples);
    _lastRaw = _offset;
    _lastWeight = 0.0f;
    _stable = false;
    _available = true;
    _fresh = true;
    _lastReadTime = millis();
}

void ScaleHX711::set_scale(float scale) {
    if (!is_valid_nonzero(scale)) return;
    _scale = scale;
}

void ScaleHX711::calibrate(float known_weight, int samples) {
    if (!_initialized) return;
    if (!is_valid_nonzero(known_weight)) return;

    int32_t raw = read_average(samples);
    float scale = (float)(raw - _offset) / known_weight;

    if (!is_valid_nonzero(scale)) return;

    _scale = scale;
    _lastRaw = raw;
    _lastWeight = known_weight;
    _stable = false;
    _available = true;
    _fresh = true;
    _lastReadTime = millis();
}

int32_t ScaleHX711::read_average(int samples) {
    if (samples < 1) samples = 1;
    if (samples > kMaxSamples) samples = kMaxSamples;

    int64_t sum = 0;
    int count = 0;

    unsigned long start = millis();
    while (!is_ready() && (millis() - start < 1000)) { yield(); }

    for (int i = 0; i < samples; ++i) {
        // Fix: per-sample timeout prevents infinite hang if HX711 goes silent
        // mid-read (e.g. cable fault between samples).
        unsigned long t = millis();
        while (!is_ready() && (millis() - t < 1000)) { yield(); }
        if (!is_ready()) break;
        sum += read_raw_internal();
        delay(1);
        count++;
    }
    return (count > 0) ? static_cast<int32_t>(sum / count) : 0;
}

float ScaleHX711::get_units(int samples) {
    if (!is_valid_nonzero(_scale)) return 0.0f;
    return (float)(read_average(samples) - _offset) / _scale;
}

float ScaleHX711::get_weight()      { return _lastWeight; }
int32_t ScaleHX711::get_raw()       { return _lastRaw; }
bool ScaleHX711::is_stable()        { return _stable; }
bool ScaleHX711::available()        { return _available; }
bool ScaleHX711::fresh()            { return _fresh; }
bool ScaleHX711::initialized()      { return _initialized; }
unsigned long ScaleHX711::last_read_time() { return _lastReadTime; }

void ScaleHX711::set_stability_threshold(int32_t counts) {
    if (counts < 0) counts = -counts;
    _stabilityThreshold = counts;
}

void ScaleHX711::power_down() {
    if (!_initialized) return;
    digitalWrite(_sck, LOW);
    digitalWrite(_sck, HIGH);
}

void ScaleHX711::power_up() {
    if (!_initialized) return;
    digitalWrite(_sck, LOW);
}

bool ScaleHX711::is_ready() {
    if (!_initialized) return false;
    return digitalRead(_dt) == LOW;
}

bool ScaleHX711::is_valid_nonzero(float value) {
    if (isnan(value)) return false;
    return value <= -kMinAbsScale || value >= kMinAbsScale;
}

int32_t ScaleHX711::read_raw_internal() {
    uint32_t value = 0;

    // HX711 is timing sensitive. Disable interrupts during bit-banging.
    noInterrupts();

    for (int i = 0; i < 24; ++i) {
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        value <<= 1;
        if (digitalRead(_dt)) value++;
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }

    // Set gain for next conversion
    for (uint8_t i = 0; i < _gain; ++i) {
        digitalWrite(_sck, HIGH);
        delayMicroseconds(1);
        digitalWrite(_sck, LOW);
        delayMicroseconds(1);
    }

    interrupts();

    if (value & 0x800000UL) value |= 0xFF000000UL;

    return static_cast<int32_t>(value);
}
