// E005_linearity.ino
// Linearity characterisation — 3-cell YZC-161A parallel platform, GISLAB HX711, ESP32-C3 SuperMini
// Non-blocking state machine throughout. No String, no double, no HX711 library.

#include <math.h>

// ----- Pin definitions -----
#define DOUT_PIN            4
#define SCK_PIN             3

// ----- Calibration (locked from 3E-001 — never change here) -----
#define CAL_FACTOR_LOCKED   36.1f

// ----- Phase 0: settling -----
#define SETTLE_STD_GATE     500.0f
#define SETTLE_DRIFT_GATE   500.0f
#define SETTLE_BLOCK_SIZE   200
#define SETTLE_CONSEC       3

// ----- Phase 1: stabilising -----
#define STAB_WIN_SIZE       20
#define STAB_CONSEC         3

// ----- Measurement -----
#define CAPTURE_N           200
#define MAX_POINTS          20
#define SAMPLE_INTERVAL_MS  12

// =============================================================
// State machines
// =============================================================

enum Phase {
    PHASE_SETTLE,
    PHASE_STAB,
    PHASE_MEASURE,
    PHASE_DONE
};

enum MeasState {
    MS_READY,
    MS_WAIT_ENTER,
    MS_GET_WEIGHT,
    MS_READ_WEIGHT,
    MS_STABILIZE,
    MS_CAPTURE,
    MS_PRINT,
    MS_CONTINUE,
    MS_WAIT_YN,
    MS_DONE
};

static Phase     g_phase      = PHASE_SETTLE;
static MeasState g_meas_state = MS_READY;

// =============================================================
// Welford online algorithm — float only
// =============================================================

struct Welford { float mean, M2; int n; };

static void wf_reset(Welford *w) {
    w->mean = 0.0f; w->M2 = 0.0f; w->n = 0;
}

static void wf_update(Welford *w, float x) {
    w->n++;
    float d   = x - w->mean;
    w->mean  += d / (float)w->n;
    w->M2    += d * (x - w->mean);   // delta before and after mean update — Welford identity
}

static float wf_std(const Welford *w) {
    return (w->n >= 2) ? sqrtf(w->M2 / (float)w->n) : 0.0f;
}

// =============================================================
// Phase 0 state
// =============================================================

static Welford settle_wf;
static int     settle_n         = 0;
static int     settle_consec    = 0;
static float   settle_prev_mean = 0.0f;
static float   noise_std_raw    = 0.0f;

// =============================================================
// Phase 1 state
// =============================================================

static Welford stab_wf;
static int     stab_n           = 0;
static int     stab_consec      = 0;
static float   stab_prev_mean   = 0.0f;
static float   tare_raw         = 0.0f;
static float   spread_gate      = 0.0f;
static float   drift_gate       = 0.0f;

// =============================================================
// Measurement state
// =============================================================

static int   point_count               = 0;
static float points_actual[MAX_POINTS];
static float points_raw_delta[MAX_POINTS];
static float points_impl_cf[MAX_POINTS];
static float cumulative_weight         = 0.0f;
static float current_actual            = 0.0f;

static Welford meas_stab_wf;
static int     meas_stab_n             = 0;
static int     meas_stab_consec        = 0;
static float   meas_stab_prev          = 0.0f;

static Welford cap_wf;
static int     cap_valid               = 0;

// =============================================================
// Serial input
// =============================================================

static char serial_buf[32];
static int  serial_buf_len = 0;

// =============================================================
// Timing
// =============================================================

static unsigned long last_sample_ms = 0;

// =============================================================
// HX711 raw bit-bang — Channel A Gain 128
// noInterrupts() wraps all 25 pulses to prevent glitched clocking
// Returns 0L on any corrupt value; caller discards those
// =============================================================
static long hx711_read(void) {
    long raw = 0L;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK_PIN, HIGH);
        delayMicroseconds(1);
        raw = (raw << 1) | digitalRead(DOUT_PIN);
        digitalWrite(SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 25th pulse: tells HX711 to use Channel A Gain 128 for the next conversion
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();

    // Sign-extend bit 23 to produce a correct 32-bit two's-complement value
    if (raw & 0x800000L) raw |= 0xFF000000L;

    // Hardware-derived corrupt patterns observed on this platform — discard silently
    if (raw == LONG_MIN)   return 0L;
    if (raw == -1L)        return 0L;
    if (raw == 0x7FFFFFL)  return 0L;
    return raw;
}

// =============================================================
// Non-blocking serial line reader
// Accumulates characters until '\n'; result left in serial_buf
// =============================================================
static bool poll_serial_line(void) {
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\r') continue;
        if (c == '\n') {
            serial_buf[serial_buf_len] = '\0';
            return true;
        }
        if (serial_buf_len < (int)(sizeof(serial_buf) - 1))
            serial_buf[serial_buf_len++] = c;
    }
    return false;
}

static void serial_buf_reset(void) {
    serial_buf_len = 0;
    serial_buf[0]  = '\0';
}

// =============================================================
// Phase 0 — settling monitor
// Blocks of SETTLE_BLOCK_SIZE samples; 3 consecutive blocks
// must pass both gates before deriving noise_std_raw.
// =============================================================
static void handle_settle(long raw) {
    if (raw == 0L) return;
    wf_update(&settle_wf, (float)raw);
    if (++settle_n < SETTLE_BLOCK_SIZE) return;

    float std   = wf_std(&settle_wf);
    float mean  = settle_wf.mean;
    float drift = fabsf(mean - settle_prev_mean);

    char buf[80];
    snprintf(buf, sizeof(buf), "[SETTLE] blk=%d std=%.1f drift=%.1f",
             settle_consec + 1, std, drift);
    Serial.print(buf);

    // First block has no valid drift reference (prev_mean is 0), so skip it
    bool pass = (std < SETTLE_STD_GATE) &&
                (settle_consec == 0 || drift < SETTLE_DRIFT_GATE);
    Serial.println(pass ? " PASS" : " FAIL");

    if (pass) {
        noise_std_raw = std;   // last passing block wins; conservative for outlier protection
        settle_consec++;
    } else {
        settle_consec = 0;
    }
    settle_prev_mean = mean;
    wf_reset(&settle_wf);
    settle_n = 0;

    if (settle_consec >= SETTLE_CONSEC) {
        char buf2[64];
        snprintf(buf2, sizeof(buf2), "[SETTLE] DONE  noise_std_raw=%.2f raw", noise_std_raw);
        Serial.println(buf2);
        spread_gate = 1.5f * noise_std_raw;
        drift_gate  = 1.0f * noise_std_raw;
        snprintf(buf2, sizeof(buf2),
                 "[STAB]   spread_gate=%.2f  drift_gate=%.2f", spread_gate, drift_gate);
        Serial.println(buf2);
        g_phase = PHASE_STAB;
    }
}

// =============================================================
// Phase 1 — stabilising, locks tare_raw
// Windows of STAB_WIN_SIZE; 3 consecutive passing windows.
// tare_raw is set to the mean of the final passing window.
// Never re-tared after this point.
// =============================================================
static void handle_stab(long raw) {
    if (raw == 0L) return;
    wf_update(&stab_wf, (float)raw);
    if (++stab_n < STAB_WIN_SIZE) return;

    float std   = wf_std(&stab_wf);
    float mean  = stab_wf.mean;
    float drift = fabsf(mean - stab_prev_mean);

    char buf[80];
    snprintf(buf, sizeof(buf), "[STAB] win=%d std=%.2f drift=%.2f",
             stab_consec + 1, std, drift);
    Serial.print(buf);

    // First window (or window after reset) has no valid drift reference
    bool pass = (std < spread_gate) &&
                (stab_consec == 0 || drift < drift_gate);
    Serial.println(pass ? " PASS" : " FAIL");

    if (pass) {
        tare_raw = mean;   // keep updating; value at consec == STAB_CONSEC is the lock
        stab_consec++;
    } else {
        stab_consec = 0;
    }
    stab_prev_mean = mean;
    wf_reset(&stab_wf);
    stab_n = 0;

    if (stab_consec >= STAB_CONSEC) {
        char buf2[64];
        snprintf(buf2, sizeof(buf2), "[TARE] tare_raw=%.0f locked", tare_raw);
        Serial.println(buf2);
        g_phase = PHASE_MEASURE;
    }
}

// =============================================================
// Summary table — printed once at end of experiment
// =============================================================
static void print_summary(void) {
    Serial.println("\n=== E-005 LINEARITY SUMMARY ===");
    Serial.println("N  actual_g  raw_delta  impl_CF  reported_g  error_g  error_pct");
    char buf[100];
    for (int i = 0; i < point_count; i++) {
        float rep_g   = points_raw_delta[i] / CAL_FACTOR_LOCKED;
        float err_g   = rep_g - points_actual[i];
        float err_pct = (points_actual[i] > 0.0f)
                        ? err_g / points_actual[i] * 100.0f : 0.0f;
        snprintf(buf, sizeof(buf),
                 "%-2d %-9.0f %-11.0f %-9.2f %-12.1f %-9.1f %.1f%%",
                 i + 1,
                 points_actual[i],
                 points_raw_delta[i],
                 points_impl_cf[i],
                 rep_g,
                 err_g,
                 err_pct);
        Serial.println(buf);
    }
    Serial.println("==============================");
    Serial.println("Experiment complete. Paste summary to chat.");
}

// =============================================================
// PHASE_MEASURE — interactive measurement loop
// Called every loop() iteration.
// Sample-consuming states (STABILIZE, CAPTURE) gate on new_sample.
// Serial-input states run every iteration regardless.
// =============================================================
static void handle_measure(long raw, bool new_sample) {
    char buf[80];

    switch (g_meas_state) {

    case MS_READY:
        Serial.println("\n=== READY FOR NEXT WEIGHT ===");
        snprintf(buf, sizeof(buf), "Current stack on platform (g): %.0f", cumulative_weight);
        Serial.println(buf);
        Serial.println("Press Enter when ready to place/add weight.");
        serial_buf_reset();
        g_meas_state = MS_WAIT_ENTER;
        break;

    case MS_WAIT_ENTER:
        if (poll_serial_line()) {
            serial_buf_reset();
            g_meas_state = MS_GET_WEIGHT;
        }
        break;

    case MS_GET_WEIGHT:
        Serial.println("Enter total weight now on platform (grams):");
        serial_buf_reset();
        g_meas_state = MS_READ_WEIGHT;
        break;

    case MS_READ_WEIGHT:
        if (poll_serial_line()) {
            current_actual = atof(serial_buf);
            snprintf(buf, sizeof(buf), "Weight locked: %.1f g", current_actual);
            Serial.println(buf);
            serial_buf_reset();
            // Reset stability tracking for this measurement point
            wf_reset(&meas_stab_wf);
            meas_stab_n      = 0;
            meas_stab_consec = 0;
            meas_stab_prev   = 0.0f;
            g_meas_state = MS_STABILIZE;
        }
        break;

    case MS_STABILIZE:
        if (!new_sample || raw == 0L) break;
        wf_update(&meas_stab_wf, (float)raw);
        if (++meas_stab_n < STAB_WIN_SIZE) break;
        {
            float std   = wf_std(&meas_stab_wf);
            float mean  = meas_stab_wf.mean;
            float drift = fabsf(mean - meas_stab_prev);

            snprintf(buf, sizeof(buf), "[STAB] win=%d std=%.2f drift=%.2f",
                     meas_stab_consec + 1, std, drift);
            Serial.print(buf);

            bool pass = (std < spread_gate) &&
                        (meas_stab_consec == 0 || drift < drift_gate);
            Serial.println(pass ? " PASS" : " FAIL");

            if (pass) meas_stab_consec++;
            else      meas_stab_consec = 0;

            meas_stab_prev = mean;
            wf_reset(&meas_stab_wf);
            meas_stab_n = 0;

            if (meas_stab_consec >= STAB_CONSEC) {
                Serial.println("[STABLE] Capturing 200-sample mean...");
                wf_reset(&cap_wf);
                cap_valid    = 0;
                g_meas_state = MS_CAPTURE;
            }
        }
        break;

    case MS_CAPTURE:
        if (!new_sample || raw == 0L) break;
        wf_update(&cap_wf, (float)raw);
        if (++cap_valid < CAPTURE_N) break;
        snprintf(buf, sizeof(buf), "mean_raw=%.2f", cap_wf.mean);
        Serial.println(buf);
        g_meas_state = MS_PRINT;
        break;

    case MS_PRINT:
        {
            float raw_delta  = cap_wf.mean - tare_raw;
            float implied_cf = (current_actual > 0.0f) ? raw_delta / current_actual : 0.0f;
            float reported_g = raw_delta / CAL_FACTOR_LOCKED;
            float error_g    = reported_g - current_actual;
            float error_pct  = (current_actual > 0.0f)
                               ? error_g / current_actual * 100.0f : 0.0f;

            if (point_count < MAX_POINTS) {
                points_actual[point_count]    = current_actual;
                points_raw_delta[point_count] = raw_delta;
                points_impl_cf[point_count]   = implied_cf;
                point_count++;
            }

            snprintf(buf, sizeof(buf), "--- POINT %d ---", point_count);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "actual_g    : %.0f", current_actual);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "raw_delta   : %.0f", raw_delta);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "implied_cf  : %.2f raw/g", implied_cf);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "reported_g  : %.1f g  (using CF=36.1)", reported_g);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "error_g     : %.1f g", error_g);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "error_pct   : %.1f %%", error_pct);
            Serial.println(buf);
            Serial.println("---------------");
            g_meas_state = MS_CONTINUE;
        }
        break;

    case MS_CONTINUE:
        if (point_count >= MAX_POINTS) {
            print_summary();
            g_meas_state = MS_DONE;
            g_phase      = PHASE_DONE;
        } else {
            Serial.println("Add more weight? (y/n):");
            serial_buf_reset();
            g_meas_state = MS_WAIT_YN;
        }
        break;

    case MS_WAIT_YN:
        if (poll_serial_line()) {
            char choice = serial_buf[0];
            serial_buf_reset();
            if (choice == 'y' || choice == 'Y') {
                cumulative_weight = current_actual;
                g_meas_state      = MS_READY;
            } else {
                print_summary();
                g_meas_state = MS_DONE;
                g_phase      = PHASE_DONE;
            }
        }
        break;

    case MS_DONE:
        break;
    }
}

// =============================================================
void setup(void) {
    Serial.begin(115200);
    pinMode(DOUT_PIN, INPUT_PULLUP);
    pinMode(SCK_PIN,  OUTPUT);
    digitalWrite(SCK_PIN, LOW);   // idle LOW — HX711 in normal operating mode, not power-down

    wf_reset(&settle_wf);
    Serial.println("E-005 Linearity characterisation — 3-cell YZC-161A");
    Serial.println("[SETTLE] Waiting for platform to settle (3 x 200-sample blocks)...");
}

void loop(void) {
    unsigned long now = millis();
    long raw        = 0L;
    bool new_sample = false;

    // millis() gate + DOUT ready check — never block waiting for data
    if ((now - last_sample_ms) >= SAMPLE_INTERVAL_MS &&
        digitalRead(DOUT_PIN) == LOW) {
        raw            = hx711_read();
        last_sample_ms = now;
        new_sample     = true;
    }

    switch (g_phase) {
    case PHASE_SETTLE:  handle_settle(raw);                break;
    case PHASE_STAB:    handle_stab(raw);                  break;
    case PHASE_MEASURE: handle_measure(raw, new_sample);   break;
    case PHASE_DONE:                                       break;
    }
}
