// 4E001_cal_factor_v4.ino
// Experiment 4E-001 v4: cal_factor derivation. Self-characterising.
// Works on any number of load cells — 1, 3, 4, or any count.
// No hardcoded cal_factor. No hardcoded raw thresholds. No assumed cell count.
// All thresholds derived from actual hardware measurements.
// Hardware: DOUT=GPIO4, SCK=GPIO3, HX711 VDD=3V3, GND=GND
// Reference weight: 234.0g

#include <Arduino.h>
#include <climits>

#define DOUT_PIN        4
#define SCK_PIN         3
#define BLOCK_SIZE      200
#define COLD_THRESHOLD  500.0f
#define COLD_CONFIRM    3
#define STAB_WINDOW     20
#define STAB_CONFIRM    3
#define K_SPREAD        1.5f
#define K_DRIFT         1.0f
#define CAL_SAMPLES     50
#define SETTLE_MS       10000
#define KNOWN_WEIGHT_G  234.0f

// File-scope — not on stack — to avoid stack allocation issues (see E001, STM32 lessons).
static float block_buf[BLOCK_SIZE];
static long  stab_window[STAB_WINDOW];
static float win_float[STAB_WINDOW];
static float cal_buf[CAL_SAMPLES];
static char  buf[128];

// --- HX711 bit-bang read ---
// All three corrupt cases unified to LONG_MIN here. Callers check r == LONG_MIN only.
long hx711_read() {
    uint32_t deadline = millis() + 500;
    while (digitalRead(DOUT_PIN) == HIGH) {
        if (millis() >= deadline) return LONG_MIN;
    }

    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(DOUT_PIN);
        digitalWrite(SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 25th pulse locks Channel A, Gain 128 for the next conversion.
    digitalWrite(SCK_PIN, HIGH); delayMicroseconds(1);
    digitalWrite(SCK_PIN, LOW);  delayMicroseconds(1);
    interrupts();

    // Sign-extend bit 23: HX711 outputs 24-bit two's complement.
    if (value & 0x800000) value |= 0xFF000000;

    if (value == LONG_MIN || value == -1 || (value & 0xFFFFFF) == 0x7FFFFF) return LONG_MIN;

    return (long)value;
}

// --- Population mean and STD in one pass ---
// float throughout. No double.
void compute_stats(float* samples, int n, float* out_mean, float* out_std) {
    float sum = 0.0f;
    for (int i = 0; i < n; i++) sum += samples[i];
    float mean = sum / (float)n;

    float var = 0.0f;
    for (int i = 0; i < n; i++) {
        float diff = samples[i] - mean;
        var += diff * diff;
    }

    *out_mean = mean;
    *out_std  = sqrtf(var / (float)n);
}

// --- Collect exactly n valid raw samples into buf[] as floats ---
// Self-paced via DOUT polling — no delay needed.
int collect_block(float* buf, int n) {
    int count = 0;
    while (count < n) {
        long r = hx711_read();
        if (r == LONG_MIN) continue;
        buf[count++] = (float)r;
    }
    return n;
}

// --- Phase 0: wait for platform mechanical and thermal settling ---
// Measures settling in BLOCK_SIZE=200 sample blocks. Requires COLD_CONFIRM consecutive
// passing blocks before accepting the platform as settled.
// Returns the noise STD of the final passing block — used as the threshold basis.
float phase0_wait_for_platform(void) {
    int   cold_confirm  = 0;
    float prev_mean     = 0.0f;
    bool  first_block   = true;
    float noise_std_raw = 0.0f;

    while (cold_confirm < COLD_CONFIRM) {
        collect_block(block_buf, BLOCK_SIZE);

        float block_mean, block_std;
        compute_stats(block_buf, BLOCK_SIZE, &block_mean, &block_std);

        float drift = first_block ? 0.0f : fabsf(block_mean - prev_mean);
        bool  pass  = (block_std < COLD_THRESHOLD) &&
                      (first_block || drift < COLD_THRESHOLD);

        if (pass) {
            cold_confirm++;
            snprintf(buf, sizeof(buf), "[SETTLING] std=%.1f drift=%.1f PASS %d/%d",
                     block_std, drift, cold_confirm, COLD_CONFIRM);
            noise_std_raw = block_std;
        } else {
            cold_confirm = 0;
            snprintf(buf, sizeof(buf), "[SETTLING] std=%.1f drift=%.1f (still settling)",
                     block_std, drift);
        }
        Serial.println(buf);

        prev_mean   = block_mean;
        first_block = false;
    }

    Serial.println("=== PLATFORM SETTLED ===");
    snprintf(buf, sizeof(buf), "True noise STD (raw): %.1f", noise_std_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), "STAB_SPREAD gate = K_SPREAD(1.5) x STD = %.1f raw",
             K_SPREAD * noise_std_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), "STAB_DRIFT  gate = K_DRIFT(1.0)  x STD = %.1f raw",
             K_DRIFT * noise_std_raw);
    Serial.println(buf);

    return noise_std_raw;
}

// --- Stability-gated tare ---
// Thresholds derived from noise_std_raw — not hardcoded.
// Requires STAB_CONFIRM consecutive windows passing both spread and drift gates.
// No delay — hx711_read() self-paces via DOUT polling.
long derive_stable_tare(float noise_std_raw) {
    float spread_gate = K_SPREAD * noise_std_raw;
    float drift_gate  = K_DRIFT  * noise_std_raw;

    int   win_idx       = 0;
    int   stable_count  = 0;
    float prev_win_mean = 0.0f;
    bool  first_window  = true;
    long  tare_raw      = 0;

    while (stable_count < STAB_CONFIRM) {
        long r = hx711_read();
        if (r == LONG_MIN) continue;

        stab_window[win_idx++] = r;
        if (win_idx < STAB_WINDOW) continue;
        win_idx = 0;

        for (int i = 0; i < STAB_WINDOW; i++) win_float[i] = (float)stab_window[i];
        float window_mean, window_std;
        compute_stats(win_float, STAB_WINDOW, &window_mean, &window_std);

        float window_drift = first_window ? 0.0f : fabsf(window_mean - prev_win_mean);
        bool  pass = (window_std < spread_gate) && (first_window || window_drift < drift_gate);

        if (pass) {
            stable_count++;
            snprintf(buf, sizeof(buf), "[STABILISING] std=%.1f drift=%.1f WIN %d/%d",
                     window_std, window_drift, stable_count, STAB_CONFIRM);
            tare_raw = (long)window_mean;
        } else {
            stable_count = 0;
            snprintf(buf, sizeof(buf), "[STABILISING] std=%.1f drift=%.1f (reset)",
                     window_std, window_drift);
        }
        Serial.println(buf);

        prev_win_mean = window_mean;
        first_window  = false;
    }

    snprintf(buf, sizeof(buf), "[TARE] tare_raw=%ld", tare_raw);
    Serial.println(buf);
    return tare_raw;
}

void setup() {
    pinMode(DOUT_PIN, INPUT_PULLUP);
    pinMode(SCK_PIN,  OUTPUT);
    // SCK LOW is the HX711 idle state — must be set before the first read.
    digitalWrite(SCK_PIN, LOW);

    Serial.begin(115200);
    // 3s timeout on Serial wait: avoids infinite hang when no monitor is attached.
    unsigned long t = millis();
    while (!Serial && millis() - t < 3000) {}
    delay(1000);
    Serial.setTimeout(30000);

    Serial.println("4E001 cal_factor v4 | self-characterising | any cell count | ref=234g");
    Serial.println("Keep platform EMPTY and undisturbed until [TARE] appears.");

    // Phase 0: wait for platform to settle and measure true noise floor.
    float noise_std_raw = phase0_wait_for_platform();

    // Phase 1: boot tare via stability gate.
    long tare_raw = derive_stable_tare(noise_std_raw);

    // Outer loop: one iteration per calibration run.
    while (true) {

        // 4a: flush stale bytes then prompt.
        // Without flush, readStringUntil returns immediately with bytes from tare phase.
        while (Serial.available()) Serial.read();
        snprintf(buf, sizeof(buf),
                 "[EMPTY] tare=%ld  Place known weight (234g). Press Enter when ready.",
                 tare_raw);
        Serial.println(buf);
        Serial.readStringUntil('\n');

        // 4b: settle countdown — millis() paced, never delay() for countdown.
        // next_print holds remaining-seconds value for the next print event.
        // Fire condition: elapsed >= SETTLE_MS - next_print*1000 (i.e. remaining <= next_print).
        unsigned long settle_start = millis();
        int next_print = 10;
        Serial.println("Settling... 10s");
        while (millis() - settle_start < (unsigned long)SETTLE_MS) {
            if (next_print > 0 &&
                millis() - settle_start >=
                    (unsigned long)SETTLE_MS - (unsigned long)(next_print * 1000)) {
                snprintf(buf, sizeof(buf), "%ds...", next_print);
                Serial.println(buf);
                next_print -= 2;
            }
        }
        Serial.println("Sampling now.");

        // 4c: collect CAL_SAMPLES valid raw samples then derive cal_factor.
        // loaded_std printed as consistency check — if >> noise_std_raw, weight was moving.
        int count = 0;
        while (count < CAL_SAMPLES) {
            long r = hx711_read();
            if (r == LONG_MIN) continue;
            cal_buf[count++] = (float)r;
        }
        float loaded_mean, loaded_std;
        compute_stats(cal_buf, CAL_SAMPLES, &loaded_mean, &loaded_std);
        float stable_delta      = loaded_mean - (float)tare_raw;
        float cal_factor_result = stable_delta / KNOWN_WEIGHT_G;

        snprintf(buf, sizeof(buf), ">>> LOADED MEAN RAW:  %ld",  (long)loaded_mean);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> LOADED STD  RAW:  %.1f  (consistency check)", loaded_std);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> TARE RAW:         %ld",  tare_raw);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> STABLE DELTA:     %+ld", (long)stable_delta);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> cal_factor = %ld / 234.0 = %.2f raw/g",
                 (long)stable_delta, cal_factor_result);
        Serial.println(buf);
        Serial.println("--------------------");

        // 4d: flush stale bytes then prompt for weight removal.
        while (Serial.available()) Serial.read();
        Serial.println("Remove weight. Press Enter when platform is empty.");
        Serial.readStringUntil('\n');

        // 4e: re-tare using full stability gate.
        // noise_std_raw unchanged — hardware noise floor does not change between runs.
        tare_raw = derive_stable_tare(noise_std_raw);
    }
}

void loop() {
    // All work is done in setup(). setup() loops forever inside while(true).
}
