// ESP32-C3 GPIO4  HX711 DT (DOUT)
// ESP32-C3 GPIO3  HX711 SCK
// ESP32-C3 3V3    HX711 VDD  ← must be 3V3, not 5V — ESP32-C3 GPIO max 3.6V
// ESP32-C3 GND    HX711 GND

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DT_PIN               4
#define SCK_PIN              3
#define STAB_WINDOW          20
#define STAB_SPREAD_G        2.5f
#define STAB_MEAN_DIFF_G     1.0f
#define STAB_CONFIRM         3
#define NOISE_SAMPLES        200
#define LOOP_SAMPLES         20
#define LOOP_INTERVAL_MS     15000
#define THRESHOLD_MULTIPLIER 4.0f

#define SERVICE_UUID      "aa206b91-235b-42aa-b370-453a3feedf35"
#define WEIGHT_CHAR_UUID  "b9b25bb1-f2a9-4545-b48f-295ab2789f41"
#define DEVICE_NAME       "GasCylMonitor"

// cal_factor from E-001 (~230g ref). E-005 will validate across full range.
static const float cal_factor = 105.0f;

long   tare_raw        = 0;
float  noise_std       = 0.0f;
float  noise_threshold = 0.0f;

BLEServer*         pServer      = nullptr;
BLECharacteristic* pWeightChar  = nullptr;
bool               deviceConnected = false;
unsigned long      lastSend     = 0;

// ── BLE server callbacks ──────────────────────────────────────────────────────

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pSvr) override {
    deviceConnected = true;
    Serial.println("Hub connected");
  }
  void onDisconnect(BLEServer* pSvr) override {
    deviceConnected = false;
    Serial.println("Hub disconnected - restarting advertising");
    pSvr->startAdvertising();
  }
};

// ── HX711 raw bit-bang ────────────────────────────────────────────────────────

long readRaw() {
  // DOUT LOW signals conversion complete - clocking while HIGH corrupts the reading
  unsigned long t = millis();
  while (digitalRead(DT_PIN) == HIGH) {
    if (millis() - t > 500) return LONG_MIN;
  }

  // ISR mid-sequence adds unintended SCK pulses, corrupting the gain setting for
  // the next conversion (25 = ch A gain 128, 26 = ch B gain 32, 27 = ch A gain 64)
  noInterrupts();

  long raw = 0;
  for (int i = 0; i < 24; i++) {
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    raw = (raw << 1) | digitalRead(DT_PIN);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);
  }

  // 25th pulse locks Channel A Gain 128 for the next conversion
  digitalWrite(SCK_PIN, HIGH);
  delayMicroseconds(1);
  digitalWrite(SCK_PIN, LOW);
  delayMicroseconds(1);

  interrupts();

  // HX711 outputs 24-bit two's complement - without sign extension, negative
  // values appear as large positives (bit 23 set = raw > 8 million)
  if (raw & 0x800000) raw |= 0xFF000000;

  // three distinct hardware fault states, unified to LONG_MIN for caller
  if (raw == LONG_MIN) return LONG_MIN;  // timeout sentinel passthrough
  if (raw == -1)       return LONG_MIN;  // all 24 bits HIGH: HX711 not ready when clocked
  if (raw == 0x7FFFFF) return LONG_MIN;  // positive saturation: wiring or VCC fault

  return raw;
}

// ── Phase 1: dynamic stability detection + tare derivation ───────────────────

long deriveStableTare() {
  float window[STAB_WINDOW];
  int   win_idx      = 0;
  int   stable_count = 0;
  int   total_reads  = 0;
  float prev_mean_g  = 0.0f;
  bool  have_prev    = false;

  Serial.println("=== PHASE 1: STABILITY CHECK ===");

  while (stable_count < STAB_CONFIRM) {
    long raw = readRaw();
    if (raw == LONG_MIN) continue;  // corrupt - skip, do not count

    window[win_idx % STAB_WINDOW] = (float)raw;
    win_idx++;
    total_reads++;

    // evaluating a partially filled buffer gives falsely tight spread
    if (win_idx < STAB_WINDOW) continue;

    float wmin = window[0], wmax = window[0], wsum = 0.0f;
    for (int i = 0; i < STAB_WINDOW; i++) {
      if (window[i] < wmin) wmin = window[i];
      if (window[i] > wmax) wmax = window[i];
      wsum += window[i];
    }

    // convert to grams for comparison against STAB_SPREAD_G / STAB_MEAN_DIFF_G
    // tare not yet known so mean_g is relative to 0 — only the delta matters
    float spread_g  = (wmax - wmin) / cal_factor;
    float mean_g    = (wsum / STAB_WINDOW) / cal_factor;
    float drift_g   = have_prev ? fabsf(mean_g - prev_mean_g) : 0.0f;

    bool spread_ok = (spread_g < STAB_SPREAD_G);
    // drift condition passes automatically on the first full window (no previous to compare)
    bool drift_ok  = (!have_prev || drift_g < STAB_MEAN_DIFF_G);

    if (spread_ok && drift_ok) {
      stable_count++;
      have_prev   = true;
      prev_mean_g = mean_g;
      Serial.println("Stable window #" + String(stable_count) +
                     "  spread: " + String(spread_g, 2) + "g" +
                     "  drift: "  + String(drift_g, 2) + "g" +
                     "  reads: "  + String(total_reads));
    } else {
      stable_count = 0;  // must be consecutive - any failure resets the run
      have_prev   = true;
      prev_mean_g = mean_g;  // update even on failure so next window compares correctly
      if (!spread_ok) Serial.println("  unstable: spread " + String(spread_g, 2) + "g");
      if (!drift_ok)  Serial.println("  drifting: mean moved " + String(drift_g, 2) + "g");
    }
  }

  // tare = mean of the settled window in raw counts
  float wsum = 0.0f;
  for (int i = 0; i < STAB_WINDOW; i++) wsum += window[i];
  long tare = (long)(wsum / STAB_WINDOW);

  Serial.println("TARE DERIVED: " + String(tare));
  return tare;
}

// ── Phase 2: noise characterisation ──────────────────────────────────────────

void characteriseNoise(long tare) {
  float samples[NOISE_SAMPLES];
  int   collected = 0;

  while (collected < NOISE_SAMPLES) {
    long raw = readRaw();
    if (raw == LONG_MIN) continue;
    samples[collected++] = (float)(raw - tare) / cal_factor;
  }

  float sum = 0.0f;
  for (int i = 0; i < NOISE_SAMPLES; i++) sum += samples[i];
  float mean = sum / NOISE_SAMPLES;

  float var_sum = 0.0f;
  for (int i = 0; i < NOISE_SAMPLES; i++) {
    float d = samples[i] - mean;
    var_sum += d * d;
  }
  float std_g = sqrtf(var_sum / NOISE_SAMPLES);

  // compute peak-to-peak (verification reference, not stored)
  float min_g = samples[0], max_g = samples[0];
  for (int i = 1; i < NOISE_SAMPLES; i++) {
    if (samples[i] < min_g) min_g = samples[i];
    if (samples[i] > max_g) max_g = samples[i];
  }
  (void)min_g; (void)max_g;  // computed per spec, not printed in this phase

  noise_std       = std_g;
  noise_threshold = THRESHOLD_MULTIPLIER * std_g;

  Serial.println("=== NOISE CHARACTERISATION ===");
  Serial.println("STD: " + String(noise_std) + "g");
  Serial.println("Threshold: " + String(noise_threshold) + "g");
  Serial.println("==============================");
}

// ── Quality computation ───────────────────────────────────────────────────────

String computeQuality(float* samples, int n, float tare, float cal, float threshold,
                      float* out_grams, float* out_sigma) {
  float valid_grams[LOOP_SAMPLES];
  int   valid_count = 0;

  for (int i = 0; i < n; i++) {
    // LONG_MIN as float is ~-2.15e9 - real raw values never reach -1e8
    if (samples[i] < -1e8f) continue;
    valid_grams[valid_count++] = (samples[i] - tare) / cal;
  }

  if (valid_count < n / 2) {
    *out_grams = 0.0f;
    *out_sigma = 0.0f;
    return "FAILED";
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

  return (sigma > threshold) ? String("DEGRADED") : String("GOOD");
}

// ── BLE init ─────────────────────────────────────────────────────────────────

void setupBLE() {
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
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising started");
  Serial.println("Service UUID: aa206b91-235b-42aa-b370-453a3feedf35");
}

// ── Arduino entry points ──────────────────────────────────────────────────────

void setup() {
  pinMode(SCK_PIN, OUTPUT);
  pinMode(DT_PIN, INPUT_PULLUP);  // pullup required - floating DOUT reads as false-ready
  digitalWrite(SCK_PIN, LOW);

  Serial.begin(115200);
  unsigned long t = millis();
  while (!Serial && millis() - t < 3000);

  tare_raw = deriveStableTare();
  characteriseNoise(tare_raw);
  setupBLE();
}

void loop() {
  // millis() pacing - never blocking in loop
  if (millis() - lastSend < LOOP_INTERVAL_MS) return;

  // collect LOOP_SAMPLES reads; positions not filled by valid reads stay as LONG_MIN sentinel
  float rawSamples[LOOP_SAMPLES];
  for (int i = 0; i < LOOP_SAMPLES; i++) rawSamples[i] = (float)LONG_MIN;

  int collected = 0;
  int attempts  = 0;
  while (collected < LOOP_SAMPLES && attempts < LOOP_SAMPLES * 2) {
    long raw = readRaw();
    attempts++;
    if (raw == LONG_MIN) continue;
    rawSamples[collected++] = (float)raw;
  }

  float out_grams = 0.0f, out_sigma = 0.0f;
  String quality = computeQuality(rawSamples, LOOP_SAMPLES,
                                  (float)tare_raw, cal_factor,
                                  noise_threshold, &out_grams, &out_sigma);

  // dtostrf with minWidth=1 produces no leading spaces - clean JSON values
  char jsonBuf[128], gramsStr[16], sigmaStr[12];
  dtostrf(out_grams, 1, 1, gramsStr);
  dtostrf(out_sigma, 1, 2, sigmaStr);
  snprintf(jsonBuf, sizeof(jsonBuf),
           "{\"grams\":%s,\"quality\":\"%s\",\"sigma\":%s}",
           gramsStr, quality.c_str(), sigmaStr);

  if (deviceConnected) {
    pWeightChar->setValue(jsonBuf);
    pWeightChar->notify();
    Serial.println("SENT: " + String(jsonBuf));
  } else {
    Serial.println("No hub connected - discarded: " + String(jsonBuf));
  }

  lastSend = millis();
}
