#ifndef HEALTH_H
#define HEALTH_H

#include <stdint.h>

/*
 * HealthResult - verdict from a single health_check() call.
 *
 * Returned by value so the orchestrator can inspect it without
 * holding a pointer into module-internal state.
 */
struct HealthResult {
    /* Coarse verdict string.
     * "GOOD"     - all enabled checks passed.
     * "DEGRADED" - at least one check failed but the reading is still usable.
     * "FAILED"   - a check failed in a way that makes the reading untrustworthy.
     * 12 bytes covers the longest value ("DEGRADED\0") with margin.
     * char array, not String, because the String class is prohibited in this sketch. */
    char quality[12];

    /* Human-readable explanation of which check failed and what the values were.
     * Written via snprintf so the orchestrator can forward it directly to Serial
     * without heap allocation. 64 bytes matches the diagnosis field in all other
     * module result structs for consistency. */
    char diagnosis[64];

    /* Bitmask of individual check outcomes. Each bit is 1 if that check passed.
     * Lets the orchestrator (or hub) inspect individual checks without parsing
     * the diagnosis string. Useful for future per-check analytics in SQLite.
     *   bit 0 (0x01) - erratic_ok  : runtime sigma within tolerance of boot sigma
     *   bit 1 (0x02) - stuck_ok    : reading is not frozen (variance > zero floor)
     *   bit 2 (0x04) - cal_ok      : current cal_factor within tolerance of previous boot
     *   bit 3 (0x08) - runtime_ok  : gross weight within physically plausible range */
    uint8_t checks_passed;
};

/*
 * health_check() - evaluate load cell and calibration health at runtime.
 *
 * Called by the orchestrator on every STATE_RUNNING tick after weight_update().
 * All thresholds are passed in as parameters — nothing is hardcoded here.
 * The caller decides what "too much drift" means; this function only computes
 * and reports.
 *
 * Parameters:
 *
 *   sigma_g
 *     Runtime sigma derived from the 20-sample weight buffer (in grams).
 *     A sudden spike above prev_sigma_g scaled by sigma_tolerance suggests an
 *     erratic cell — intermittent contact or one cell oscillating.
 *
 *   prev_sigma_g
 *     Sigma from the last known-good boot, loaded from config.json.
 *     Used as the historical noise baseline for the erratic check. A ratio of
 *     sigma_g / prev_sigma_g above sigma_tolerance flags erratic behaviour.
 *     Sentinel -1.0f means first boot — no baseline exists yet, skip check.
 *
 *   tare_variance_raw
 *     Variance of the raw tare window collected during the boot settle phase.
 *     Abnormally high variance at boot means the platform was not mechanically
 *     settled when tare was derived, which contaminates the zero reference for
 *     the entire session. Used to qualify the cal_ok and runtime_ok checks.
 *
 *   cur_cal_factor
 *     Cal factor derived this boot (raw counts per gram).
 *     Cross-checked against prev_cal_factor to detect cell failures or loose
 *     wires between power cycles.
 *
 *   prev_cal_factor
 *     Cal factor from the most recent previous boot, loaded from config.json
 *     cal_history. If -1.0f (no history exists yet), the cal_ok check is skipped
 *     rather than reporting a spurious fault on first boot. Sentinel is -1.0f,
 *     not 0.0f — a corrupt config.json could produce 0.0f, but a real cal_factor
 *     is always a large positive number (~37 raw/g on this platform), so -1.0f
 *     is physically impossible and unambiguous as a "no previous value" marker.
 *
 *   cur_gross_g
 *     Current gross weight reading in grams from the weight buffer mean.
 *     Checked against a physically plausible range: below FAIL_LOW or above
 *     FAIL_HIGH cannot be a real cylinder weight and indicates a sensor fault.
 *     The range bounds are encoded in weight.cpp; this function receives the
 *     already-computed gram value, not raw counts.
 *
 *   prev_gross_g
 *     Most recent previous gross weight reading in grams.
 *     Used to detect impossible single-tick jumps. A delta larger than any
 *     physically possible weight change in one loop() cycle (100ms) cannot
 *     be real and indicates an erratic cell or corrupt read that slipped
 *     through the corrupt filters. Pass -1.0f on the first STATE_RUNNING tick
 *     when no previous reading exists yet — the jump check is skipped for
 *     that tick rather than comparing against an invalid baseline.
 *
 *   cal_tolerance
 *     Fractional tolerance for the cal_factor cross-check (e.g. 0.15 = 15%).
 *     If |cur_cal_factor - prev_cal_factor| / prev_cal_factor exceeds this,
 *     the cal_ok bit is cleared. Passed in so the deployment can tune
 *     sensitivity without recompiling.
 *
 *   sigma_tolerance
 *     Multiplier on the boot-time sigma_g. If the runtime sigma exceeds
 *     (boot_sigma * sigma_tolerance), the erratic_ok bit is cleared.
 *     e.g. 3.0 means "flag if runtime noise is more than 3x the boot baseline".
 *     Passed in for the same reason as cal_tolerance.
 */
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
);

#endif /* HEALTH_H */
