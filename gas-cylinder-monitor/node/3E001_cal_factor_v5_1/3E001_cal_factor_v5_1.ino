// 3E001 cal_factor v5.1 | 3-cell platform | self-characterising | user-entered ref weight | timing instrumentation
// ESP32-C3 SuperMini | 3x YZC-161A 20kg in parallel | HX711 DOUT=GPIO4 SCK=GPIO3

#include <Arduino.h>
#include <limits.h>
#include <math.h>

// ---- Pin definitions (never change) ----
#define HX711_DOUT  4
#define HX711_SCK   3

// ---- Constants ----
#define BLOCK_SIZE      200
#define WIN_SIZE        20
#define MEAS_N          50
#define COLD_THRESHOLD  500.0f
#define COLD_CONFIRM    3
#define STAB_CONFIRM    3
#define K_SPREAD        1.5f
#define K_DRIFT         1.0f
#define SAMPLE_MS       5UL

// ---- State machine ----
enum Phase {
  PHASE_SETTLING,
  PHASE_STABILISING,
  PHASE_MEASURE_GATE,
  PHASE_MEASURE,
  PHASE_RETARE_WAIT,
  PHASE_RETARE_GATE,
  PHASE_MEASURE_AGAIN_GATE,
  PHASE_MEASURE_AGAIN
};

// ---- Global state ----
static Phase         phase          = PHASE_SETTLING;
static unsigned long last_sample_ms = 0;

// Phase 0: block settling
static float  block_buf[BLOCK_SIZE];
static int    block_count     = 0;
static int    cold_pass_count = 0;
static float  prev_block_mean = 0.0f;
static bool   first_block     = true;
static float  noise_std_raw   = 0.0f;

// Phase 1 / retare: window stabilising
static float  win_buf[WIN_SIZE];
static int    win_count       = 0;
static int    stab_pass_count = 0;
static float  prev_win_mean   = 0.0f;
static bool   first_win       = true;
static float  spread_gate     = 0.0f;
static float  drift_gate      = 0.0f;
static float  tare_raw        = 0.0f;

// Gate sequencing
static int           gate_step      = 0;
static float         ref_weight_g   = 0.0f;
static unsigned long countdown_start = 0;
static int           countdown_last  = 11;

// Measurement buffers
static float meas_buf[MEAS_N];
static int   meas_count = 0;

// Timing instrumentation (STEP 1, 5, 6)
static unsigned long g_boot_ms      = 0;
static unsigned long g_removal_ms   = 0;
static unsigned long g_placement_ms = 0;

// ---------------------------------------------------------------
// HX711 raw bit-bang read — no library
// Returns LONG_MIN for any corrupt/invalid result
// ---------------------------------------------------------------
static long hx711_read_raw() {
  long val = 0;

  noInterrupts();
  for (int i = 0; i < 24; i++) {
    digitalWrite(HX711_SCK, HIGH);
    delayMicroseconds(1);
    val = (val << 1) | (long)digitalRead(HX711_DOUT);
    digitalWrite(HX711_SCK, LOW);
    delayMicroseconds(1);
  }
  // 25th pulse: select channel A, gain 128
  digitalWrite(HX711_SCK, HIGH);
  delayMicroseconds(1);
  digitalWrite(HX711_SCK, LOW);
  delayMicroseconds(1);
  interrupts();

  // Sign-extend bit 23 → signed 32-bit two's complement
  if (val & 0x800000L) val |= 0xFF000000L;

  // Corrupt filters (spec-mandated order)
  if (val == (long)LONG_MIN) return (long)LONG_MIN;
  if (val == -1L)             return (long)LONG_MIN;
  if (val == 0x7FFFFFL)       return (long)LONG_MIN;

  return val;
}

// ---------------------------------------------------------------
// Population STD — float only, sets *mean_out if non-NULL
// ---------------------------------------------------------------
static float compute_std(float *arr, int n, float *mean_out) {
  float sum = 0.0f;
  for (int i = 0; i < n; i++) sum += arr[i];
  float mean = sum / (float)n;
  if (mean_out) *mean_out = mean;
  float var = 0.0f;
  for (int i = 0; i < n; i++) {
    float d = arr[i] - mean;
    var += d * d;
  }
  return sqrtf(var / (float)n);
}

// ---------------------------------------------------------------
// Human gate — 2 s mandatory flush + wait for Enter
// ---------------------------------------------------------------
void waitForEnter(const char *prompt) {
  delay(2000);
  while (Serial.available()) Serial.read();
  Serial.println(prompt);
  Serial.println(">>> Press Enter when ready <<<");
  while (!Serial.available()) { delay(10); }
  while (Serial.available()) Serial.read();
}

// ---------------------------------------------------------------
// Blocking human float input — no String class
// ---------------------------------------------------------------
static float read_weight_blocking() {
  char buf[16];
  int  idx = 0;
  while (true) {
    int c = Serial.read();
    if (c == -1)   continue;
    if (c == '\r') continue;
    if (c == '\n') { if (idx > 0) break; continue; }
    if (idx < 15)  buf[idx++] = (char)c;
  }
  buf[idx] = '\0';
  return atof(buf);
}

// ---------------------------------------------------------------
// Reset stabilising-window state (call before entering stab phases)
// ---------------------------------------------------------------
static void reset_stab() {
  win_count       = 0;
  stab_pass_count = 0;
  prev_win_mean   = 0.0f;
  first_win       = true;
}

// ---------------------------------------------------------------
// Shared window-stability engine (STATE 1 and STATE 4 / retare)
// Accumulates WIN_SIZE samples, prints result, returns true on
// 3 consecutive passing windows. Updates tare_raw on success.
// ---------------------------------------------------------------
static bool run_stab_window(float raw) {
  win_buf[win_count++] = raw;
  if (win_count < WIN_SIZE) return false;

  float wm;
  float ws    = compute_std(win_buf, WIN_SIZE, &wm);
  float drift = first_win ? 0.0f : fabsf(wm - prev_win_mean);
  bool  pass  = (ws < spread_gate) && (first_win || drift < drift_gate);

  char buf[80];
  if (pass) {
    stab_pass_count++;
    snprintf(buf, sizeof(buf), "[STABILISING] std=%.1f drift=%.1f WIN %d/%d",
             ws, drift, stab_pass_count, STAB_CONFIRM);
  } else {
    stab_pass_count = 0;
    snprintf(buf, sizeof(buf), "[STABILISING] std=%.1f drift=%.1f (reset)",
             ws, drift);
  }
  Serial.println(buf);

  prev_win_mean = wm;
  first_win     = false;
  win_count     = 0;

  if (stab_pass_count >= STAB_CONFIRM) {
    tare_raw = wm;
    snprintf(buf, sizeof(buf), "[TARE] tare_raw=%.0f", tare_raw);
    Serial.println(buf);
    return true;
  }
  return false;
}

// ---------------------------------------------------------------
// Non-blocking 10 s countdown — prints at 10,8,6,4,2 s remaining
// Call repeatedly from loop(); advances automatically.
// ---------------------------------------------------------------
static void do_countdown() {
  unsigned long elapsed   = millis() - countdown_start;
  int           remaining = 10 - (int)(elapsed / 1000UL);
  if (remaining < 0) remaining = 0;

  if (remaining < countdown_last && remaining > 0 && remaining % 2 == 0) {
    char buf[12];
    snprintf(buf, sizeof(buf), "%ds...  ", remaining);
    Serial.print(buf);
    countdown_last = remaining;
  }
}

// ---------------------------------------------------------------
// Measurement result printer — shared by PHASE_MEASURE and _AGAIN
// ---------------------------------------------------------------
static void print_meas_results() {
  float lm;
  float ls           = compute_std(meas_buf, MEAS_N, &lm);
  float stable_delta = lm - tare_raw;
  float cal_factor   = stable_delta / ref_weight_g;
  bool  good         = ls < 3.0f * noise_std_raw;

  char buf[80];
  // STEP 6: placement-to-sampling-complete elapsed time
  snprintf(buf, sizeof(buf), "[TIMING] placement confirmed -> sampling complete: %.1fs",
           (millis() - g_placement_ms) / 1000.0f);
  Serial.println(buf);
  snprintf(buf, sizeof(buf), ">>> noise_std_raw:  %.1f", noise_std_raw);
  Serial.println(buf);
  snprintf(buf, sizeof(buf),
           good ? ">>> loaded_std_raw: %.1f  <- GOOD"
                : ">>> loaded_std_raw: %.1f  <- HIGH",
           ls);
  Serial.println(buf);
  snprintf(buf, sizeof(buf), ">>> tare_raw:       %.0f", tare_raw);
  Serial.println(buf);
  snprintf(buf, sizeof(buf), ">>> stable_delta:   %+.0f", stable_delta);
  Serial.println(buf);
  snprintf(buf, sizeof(buf), ">>> cal_factor:     %.2f raw/g", cal_factor);
  Serial.println(buf);
  if (good) {
    Serial.println(">>> QUALITY: GOOD");
  } else {
    Serial.println(">>> QUALITY: SUSPECT -- loaded_std HIGH, weight was moving, discard this reading");
  }
  Serial.println("--------------------");
}

// ===============================================================
// setup
// ===============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(HX711_SCK,  OUTPUT);
  pinMode(HX711_DOUT, INPUT_PULLUP);
  digitalWrite(HX711_SCK, LOW);

  Serial.println("3E001 cal_factor v5 | 3-cell platform | self-characterising | user-entered ref weight");
  Serial.println("Keep platform EMPTY and undisturbed until [TARE] appears.");

  g_boot_ms      = millis();   // STEP 2: capture boot reference time
  last_sample_ms = millis();
}

// ===============================================================
// loop — pure state machine, millis-paced
// ===============================================================
void loop() {
  unsigned long now = millis();

  // ---- STATE 0: PHASE_SETTLING ----
  if (phase == PHASE_SETTLING) {
    if (now - last_sample_ms < SAMPLE_MS)      return;
    if (digitalRead(HX711_DOUT) != LOW)         return;
    last_sample_ms = now;

    long raw = hx711_read_raw();
    if (raw == (long)LONG_MIN) return;

    block_buf[block_count++] = (float)raw;
    if (block_count < BLOCK_SIZE) return;

    // Full block — evaluate
    float bm;
    float bs    = compute_std(block_buf, BLOCK_SIZE, &bm);
    float drift = first_block ? 0.0f : fabsf(bm - prev_block_mean);
    bool  pass  = (bs < COLD_THRESHOLD) && (first_block || drift < COLD_THRESHOLD);

    char buf[80];
    if (pass) {
      cold_pass_count++;
      snprintf(buf, sizeof(buf), "[SETTLING] std=%.1f drift=%.1f PASS %d/%d",
               bs, drift, cold_pass_count, COLD_CONFIRM);
    } else {
      cold_pass_count = 0;
      snprintf(buf, sizeof(buf), "[SETTLING] std=%.1f drift=%.1f (still settling)",
               bs, drift);
    }
    Serial.println(buf);

    prev_block_mean = bm;
    first_block     = false;
    block_count     = 0;

    if (cold_pass_count >= COLD_CONFIRM) {
      noise_std_raw = bs;
      Serial.println("=== PLATFORM SETTLED ===");
      // STEP 3: boot-to-settled elapsed time
      snprintf(buf, sizeof(buf), "[TIMING] boot -> platform settled: %.1fs",
               (millis() - g_boot_ms) / 1000.0f);
      Serial.println(buf);
      snprintf(buf, sizeof(buf), "True noise STD (raw): %.1f", noise_std_raw);
      Serial.println(buf);
      spread_gate = K_SPREAD * noise_std_raw;
      drift_gate  = K_DRIFT  * noise_std_raw;
      snprintf(buf, sizeof(buf), "STAB_SPREAD gate = K_SPREAD(%.1f) x STD = %.1f raw",
               K_SPREAD, spread_gate);
      Serial.println(buf);
      snprintf(buf, sizeof(buf), "STAB_DRIFT  gate = K_DRIFT(%.1f)  x STD = %.1f raw",
               K_DRIFT, drift_gate);
      Serial.println(buf);
      reset_stab();
      phase = PHASE_STABILISING;
    }
    return;
  }

  // ---- STATE 1: PHASE_STABILISING ----
  if (phase == PHASE_STABILISING) {
    if (now - last_sample_ms < SAMPLE_MS)      return;
    if (digitalRead(HX711_DOUT) != LOW)         return;
    last_sample_ms = now;

    long raw = hx711_read_raw();
    if (raw == (long)LONG_MIN) return;

    if (run_stab_window((float)raw)) {
      // STEP 4: boot-to-first-tare elapsed time (STATE 1 only)
      char tbuf[80];
      snprintf(tbuf, sizeof(tbuf), "[TIMING] boot -> first tare locked: %.1fs",
               (millis() - g_boot_ms) / 1000.0f);
      Serial.println(tbuf);
      gate_step = 0;
      phase     = PHASE_MEASURE_GATE;
    }
    return;
  }

  // ---- STATE 2: PHASE_MEASURE_GATE ----
  if (phase == PHASE_MEASURE_GATE) {
    if (gate_step == 0) {
      // Confirm tare with user, flush stale Enter bytes
      waitForEnter("[EMPTY] Platform confirmed empty and tared.");
      gate_step = 1;
      return;
    }

    if (gate_step == 1) {
      // Ask for reference weight — blocking human input
      Serial.println("Enter reference weight in grams, press Enter:");
      while (Serial.available()) Serial.read();
      float w = 0.0f;
      do {
        w = read_weight_blocking();
        if (w <= 50.0f || w >= 5000.0f) {
          Serial.println("Invalid. Must be > 50 g and < 5000 g. Try again:");
        }
      } while (w <= 50.0f || w >= 5000.0f);
      ref_weight_g = w;
      char buf[48];
      snprintf(buf, sizeof(buf), "Reference weight locked: %.1f g", ref_weight_g);
      Serial.println(buf);
      gate_step = 2;
      return;
    }

    if (gate_step == 2) {
      waitForEnter("Place reference weight now. Press Enter when placed and still.");
      g_placement_ms  = millis();   // STEP 6: capture placement confirmation time
      countdown_start = millis();
      countdown_last  = 11;
      gate_step       = 3;
      return;
    }

    if (gate_step == 3) {
      // Non-blocking 10 s countdown
      do_countdown();
      if (millis() - countdown_start >= 10000UL) {
        Serial.println();
        Serial.println("Sampling now.");
        meas_count = 0;
        phase      = PHASE_MEASURE;
      }
      return;
    }
    return;
  }

  // ---- STATE 3: PHASE_MEASURE ----
  if (phase == PHASE_MEASURE) {
    if (now - last_sample_ms < SAMPLE_MS)      return;
    if (digitalRead(HX711_DOUT) != LOW)         return;
    last_sample_ms = now;

    long raw = hx711_read_raw();
    if (raw == (long)LONG_MIN) return;

    meas_buf[meas_count++] = (float)raw;
    if (meas_count < MEAS_N) return;

    print_meas_results();
    phase = PHASE_RETARE_WAIT;
    return;
  }

  // ---- STATE 4a: PHASE_RETARE_WAIT ----
  if (phase == PHASE_RETARE_WAIT) {
    waitForEnter("Remove weight. Press Enter when platform is clear.");
    g_removal_ms = millis();   // STEP 5: capture removal confirmation time
    reset_stab();
    phase = PHASE_RETARE_GATE;
    return;
  }

  // ---- STATE 4b: PHASE_RETARE_GATE ----
  if (phase == PHASE_RETARE_GATE) {
    if (now - last_sample_ms < SAMPLE_MS)      return;
    if (digitalRead(HX711_DOUT) != LOW)         return;
    last_sample_ms = now;

    long raw = hx711_read_raw();
    if (raw == (long)LONG_MIN) return;

    if (run_stab_window((float)raw)) {
      // STEP 5: removal-to-re-tare elapsed time
      char tbuf[80];
      snprintf(tbuf, sizeof(tbuf), "[TIMING] removal confirmed -> re-tare locked: %.1fs",
               (millis() - g_removal_ms) / 1000.0f);
      Serial.println(tbuf);
      gate_step = 0;
      phase     = PHASE_MEASURE_AGAIN_GATE;
    }
    return;
  }

  // ---- STATE 4c: PHASE_MEASURE_AGAIN_GATE ----
  if (phase == PHASE_MEASURE_AGAIN_GATE) {
    if (gate_step == 0) {
      waitForEnter("Place reference weight again. Press Enter when placed and still.");
      g_placement_ms  = millis();   // STEP 6: capture placement confirmation time
      countdown_start = millis();
      countdown_last  = 11;
      gate_step       = 1;
      return;
    }

    if (gate_step == 1) {
      // Non-blocking 10 s countdown
      do_countdown();
      if (millis() - countdown_start >= 10000UL) {
        Serial.println();
        Serial.println("Sampling now.");
        meas_count = 0;
        phase      = PHASE_MEASURE_AGAIN;
      }
      return;
    }
    return;
  }

  // ---- STATE 3 (repeat): PHASE_MEASURE_AGAIN ----
  if (phase == PHASE_MEASURE_AGAIN) {
    if (now - last_sample_ms < SAMPLE_MS)      return;
    if (digitalRead(HX711_DOUT) != LOW)         return;
    last_sample_ms = now;

    long raw = hx711_read_raw();
    if (raw == (long)LONG_MIN) return;

    meas_buf[meas_count++] = (float)raw;
    if (meas_count < MEAS_N) return;

    print_meas_results();
    phase = PHASE_RETARE_WAIT;   // loop forever: RETARE_WAIT → RETARE_GATE → MEASURE_AGAIN_GATE → MEASURE_AGAIN
    return;
  }
}
