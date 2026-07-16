#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "ScaleHX711.h"

struct FakeArduinoState {
    std::vector<int> readBits;
    std::vector<int> writePins;
    std::vector<int> writeValues;
    std::vector<int> pinModes;
    std::vector<int> pinModeValues;
    unsigned long now = 0;
    size_t readIndex = 0;
};

FakeArduinoState gState;

void reset_state() {
    gState = FakeArduinoState();
}

void add_ready_bits(const std::vector<int>& dataBits) {
    gState.readBits.clear();
    gState.readIndex = 0;
    gState.readBits.push_back(LOW); // Ready bit
    gState.readBits.insert(gState.readBits.end(), dataBits.begin(), dataBits.end());
    // Padding for gain pulses and next ready checks (HX711 DT is HIGH when not ready)
    for (int i = 0; i < 5; ++i) gState.readBits.push_back(HIGH);
}

std::vector<int> bits24(uint32_t value) {
    std::vector<int> bits;
    bits.reserve(24);
    for (int i = 23; i >= 0; --i) {
        bits.push_back((value >> i) & 0x1U);
    }
    return bits;
}

void pinMode(int pin, int mode) {
    gState.pinModes.push_back(pin);
    gState.pinModeValues.push_back(mode);
}

void digitalWrite(int pin, int value) {
    // If SCK (pin 2) goes from LOW to HIGH, advance the read index (clock edge)
    if (pin == 2 && value == HIGH) {
        if (!gState.writeValues.empty() && gState.writeValues.back() == LOW) {
            if (!gState.readBits.empty()) {
                gState.readIndex++;
            }
        }
    }
    gState.writePins.push_back(pin);
    gState.writeValues.push_back(value);
}

int digitalRead(int) {
    if (gState.readIndex >= gState.readBits.size()) {
        return HIGH; // Not ready if no more bits
    }
    return gState.readBits[gState.readIndex];
}

unsigned long millis() {
    return gState.now;
}

void noInterrupts() {}
void interrupts() {}
void delay(unsigned long ms) { gState.now += ms; }
void delayMicroseconds(unsigned int) {}  // no-op in host tests
void yield() { gState.now++; }

bool nearly_equal(float a, float b) {
    return std::fabs(a - b) < 0.01f;
}

void test_begin_sets_clock_low() {
    reset_state();
    ScaleHX711 scale;

    scale.begin(3, 2);

    assert(scale.initialized());
    bool pin2_pulsed = false;
    for (int p : gState.writePins) {
        if (p == 2) pin2_pulsed = true;
    }
    assert(pin2_pulsed);
}

void test_update_reads_positive_value() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    scale.set_scale(2.0f);

    add_ready_bits(bits24(0x000123U));

    gState.now = 1000;
    scale.update();

    assert(scale.available());
    assert(scale.fresh());
    assert(scale.get_raw() == 0x123);
    // (0x123 - 0) / 2.0 = 291 / 2.0 = 145.5
    assert(nearly_equal(scale.get_weight(), 145.5f));
}

void test_update_reads_negative_value() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    add_ready_bits(bits24(0xFF0000U));

    scale.update();

    assert(scale.available());
    assert(scale.fresh());
    assert(scale.get_raw() == static_cast<int32_t>(0xFFFF0000U));
}

void test_update_not_ready_marks_unavailable() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    // No bits added — digitalRead returns HIGH (not ready)

    scale.update();

    assert(!scale.available());
    assert(!scale.fresh());
    assert(!scale.is_stable());
}

// available() stays true after a successful read even if the next update()
// finds HX711 not ready. fresh() correctly reflects only the latest call.
void test_available_persists_fresh_does_not() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    scale.set_scale(2.0f);

    add_ready_bits(bits24(0x000010U));
    scale.update();
    assert(scale.available());
    assert(scale.fresh());

    // Next update with HX711 not ready
    scale.update();
    assert(scale.available()); // cached data still valid
    assert(!scale.fresh());    // no new reading this call
}

void test_tare_captures_offset_and_zeroes_weight() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);

    add_ready_bits(bits24(0x000010U));
    gState.now = 50;
    scale.tare(1);

    assert(scale.available());
    assert(scale.fresh());
    assert(scale.get_raw() == 0x10);
    assert(nearly_equal(scale.get_weight(), 0.0f));

    add_ready_bits(bits24(0x000014U));
    scale.set_scale(2.0f);
    scale.update();

    // (0x14 - 0x10) / 2.0 = 4 / 2.0 = 2.0
    assert(nearly_equal(scale.get_weight(), 2.0f));
}

void test_invalid_scale_is_ignored() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    scale.set_scale(4.0f);
    scale.set_scale(0.0f);

    add_ready_bits(bits24(0x000008U));
    scale.update();

    // (8 - 0) / 4.0 = 2.0
    assert(nearly_equal(scale.get_weight(), 2.0f));
}

void test_calibrate_updates_scale_and_weight() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);

    add_ready_bits(bits24(0x000064U));
    scale.tare(1);

    add_ready_bits(bits24(0x0000C8U));
    scale.calibrate(10.0f, 1);

    assert(scale.available());
    assert(scale.fresh());
    assert(scale.get_raw() == 0xC8);
    assert(nearly_equal(scale.get_weight(), 10.0f));

    add_ready_bits(bits24(0x00012CU));
    scale.update();

    // raw=300, offset=100, scale=(200-100)/10=10 -> weight=(300-100)/10=20
    assert(nearly_equal(scale.get_weight(), 20.0f));
}

void test_stability_threshold() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);
    scale.set_stability_threshold(2);

    add_ready_bits(bits24(100U));
    scale.update();
    assert(!scale.is_stable()); // no previous sample yet

    add_ready_bits(bits24(101U));
    scale.update();
    assert(scale.is_stable()); // delta=1 <= 2

    add_ready_bits(bits24(105U));
    scale.update();
    assert(!scale.is_stable()); // delta=4 > 2
}

void test_power_down_up() {
    reset_state();
    ScaleHX711 scale;
    scale.begin(3, 2);

    size_t writes_before = gState.writePins.size();
    scale.power_down();
    assert(gState.writePins.size() > writes_before);
    assert(gState.writePins.back() == 2);
    assert(gState.writeValues.back() == HIGH);

    scale.power_up();
    assert(gState.writeValues.back() == LOW);
}

// power_down/up before begin() must not touch pin 0 (uninitialized _sck)
void test_power_before_begin_is_noop() {
    reset_state();
    ScaleHX711 scale;

    size_t writes_before = gState.writePins.size();
    scale.power_down();
    scale.power_up();
    assert(gState.writePins.size() == writes_before);
}

int main() {
    test_begin_sets_clock_low();
    test_update_reads_positive_value();
    test_update_reads_negative_value();
    test_update_not_ready_marks_unavailable();
    test_available_persists_fresh_does_not();
    test_tare_captures_offset_and_zeroes_weight();
    test_invalid_scale_is_ignored();
    test_calibrate_updates_scale_and_weight();
    test_stability_threshold();
    test_power_down_up();
    test_power_before_begin_is_noop();

    std::cout << "All tests passed\n";
    return 0;
}
