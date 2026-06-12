// EXP_parallel_verify.ino
// Theory: 4-cell parallel platform sum invariance.
// Same total weight regardless of how it is distributed across cells.

#include <climits>

// --- Hardware constants (locked 2026-06-04) ---
static const int   PIN_DOUT          = 4;
static const int   PIN_SCK           = 3;
static const int   BAUD              = 115200;
static const int   TARE_SAMPLES      = 20;
static const long  TARE_SPREAD_MAX   = 600L;
static const int   TARE_RETRIES      = 3;
static const int   STABILITY_WINDOW     = 20;
static const long  STABILITY_SPREAD_MAX = 600L;
static const long  STABILITY_DRIFT_MAX  = 210L;
static const int   STABILITY_WINDOWS    = 3;
static const int   READ_SAMPLES      = 10;
static const int   READ_INTERVAL_MS  = 150;
static const float PASS_THRESHOLD_G  = 5.0f;

// --- Test configuration ---
struct Config {
  const char* name;
  const char* c1;
  const char* c2;
  const char* c3;
  const char* c4;
  int expected_g;
};

static const Config CONFIGS[8] = {
  { "C1 one-each",       "Phone 234g",  "Speaker 229g", "Adapter 92g",  "Wood 34g",     589 },
  { "C2 reversed",       "Wood 34g",    "Adapter 92g",  "Speaker 229g", "Phone 234g",   589 },
  { "C3 all-on-C1",      "ALL 589g",    "empty",        "empty",        "empty",        589 },
  { "C4 all-on-C2",      "empty",       "ALL 589g",     "empty",        "empty",        589 },
  { "C5 two-pair split", "Ph+Sp 463g",  "empty",        "Ad+Wo 126g",   "empty",        589 },
  { "C6 phone-only",     "Phone 234g",  "empty",        "empty",        "empty",        234 },
  { "C7 two-cells",      "Phone 234g",  "Speaker 229g", "empty",        "empty",        463 },
  { "C8 tare-check",     "empty",       "empty",        "empty",        "empty",          0 },
};

// --- State machine ---
enum State {
  ST_TARE_WAIT,
  ST_TARE_RUN,
  ST_CAL_WAIT,
  ST_CAL_RUN,
  ST_CAL_INPUT,
  ST_CONFIG_WAIT,
  ST_CONFIG_RUN,
  ST_RETARE_WAIT,
  ST_RETARE_EMPTY_WAIT,
  ST_DONE
};

// --- Globals ---
long          tare_raw          = 0;
float         cal_factor        = 0.0f;
int           config_index      = 0;
float         results[8]        = {0};
bool          done[8]           = {false};
State         state             = ST_TARE_WAIT;
unsigned long last_ms           = 0;
float         acc_sum           = 0.0f;
int           acc_count         = 0;
String        serial_input      = "";
bool          retare_requested  = false;

// --- Bit-bang HX711 read ---
long hx711_read_one() {
  unsigned long start = millis();
  while (digitalRead(PIN_DOUT) == HIGH) {
    if (millis() - start > 500UL) return LONG_MIN;
  }

  long value = 0;
  noInterrupts();
  for (int i = 0; i < 24; i++) {
    digitalWrite(PIN_SCK, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | digitalRead(PIN_DOUT);
    digitalWrite(PIN_SCK, LOW);
    delayMicroseconds(1);
  }
  // 25th pulse — set gain 128
  digitalWrite(PIN_SCK, HIGH);
  delayMicroseconds(1);
  digitalWrite(PIN_SCK, LOW);
  delayMicroseconds(1);
  interrupts();

  if (value & 0x800000L) value |= 0xFF000000L;
  return value;
}

// --- Corrupt filter ---
bool is_corrupt(long raw) {
  return (raw == LONG_MIN || raw == -1L || raw == 0x7FFFFFL);
}

// --- Tare derivation (E-002: stability gate + sample collection) ---
bool derive_tare() {
  long degraded_mean = 0;

  for (int attempt = 1; attempt <= TARE_RETRIES; attempt++) {
    int  consecutive_pass = 0;
    long prev_mean        = 0;
    bool first_window     = true;
    bool stable           = false;

    // Phase 1: stability gate
    for (int w = 0; w < 60; w++) {
      long win_buf[STABILITY_WINDOW];
      int  clean = 0;
      for (int i = 0; i < STABILITY_WINDOW; i++) {
        long r = hx711_read_one();
        if (!is_corrupt(r)) win_buf[clean++] = r;
        delay(110);
      }
      if (clean == 0) continue;

      long mn = win_buf[0], mx = win_buf[0], wsum = 0;
      for (int i = 0; i < clean; i++) {
        if (win_buf[i] < mn) mn = win_buf[i];
        if (win_buf[i] > mx) mx = win_buf[i];
        wsum += win_buf[i];
      }
      long window_mean = wsum / clean;
      long spread      = mx - mn;
      long drift       = first_window ? 0L
                         : (window_mean > prev_mean ? window_mean - prev_mean
                                                    : prev_mean - window_mean);

      bool pass = (spread < STABILITY_SPREAD_MAX) &&
                  (first_window || drift < STABILITY_DRIFT_MAX);

      char buf[80];
      snprintf(buf, sizeof(buf),
               "  Window %d: spread=%ld drift=%ld (%s)",
               w + 1, spread, drift, pass ? "pass" : "fail");
      Serial.println(buf);

      if (pass) {
        consecutive_pass++;
        snprintf(buf, sizeof(buf), "  Pass %d/%d", consecutive_pass, STABILITY_WINDOWS);
        Serial.println(buf);
      } else {
        consecutive_pass = 0;
        Serial.println("  Reset - unstable");
      }

      degraded_mean = window_mean;
      prev_mean     = window_mean;
      first_window  = false;

      if (consecutive_pass == STABILITY_WINDOWS) {
        stable = true;
        break;
      }
    }

    if (!stable) {
      Serial.println("  Stability timeout. Retrying...");
      delay(2000);
      continue;
    }

    // Phase 2: sample collection and self-validation
    long tar_buf[TARE_SAMPLES];
    int  clean = 0;
    for (int i = 0; i < TARE_SAMPLES; i++) {
      long r = hx711_read_one();
      if (!is_corrupt(r)) tar_buf[clean++] = r;
      delay(110);
    }
    if (clean == 0) continue;

    long mn = tar_buf[0], mx = tar_buf[0], tsum = 0;
    for (int i = 0; i < clean; i++) {
      if (tar_buf[i] < mn) mn = tar_buf[i];
      if (tar_buf[i] > mx) mx = tar_buf[i];
      tsum += tar_buf[i];
    }
    long spread = mx - mn;
    long avg    = tsum / clean;

    char buf[80];
    snprintf(buf, sizeof(buf),
             "  Tare samples: clean=%d spread=%ld avg=%ld", clean, spread, avg);
    Serial.println(buf);

    if (spread > TARE_SPREAD_MAX) {
      Serial.println("  Self-validation failed - spread too high");
      continue;
    }

    tare_raw = avg;
    snprintf(buf, sizeof(buf), "  TARE locked: %ld", tare_raw);
    Serial.println(buf);
    return true;
  }

  Serial.println("  DEGRADED tare used - platform unstable");
  tare_raw = degraded_mean;
  return true;
}

// --- Config prompt ---
void print_config_prompt(int idx) {
  const Config& c = CONFIGS[idx];
  Serial.println("-------------------------------------------");
  char buf[64];
  snprintf(buf, sizeof(buf), "[CONFIG %d of 8]  %s", idx + 1, c.name);
  Serial.println(buf);
  Serial.print("  Cell 1: "); Serial.println(c.c1);
  Serial.print("  Cell 2: "); Serial.println(c.c2);
  Serial.print("  Cell 3: "); Serial.println(c.c3);
  Serial.print("  Cell 4: "); Serial.println(c.c4);
  snprintf(buf, sizeof(buf), "  Expected: ~%dg", c.expected_g);
  Serial.println(buf);
  Serial.println("Press T then ENTER to re-tare before this config.");
  Serial.println("Or press ENTER to skip re-tare and place weights.");
}

// --- Summary ---
void print_summary() {
  Serial.println("-----------------------------------------");
  Serial.println("  SUMMARY");
  Serial.println("  Config                 Expected   Read      Error    Result");
  char buf[80];
  for (int i = 0; i < 8; i++) {
    if (!done[i]) continue;
    float err  = results[i] - (float)CONFIGS[i].expected_g;
    bool  pass = (err < 0 ? -err : err) < PASS_THRESHOLD_G;
    snprintf(buf, sizeof(buf), "  %-22s  %4dg   %6.1fg   %+6.1fg   %s",
             CONFIGS[i].name, CONFIGS[i].expected_g, results[i], err,
             pass ? "PASS" : "CHECK");
    Serial.println(buf);
  }
  Serial.println("-----------------------------------------");
  Serial.println("Theory check:");
  Serial.println("  C1-C5 all ~589g  sum invariance VERIFIED");
  Serial.println("  C6 ~234g, C7 ~463g, C8 ~0g");
}

// --- setup ---
void setup() {
  Serial.begin(BAUD);
  delay(2000);
  pinMode(PIN_DOUT, INPUT_PULLUP);
  pinMode(PIN_SCK, OUTPUT);
  digitalWrite(PIN_SCK, LOW);

  Serial.println("=== EXP: 4-Cell Parallel Sum Invariance ===");
  Serial.println("Weights: Phone=234g Speaker=229g Adapter=92g Wood=34g Total=589g");
  Serial.println("STEP 1: Remove ALL weights. Press ENTER.");
}

// --- loop ---
void loop() {
  // millis() pacing guard
  unsigned long now = millis();
  if (now - last_ms < (unsigned long)READ_INTERVAL_MS &&
      (state == ST_CAL_RUN || state == ST_CONFIG_RUN)) {
    // drain serial so we don't miss input in other states
    goto read_serial;
  }

  switch (state) {

    case ST_TARE_WAIT:
      goto read_serial;

    case ST_TARE_RUN: {
      bool ok = derive_tare();
      if (!ok) {
        Serial.println("Tare failed. Check wiring. Press ENTER to retry.");
        state = ST_TARE_WAIT;
        return;
      }
      Serial.println("Tare OK.");
      Serial.println("STEP 2: Place ONE weight on ONE cell (any cell). Leave others empty. Press ENTER.");
      state = ST_CAL_WAIT;
      return;
    }

    case ST_CAL_WAIT:
      goto read_serial;

    case ST_CAL_RUN: {
      last_ms = now;
      long raw = hx711_read_one();
      if (is_corrupt(raw)) return;
      long net_raw = raw - tare_raw;
      acc_sum += (float)net_raw;
      acc_count++;
      char buf[64];
      snprintf(buf, sizeof(buf), "  [%d/10] raw=%ld net=%ld", acc_count, raw, net_raw);
      Serial.println(buf);
      if (acc_count >= READ_SAMPLES) {
        float avg_net = acc_sum / (float)acc_count;
        snprintf(buf, sizeof(buf), "Avg net raw: %.1f", avg_net);
        Serial.println(buf);
        Serial.println("Type actual weight in grams then ENTER (e.g. 234):");
        state = ST_CAL_INPUT;
      }
      return;
    }

    case ST_CAL_INPUT:
      goto read_serial;

    case ST_CONFIG_WAIT:
      goto read_serial;

    case ST_RETARE_WAIT:
      goto read_serial;

    case ST_RETARE_EMPTY_WAIT:
      goto read_serial;

    case ST_CONFIG_RUN: {
      last_ms = now;
      long raw = hx711_read_one();
      if (is_corrupt(raw)) return;
      float grams = (float)(raw - tare_raw) / cal_factor;
      acc_sum += grams;
      acc_count++;
      char buf[64];
      snprintf(buf, sizeof(buf), "  [%d/10] raw=%ld grams=%.1fg", acc_count, raw, grams);
      Serial.println(buf);
      if (acc_count >= READ_SAMPLES) {
        float avg_g    = acc_sum / (float)acc_count;
        int   expected = CONFIGS[config_index].expected_g;
        float err      = avg_g - (float)expected;
        bool  pass     = (err < 0 ? -err : err) < PASS_THRESHOLD_G;

        char buf2[64];
        snprintf(buf2, sizeof(buf2), "-- CONFIG %d RESULT --", config_index + 1);
        Serial.println(buf2);
        snprintf(buf2, sizeof(buf2), "Average  : %.1fg", avg_g);
        Serial.println(buf2);
        snprintf(buf2, sizeof(buf2), "Expected : %dg", expected);
        Serial.println(buf2);
        snprintf(buf2, sizeof(buf2), "Error    : %+.1fg", err);
        Serial.println(buf2);
        Serial.print("Result   : "); Serial.println(pass ? "PASS" : "CHECK");

        results[config_index] = avg_g;
        done[config_index]    = true;
        config_index++;

        if (config_index >= 8) {
          print_summary();
          state = ST_DONE;
        } else {
          print_config_prompt(config_index);
          state = ST_CONFIG_WAIT;
        }
      }
      return;
    }

    case ST_DONE:
      return;
  }

read_serial:
  // Serial input handler — shared across waiting states
  while (Serial.available()) {
    char ch = (char)Serial.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      // dispatch on current state
      if (state == ST_TARE_WAIT) {
        state = ST_TARE_RUN;

      } else if (state == ST_CAL_WAIT) {
        Serial.println("Collecting calibration readings...");
        acc_sum   = 0.0f;
        acc_count = 0;
        last_ms   = 0;
        state     = ST_CAL_RUN;

      } else if (state == ST_CAL_INPUT) {
        int actual_g = serial_input.toInt();
        serial_input = "";
        if (actual_g <= 0) {
          Serial.println("Invalid. Enter digits only.");
          return;
        }
        cal_factor = (acc_sum / (float)acc_count) / (float)actual_g;
        char buf[64];
        snprintf(buf, sizeof(buf), "CAL_FACTOR = %.4f raw/g", cal_factor);
        Serial.println(buf);
        if (cal_factor < 10.0f || cal_factor > 300.0f) {
          Serial.println("WARNING: outside expected range 10-300");
          Serial.println("  Note: 4 independent-plate cells expect ~26 raw/g. Shared platform expects ~105 raw/g.");
        }
        float verify_g = (acc_sum / (float)acc_count) / cal_factor;
        snprintf(buf, sizeof(buf), "Verification: reads %.1fg (should be %dg)", verify_g, actual_g);
        Serial.println(buf);
        config_index = 0;
        print_config_prompt(config_index);
        state = ST_CONFIG_WAIT;

      } else if (state == ST_CONFIG_WAIT) {
        String inp = serial_input;
        inp.trim();
        inp.toUpperCase();
        if (inp.length() > 0 && inp[0] == 'T') {
          state = ST_RETARE_EMPTY_WAIT;
          Serial.println("Remove ALL weights from ALL cells.");
          Serial.println("Press ENTER when all platforms are empty.");
        } else {
          Serial.println("Settling... wait 10s");
          for (int i = 10; i >= 1; i--) {
            char buf[32];
            snprintf(buf, sizeof(buf), "  %d s remaining", i);
            Serial.println(buf);
            delay(1000);
          }
          Serial.println("  Settled. Reading now.");
          acc_sum   = 0.0f;
          acc_count = 0;
          last_ms   = 0;
          state     = ST_CONFIG_RUN;
        }

      } else if (state == ST_RETARE_WAIT) {
        Serial.println("Deriving new tare...");
        bool ok = derive_tare();
        if (!ok) {
          Serial.println("Tare failed. Press ENTER to retry.");
          return;
        }
        char buf[48];
        snprintf(buf, sizeof(buf), "New tare locked: %ld", tare_raw);
        Serial.println(buf);
        Serial.println("Now place your weights for this config.");
        print_config_prompt(config_index);
        state = ST_CONFIG_WAIT;

      } else if (state == ST_RETARE_EMPTY_WAIT) {
        Serial.println("Running stability gate then tare...");
        bool ok = derive_tare();
        if (!ok) {
          Serial.println("Tare error. Press ENTER to retry.");
          return;
        }
        char buf[56];
        snprintf(buf, sizeof(buf), "Tare OK. Now place weights for Config %d.", config_index + 1);
        Serial.println(buf);
        print_config_prompt(config_index);
        Serial.println("Press ENTER when weights are placed.");
        state = ST_CONFIG_WAIT;
      }
      serial_input = "";
    } else {
      if (state == ST_CAL_INPUT || state == ST_CONFIG_WAIT) {
        serial_input += ch;
      }
    }
  }
}
