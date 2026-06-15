// 3E-002 Run B - BLE ON (radio EMI included)

#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Pin definitions ---
#define DOUT_PIN 4
#define SCK_PIN  3

// --- Locked calibration constant ---
const float CAL_FACTOR_LOCKED = 36.1f;  // LOCKED 2026-06-12 - 3-cell parallel, shared plate

// --- Phase 0 (settling) parameters ---
#define SETTLE_BLOCK_SIZE  200
#define SETTLE_STD_GATE    500.0f
#define SETTLE_DRIFT_GATE  500.0f
#define SETTLE_CONSEC_REQ  3

// --- Phase 1 (stabilising) parameters ---
#define STAB_WINDOW_SIZE  20
#define STAB_CONSEC_REQ   3

// --- Phase 2 (noise capture) ---
#define N_NOISE  200

// --- BLE identifiers (same as E003_ble_transport) ---
#define SERVICE_UUID     "aa206b91-235b-42aa-b370-453a3feedf35"
#define WEIGHT_CHAR_UUID "b9b25bb1-f2a9-4545-b48f-295ab2789f41"
#define DEVICE_NAME      "GasCylMonitor"

// --- BLE globals ---
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

// --- State machine ---
enum Phase { PHASE_SETTLING, PHASE_STABILISING, PHASE_NOISE_CAPTURE, PHASE_LIVE };
static Phase phase = PHASE_SETTLING;

// --- Phase 0 state ---
static int   s0_count     = 0;
static int   s0_valid     = 0;
static int   s0_block     = 0;
static int   s0_consec    = 0;
static float s0_mean      = 0.0f;
static float s0_M2        = 0.0f;
static float s0_prev_mean = 0.0f;
static float noise_std_raw_settle = 0.0f;

// --- Phase 1 state ---
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

// --- Phase 3 (live) state ---
static unsigned long live_last_ms = 0;

// =================================================================
// HX711 bit-bang read
// Call only when DOUT is already LOW (caller checks before calling).
// Returns raw 24-bit signed value, or 0 if corrupt.
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
// Phase 0 - settling monitor
// Waits for mechanical and electrical drift to die after power-on.
// Uses Welford online algorithm (float) - avoids double sum=0 bug.
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
        s0_M2      += delta * (x - s0_mean);  // Welford: delta * delta2
    }

    if (s0_count < SETTLE_BLOCK_SIZE) return;

    // Block complete - evaluate
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
// Phase 1 - tare stabilising
// Derives tare_raw from a fully settled, unloaded platform.
// BLE advertising is started here when tare is confirmed stable,
// so radio is ON for the entire Phase 2 noise capture.
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

    // Window complete - evaluate
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
            // BLE advertising starts here - radio must be ON for entire Phase 2
            BLEDevice::startAdvertising();
            Serial.println("[BLE] Advertising started. Radio ON for noise capture.");
            Serial.println("[P2] Collecting 200 valid samples (BLE ON)...");
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
// Collects exactly 200 valid (non-corrupt) samples.
// Bessel correction applied (divide by N-1).
// BLE is advertising during this entire phase - no notifications sent.
// =================================================================
static void handleNoiseCapture(long raw) {
    if (raw == 0L) return;

    s2_count++;
    float x     = (float)raw;
    float delta = x - s2_mean;
    s2_mean    += delta / (float)s2_count;
    s2_M2      += delta * (x - s2_mean);

    // Progress every 50 valid samples
    if (s2_count % 50 == 0) {
        float running_std = (s2_count > 1) ? sqrtf(s2_M2 / (float)(s2_count - 1)) : 0.0f;
        char buf[80];
        snprintf(buf, sizeof(buf), "[P2] samples=%d  mean_raw=%.1f  std_raw=%.2f",
                 s2_count, s2_mean, running_std);
        Serial.println(buf);
    }

    if (s2_count < N_NOISE) return;

    // 200 valid samples collected - compute final results
    float noise_std_raw_final = sqrtf(s2_M2 / (float)(s2_count - 1));
    float noise_std_grams     = noise_std_raw_final / CAL_FACTOR_LOCKED;
    float threshold_grams     = 4.0f * noise_std_grams;
    float grams_offset        = (s2_mean - tare_raw) / CAL_FACTOR_LOCKED;

    Serial.println();
    Serial.println("  === 3E-002 NOISE FLOOR RESULT (BLE ON) ===");
    char buf[80];
    snprintf(buf, sizeof(buf), "  samples        : %d",                 s2_count);             Serial.println(buf);
    snprintf(buf, sizeof(buf), "  tare_raw       : %.1f",               tare_raw);              Serial.println(buf);
    snprintf(buf, sizeof(buf), "  noise_mean_raw : %.1f",               s2_mean);               Serial.println(buf);
    snprintf(buf, sizeof(buf), "  noise_std_raw  : %.2f",               noise_std_raw_final);   Serial.println(buf);
    snprintf(buf, sizeof(buf), "  noise_std_g    : %.4f g",             noise_std_grams);        Serial.println(buf);
    snprintf(buf, sizeof(buf), "  threshold_g    : %.4f g  (4 x STD)", threshold_grams);         Serial.println(buf);
    snprintf(buf, sizeof(buf), "  grams_offset   : %.4f g  (should be near 0)", grams_offset);   Serial.println(buf);
    Serial.println("  ===========================================");
    Serial.println();

    live_last_ms = millis();
    phase = PHASE_LIVE;
}

// =================================================================
// Phase 3 - live continuous print every 2 seconds
// =================================================================
static void handleLive(long raw, unsigned long now) {
    if (raw == 0L)                 return;
    if (now - live_last_ms < 2000) return;
    live_last_ms = now;
    float grams = ((float)raw - tare_raw) / CAL_FACTOR_LOCKED;
    char buf[64];
    snprintf(buf, sizeof(buf), "[LIVE] raw=%ld  grams=%.2fg", raw, grams);
    Serial.println(buf);
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

    Serial.println("3E-002 Run B - BLE ON - noise floor characterisation");
    Serial.println("Platform: 3-cell YZC-161A parallel, 3V3 HX711");

    // Init BLE GATT server now - advertising deferred until Phase 2
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
    // startAdvertising() is called in handleStabilising() after tare is locked

    Serial.println("[BLE] GATT server ready. Advertising held until Phase 2.");
    Serial.println("[P0] Settling monitor started (blocks of 200 samples)...");
}

void loop() {
    unsigned long now = millis();

    // Non-blocking pacing: return immediately if HX711 not ready
    if (digitalRead(DOUT_PIN) == HIGH) return;

    long raw = readHX711();

    switch (phase) {
        case PHASE_SETTLING:      handleSettling(raw);      break;
        case PHASE_STABILISING:   handleStabilising(raw);   break;
        case PHASE_NOISE_CAPTURE: handleNoiseCapture(raw);  break;
        case PHASE_LIVE:          handleLive(raw, now);     break;
    }
}
