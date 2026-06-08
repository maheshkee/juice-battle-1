// ESP32-C3 GPIO4  HX711 DOUT
// ESP32-C3 GPIO3  HX711 SCK
// ESP32-C3 3V3    HX711 VDD
// ESP32-C3 GND    HX711 GND

#define PIN_DOUT        4
#define PIN_SCK         3
#define CAL_FACTOR      105.0f
#define STAB_WINDOW     20       // rolling window size for stability check
#define STAB_SPREAD     2.5f    // max (max-min) within one window to declare settled (grams)
#define STAB_MEAN_DIFF  1.0f    // max allowed mean shift between consecutive windows (grams)
#define STAB_CONFIRM    3        // consecutive passing windows required - single pass could be noise
#define TARE_SAMPLES    20       // fresh reads for real_tare after stability confirmed
#define N_CHAR          200      // characterisation sample count
#define MAX_WAIT_MS     120000   // 2-minute safety timeout

// real_tare global - derived post-settle in setup(), used in every loop() conversion
long real_tare = 0;
unsigned long last_sample_ms = 0;

long hx711_read() {
  // DOUT HIGH = HX711 still converting - clocking before ready corrupts the reading
  unsigned long t = millis();
  while (digitalRead(PIN_DOUT) == HIGH) {
    if (millis() - t > 200) return LONG_MIN;
  }

  // an ISR adding unintended pulses shifts the gain for the next conversion
  // (25 pulses = ch A gain 128, 26 = ch B gain 32, 27 = ch A gain 64)
  noInterrupts();

  long value = 0;
  for (int i = 0; i < 24; i++) {
    digitalWrite(PIN_SCK, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | digitalRead(PIN_DOUT);
    digitalWrite(PIN_SCK, LOW);
    delayMicroseconds(1);
  }

  // 25th pulse is mandatory - locks Channel A Gain 128 for the next conversion
  digitalWrite(PIN_SCK, HIGH);
  delayMicroseconds(1);
  digitalWrite(PIN_SCK, LOW);
  delayMicroseconds(1);

  interrupts();

  // HX711 outputs 24-bit two's complement - bit 23 is the sign bit
  // without sign extension, negative values appear as large positives (>8 million)
  if (value & 0x800000) value |= 0xFF000000;

  // three distinct hardware fault states - unified to LONG_MIN for caller simplicity
  if (value == LONG_MIN) return LONG_MIN;  // timeout sentinel passthrough
  if (value == -1)       return LONG_MIN;  // all 24 bits HIGH: HX711 not ready when clocked
  if (value == 0x7FFFFF) return LONG_MIN;  // positive saturation: wiring or VCC fault

  return value;
}

void setup() {
  pinMode(PIN_SCK, OUTPUT);
  pinMode(PIN_DOUT, INPUT_PULLUP);  // pullup required - floating DOUT reads as false-ready
  digitalWrite(PIN_SCK, LOW);

  Serial.begin(115200);
  unsigned long t = millis();
  while (!Serial && millis() - t < 3000);

  Serial.println("=== E-002 NOISE FLOOR CHARACTERISATION v3 ===");
  Serial.println("Hardware: ESP32-C3 + GISLAB HX711 + YZC-161A");
  Serial.println("Fix 1: tare derived AFTER stability confirmed");
  Serial.println("Fix 2: mean drift check added to stability detection");
  Serial.println("Phase 1: waiting for load cell to settle...");

  // Step 3 data structures
  float window[STAB_WINDOW];
  int   win_idx      = 0;
  int   stable_count = 0;
  int   total_reads  = 0;
  float prev_mean    = 0.0f;
  bool  have_prev    = false;
  long  raw_sum      = 0;
  int   raw_count    = 0;

  // Preliminary tare: first 20 valid raw readings
  // used ONLY to convert grams during the stability wait - never used for characterisation
  // real_tare (derived post-settle) absorbs the settled zero, which may differ from this
  while (raw_count < 20) {
    long r = hx711_read();
    if (r == LONG_MIN) continue;
    raw_sum += r;
    raw_count++;
  }
  long preliminary_tare = raw_sum / raw_count;
  Serial.print("Preliminary tare (stability loop only): ");
  Serial.print(preliminary_tare);
  Serial.println(" raw");

  unsigned long start_ms = millis();

  // Stability loop: TWO conditions must both pass for STAB_CONFIRM consecutive windows
  // spread alone is insufficient - a slowly drifting mean can have tight per-window spread
  while (stable_count < STAB_CONFIRM && millis() - start_ms <= MAX_WAIT_MS) {
    long r = hx711_read();
    if (r == LONG_MIN) continue;  // corrupt - do not count, retry immediately

    float g = (float)(r - preliminary_tare) / CAL_FACTOR;
    window[win_idx % STAB_WINDOW] = g;
    win_idx++;
    total_reads++;

    // evaluating a partially filled buffer gives falsely tight spread
    if (win_idx < STAB_WINDOW) continue;

    float wmin = window[0];
    float wmax = window[0];
    float wsum = 0.0f;
    for (int i = 0; i < STAB_WINDOW; i++) {
      if (window[i] < wmin) wmin = window[i];
      if (window[i] > wmax) wmax = window[i];
      wsum += window[i];
    }
    float spread      = wmax - wmin;
    float window_mean = wsum / STAB_WINDOW;
    float drift       = have_prev ? fabsf(window_mean - prev_mean) : 0.0f;

    bool spread_ok = (spread < STAB_SPREAD);
    // condition 2 passes automatically when there is no previous window to compare against
    bool drift_ok  = (!have_prev || drift < STAB_MEAN_DIFF);

    if (spread_ok && drift_ok) {
      stable_count++;
      have_prev = true;
      prev_mean = window_mean;
      Serial.print("stable window #");
      Serial.print(stable_count);
      Serial.print("  spread: ");
      Serial.print(spread, 2);
      Serial.print("g  mean: ");
      Serial.print(window_mean, 2);
      Serial.print("g  drift: ");
      Serial.print(drift, 2);
      Serial.print("g  reads: ");
      Serial.println(total_reads);
    } else {
      stable_count = 0;  // must be consecutive - any failure resets the run
      have_prev    = true;
      prev_mean    = window_mean;  // update even on failure so next window sees current mean
      if (!spread_ok) {
        Serial.print("  unstable: spread ");
        Serial.print(spread, 2);
        Serial.print("g > ");
        Serial.print(STAB_SPREAD, 2);
        Serial.println("g");
      }
      if (!drift_ok) {
        Serial.print("  drifting: mean moved ");
        Serial.print(drift, 2);
        Serial.println("g");
      }
    }
  }

  unsigned long elapsed = millis() - start_ms;

  if (stable_count < STAB_CONFIRM) {
    Serial.println("WARNING: stability timeout - proceeding anyway");
  } else {
    Serial.print("Settled after ");
    Serial.print(total_reads);
    Serial.print(" samples (");
    Serial.print(elapsed);
    Serial.println("ms)");
  }

  // Step 4: derive REAL tare NOW - after stability confirmed
  // preliminary_tare was taken before the cell finished settling; this captures the true zero
  {
    long tare_sum = 0;
    int  count    = 0;
    while (count < TARE_SAMPLES) {
      long r = hx711_read();
      if (r == LONG_MIN) continue;
      tare_sum += r;
      count++;
    }
    real_tare = tare_sum / TARE_SAMPLES;
  }
  Serial.print("Real tare (post-settle): ");
  Serial.print(real_tare);
  Serial.println(" raw");
  Serial.print("Preliminary tare was:    ");
  Serial.print(preliminary_tare);
  Serial.println(" raw");
  Serial.print("Tare correction:         ");
  Serial.print(real_tare - preliminary_tare);
  Serial.println(" raw");

  // Step 5: characterisation - 200 samples using real_tare only
  float samples[N_CHAR];
  int collected = 0;
  int retries   = 0;
  while (collected < N_CHAR) {
    long r = hx711_read();
    if (r == LONG_MIN) {
      retries++;
      if (retries > N_CHAR * 3) {
        Serial.println("ERROR: too many corrupt reads");
        while (true);
      }
      continue;
    }
    samples[collected++] = (float)(r - real_tare) / CAL_FACTOR;
  }

  // Step 6: statistics - population std (divide by N) to characterise this
  // hardware's actual noise distribution, not estimate a population parameter
  float sum = 0.0f;
  for (int i = 0; i < N_CHAR; i++) sum += samples[i];
  float mean_g = sum / N_CHAR;

  float var_sum = 0.0f;
  for (int i = 0; i < N_CHAR; i++) {
    float diff = samples[i] - mean_g;
    var_sum += diff * diff;
  }
  float std_g = sqrt(var_sum / N_CHAR);

  float min_g = samples[0];
  float max_g = samples[0];
  for (int i = 1; i < N_CHAR; i++) {
    if (samples[i] < min_g) min_g = samples[i];
    if (samples[i] > max_g) max_g = samples[i];
  }
  float pp_g   = max_g - min_g;
  float thresh = 4.0f * std_g;

  Serial.println("--- CHARACTERISATION COMPLETE ---");
  Serial.println("N samples      : 200");
  Serial.print("Mean (grams)   : "); Serial.println(mean_g, 2);  // should be near 0 if tare is correct
  Serial.print("STD (grams)    : "); Serial.println(std_g, 2);
  Serial.print("Min (grams)    : "); Serial.println(min_g, 2);
  Serial.print("Max (grams)    : "); Serial.println(max_g, 2);
  Serial.print("Peak-to-peak   : "); Serial.println(pp_g, 2);
  Serial.print("Threshold 4xSTD: "); Serial.println(thresh, 2);
  Serial.print("Settle reads   : "); Serial.println(total_reads);
  Serial.print("Settle time ms : "); Serial.println(elapsed);
  Serial.println("--- STM32 reference: STD ~1.87g, threshold ~6g ---");
  Serial.println("--- ENTERING LIVE LOOP ---");
}

void loop() {
  // millis() pacing at top of loop - never blocking delay() in loop()
  if (millis() - last_sample_ms < 500) return;
  last_sample_ms = millis();

  long r = hx711_read();
  if (r == LONG_MIN) {
    Serial.println("grams: ERR");
    return;
  }
  float g = (float)(r - real_tare) / CAL_FACTOR;
  Serial.print("grams: ");
  Serial.println(g, 2);
}
