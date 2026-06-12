// 4E001_cal_factor_v2.ino
// Experiment 4E-001 v2: cal_factor derivation on 4-cell platform.
// Reference weight: 597.0g (water bottle).
// Modelled on E001_tare_cal_grams.ino and E002_noise_floor.ino.
// Hardware: 4x YZC-161A in parallel, one HX711, ESP32-C3 3V3.
// Wiring: DOUT=GPIO4, SCK=GPIO3, HX711 VDD=3V3, GND=GND

#include <Arduino.h>
#include <climits>

#define DOUT_PIN        4
#define SCK_PIN         3
#define STAB_WINDOW     20
#define STAB_SPREAD_RAW 300
#define STAB_DRIFT_RAW  200
#define STAB_CONFIRM    3
#define SETTLE_MS       10000
#define CAL_SAMPLES     50
#define KNOWN_WEIGHT_G  597.0f

// File-scope — not inside any function — to avoid stack allocation issues.
// Pattern from E001: double/float arrays on stack inside loop() caused corruption on STM32U585.
static float win_buf[STAB_WINDOW];
static char  buf[128];

// --- Bit-bang read (ported from E001_tare_cal_grams.ino) ---
long hx711_read() {
  // 500ms timeout: DOUT staying HIGH means HX711 not ready or not connected.
  // LONG_MIN is the sentinel — every caller must pass the return through is_corrupt().
  uint32_t deadline = millis() + 500;
  while (digitalRead(DOUT_PIN) == HIGH) {
    if (millis() >= deadline) return LONG_MIN;
  }

  int32_t value = 0;
  // Disable interrupts for the entire 25-pulse sequence.
  // An ISR firing mid-sequence adds an unintended clock pulse, shifting the
  // gain for the next conversion (25 pulses = Gain128; 26 pulses = Gain32).
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
  // Without this, negative readings (bit 23 = 1) appear as large positive numbers.
  if (value & 0x800000) value |= 0xFF000000;
  return (long)value;
}

// --- Corrupt filter — all three cases, every read (ported from E001) ---
bool is_corrupt(long v) {
  return v == LONG_MIN   // timeout sentinel from hx711_read()
      || v == -1         // all 24 bits HIGH: HX711 not ready when clocked
      || v == 0x7FFFFF;  // positive saturation: wiring or VCC fault on analog path
}

// --- Stability-gated tare (modelled on E002_noise_floor.ino stability loop) ---
// Uses raw counts, not grams — no cal_factor required at this stage.
// Fills a window of STAB_WINDOW raw samples, evaluates spread and drift,
// requires STAB_CONFIRM consecutive passing windows before accepting tare.
long derive_stable_tare() {
  int   win_idx       = 0;
  int   stable_count  = 0;
  float prev_mean     = 0.0f;
  float last_win_mean = 0.0f;
  bool  first_win     = true;

  while (stable_count < STAB_CONFIRM) {
    long r = hx711_read();
    if (is_corrupt(r)) continue;

    win_buf[win_idx++] = (float)r;
    // Evaluating a partially filled buffer gives falsely tight spread — wait for full window.
    if (win_idx < STAB_WINDOW) continue;
    win_idx = 0;  // reset for next window

    float mn = win_buf[0], mx = win_buf[0], wsum = 0.0f;
    for (int i = 0; i < STAB_WINDOW; i++) {
      if (win_buf[i] < mn) mn = win_buf[i];
      if (win_buf[i] > mx) mx = win_buf[i];
      wsum += win_buf[i];
    }
    float win_mean = wsum / (float)STAB_WINDOW;
    long  spread   = (long)(mx - mn);
    // First window has no prev to compare — skip drift check (condition passes automatically).
    long  drift    = first_win ? 0L : (long)fabsf(win_mean - prev_mean);
    bool  pass     = (spread < STAB_SPREAD_RAW) && (first_win || drift < STAB_DRIFT_RAW);

    if (pass) {
      stable_count++;
      snprintf(buf, sizeof(buf), "[STABILISING] spread=%ld drift=%ld WIN %d/%d",
               spread, drift, stable_count, STAB_CONFIRM);
    } else {
      stable_count = 0;  // must be consecutive — any failure resets the run
      snprintf(buf, sizeof(buf), "[STABILISING] spread=%ld drift=%ld (reset)",
               spread, drift);
    }
    Serial.println(buf);

    // Update prev even on failure so the next window sees the current mean.
    last_win_mean = win_mean;
    prev_mean     = win_mean;
    first_win     = false;
  }

  long tare_raw = (long)last_win_mean;
  snprintf(buf, sizeof(buf), "[TARE] tare_raw=%ld", tare_raw);
  Serial.println(buf);
  return tare_raw;
}

// --- Collect exactly CAL_SAMPLES valid raw reads, return float mean ---
// Caller subtracts tare and divides by known weight — this function returns raw mean only.
// Blocking is acceptable: called only from setup(), never from loop().
float collect_and_mean(long tare_raw) {
  (void)tare_raw;  // unused here; caller computes stable_delta = mean - tare_raw
  float sum   = 0.0f;
  int   count = 0;
  while (count < CAL_SAMPLES) {
    long v = hx711_read();
    // Discard corrupt reads and retry — do not advance count.
    if (is_corrupt(v)) continue;
    sum += (float)v;
    count++;
    // 110ms between samples: HX711 at 10Hz = 100ms per conversion, 10ms margin.
    delay(110);
  }
  return sum / (float)CAL_SAMPLES;
}

void setup() {
  // INPUT_PULLUP mandatory: DOUT is open-drain. Without pullup it floats,
  // producing random noise → false ready signals → garbage bits.
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

  Serial.println("4E001 cal_factor derivation v2 | 4-cell platform | ref=597g");

  // Step 2: boot tare — platform must be empty and settled before proceeding.
  long tare_raw = derive_stable_tare();

  // Step 3: outer loop — each iteration is one complete measurement run.
  while (true) {

    // 3a: flush stale bytes then prompt.
    // Bytes accumulate during tare or the previous iteration; without flush,
    // readStringUntil returns immediately with stale data.
    while (Serial.available()) Serial.read();
    snprintf(buf, sizeof(buf),
             "[EMPTY] tare=%ld  Place 597g water bottle. Press Enter when ready.", tare_raw);
    Serial.println(buf);
    Serial.readStringUntil('\n');

    // 3b: settle countdown — millis() based, not delay().
    // Load cell mechanical creep: metal deforms slowly under load and takes ~10s
    // to reach its final resting value. Sampling before settling yields creep error.
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

    // 3c: collect 50 samples and compute cal_factor.
    float loaded_mean_raw = collect_and_mean(tare_raw);
    float stable_delta    = loaded_mean_raw - (float)tare_raw;
    float cal_factor      = stable_delta / KNOWN_WEIGHT_G;

    snprintf(buf, sizeof(buf), ">>> LOADED MEAN RAW: %ld",  (long)loaded_mean_raw);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), ">>> STABLE DELTA:    %+ld", (long)stable_delta);
    Serial.println(buf);
    snprintf(buf, sizeof(buf), ">>> cal_factor = %ld / 597.0 = %.2f raw/g",
             (long)stable_delta, cal_factor);
    Serial.println(buf);
    Serial.println("--------------------");

    // 3d: prompt for weight removal.
    while (Serial.available()) Serial.read();
    Serial.println("Remove weight. Press Enter when platform is empty.");
    Serial.readStringUntil('\n');

    // 3e: re-tare after removal using the full stability gate.
    // This absorbs any thermal drift since the last tare.
    tare_raw = derive_stable_tare();
  }
}

void loop() {
  // All work is done in setup(). setup() loops forever inside while(true).
  // loop() is never reached.
}
