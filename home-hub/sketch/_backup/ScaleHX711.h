#ifndef SCALEHX711_H
#define SCALEHX711_H

#include <Arduino.h>

class ScaleHX711 {
private:
    int _dt;
    int _sck;
    uint8_t _gain;
    int32_t _offset;
    float _scale;
    int32_t _lastRaw;
    float _lastWeight;
    bool _stable;
    bool _available;
    bool _fresh;
    bool _initialized;
    unsigned long _lastReadTime;
    int32_t _stabilityThreshold;

    bool is_ready();
    bool is_valid_nonzero(float value);
    int32_t read_raw_internal();

public:
    ScaleHX711();
    void begin(int dt, int sck, uint8_t gain = 128);
    void update();

    void tare(int samples = 10);
    void set_scale(float scale);
    void set_gain(uint8_t gain = 128);
    void calibrate(float known_weight, int samples = 10);

    int32_t read_average(int samples = 10);
    float get_units(int samples = 1);

    float get_weight();
    int32_t get_raw();
    bool is_stable();
    bool available();
    bool fresh();
    bool initialized();
    unsigned long last_read_time();
    void set_stability_threshold(int32_t counts);

    void power_down();
    void power_up();
};

#endif
