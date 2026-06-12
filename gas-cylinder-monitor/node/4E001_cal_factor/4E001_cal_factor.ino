// 4E001_cal_factor.ino
// Experiment 4E-001: cal_factor derivation on 4-cell platform.
// Reference weight: 597.0g (water bottle).
// Hardware: 4x YZC-161A in parallel, one HX711, ESP32-C3 3V3.

#include <Arduino.h>
#include <climits>

#define HX711_DT            4
#define HX711_SCK           3
#define WIN_SIZE            20
#define WIN_SPREAD_MAX      300
#define WIN_DRIFT_MAX       200
#define WIN_CONFIRM         3
#define PLACE_THRESHOLD     2000
#define REMOVE_THRESHOLD    500
#define RETARE_DRIFT_MAX    300
#define KNOWN_WEIGHT_G      597.0f
#define EST_CAL_FACTOR      26.0f
#define SAMPLE_INTERVAL_MS  100

enum State { STATE_STABILISING, STATE_EMPTY, STATE_LOADED };

static State         state            = STATE_STABILISING;
static float         win_buf[WIN_SIZE];
static int           win_index        = 0;
static float         prev_win_mean    = 0.0f;
static int           confirm_count    = 0;
static bool          first_window     = true;
static long          tare_raw         = 0;
static unsigned long last_sample_ms   = 0;
static unsigned long last_status_ms   = 0;
static bool          watching_removal = false;

static long hx711_read_raw() {
  unsigned long t0 = millis();
  while (digitalRead(HX711_DT) == HIGH) {
    if (millis() - t0 > 200UL) return LONG_MIN;
  }
  long value = 0;
  noInterrupts();
  for (int i = 0; i < 24; i++) {
    digitalWrite(HX711_SCK, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | digitalRead(HX711_DT);
    digitalWrite(HX711_SCK, LOW);
    delayMicroseconds(1);
  }
  // 25th pulse — sets gain 128 for next conversion
  digitalWrite(HX711_SCK, HIGH);
  delayMicroseconds(1);
  digitalWrite(HX711_SCK, LOW);
  delayMicroseconds(1);
  interrupts();
  if (value & 0x800000L) value |= 0xFF000000L;
  return value;
}

static void reset_window() {
  win_index     = 0;
  confirm_count = 0;
  prev_win_mean = 0.0f;
  first_window  = true;
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("4E-001 | cal_factor derivation | 4-cell platform | 597g ref | GPIO4=DT GPIO3=SCK");
  pinMode(HX711_DT,  INPUT_PULLUP);
  pinMode(HX711_SCK, OUTPUT);
  digitalWrite(HX711_SCK, LOW);
}

void loop() {
  // millis() pacing guard — TOP of loop(), before all state logic
  unsigned long now = millis();
  if (now - last_sample_ms < (unsigned long)SAMPLE_INTERVAL_MS) return;
  last_sample_ms = now;

  long raw = hx711_read_raw();

  // Three corrupt filters — skip silently on any match
  if (raw == LONG_MIN || raw == -1L || (raw & 0xFFFFFF) == 0x7FFFFF) return;

  char buf[128];

  switch (state) {

    case STATE_STABILISING: {
      win_buf[win_index++] = (float)raw;
      if (win_index < WIN_SIZE) break;
      win_index = 0;

      float mn = win_buf[0], mx = win_buf[0], wsum = 0.0f;
      for (int i = 0; i < WIN_SIZE; i++) {
        if (win_buf[i] < mn) mn = win_buf[i];
        if (win_buf[i] > mx) mx = win_buf[i];
        wsum += win_buf[i];
      }
      float win_mean = wsum / (float)WIN_SIZE;
      long  spread   = (long)(mx - mn);
      long  drift    = first_window ? 0L : (long)fabsf(win_mean - prev_win_mean);
      bool  pass     = (spread < WIN_SPREAD_MAX) && (first_window || drift < WIN_DRIFT_MAX);

      if (pass) {
        confirm_count++;
        snprintf(buf, sizeof(buf), "[STABILISING] spread=%ld drift=%ld WIN %d/%d",
                 spread, drift, confirm_count, WIN_CONFIRM);
      } else {
        confirm_count = 0;
        snprintf(buf, sizeof(buf), "[STABILISING] spread=%ld drift=%ld (reset)",
                 spread, drift);
      }
      Serial.println(buf);

      prev_win_mean = win_mean;
      first_window  = false;

      if (confirm_count >= WIN_CONFIRM) {
        tare_raw = (long)win_mean;
        snprintf(buf, sizeof(buf), "[TARE] tare_raw=%ld", tare_raw);
        Serial.println(buf);
        reset_window();
        state = STATE_EMPTY;
      }
      break;
    }

    case STATE_EMPTY: {
      long delta     = raw - tare_raw;
      long abs_delta = delta < 0L ? -delta : delta;

      // Creep check: small drift that isn't placement — retare silently
      if (abs_delta > RETARE_DRIFT_MAX && abs_delta < PLACE_THRESHOLD) {
        tare_raw = raw;
        snprintf(buf, sizeof(buf), "[EMPTY] AUTO-RETARE  tare_raw=%ld", tare_raw);
        Serial.println(buf);
        break;
      }

      // Placement check
      if (delta > PLACE_THRESHOLD) {
        state = STATE_LOADED;
        reset_window();
        watching_removal = false;
        break;
      }

      // Status print every 2000ms
      if (now - last_status_ms >= 2000UL) {
        last_status_ms = now;
        snprintf(buf, sizeof(buf),
                 "[EMPTY] tare=%ld  delta=%+ld  Place 597g water bottle on platform.",
                 tare_raw, delta);
        Serial.println(buf);
      }
      break;
    }

    case STATE_LOADED: {
      long delta_from_tare = raw - tare_raw;

      // Removal-watch sub-mode: weight has been measured, waiting for removal
      if (watching_removal) {
        if (delta_from_tare < REMOVE_THRESHOLD) {
          tare_raw = raw;
          snprintf(buf, sizeof(buf), "[EMPTY] AUTO-RETARE  tare_raw=%ld", tare_raw);
          Serial.println(buf);
          state = STATE_EMPTY;
          reset_window();
          watching_removal = false;
        }
        break;
      }

      // Window accumulation on delta_from_tare values
      win_buf[win_index++] = (float)delta_from_tare;
      if (win_index < WIN_SIZE) break;
      win_index = 0;

      float mn = win_buf[0], mx = win_buf[0], wsum = 0.0f;
      for (int i = 0; i < WIN_SIZE; i++) {
        if (win_buf[i] < mn) mn = win_buf[i];
        if (win_buf[i] > mx) mx = win_buf[i];
        wsum += win_buf[i];
      }
      float win_mean = wsum / (float)WIN_SIZE;
      long  spread   = (long)(mx - mn);
      long  drift    = first_window ? 0L : (long)fabsf(win_mean - prev_win_mean);
      bool  pass     = (spread < WIN_SPREAD_MAX) && (first_window || drift < WIN_DRIFT_MAX);

      if (pass) confirm_count++;
      else      confirm_count = 0;

      prev_win_mean = win_mean;
      first_window  = false;

      if (confirm_count >= WIN_CONFIRM) {
        float stable_delta = win_mean;
        float est_grams    = stable_delta / EST_CAL_FACTOR;
        float cal_factor   = stable_delta / KNOWN_WEIGHT_G;

        snprintf(buf, sizeof(buf), ">>> STABLE DELTA: %+ld", (long)stable_delta);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> EST GRAMS (div 26): %ldg", (long)est_grams);
        Serial.println(buf);
        snprintf(buf, sizeof(buf), ">>> cal_factor = %ld / 597.0 = %.2f raw/g",
                 (long)stable_delta, cal_factor);
        Serial.println(buf);
        Serial.println(">>> Remove weight now.");

        watching_removal = true;
      }
      break;
    }
  }
}
