// E001_tare_cal_grams.ino
// Experiment E-001: tare derivation, cal_factor derivation, grams output.
// Three phases: TARE → CAL → RUN
// Wiring: DOUT=GPIO4, SCK=GPIO3, HX711 VDD=3V3, GND=GND
// Load cell: Red=E+, Black=E-, Green=A+, White=A-

#define DOUT_PIN  4
#define SCK_PIN   3
#define N_SAMPLES 50

// Declared at file scope — not inside loop() — to avoid stack allocation on every
// loop() call. double arrays on stack inside loop() caused stack corruption on STM32U585.
static long  raw_buf[N_SAMPLES];
static float tare          = 0.0f;
static float cal_factor    = 0.0f;
static char  buf[64];             // scratch buffer for all snprintf output lines

// millis() timestamp for RUN phase pacing
static unsigned long last_print_ms = 0;

// --- Bit-bang read (ported from E000) ---
long hx711_read() {
  // 500ms timeout: if DOUT stays HIGH, HX711 is not ready or not connected.
  // LONG_MIN is the sentinel — caller must apply is_corrupt() to every return value.
  uint32_t deadline = millis() + 500;
  while (digitalRead(DOUT_PIN) == HIGH) {
    if (millis() >= deadline) return LONG_MIN;
  }

  int32_t value = 0;
  // Disable interrupts for the entire 25-pulse sequence.
  // An ISR firing mid-sequence adds an unintended clock pulse, which shifts the
  // gain setting for the NEXT conversion (25 pulses → Gain128; 26 → Gain32).
  noInterrupts();
  for (int i = 0; i < 24; i++) {
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    value = (value << 1) | digitalRead(DOUT_PIN);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);
  }
  // 25th pulse locks Channel A, Gain 128 for the next conversion.
  // Without it, the gain state is undefined after the 24-bit read.
  digitalWrite(SCK_PIN, HIGH); delayMicroseconds(1);
  digitalWrite(SCK_PIN, LOW);  delayMicroseconds(1);
  interrupts();

  // Sign-extend bit 23: HX711 outputs 24-bit two's complement.
  // Without this, any negative reading (bit 23 = 1) appears as a large positive number.
  if (value & 0x800000) value |= 0xFF000000;
  return (long)value;
}

// --- Corrupt filter — all three cases must be checked on every read ---
bool is_corrupt(long v) {
  return v == LONG_MIN   // timeout sentinel from hx711_read()
      || v == -1         // all 24 bits HIGH: HX711 not ready when we clocked
      || v == 0x7FFFFF;  // positive saturation: wiring or VCC fault on analog path
}

// --- Collect exactly n valid samples into raw_buf ---
// Re-reads on every corrupt value until n valid samples are stored.
// Blocking is acceptable here — this only runs during setup, not in loop().
void collect_samples(int n) {
  int count = 0;
  while (count < n) {
    long v = hx711_read();
    // Discard corrupt reads and retry — do not advance count.
    if (is_corrupt(v)) continue;
    raw_buf[count++] = v;
    // 110ms between samples: HX711 at 10Hz outputs one conversion per 100ms.
    // 10ms margin prevents clocking before the next conversion is ready.
    delay(110);
  }
}

// --- Compute float mean of raw_buf[0..n-1] ---
float mean_of(int n) {
  // float accumulator — not double. double silently produced sum=0 on STM32U585.
  // float re-verified as correct on ESP32-C3 before using here.
  float sum = 0.0f;
  for (int i = 0; i < n; i++) {
    sum += (float)raw_buf[i];
  }
  return sum / (float)n;
}

void setup() {
  // INPUT_PULLUP is mandatory: DOUT is open-drain. Without pullup, DOUT floats
  // and reads random noise → false "ready" signals → garbage bits every read.
  pinMode(DOUT_PIN, INPUT_PULLUP);
  pinMode(SCK_PIN, OUTPUT);
  // SCK LOW is the idle state for HX711 — must be set before first read.
  digitalWrite(SCK_PIN, LOW);

  Serial.begin(115200);
  // Wait for USB CDC enumeration. ESP32-C3 SuperMini has no CH340/CP2102 —
  // Serial is not ready at power-on. Output before this wait is silently dropped.
  while (!Serial) { delay(10); }
  // Additional settle time for Serial Monitor to reconnect after enumeration.
  delay(1000);

  Serial.println("E001 tare+cal+grams");
  Serial.println("====================");

  // --- TARE PHASE ---
  Serial.println("TARE: collecting 50 samples...");
  collect_samples(N_SAMPLES);
  tare = mean_of(N_SAMPLES);
  snprintf(buf, sizeof(buf), "Tare: %.2f raw", tare);
  Serial.println(buf);

  // --- CAL PHASE ---
  Serial.println("");
  Serial.println("Enter known weight in grams, then press Enter:");
  // Extend timeout so slow typists do not trigger a premature empty read.
  // Default Serial.setTimeout() is 1000ms — far too short for manual entry.
  Serial.setTimeout(30000);
  String line = Serial.readStringUntil('\n');
  float known_weight_g = line.toFloat();
  snprintf(buf, sizeof(buf), "Known weight: %.2f g", known_weight_g);
  Serial.println(buf);

  Serial.println("Place weight on load cell. Press any key when ready.");
  while (!Serial.available()) { delay(10); }
  // Flush the keypress — do not leave it in the buffer for any later Serial.read().
  while (Serial.available()) Serial.read();

  Serial.println("CAL: collecting 50 loaded samples...");
  collect_samples(N_SAMPLES);
  float loaded_mean = mean_of(N_SAMPLES);
  snprintf(buf, sizeof(buf), "Loaded mean: %.2f raw", loaded_mean);
  Serial.println(buf);

  // cal_factor = raw counts per gram on this specific hardware combination.
  // Absorbs: load cell sensitivity, HX711 gain, actual VCC, mechanical mounting.
  // This value is VOID if any hardware or physical setup changes — re-derive then.
  cal_factor = (loaded_mean - tare) / known_weight_g;
  snprintf(buf, sizeof(buf), "Cal factor: %.4f raw/g", cal_factor);
  Serial.println(buf);

  Serial.println("Calibration complete. Starting measurement loop.");
  Serial.println("");
}

void loop() {
  // millis() pacing at the TOP of loop() — not a blocking delay().
  // A blocking delay inside loop() would prevent any other work during the wait.
  unsigned long now = millis();
  if (now - last_print_ms < 500) return;
  last_print_ms = now;

  long raw = hx711_read();
  if (is_corrupt(raw)) {
    Serial.println("corrupt read, skipping");
    return;
  }

  // grams = (raw - tare) / cal_factor — the fundamental measurement equation.
  float grams = ((float)raw - tare) / cal_factor;
  snprintf(buf, sizeof(buf), "Raw: %ld  Grams: %.2f", raw, grams);
  Serial.println(buf);
}
