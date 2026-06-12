// 4E001_cal_factor_v3.ino
// Experiment 4E-001 v3: cal_factor derivation on 4-cell platform.
// Self-characterising: derives all thresholds from measured hardware noise.
// No hardcoded raw thresholds. No assumed cal_factor.
// Modelled on E001 + E002 + E003 combined, working in raw counts throughout.
// Hardware: DOUT=GPIO4, SCK=GPIO3, HX711 VDD=3V3, GND=GND
// Reference weight: 597.0g (water bottle)

#include <Arduino.h>
#include <climits>

#define DOUT_PIN        4
#define SCK_PIN         3
#define NOISE_SAMPLES   200
#define STAB_WINDOW     20
#define STAB_CONFIRM    3
#define SETTLE_MS       10000
#define CAL_SAMPLES     50
#define K_SPREAD        1.5f
#define K_DRIFT         1.0f
#define KNOWN_WEIGHT_G  597.0f

// File-scope — not on stack — to avoid stack allocation issues (see E001, STM32 lessons).
static float noise_buf[NOISE_SAMPLES];
static long  stab_window[STAB_WINDOW];
static float win_float[STAB_WINDOW];   // scratch buffer for window-to-float conversion
static float cal_buf[CAL_SAMPLES];
static char  buf[128];

// --- HX711 bit-bang read (ported from E001_tare_cal_grams.ino, E003_ble_transport.ino) ---
// All three corrupt cases (timeout, all-HIGH, positive-saturation) unified to LONG_MIN here.
// Every caller uses is_corrupt() on the return value — no other corrupt checks needed.
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

    // Unified corrupt filter — all three cases return LONG_MIN.
    if (value == LONG_MIN || value == -1 || (value & 0xFFFFFF) == 0x7FFFFF) return LONG_MIN;

    return (long)value;
}

// --- Corrupt check — LONG_MIN only: all cases are unified inside hx711_read() ---
bool is_corrupt(long v) {
    return v == LONG_MIN;
}

// --- Float statistics helpers ---
float compute_mean(float* samples, int n) {
    float sum = 0.0f;
    for (int i = 0; i < n; i++) sum += samples[i];
    return sum / (float)n;
}

float compute_std(float* samples, int n) {
    float mean = compute_mean(samples, n);
    float var  = 0.0f;
    for (int i = 0; i < n; i++) {
        float diff = samples[i] - mean;
        var += diff * diff;
    }
    return sqrtf(var / (float)n);
}

// Convert long window to float, then delegate to compute_mean / compute_std.
// Uses file-scope win_float[STAB_WINDOW] to avoid stack allocation.
float compute_window_mean(long* window, int n) {
    for (int i = 0; i < n; i++) win_float[i] = (float)window[i];
    return compute_mean(win_float, n);
}

float compute_window_std(long* window, int n) {
    for (int i = 0; i < n; i++) win_float[i] = (float)window[i];
    return compute_std(win_float, n);
}

// --- Phase 1: measure hardware noise floor in raw counts ---
// Collects NOISE_SAMPLES valid reads at rest. No stability gate — just characterise.
// Returns mean_raw (display only). Sets *out_std_raw for threshold derivation.
float phase1_characterise(float* out_std_raw) {
    Serial.println("=== PHASE 1: NOISE CHARACTERISATION ===");
    Serial.println("Collecting 200 raw samples...");

    int count = 0;
    while (count < NOISE_SAMPLES) {
        long r = hx711_read();
        if (is_corrupt(r)) continue;
        noise_buf[count++] = (float)r;
        delay(110);
    }

    float mean_raw = compute_mean(noise_buf, NOISE_SAMPLES);
    float std_raw  = compute_std(noise_buf, NOISE_SAMPLES);

    snprintf(buf, sizeof(buf), "Noise mean (raw): %.0f", mean_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), "Noise STD  (raw): %.2f", std_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), "STAB_SPREAD gate = K_SPREAD(1.5) x STD = %.2f raw", K_SPREAD * std_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), "STAB_DRIFT  gate = K_DRIFT(1.0)  x STD = %.2f raw", K_DRIFT * std_raw);
    Serial.println(buf);

    *out_std_raw = std_raw;
    return mean_raw;
}

// --- Phase 2: stability-gated tare ---
// Thresholds derived from noise_std_raw — not hardcoded.
// Requires STAB_CONFIRM consecutive windows where:
//   window_std < spread_gate AND (first OR window_drift < drift_gate)
// No delay() — hx711_read() self-paces via DOUT polling.
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
        if (is_corrupt(r)) continue;

        stab_window[win_idx++] = r;
        if (win_idx < STAB_WINDOW) continue;
        win_idx = 0;

        float window_std   = compute_window_std(stab_window, STAB_WINDOW);
        float window_mean  = compute_window_mean(stab_window, STAB_WINDOW);
        float window_drift = first_window ? 0.0f : fabsf(window_mean - prev_win_mean);

        bool pass = (window_std < spread_gate) && (first_window || window_drift < drift_gate);

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
    // INPUT_PULLUP mandatory: DOUT is open-drain; floats without pullup → false ready signals.
    pinMode(DOUT_PIN, INPUT_PULLUP);
    pinMode(SCK_PIN,  OUTPUT);
    // SCK LOW is the HX711 idle state — must be set before the first read.
    digitalWrite(SCK_PIN, LOW);

    Serial.begin(115200);
    // Wait for USB CDC enumeration on ESP32-C3 SuperMini (no CH340/CP2102).
    while (!Serial) { delay(10); }
    delay(1000);
    // Extend timeout to 30s so the user has time to place weight and press Enter.
    Serial.setTimeout(30000);

    Serial.println("4E001 cal_factor v3 | 4-cell | self-characterising | ref=597g");

    // Step 2: characterise noise floor — must run with platform empty and at rest.
    float noise_std_raw = 0.0f;
    phase1_characterise(&noise_std_raw);

    // Step 3: boot tare via full stability gate.
    long tare_raw = derive_stable_tare(noise_std_raw);

    // Step 4: outer loop — one iteration per calibration run.
    while (true) {

        // 4a: flush stale bytes then prompt. Bytes accumulate during tare or the
        // previous iteration; without flush, readStringUntil returns immediately.
        while (Serial.available()) Serial.read();
        snprintf(buf, sizeof(buf),
                 "[EMPTY] tare=%ld  Place 597g water bottle. Press Enter when ready.", tare_raw);
        Serial.println(buf);
        Serial.readStringUntil('\n');

        // 4b: settle countdown — millis() paced, not delay().
        // Load cell mechanical creep: metal deforms slowly under load and takes ~10s
        // to reach its final resting value.
        unsigned long settle_start  = millis();
        unsigned long next_print_ms = 2000UL;
        Serial.println("Settling... 10s");
        while (millis() - settle_start < (unsigned long)SETTLE_MS) {
            if (millis() - settle_start >= next_print_ms) {
                int remaining = (int)(SETTLE_MS / 1000) - (int)(next_print_ms / 1000);
                snprintf(buf, sizeof(buf), "%ds...", remaining);
                Serial.println(buf);
                next_print_ms += 2000UL;
            }
        }
        Serial.println("Sampling now.");

        // 4c: collect CAL_SAMPLES valid raw samples then derive cal_factor.
        int count = 0;
        while (count < CAL_SAMPLES) {
            long r = hx711_read();
            if (is_corrupt(r)) continue;
            cal_buf[count++] = (float)r;
            delay(110);
        }
        float loaded_mean_raw    = compute_mean(cal_buf, CAL_SAMPLES);
        float stable_delta       = loaded_mean_raw - (float)tare_raw;
        float cal_factor_derived = stable_delta / KNOWN_WEIGHT_G;

        snprintf(buf, sizeof(buf), ">>> LOADED MEAN RAW:  %ld",  (long)loaded_mean_raw);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> TARE RAW:         %ld",  tare_raw);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> STABLE DELTA:     %+ld", (long)stable_delta);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> cal_factor = %ld / 597.0 = %.2f raw/g",
                 (long)stable_delta, cal_factor_derived);
        Serial.println(buf);
        Serial.println("--------------------");

        // 4d: flush stale bytes then prompt for weight removal.
        while (Serial.available()) Serial.read();
        Serial.println("Remove weight. Press Enter when platform is empty.");
        Serial.readStringUntil('\n');

        // 4e: re-tare using full stability gate. noise_std_raw unchanged —
        // hardware noise floor does not change between runs.
        tare_raw = derive_stable_tare(noise_std_raw);
    }
}

void loop() {
    // All work is done in setup(). setup() loops forever inside while(true).
}
