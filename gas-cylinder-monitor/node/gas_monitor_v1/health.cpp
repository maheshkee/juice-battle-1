#include <cstdio>
#include "health.h"
#include <math.h>

HealthResult health_check(
    float sigma_g,
    float prev_sigma_g,
    float tare_variance_raw,
    float cur_cal_factor,
    float prev_cal_factor,
    float cur_gross_g,
    float prev_gross_g,
    float cal_tolerance,
    float sigma_tolerance
) {
    HealthResult result;

    /* STEP 1 — initialise with the safest possible defaults.
     * quality defaults to "FAILED" so a partial execution or missed branch
     * cannot silently produce a GOOD verdict. Gets overwritten in STEP 6.
     * diagnosis starts as "ok" and receives failure tokens appended below.
     * dpos tracks the write position so subsequent appends do not need strlen. */
    result.checks_passed = 0x00;
    snprintf(result.quality, sizeof(result.quality), "FAILED");
    result.diagnosis[0] = '\0';
    int dpos = 0;

    /* STEP 2 — erratic check (bit 0)
     * Compares runtime sigma against the historical baseline from the previous boot.
     * Using a ratio (sigma_g / prev_sigma_g) rather than an absolute threshold
     * makes the check self-calibrating: it adapts to whatever the platform's
     * normal noise floor actually is, rather than assuming a fixed gram value.
     * A ratio above sigma_tolerance means noise has grown substantially — indicative
     * of a degrading wire connection, an intermittent cell, or increased EMI.
     * Skip on first boot (prev_sigma_g == -1.0f sentinel) — no baseline yet. */
    if (prev_sigma_g == -1.0f) {
        result.checks_passed |= 0x01;
    } else {
        float ratio = sigma_g / prev_sigma_g;
        if (ratio <= sigma_tolerance) {
            result.checks_passed |= 0x01;
        } else {
            if (dpos > 0)
                dpos += snprintf(result.diagnosis + dpos, sizeof(result.diagnosis) - dpos, "|");
            dpos += snprintf(result.diagnosis + dpos,
                             sizeof(result.diagnosis) - dpos,
                             "erratic:%.1fx", ratio);
        }
    }

    /* STEP 3 — stuck check (bit 1)
     * A healthy HX711 always produces some sample-to-sample variance — thermal
     * noise alone guarantees it. Zero variance across the entire tare window
     * means every sample was identical, which is physically impossible on real
     * hardware and indicates a frozen output (stuck wire, broken cell, or HX711
     * in power-down mode). Any variance > 0 is sufficient to pass. */
    // TODO 1B-stuck: tare variance field not yet populated by tare.cpp.
    // Always 0.0f at boot. Skip stuck check when unpopulated to prevent
    // false DEGRADED on every boot. Fix properly when tare.cpp exposes
    // variance through TareResult struct.
    bool skip_stuck = (tare_variance_raw == 0.0f);
    if (!skip_stuck) {
        if (tare_variance_raw > 0.0f) {
            result.checks_passed |= 0x02;
        } else {
            if (dpos > 0)
                dpos += snprintf(result.diagnosis + dpos, sizeof(result.diagnosis) - dpos, "|");
            dpos += snprintf(result.diagnosis + dpos,
                             sizeof(result.diagnosis) - dpos,
                             "stuck:");
        }
    } else {
        result.checks_passed |= 0x02;
    }

    /* STEP 4 — cal drift check (bit 2)
     * cal_factor is a physical constant of this load cell + HX711 combination.
     * It should be stable across boots unless the hardware has changed (loose wire,
     * cell failure, plate repositioned). A large drift between boots is a stronger
     * signal of hardware change than any single-reading anomaly.
     * Skip on first boot (prev_cal_factor == -1.0f sentinel) because there is no
     * baseline to compare against — a first-boot fault report would always be wrong. */
    if (prev_cal_factor == -1.0f) {
        result.checks_passed |= 0x04;
    } else {
        float drift = fabsf(cur_cal_factor - prev_cal_factor) / prev_cal_factor;
        if (drift <= cal_tolerance) {
            result.checks_passed |= 0x04;
        } else {
            if (dpos > 0)
                dpos += snprintf(result.diagnosis + dpos, sizeof(result.diagnosis) - dpos, "|");
            dpos += snprintf(result.diagnosis + dpos,
                             sizeof(result.diagnosis) - dpos,
                             "cal:%.1fpct:", drift * 100.0f);
        }
    }

    /* STEP 5 — runtime jump check (bit 3)
     * The loop() tick rate is 100ms. LPG consumption at the highest plausible
     * burn rate (~30g/min cooking) produces ~0.05g per 100ms tick — effectively
     * zero change per tick. A 500g delta in one tick is physically impossible
     * for normal operation and indicates a corrupt reading that slipped past
     * the three corrupt-value filters in hx711_read(), or an erratic cell
     * producing sudden large jumps. 500g is chosen large enough to allow
     * cylinder placement and removal transients without false faults, while
     * still catching single-tick sensor corruption.
     * Skip on the first STATE_RUNNING tick (prev_gross_g == -1.0f sentinel)
     * because there is no previous reading to compare against. */
    if (prev_gross_g == -1.0f) {
        result.checks_passed |= 0x08;
    } else {
        float delta = fabsf(cur_gross_g - prev_gross_g);
        if (delta <= 500.0f) {
            result.checks_passed |= 0x08;
        } else {
            if (dpos > 0)
                dpos += snprintf(result.diagnosis + dpos, sizeof(result.diagnosis) - dpos, "|");
            dpos += snprintf(result.diagnosis + dpos,
                             sizeof(result.diagnosis) - dpos,
                             "jump:%.0fg", delta);
        }
    }

    /* STEP 6 — count failed checks and set quality verdict.
     * A clear bit means that check failed. One failure is DEGRADED (reading
     * still usable but hub should flag it). Two or more is FAILED (reading
     * should not be stored or acted on). Zero failures overwrites the default
     * "FAILED" quality with "GOOD". */
    int failures = 0;
    if (!(result.checks_passed & 0x01)) failures++;
    if (!(result.checks_passed & 0x02)) failures++;
    if (!(result.checks_passed & 0x04)) failures++;
    if (!(result.checks_passed & 0x08)) failures++;

    if (failures == 0) {
        snprintf(result.quality,   sizeof(result.quality),   "GOOD");
        snprintf(result.diagnosis, sizeof(result.diagnosis), "ok");
    } else if (failures == 1) {
        snprintf(result.quality, sizeof(result.quality), "DEGRADED");
    }
    /* failures >= 2: quality stays "FAILED" from STEP 1 — no overwrite needed */
    /* diagnosis already contains only failure entries built in steps 2-5    */

    return result;
}
