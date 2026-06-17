#pragma once
#include <stdint.h>
#include "health.h"
#include "weight.h"

void journal_init(uint32_t boot_count);
void journal_boot_start();
void journal_phase_complete(const char* phase, const char* result,
                             float duration_s, float extra1, float extra2,
                             float extra3);
void journal_boot_complete(float total_s, float cal_factor,
                            float sigma, float tare);
void journal_run(float grams, float sigma, const HealthResult& health,
                 WeightEvent event, float delta);
void journal_heartbeat_tick(float grams, float sigma,
                             const HealthResult& health);
void journal_phase_fail(const char* phase, const char* reason, float value);
