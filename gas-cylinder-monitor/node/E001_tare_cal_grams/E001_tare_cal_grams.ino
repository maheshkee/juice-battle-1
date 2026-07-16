// E001_tare_cal_grams.ino
// Experiment E-001: tare derivation, cal_factor derivation, grams output.
// Flow: TARE once at boot → CALIBRATION+OBSERVATION loop until user enters 0.
// Wiring: DOUT=GPIO4, SCK=GPIO3, HX711 VDD=3V3, GND=GND
// Load cell: Red=E+, Black=E-, Green=A+, White=A-

#define DOUT_PIN  4
#define SCK_PIN   3
#define N_SAMPLES 50

// File-scope — not inside loop() — to avoid stack allocation on every call.
// double arrays on stack inside loop() caused stack corruption on STM32U585.
static long  raw_buf[N_SAMPLES];
static float tare       = 0.0f;
static float cal_factor = 0.0f;
static char  buf[64];   // snprintf scratch buffer — reused for all output lines

// --- Bit-bang read (ported from E000) ---
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
  // Without it, gain state is undefined after the 24-bit read.
  digitalWrite(SCK_PIN, HIGH); delayMicroseconds(1);
  digitalWrite(SCK_PIN, LOW);  delayMicroseconds(1);
  interrupts();

  // Sign-extend bit 23: HX711 outputs 24-bit two's complement.
  // Without this, negative readings (bit 23 = 1) appear as large positive numbers.
  if (value & 0x800000) value |= 0xFF000000;
  return (long)value;
}

// --- Corrupt filter — all three cases, every read ---
bool is_corrupt(long v) {
  return v == LONG_MIN   // timeout sentinel from hx711_read()
      || v == -1         // all 24 bits HIGH: HX711 not ready when clocked
      || v == 0x7FFFFF;  // positive saturation: wiring or VCC fault on analog path
}

// --- Collect exactly n valid samples into raw_buf ---
// Re-reads on corrupt values until n valid samples are stored.
// Blocking is acceptable — called only during setup, never from loop().
void collect_samples(int n) {
  int count = 0;
  while (count < n) {
    long v = hx711_read();
    // Discard corrupt reads and retry — do not advance count.
    if (is_corrupt(v)) continue;
    raw_buf[count++] = v;
    // 110ms between samples: HX711 at 10Hz = 100ms per conversion, 10ms margin.
    delay(110);
  }
}

// --- Float mean of raw_buf[0..n-1] ---
float mean_of(int n) {
  // float accumulator — not double. double silently produced sum=0 on STM32U585.
  float sum = 0.0f;
  for (int i = 0; i < n; i++) {
    sum += (float)raw_buf[i];
  }
  return sum / (float)n;
}

void setup() {
  // INPUT_PULLUP mandatory: DOUT is open-drain. Without pullup it floats,
  // producing random noise → false ready signals → garbage bits.
  pinMode(DOUT_PIN, INPUT_PULLUP);
  pinMode(SCK_PIN, OUTPUT);
  // SCK LOW is the HX711 idle state — must be set before the first read.
  digitalWrite(SCK_PIN, LOW);

  Serial.begin(115200);
  // Wait for USB CDC enumeration. ESP32-C3 SuperMini has no CH340/CP2102 —
  // output before this wait is silently dropped.
  while (!Serial) { delay(10); }
  // Additional settle time for Serial Monitor to reconnect after enumeration.
  delay(1000);

  // Extend timeout to 30s so the user has time to type a weight value.
  // Default Serial.setTimeout() is 1000ms — too short for manual entry.
  Serial.setTimeout(30000);

  Serial.println("E001 tare+cal+grams");
  Serial.println("====================");

  // --- TARE PHASE ---
  Serial.println("TARE: collecting 50 samples...");
  collect_samples(N_SAMPLES);
  tare = mean_of(N_SAMPLES);
  snprintf(buf, sizeof(buf), "Tare: %.2f raw", tare);
  Serial.println(buf);
  Serial.println("");

  // --- CALIBRATION + OBSERVATION LOOP ---
  // Repeats for each weight the user wants to test. Enter 0 to finish.
  while (true) {
    // Flush stale bytes before reading input.
    // Bytes accumulate from keypresses during tare or the previous iteration.
    // Without this flush, readStringUntil returns immediately with stale data.
    while (Serial.available()) Serial.read();

    Serial.println("Enter known weight in grams (0 to finish):");
    String line = Serial.readStringUntil('\n');
    float known_weight_g = line.toFloat();

    if (known_weight_g <= 0.0f) {
      Serial.println("Done. Exiting.");
      // Halt — all useful work is complete. loop() will never be reached.
      while (true) {}
    }

    snprintf(buf, sizeof(buf), "Known weight: %.2f g", known_weight_g);
    Serial.println(buf);

    Serial.println("Place weight on load cell. Press any key when ready.");
    while (!Serial.available()) { delay(10); }
    Serial.read();  // consume the keypress byte

    // Load cell mechanical creep: metal deforms slowly under load and takes ~10 s
    // to reach its final resting value. Sampling before settling yields creep error.
    Serial.println("Settling... wait 10 seconds");
    unsigned long settle_start = millis();
    int next_print_sec = 2;
    while (millis() - settle_start < 10000UL) {
      if (millis() - settle_start >= (unsigned long)next_print_sec * 1000UL) {
        snprintf(buf, sizeof(buf), "%d seconds...", 10 - next_print_sec);
        Serial.println(buf);
        next_print_sec += 2;
      }
    }
    Serial.println("Sampling now.");

    Serial.println("CAL: collecting 50 loaded samples...");
    collect_samples(N_SAMPLES);
    float loaded_mean = mean_of(N_SAMPLES);

    // cal_factor = raw counts per gram on this specific hardware combination.
    // Absorbs: load cell sensitivity, HX711 gain, actual VCC, mechanical mounting.
    // VOID on any hardware or mounting change — re-derive then.
    cal_factor = (loaded_mean - tare) / known_weight_g;
    snprintf(buf, sizeof(buf), "Cal factor for %.0fg: %.4f raw/g", known_weight_g, cal_factor);
    Serial.println(buf);

    Serial.println("Observing 20 readings...");

    // 20 readings at 500ms intervals using millis(), not delay().
    // delay() here would block the CPU for the full interval with no way to break out.
    int obs_count = 0;
    unsigned long next_ms = millis();
    while (obs_count < 20) {
      unsigned long now = millis();
      if (now < next_ms) continue;
      next_ms = now + 500;

      long raw = hx711_read();
      if (is_corrupt(raw)) {
        Serial.println("corrupt read, skipping");
      } else {
        // grams = (raw - tare) / cal_factor — the fundamental measurement equation.
        float grams = ((float)raw - tare) / cal_factor;
        snprintf(buf, sizeof(buf), "Raw: %ld  Grams: %.2f", raw, grams);
        Serial.println(buf);
      }
      obs_count++;
    }

    Serial.println("--------------------");
    Serial.println("");
  }
}

void loop() {
  // All work is done in setup(). setup() either loops forever (cal+obs iterations)
  // or halts in while(true){} after the user enters 0. loop() is never reached.
}
