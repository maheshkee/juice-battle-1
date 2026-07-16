// 3E-004 cal+run — self-calibrating boot for 3-cell YZC-161A platform
// Phases 0-2 identical to 3E003. Phase 3 derives cal_factor from a Serial-prompted
// reference weight. Phase 4 runs with those exact values — no hardcoded cal_factor.

#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Pin definitions ---
#define DOUT_PIN 4
#define SCK_PIN  3

// --- Phase 0 (settling) parameters — identical to 3E003 ---
#define SETTLE_BLOCK_SIZE  200
#define SETTLE_STD_GATE    500.0f
#define SETTLE_DRIFT_GATE  500.0f
#define SETTLE_CONSEC_REQ  3

// --- Phase 1 (stabilising) parameters — identical to 3E003 ---
#define STAB_WINDOW_SIZE  20
#define STAB_CONSEC_REQ   3

// --- Phase 2 (noise capture) — identical to 3E003 ---
#define N_NOISE  200

// --- Phase 3 (cal) ---
#define CAL_CAPTURE_N  200

// --- Phase 4 (running) parameters — identical to 3E003 ---
#define LOOP_INTERVAL_MS  15000
#define LOOP_SAMPLES      20

// --- BLE identifiers — identical to 3E003 ---
#define SERVICE_UUID     "aa206b91-235b-42aa-b370-453a3feedf35"
#define WEIGHT_CHAR_UUID "b9b25bb1-f2a9-4545-b48f-295ab2789f41"
#define DEVICE_NAME      "GasCylMonitor"

// --- BLE globals --- identical to 3E003 ---
BLEServer*         pServer         = nullptr;
BLECharacteristic* pWeightChar     = nullptr;
bool               deviceConnected = false;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pSvr) override {
    deviceConnected = true;
    Serial.println("[BLE] Hub connected");
  }
  void onDisconnect(BLEServer* pSvr) override {
    deviceConnected = false;
    Serial.println("[BLE] Hub disconnected - restarting advertising");
    pSvr->startAdvertising();
  }
};

// --- Top-level state machine ---
enum Phase {
    PHASE_SETTLING,
    PHASE_STABILISING,
    PHASE_NOISE_CAPTURE,
    PHASE_CAL,
    PHASE_RUNNING
};
static Phase phase = PHASE_SETTLING;

// --- CAL sub-states ---
enum CalState {
    CS_WAIT_WEIGHT,       // polling Serial for reference weight (float)
    CS_STABILISE_LOADED,  // stability gate with reference weight on platform
    CS_CAPTURE_LOADED,    // 200-sample Welford capture, loaded
    CS_WAIT_REMOVAL,      // polling Serial for Enter after weight removed
    CS_STABILISE_EMPTY,   // re-tare stability gate after removal
};
static CalState cal_state = CS_WAIT_WEIGHT;

// --- Phase 0 state --- identical to 3E003 ---
static int   s0_count     = 0;
static int   s0_valid     = 0;
static int   s0_block     = 0;
static int   s0_consec    = 0;
static float s0_mean      = 0.0f;
static float s0_M2        = 0.0f;
static float s0_prev_mean = 0.0f;
static float noise_std_raw_settle = 0.0f;

// --- Phase 1 state --- identical to 3E003 ---
static float spread_gate  = 0.0f;
static float drift_gate   = 0.0f;
static int   s1_count     = 0;
static int   s1_valid     = 0;
static int   s1_window    = 0;
static int   s1_consec    = 0;
static float s1_mean      = 0.0f;
static float s1_M2        = 0.0f;
static float s1_prev_mean = 0.0f;
static float tare_raw     = 0.0f;

// --- Phase 2 state ---
static int   s2_count = 0;
static float s2_mean  = 0.0f;
static float s2_M2    = 0.0f;
// noise_std_raw_final stored here; noise_threshold_g deferred until cal_factor is known
static float noise_std_raw_final = 0.0f;

// --- Phase 3 (CAL) state ---
static float reference_weight_g  = 0.0f;
static char  cal_serial_buf[32];
static int   cal_serial_len       = 0;
// Welford window accumulators for both CAL stability gates
static int   sc_count     = 0;
static int   sc_valid     = 0;
static int   sc_window    = 0;
static int   sc_consec    = 0;
static float sc_mean      = 0.0f;
static float sc_M2        = 0.0f;
static float sc_prev_mean = 0.0f;

// --- Phase 4 (running) state ---
static float         tare_raw_boot     = 0.0f;  // s2_mean at Phase 2 end; updated post-removal
static float         cal_factor        = 0.0f;  // derived in Phase 3 — never hardcoded
static float         noise_threshold_g = 0.0f;  // 4 × noise_std_g, computed after cal_factor known
static unsigned long lastSend          = 0;

// =================================================================
// HX711 bit-bang read — identical to 3E003
// Call only when DOUT is already LOW (loop() guarantees this).
// Returns 0L on any corrupt value.
// =================================================================
static long readHX711() {
    noInterrupts();
    long value = 0;
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK_PIN, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(DOUT_PIN);
        digitalWrite(SCK_PIN, LOW);
        delayMicroseconds(1);
    }
    // 25th pulse: lock Channel A, Gain 128 for next conversion
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);
    interrupts();

    // Sign-extend bit 23
    if (value & 0x800000L) value |= 0xFF000000L;

    // Corrupt filters
    if (value == LONG_MIN)       return 0L;
    if (value == -1L)            return 0L;
    if (value == (long)0x7FFFFF) return 0L;

    return value;
}

// =================================================================
// Phase 0 - settling monitor — identical to 3E003
// =================================================================
static void resetSettleBlock() {
    s0_count = 0;
    s0_valid = 0;
    s0_mean  = 0.0f;
    s0_M2    = 0.0f;
}

static void handleSettling(long raw) {
    s0_count++;

    if (raw != 0L) {
        s0_valid++;
        float x     = (float)raw;
        float delta = x - s0_mean;
        s0_mean    += delta / (float)s0_valid;
        s0_M2      += delta * (x - s0_mean);
    }

    if (s0_count < SETTLE_BLOCK_SIZE) return;

    s0_block++;
    float block_std  = (s0_valid > 1) ? sqrtf(s0_M2 / (float)(s0_valid - 1)) : 9999.0f;
    float block_mean = s0_mean;
    float drift      = fabsf(block_mean - s0_prev_mean);
    bool  pass       = (block_std < SETTLE_STD_GATE) && (drift < SETTLE_DRIFT_GATE);

    {
        char buf[96];
        snprintf(buf, sizeof(buf), "[P0] block=%d  std=%.1f  mean=%.1f  drift=%.1f  %s",
                 s0_block, block_std, block_mean, drift, pass ? "PASS" : "FAIL");
        Serial.println(buf);
    }

    if (pass) {
        s0_consec++;
        if (s0_consec >= SETTLE_CONSEC_REQ) {
            noise_std_raw_settle = block_std;
            spread_gate = 1.5f * noise_std_raw_settle;
            drift_gate  = 1.0f * noise_std_raw_settle;
            char buf[96];
            snprintf(buf, sizeof(buf),
                     "[P0] SETTLED. blocks=%d  noise_std_raw=%.1f -> Phase 1",
                     s0_block, noise_std_raw_settle);
            Serial.println(buf);
            snprintf(buf, sizeof(buf),
                     "[P1] spread_gate=%.1f raw  drift_gate=%.1f raw",
                     spread_gate, drift_gate);
            Serial.println(buf);
            s1_count = 0; s1_valid = 0; s1_window = 0; s1_consec = 0;
            s1_mean = 0.0f; s1_M2 = 0.0f; s1_prev_mean = 0.0f;
            phase = PHASE_STABILISING;
            return;
        }
    } else {
        s0_consec = 0;
    }

    s0_prev_mean = block_mean;
    resetSettleBlock();
}

// =================================================================
// Phase 1 - tare stabilising — identical to 3E003
// =================================================================
static void resetStabWindow() {
    s1_count = 0;
    s1_valid = 0;
    s1_mean  = 0.0f;
    s1_M2    = 0.0f;
}

static void handleStabilising(long raw) {
    s1_count++;

    if (raw != 0L) {
        s1_valid++;
        float x     = (float)raw;
        float delta = x - s1_mean;
        s1_mean    += delta / (float)s1_valid;
        s1_M2      += delta * (x - s1_mean);
    }

    if (s1_count < STAB_WINDOW_SIZE) return;

    s1_window++;
    float window_std  = (s1_valid > 1) ? sqrtf(s1_M2 / (float)(s1_valid - 1)) : 9999.0f;
    float window_mean = s1_mean;
    float drift       = fabsf(window_mean - s1_prev_mean);
    bool  pass        = (window_std < spread_gate) && (drift < drift_gate);

    {
        char buf[96];
        snprintf(buf, sizeof(buf), "[P1] win=%d  std=%.1f  mean=%.1f  drift=%.1f  %s",
                 s1_window, window_std, window_mean, drift, pass ? "PASS" : "FAIL");
        Serial.println(buf);
    }

    if (pass) {
        s1_consec++;
        if (s1_consec >= STAB_CONSEC_REQ) {
            tare_raw = window_mean;
            char buf[80];
            snprintf(buf, sizeof(buf),
                     "[P1] STABLE. windows=%d  tare_raw=%.1f -> Phase 2",
                     s1_window, tare_raw);
            Serial.println(buf);
            s2_count = 0; s2_mean = 0.0f; s2_M2 = 0.0f;
            Serial.println("[P2] Collecting 200 valid samples for noise characterisation...");
            phase = PHASE_NOISE_CAPTURE;
            return;
        }
    } else {
        s1_consec = 0;
    }

    s1_prev_mean = window_mean;
    resetStabWindow();
}

// =================================================================
// Phase 2 - noise capture
// Modified from 3E003: stores noise_std_raw_final instead of computing
// noise_threshold_g (requires cal_factor, not yet known).
// Transitions to PHASE_CAL instead of PHASE_RUNNING.
// =================================================================
static void handleNoiseCapture(long raw) {
    if (raw == 0L) return;

    s2_count++;
    float x     = (float)raw;
    float delta = x - s2_mean;
    s2_mean    += delta / (float)s2_count;
    s2_M2      += delta * (x - s2_mean);

    if (s2_count % 50 == 0) {
        float running_std = (s2_count > 1) ? sqrtf(s2_M2 / (float)(s2_count - 1)) : 0.0f;
        char buf[80];
        snprintf(buf, sizeof(buf), "[P2] samples=%d  mean_raw=%.1f  std_raw=%.2f",
                 s2_count, s2_mean, running_std);
        Serial.println(buf);
    }

    if (s2_count < N_NOISE) return;

    noise_std_raw_final = sqrtf(s2_M2 / (float)(s2_count - 1));
    // tare_raw_boot: 200-sample mean beats 20-sample Phase 1 window by 3x on error of mean.
    // noise_threshold_g deferred until Phase 3 produces cal_factor.
    tare_raw_boot = s2_mean;

    {
        Serial.println();
        Serial.println("  === 3E-004 NOISE FLOOR ===");
        char buf[80];
        snprintf(buf, sizeof(buf), "  samples        : %d",       s2_count);             Serial.println(buf);
        snprintf(buf, sizeof(buf), "  tare_raw_boot  : %.1f",     tare_raw_boot);        Serial.println(buf);
        snprintf(buf, sizeof(buf), "  noise_std_raw  : %.2f raw", noise_std_raw_final);  Serial.println(buf);
        Serial.println("  noise_threshold_g : computed after calibration");
        Serial.println("  =========================");
        Serial.println();
    }

    Serial.println("[CAL] Tare and noise locked. Ready for calibration.");
    Serial.println("[CAL] Place reference weight on platform. Enter weight in grams via Serial, then press Enter.");
    Serial.println("[CAL] Waiting...");

    cal_state         = CS_WAIT_WEIGHT;
    cal_serial_len    = 0;
    cal_serial_buf[0] = '\0';
    phase             = PHASE_CAL;
}

// =================================================================
// CAL stability window helpers
// Resets the full sc_* state (entering a new gate) vs just the
// per-window accumulators (after each window evaluation).
// =================================================================
static void resetCalStab() {
    sc_count     = 0; sc_valid     = 0;
    sc_window    = 0; sc_consec    = 0;
    sc_mean      = 0.0f; sc_M2       = 0.0f;
    sc_prev_mean = 0.0f;
}

static void resetCalStabWindow() {
    sc_count = 0; sc_valid = 0;
    sc_mean  = 0.0f; sc_M2   = 0.0f;
}

// =================================================================
// Phase 3 - calibration
// Non-blocking throughout. Serial polling happens at HX711 rate
// (loop() gates on DOUT LOW), which is adequate for human input.
// =================================================================
static void handleCal(long raw) {
    char buf[96];

    switch (cal_state) {

    // ---- Step 1: wait for reference weight entry via Serial ----
    case CS_WAIT_WEIGHT:
        while (Serial.available()) {
            char c = (char)Serial.read();
            if (c == '\r') continue;
            if (c == '\n') {
                cal_serial_buf[cal_serial_len] = '\0';
                if (cal_serial_len > 0) {
                    reference_weight_g = atof(cal_serial_buf);
                    snprintf(buf, sizeof(buf), "[CAL] Reference weight locked: %.1f g",
                             reference_weight_g);
                    Serial.println(buf);
                    // Drain any residual bytes before entering stability gate
                    while (Serial.available()) Serial.read();
                    resetCalStab();
                    cal_state = CS_STABILISE_LOADED;
                }
                cal_serial_len = 0;
                return;
            }
            if (cal_serial_len < (int)(sizeof(cal_serial_buf) - 1))
                cal_serial_buf[cal_serial_len++] = c;
        }
        break;

    // ---- Step 2: stability gate with reference weight loaded ----
    case CS_STABILISE_LOADED:
        sc_count++;
        if (raw != 0L) {
            sc_valid++;
            float x     = (float)raw;
            float delta = x - sc_mean;
            sc_mean    += delta / (float)sc_valid;
            sc_M2      += delta * (x - sc_mean);
        }
        if (sc_count < STAB_WINDOW_SIZE) break;

        {
            sc_window++;
            float win_std  = (sc_valid > 1) ? sqrtf(sc_M2 / (float)(sc_valid - 1)) : 9999.0f;
            float win_mean = sc_mean;
            float drift    = fabsf(win_mean - sc_prev_mean);
            bool  pass     = (win_std < spread_gate) && (drift < drift_gate);

            snprintf(buf, sizeof(buf), "[CAL] win=%d std=%.2f drift=%.2f %s",
                     sc_window, win_std, drift, pass ? "PASS" : "FAIL");
            Serial.println(buf);

            if (pass) {
                sc_consec++;
                if (sc_consec >= STAB_CONSEC_REQ) {
                    Serial.println("[CAL] Platform stable. Capturing 200-sample mean...");
                    // Reuse s2_* for the loaded capture — Phase 2 is done
                    s2_count = 0; s2_mean = 0.0f; s2_M2 = 0.0f;
                    cal_state = CS_CAPTURE_LOADED;
                }
            } else {
                sc_consec = 0;
            }
            sc_prev_mean = win_mean;
            resetCalStabWindow();
        }
        break;

    // ---- Step 3: capture exactly 200 valid samples with weight loaded ----
    case CS_CAPTURE_LOADED:
        if (raw == 0L) break;
        s2_count++;
        {
            float x     = (float)raw;
            float delta = x - s2_mean;
            s2_mean    += delta / (float)s2_count;
            s2_M2      += delta * (x - s2_mean);
        }
        if (s2_count < CAL_CAPTURE_N) break;

        // ---- Step 4: compute cal_factor from raw_delta / reference ----
        {
            float mean_raw_loaded = s2_mean;
            float raw_delta       = mean_raw_loaded - tare_raw_boot;
            float cal_factor_new  = raw_delta / reference_weight_g;

            // noise_threshold_g now computable with the real cal_factor
            float noise_std_g   = noise_std_raw_final / cal_factor_new;
            noise_threshold_g   = 4.0f * noise_std_g;
            cal_factor          = cal_factor_new;

            // Verification: weight computed with the just-derived cal_factor should equal reference
            float verification_g = raw_delta / cal_factor;

            snprintf(buf, sizeof(buf), "[CAL] raw_delta   : %.0f counts",  raw_delta);    Serial.println(buf);
            snprintf(buf, sizeof(buf), "[CAL] cal_factor  : %.2f raw/g",   cal_factor);   Serial.println(buf);
            snprintf(buf, sizeof(buf), "[CAL] Verification: place weight reads %.1f g  (should equal reference)",
                     verification_g);
            Serial.println(buf);
            snprintf(buf, sizeof(buf), "[CAL] noise_std_g : %.4f g",           noise_std_g);       Serial.println(buf);
            snprintf(buf, sizeof(buf), "[CAL] threshold_g : %.4f g  (4 x STD)", noise_threshold_g); Serial.println(buf);
            Serial.println("[CAL] CALIBRATION LOCKED.");
            Serial.println("[CAL] Remove reference weight. Press Enter when platform is clear.");

            // Drain buffer so a stray Enter typed during calibration doesn't skip removal wait
            while (Serial.available()) Serial.read();
            cal_serial_len    = 0;
            cal_serial_buf[0] = '\0';
            cal_state         = CS_WAIT_REMOVAL;
        }
        break;

    // ---- Step 5a: wait for Enter confirming weight removed ----
    case CS_WAIT_REMOVAL:
        while (Serial.available()) {
            char c = (char)Serial.read();
            if (c == '\n' || c == '\r') {
                while (Serial.available()) Serial.read();
                resetCalStab();
                cal_state = CS_STABILISE_EMPTY;
                return;
            }
        }
        break;

    // ---- Step 5b: re-tare stability gate after weight removal ----
    case CS_STABILISE_EMPTY:
        sc_count++;
        if (raw != 0L) {
            sc_valid++;
            float x     = (float)raw;
            float delta = x - sc_mean;
            sc_mean    += delta / (float)sc_valid;
            sc_M2      += delta * (x - sc_mean);
        }
        if (sc_count < STAB_WINDOW_SIZE) break;

        {
            sc_window++;
            float win_std  = (sc_valid > 1) ? sqrtf(sc_M2 / (float)(sc_valid - 1)) : 9999.0f;
            float win_mean = sc_mean;
            float drift    = fabsf(win_mean - sc_prev_mean);
            bool  pass     = (win_std < spread_gate) && (drift < drift_gate);

            snprintf(buf, sizeof(buf), "[CAL] retare win=%d std=%.2f drift=%.2f %s",
                     sc_window, win_std, drift, pass ? "PASS" : "FAIL");
            Serial.println(buf);

            if (pass) {
                sc_consec++;
                if (sc_consec >= STAB_CONSEC_REQ) {
                    // ---- Step 6: lock post-removal tare, start BLE ----
                    tare_raw_boot = win_mean;
                    snprintf(buf, sizeof(buf), "[CAL] Post-removal tare locked: %.0f", tare_raw_boot);
                    Serial.println(buf);

                    BLEDevice::startAdvertising();
                    Serial.println("[BLE] Advertising started. Entering PHASE_RUNNING.");

                    lastSend = millis();
                    phase    = PHASE_RUNNING;
                }
            } else {
                sc_consec = 0;
            }
            sc_prev_mean = win_mean;
            resetCalStabWindow();
        }
        break;
    }
}

// =================================================================
// Quality computation — no String class (3E003 used String)
// out_quality must be at least 9 bytes ("DEGRADED\0")
// =================================================================
static void computeQuality(float* samples, int n, float tare, float cal, float threshold,
                            float* out_grams, float* out_sigma, char* out_quality) {
    float valid_grams[LOOP_SAMPLES];
    int   valid_count = 0;

    for (int i = 0; i < n; i++) {
        // LONG_MIN cast to float is ~-2.15e9 — real raw values never reach -1e8
        if (samples[i] < -1e8f) continue;
        valid_grams[valid_count++] = (samples[i] - tare) / cal;
    }

    if (valid_count < n / 2) {
        *out_grams = 0.0f;
        *out_sigma = 0.0f;
        snprintf(out_quality, 9, "FAILED");
        return;
    }

    float sum = 0.0f;
    for (int i = 0; i < valid_count; i++) sum += valid_grams[i];
    float mean_g = sum / valid_count;

    float var_sum = 0.0f;
    for (int i = 0; i < valid_count; i++) {
        float d = valid_grams[i] - mean_g;
        var_sum += d * d;
    }
    float sigma = sqrtf(var_sum / valid_count);

    *out_grams = mean_g;
    *out_sigma = sigma;
    snprintf(out_quality, 9, "%s", (sigma > threshold) ? "DEGRADED" : "GOOD");
}

// =================================================================
// Phase 4 - running — identical to 3E003 except:
//   tare_raw_g  → tare_raw_boot  (post-removal tare from Phase 3)
//   CAL_FACTOR_LOCKED → cal_factor  (derived in Phase 3)
//   String return from computeQuality → char[] (no String class)
// =================================================================
static void handleRunning() {
    if (millis() - lastSend < LOOP_INTERVAL_MS) return;

    float rawSamples[LOOP_SAMPLES];
    for (int i = 0; i < LOOP_SAMPLES; i++) rawSamples[i] = (float)LONG_MIN;
    int collected = 0, attempts = 0;
    while (collected < LOOP_SAMPLES && attempts < LOOP_SAMPLES * 4) {
        unsigned long t = millis();
        while (digitalRead(DOUT_PIN) == HIGH) {
            if (millis() - t > 200) break;
        }
        long raw = readHX711();
        attempts++;
        if (raw == 0L) continue;
        rawSamples[collected++] = (float)raw;
    }

    float out_grams = 0.0f, out_sigma = 0.0f;
    char  quality[9];
    computeQuality(rawSamples, LOOP_SAMPLES,
                   tare_raw_boot, cal_factor, noise_threshold_g,
                   &out_grams, &out_sigma, quality);

    char jsonBuf[128], gramsStr[16], sigmaStr[12];
    dtostrf(out_grams, 1, 1, gramsStr);
    dtostrf(out_sigma, 1, 2, sigmaStr);
    snprintf(jsonBuf, sizeof(jsonBuf),
             "{\"grams\":%s,\"quality\":\"%s\",\"sigma\":%s}",
             gramsStr, quality, sigmaStr);

    char logBuf[140];
    if (deviceConnected) {
        pWeightChar->setValue(jsonBuf);
        pWeightChar->notify();
        snprintf(logBuf, sizeof(logBuf), "SENT: %s", jsonBuf);
    } else {
        snprintf(logBuf, sizeof(logBuf), "No hub - discarded: %s", jsonBuf);
    }
    Serial.println(logBuf);
    lastSend = millis();
}

// =================================================================
// setup / loop
// =================================================================
void setup() {
    Serial.begin(115200);
    delay(1000);

    pinMode(DOUT_PIN, INPUT_PULLUP);
    pinMode(SCK_PIN,  OUTPUT);
    digitalWrite(SCK_PIN, LOW);

    Serial.println("3E004 cal+run | 3-cell | self-calibrating boot");
    Serial.println("Platform: 3-cell YZC-161A parallel, 3V3 HX711");

    // BLE GATT server initialised now; advertising deferred until calibration complete
    BLEDevice::init(DEVICE_NAME);
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);
    pWeightChar = pService->createCharacteristic(
        WEIGHT_CHAR_UUID,
        BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ
    );
    pWeightChar->addDescriptor(new BLE2902());
    pService->start();

    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    // startAdvertising() called inside handleCal() after calibration complete

    Serial.println("[BLE] GATT server ready. Advertising deferred until calibration complete.");
    Serial.println("[P0] Settling monitor started (blocks of 200 samples)...");
}

void loop() {
    // Gate on HX711 conversion ready. PHASE_CAL serial polling happens here too —
    // HX711 at 10-80 Hz is fast enough for human serial input.
    if (digitalRead(DOUT_PIN) == HIGH) return;

    long raw = readHX711();

    switch (phase) {
        case PHASE_SETTLING:      handleSettling(raw);      break;
        case PHASE_STABILISING:   handleStabilising(raw);   break;
        case PHASE_NOISE_CAPTURE: handleNoiseCapture(raw);  break;
        case PHASE_CAL:           handleCal(raw);           break;
        case PHASE_RUNNING:       handleRunning();           break;
    }
}
