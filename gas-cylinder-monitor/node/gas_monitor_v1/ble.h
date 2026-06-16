#pragma once
#include <Arduino.h>

void ble_init();
void ble_notify(float grams, const char* quality_str, float sigma_g);
