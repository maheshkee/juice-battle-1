#include "HX711.h"

HX711::HX711() {}
HX711::~HX711() {}

void HX711::begin(byte dout, byte pd_sck, byte gain) {
    PD_SCK = pd_sck;
    DOUT   = dout;
    pinMode(PD_SCK, OUTPUT);
    pinMode(DOUT,   INPUT);
    set_gain(gain);
}

bool HX711::is_ready() {
    return digitalRead(DOUT) == LOW;
}

void HX711::set_gain(byte gain) {
    switch (gain) {
        case 128: GAIN = 1; break;
        case 64:  GAIN = 3; break;
        case 32:  GAIN = 2; break;
        default:  GAIN = 1; break;
    }
}

long HX711::read() {
    while (!is_ready()) {
        delayMicroseconds(100);
    }

    long data = 0;

    for (int i = 0; i < 24; i++) {
        digitalWrite(PD_SCK, HIGH);
        delayMicroseconds(1);
        data = (data << 1) | digitalRead(DOUT);
        digitalWrite(PD_SCK, LOW);
        delayMicroseconds(1);
    }

    // Extra pulses set gain for next reading (1=128, 2=32, 3=64)
    for (byte i = 0; i < GAIN; i++) {
        digitalWrite(PD_SCK, HIGH);
        delayMicroseconds(1);
        digitalWrite(PD_SCK, LOW);
        delayMicroseconds(1);
    }

    // Sign-extend 24-bit two's complement to 32-bit
    if (data & 0x800000) {
        data |= 0xFF000000;
    }

    return data;
}

long HX711::read_average(byte times) {
    long sum = 0;
    for (byte i = 0; i < times; i++) {
        sum += read();
    }
    return sum / times;
}

double HX711::get_value(byte times) {
    return read_average(times) - OFFSET;
}

float HX711::get_units(byte times) {
    return (float)get_value(times) / SCALE;
}

void HX711::tare(byte times) {
    OFFSET = read_average(times);
}

void HX711::set_scale(float scale) {
    SCALE = scale;
}

float HX711::get_scale() {
    return SCALE;
}

void HX711::set_offset(long offset) {
    OFFSET = offset;
}

long HX711::get_offset() {
    return OFFSET;
}

void HX711::wait_ready(unsigned long delay_ms) {
    while (!is_ready()) {
        delay(delay_ms > 0 ? delay_ms : 1);
    }
}

bool HX711::wait_ready_retry(int retries, unsigned long delay_ms) {
    for (int i = 0; i < retries; i++) {
        if (is_ready()) return true;
        delay(delay_ms > 0 ? delay_ms : 1);
    }
    return false;
}

bool HX711::wait_ready_timeout(unsigned long timeout, unsigned long delay_ms) {
    unsigned long start = millis();
    while (millis() - start < timeout) {
        if (is_ready()) return true;
        delay(delay_ms > 0 ? delay_ms : 1);
    }
    return false;
}

void HX711::power_down() {
    digitalWrite(PD_SCK, LOW);
    digitalWrite(PD_SCK, HIGH);
    delayMicroseconds(65);
}

void HX711::power_up() {
    digitalWrite(PD_SCK, LOW);
}
