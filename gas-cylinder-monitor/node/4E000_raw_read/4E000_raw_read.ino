// 4E000_raw_read.ino
// Experiment 4E-000 v2: 4-cell parallel bring-up, stability-gated tare.
// Purpose: thermally-stable tare before any delta measurements.
// Hardware: 4x YZC-161A in parallel, one HX711, ESP32-C3 3V3.

#include <climits>

#define HX711_DT       4
#define HX711_SCK      3
#define PACE_MS        110
#define WIN_SIZE       20
#define WIN_SPREAD_MAX 300   // raw counts — tune if needed
#define WIN_DRIFT_MAX  200   // raw counts between consecutive windows
#define WIN_CONFIRM    3     // consecutive passing windows needed
#define AVG_SAMPLES    20

enum State { WARMUP, STABILISING, RUNNING };

static State         state         = WARMUP;
static int           warmup_count  = 0;
static long          win_buf[WIN_SIZE];
static int           win_fill      = 0;
static float         prev_win_mean = 0.0f;
static int           confirm_count = 0;
static long          tare_raw      = 0;
static unsigned long start_ms      = 0;
static unsigned long last_ms       = 0;
static float         acc_sum       = 0.0f;
static int           acc_count     = 0;

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

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("4E-000 v2 | 4-cell parallel | stability-gated tare | GPIO4=DT GPIO3=SCK");
  pinMode(HX711_DT,  INPUT_PULLUP);
  pinMode(HX711_SCK, OUTPUT);
  start_ms = millis();
}

void loop() {
  // millis() pacing guard — RUNNING state only
  if (state == RUNNING) {
    unsigned long now = millis();
    if (now - last_ms < (unsigned long)PACE_MS) return;
    last_ms = now;
  }

  long raw = hx711_read_raw();

  // Corrupt filters — discard silently
  if (raw == LONG_MIN || raw == -1L || raw == 0x7FFFFFL) return;

  char buf[80];

  switch (state) {

    case WARMUP:
      if (warmup_count == 0) {
        Serial.println("4E-000 v2: waiting for thermal stability...");
      }
      warmup_count++;
      if (warmup_count >= 10) {
        state = STABILISING;
      }
      break;

    case STABILISING:
      win_buf[win_fill++] = raw;
      if (win_fill == WIN_SIZE) {
        win_fill = 0;

        long mn = win_buf[0], mx = win_buf[0];
        float wsum = 0.0f;
        for (int i = 0; i < WIN_SIZE; i++) {
          if (win_buf[i] < mn) mn = win_buf[i];
          if (win_buf[i] > mx) mx = win_buf[i];
          wsum += (float)win_buf[i];
        }
        long  spread   = mx - mn;
        float win_mean = wsum / (float)WIN_SIZE;
        long  drift    = (long)fabsf(win_mean - prev_win_mean);

        if (spread < WIN_SPREAD_MAX && drift < WIN_DRIFT_MAX) {
          confirm_count++;
        } else {
          confirm_count = 0;
        }
        prev_win_mean = win_mean;

        snprintf(buf, sizeof(buf), "WIN spread=%ld drift=%ld confirms=%d/%d",
                 spread, drift, confirm_count, WIN_CONFIRM);
        Serial.println(buf);

        if (confirm_count >= WIN_CONFIRM) {
          tare_raw = (long)win_mean;
          unsigned long elapsed = (millis() - start_ms) / 1000UL;
          snprintf(buf, sizeof(buf), "STABLE. TARE: %ld (after %lus)", tare_raw, elapsed);
          Serial.println(buf);
          Serial.println("--- Begin cell-by-cell test. Place mobile on each plate one at a time ---");
          state = RUNNING;
        }
      }
      break;

    case RUNNING:
      {
        long delta = raw - tare_raw;
        snprintf(buf, sizeof(buf), "RAW: %ld  DELTA: %+ld", raw, delta);
        Serial.println(buf);

        acc_sum += (float)raw;
        acc_count++;

        if (acc_count == AVG_SAMPLES) {
          long avg_val   = (long)(acc_sum / (float)AVG_SAMPLES);
          long avg_delta = avg_val - tare_raw;
          snprintf(buf, sizeof(buf), "AVG(20): %ld  DELTA: %+ld", avg_val, avg_delta);
          Serial.println(buf);
          Serial.println("----");
          acc_sum   = 0.0f;
          acc_count = 0;
        }
      }
      break;
  }
}
