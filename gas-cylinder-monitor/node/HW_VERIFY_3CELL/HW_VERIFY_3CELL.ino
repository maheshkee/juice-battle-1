// HW_VERIFY_3CELL - 3-cell parallel platform diagnostic
//
// Purpose : confirm all 3 cells connected, contributing, and behaving.
// Hardware: ESP32-C3 SuperMini, GPIO4=DOUT, GPIO3=SCK, HX711 at 3V3.
// Platform: 3-cell YZC-161A parallel wiring.
// Usage   : flash, open Serial Monitor 115200, follow prompts. ~2 min total.

#include <math.h>
#include <limits.h>

#define DOUT_PIN   4
#define SCK_PIN    3

#define CAL_FACTOR  36.1f   // LOCKED 2026-06-12 - 3-cell parallel

// ---- HX711 bit-bang ----
long hx711_read() {
  uint32_t deadline = millis() + 500;
  while (digitalRead(DOUT_PIN) == HIGH) {
    if (millis() >= deadline) return LONG_MIN;
  }
  int32_t value = 0;
  noInterrupts();
  for (int i = 0; i < 24; i++) {
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | digitalRead(DOUT_PIN);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);
  }
  // 25th pulse: gain 128 channel A
  digitalWrite(SCK_PIN, HIGH); delayMicroseconds(1);
  digitalWrite(SCK_PIN, LOW);  delayMicroseconds(1);
  interrupts();
  // Sign-extend bit 23
  if (value & 0x800000) value |= 0xFF000000;
  long v = (long)value;
  // Three corrupt filters
  if (v == LONG_MIN || v == -1L || v == (long)0x7FFFFF) return LONG_MIN;
  return v;
}

// ---- Collect n valid readings. Skips LONG_MIN. Prints each if verbose. ----
// Returns count collected (may be < n if max_tries exhausted).
int collect_valid(int n, float* buf, bool verbose) {
  int count = 0;
  int tries = 0;
  int max_tries = n * 10;
  while (count < n && tries < max_tries) {
    tries++;
    long v = hx711_read();
    if (v == LONG_MIN) { delay(110); continue; }
    buf[count] = (float)v;
    if (verbose) {
      char tmp[48];
      snprintf(tmp, sizeof(tmp), "  [%2d] %ld", count + 1, v);
      Serial.println(tmp);
    }
    count++;
    delay(110);
  }
  return count;
}

// ---- Mean and population STD ----
void compute_stats(float* buf, int n, float* mean_out, float* std_out) {
  float sum = 0.0f;
  for (int i = 0; i < n; i++) sum += buf[i];
  *mean_out = sum / (float)n;
  float var = 0.0f;
  for (int i = 0; i < n; i++) {
    float d = buf[i] - *mean_out;
    var += d * d;
  }
  *std_out = sqrtf(var / (float)n);
}

// ---- Wait for user to press Enter ----
void waitForEnter(const char* prompt) {
  delay(2000);
  while (Serial.available()) Serial.read();
  Serial.println(prompt);
  Serial.println(">>> Press Enter when ready <<<");
  while (!Serial.available()) { delay(10); }
  while (Serial.available()) Serial.read();
}

void setup() {
  pinMode(DOUT_PIN, INPUT_PULLUP);
  pinMode(SCK_PIN,  OUTPUT);
  digitalWrite(SCK_PIN, LOW);

  Serial.begin(115200);
  Serial.setTimeout(30000);
  while (!Serial) { delay(10); }
  delay(1000);

  Serial.println("========================================");
  Serial.println("HW_VERIFY_3CELL - 3-cell parallel diagnostic");
  Serial.println("GPIO4=DOUT  GPIO3=SCK  HX711 at 3V3");
  Serial.println("3-cell YZC-161A parallel | CAL=36.1 raw/g");
  Serial.println("========================================");
  Serial.println("");

  // Summary state
  bool  sec1_pass           = false;
  float tare_raw            = 0.0f;
  bool  cell_lift_pass[3]        = {false, false, false};
  bool  cell_lift_polarity[3]    = {false, false, false};
  bool  cell_lift_sensitivity[3] = {false, false, false};
  bool  cell_recovery_pass[3]    = {false, false, false};
  bool  sec4_pass           = false;
  float derived_cal         = 0.0f;

  float buf[20];
  char  line[96];
  int   n;

  // ======== SECTION 1 - RAW STABILITY CHECK ========
  Serial.println("--- SECTION 1: RAW STABILITY CHECK ---");
  Serial.println("Collecting 20 valid raw readings (skipping LONG_MIN)...");

  n = collect_valid(20, buf, true);
  if (n < 20) {
    Serial.println("ERROR: could not collect 20 valid readings. Check wiring.");
    goto summary;
  }

  {
    float mean1, std1;
    compute_stats(buf, 20, &mean1, &std1);
    float cv = (fabsf(mean1) > 0.0f) ? (std1 / fabsf(mean1) * 100.0f) : 999.0f;
    snprintf(line, sizeof(line), "Mean: %.1f  STD: %.1f  CV: %.3f%%", mean1, std1, cv);
    Serial.println(line);
    if (cv < 1.0f) {
      Serial.println("RAW STABILITY: PASS");
      sec1_pass = true;
    } else {
      Serial.println("RAW STABILITY: FAIL - possible loose connection or noisy platform");
    }
  }
  Serial.println("");

  // ======== SECTION 2 - TARE DERIVATION ========
  Serial.println("--- SECTION 2: TARE DERIVATION ---");
  Serial.println("Collecting 20 valid readings for tare (platform unloaded)...");

  n = collect_valid(20, buf, false);
  if (n < 20) {
    Serial.println("ERROR: could not collect 20 valid readings. Check wiring.");
    goto summary;
  }

  {
    float mean2, std2;
    compute_stats(buf, 20, &mean2, &std2);
    tare_raw = mean2;
    snprintf(line, sizeof(line), "tare_raw: %.1f", tare_raw);
    Serial.println(line);
    Serial.println("Expected range: -80000 to -120000 raw (3-cell parallel)");
    if (tare_raw < -130000.0f || tare_raw > -60000.0f) {
      Serial.println("TARE WARNING: value outside expected range - check wiring");
    }
  }
  Serial.println("");

  // ======== SECTION 3 - LIFT TEST ========
  Serial.println("--- SECTION 3: LIFT TEST (one cell at a time) ---");
  Serial.println("Lift each corner ~1cm. Lifting reduces that cell's load.");
  Serial.println("Expected: delta_g NEGATIVE, |delta_g| > 50g.");
  Serial.println("");

  for (int c = 0; c < 3; c++) {
    char prompt[80];
    snprintf(prompt, sizeof(prompt),
             "Lift corner %d slightly (~1cm) off the surface. Press Enter.", c + 1);
    waitForEnter(prompt);

    Serial.println("  Collecting 10 readings (lifted)...");
    float lbuf[10];
    int ln = collect_valid(10, lbuf, false);

    if (ln < 10) {
      Serial.println("  ERROR: not enough valid readings during lift.");
      cell_lift_sensitivity[c] = true;
    } else {
      float lifted_mean, lifted_std;
      compute_stats(lbuf, 10, &lifted_mean, &lifted_std);

      float delta_raw_f = lifted_mean - tare_raw;
      float delta_g     = delta_raw_f / CAL_FACTOR;

      snprintf(line, sizeof(line), "  delta_raw: %.1f  delta_g: %.1f g", delta_raw_f, delta_g);
      Serial.println(line);

      bool polarity_ok    = (delta_g < 0.0f);
      bool sensitivity_ok = (fabsf(delta_g) > 50.0f);

      if (polarity_ok && sensitivity_ok) {
        snprintf(line, sizeof(line),
                 "CELL %d: PASS - responds to lift, delta=%.1fg", c + 1, delta_g);
        Serial.println(line);
        cell_lift_pass[c] = true;
      } else if (!polarity_ok) {
        snprintf(line, sizeof(line),
                 "CELL %d: POLARITY WARN - lifting increased reading, check wiring", c + 1);
        Serial.println(line);
        cell_lift_polarity[c] = true;
      } else {
        snprintf(line, sizeof(line),
                 "CELL %d: SENSITIVITY WARN - lift not detected, possible open circuit", c + 1);
        Serial.println(line);
        cell_lift_sensitivity[c] = true;
      }
    }

    snprintf(prompt, sizeof(prompt),
             "Put corner %d back down. Press Enter when settled.", c + 1);
    waitForEnter(prompt);

    Serial.println("  Collecting 10 readings (recovery)...");
    float rbuf[10];
    int rn = collect_valid(10, rbuf, false);

    if (rn < 10) {
      Serial.println("  ERROR: not enough valid readings during recovery.");
    } else {
      float rec_mean, rec_std;
      compute_stats(rbuf, 10, &rec_mean, &rec_std);
      float rec_delta_g = (rec_mean - tare_raw) / CAL_FACTOR;
      snprintf(line, sizeof(line), "  recovery_delta_g: %.1f g", rec_delta_g);
      Serial.println(line);
      if (fabsf(rec_delta_g) < 20.0f) {
        snprintf(line, sizeof(line), "CELL %d RECOVERY: PASS", c + 1);
        Serial.println(line);
        cell_recovery_pass[c] = true;
      } else {
        snprintf(line, sizeof(line),
                 "CELL %d RECOVERY: WARN - platform not settling back to tare", c + 1);
        Serial.println(line);
      }
    }
    Serial.println("");
  }

  // ======== SECTION 4 - LOAD TEST ========
  Serial.println("--- SECTION 4: LOAD TEST ---");
  waitForEnter("Place your reference weight (any known weight 500g-1500g) on platform centre.");

  {
    // millis()-paced 5 second settle
    Serial.println("  Settling 5 seconds...");
    uint32_t settle_end = millis() + 5000;
    while (millis() < settle_end) { delay(50); }

    Serial.println("  Collecting 20 valid readings...");
    float ldbuf[20];
    int ldn = collect_valid(20, ldbuf, false);

    if (ldn < 20) {
      Serial.println("ERROR: not enough valid readings. Check wiring.");
    } else {
      float loaded_mean, loaded_std;
      compute_stats(ldbuf, 20, &loaded_mean, &loaded_std);

      float delta_raw_load = loaded_mean - tare_raw;
      float delta_g_load   = delta_raw_load / CAL_FACTOR;

      snprintf(line, sizeof(line), "  delta_raw: %.1f  delta_g: %.1f g",
               delta_raw_load, delta_g_load);
      Serial.println(line);
      Serial.println("  Expected cal_factor range: 32.0 to 40.0 raw/g");
      Serial.println("  Enter known weight in grams (e.g. 1000) and press Enter:");

      while (Serial.available()) Serial.read();  // flush before read
      char wbuf[16];
      int wlen = Serial.readBytesUntil('\n', wbuf, sizeof(wbuf) - 1);
      wbuf[wlen] = '\0';
      // strip trailing \r (Windows Serial Monitor)
      if (wlen > 0 && wbuf[wlen - 1] == '\r') wbuf[wlen - 1] = '\0';

      float known_g = atof(wbuf);
      if (known_g > 0.0f) {
        derived_cal = delta_raw_load / known_g;
        snprintf(line, sizeof(line), "  derived cal_factor: %.2f raw/g", derived_cal);
        Serial.println(line);
        if (derived_cal >= 32.0f && derived_cal <= 40.0f) {
          Serial.println("LOAD TEST: PASS - cal_factor plausible");
          sec4_pass = true;
        } else {
          Serial.println("LOAD TEST: FAIL - cal_factor out of range, check all cell connections");
        }
      } else {
        Serial.println("  WARN: invalid weight entered. Skipping cal_factor range check.");
      }
    }
  }
  Serial.println("");

  // ======== SECTION 5 - SUMMARY ========
  summary:
  Serial.println("=== HW_VERIFY_3CELL SUMMARY ===");
  snprintf(line, sizeof(line), "Raw stability : %s", sec1_pass ? "PASS" : "FAIL");
  Serial.println(line);
  snprintf(line, sizeof(line), "Tare raw      : %.1f", tare_raw);
  Serial.println(line);
  for (int c = 0; c < 3; c++) {
    const char* s = cell_lift_pass[c] ? "PASS" : "WARN";
    snprintf(line, sizeof(line), "Cell %d lift   : %s", c + 1, s);
    Serial.println(line);
  }
  snprintf(line, sizeof(line), "Load test     : %s", sec4_pass ? "PASS" : "FAIL");
  Serial.println(line);
  snprintf(line, sizeof(line), "derived cal_f : %.2f raw/g", derived_cal);
  Serial.println(line);
  Serial.println("================================");

  bool all_pass = sec1_pass && sec4_pass
                  && cell_lift_pass[0]     && cell_lift_pass[1]     && cell_lift_pass[2]
                  && cell_recovery_pass[0] && cell_recovery_pass[1] && cell_recovery_pass[2];
  if (all_pass) {
    Serial.println("Overall: ALL PASS");
  } else {
    Serial.print("Overall: FAILURES -");
    if (!sec1_pass) Serial.print(" raw_stability");
    if (!sec4_pass) Serial.print(" load_test");
    for (int c = 0; c < 3; c++) {
      if (!cell_lift_pass[c]) {
        snprintf(line, sizeof(line), " cell%d_lift", c + 1);
        Serial.print(line);
      }
      if (!cell_recovery_pass[c]) {
        snprintf(line, sizeof(line), " cell%d_recovery", c + 1);
        Serial.print(line);
      }
    }
    Serial.println("");
  }
  Serial.println("================================");
}

void loop() {
  // All work done in setup(). Nothing here.
}
