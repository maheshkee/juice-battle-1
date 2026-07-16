// HW_VERIFY.ino
// Hardware verification sketch for ESP32-C3 + HX711 + load cell.
// Flash this anytime you want to confirm the wiring is correct.
//
// What it checks:
//   1. HX711 is responding (DOUT goes LOW within timeout)
//   2. Raw reads are non-corrupt
//   3. Load cell responds to weight (delta check)
//
// How to use:
//   1. Flash this sketch
//   2. Open Serial Monitor at 115200
//   3. Watch the output - it tells you exactly what is working and what is not
//   4. Place a weight on the load cell when prompted
//   5. LED blinks: two slow blinks = PASS, five rapid blinks = FAIL (onboard blue LED)
//
// Wiring it verifies:
//   ESP32-C3 3V3 -> HX711 VDD
//   ESP32-C3 GND -> HX711 GND
//   ESP32-C3 GPIO4 -> HX711 SDO (DOUT)
//   ESP32-C3 GPIO3 -> HX711 SCK
//   Load cell Red->E+, Black->E-, Green->A+, White->A-

#define DOUT_PIN   4
#define SCK_PIN    3
#define LED_PIN    8    // onboard blue LED
#define BLINK_PASS 2    // short double-blink = PASS
#define BLINK_FAIL 5    // rapid five-blink = FAIL

// --- HX711 read (same bit-bang as E000, all three corrupt filters) ---
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
  digitalWrite(SCK_PIN, HIGH); delayMicroseconds(1);
  digitalWrite(SCK_PIN, LOW);  delayMicroseconds(1);
  interrupts();
  if (value & 0x800000) value |= 0xFF000000;
  return (long)value;
}

bool is_corrupt(long v) {
  return v == LONG_MIN || v == -1 || v == 0x7FFFFF;
}

// --- LED blink patterns ---
void blink_pass() {
  // Two slow blinks = PASS
  for (int i = 0; i < BLINK_PASS; i++) {
    digitalWrite(LED_PIN, LOW);  delay(300);
    digitalWrite(LED_PIN, HIGH); delay(300);
  }
}

void blink_fail() {
  // Five rapid blinks = FAIL
  for (int i = 0; i < BLINK_FAIL; i++) {
    digitalWrite(LED_PIN, LOW);  delay(100);
    digitalWrite(LED_PIN, HIGH); delay(100);
  }
}

// --- Take N averaged reads, return mean. Returns LONG_MIN if majority corrupt ---
long average_reads(int n) {
  long sum = 0;
  int good = 0;
  for (int i = 0; i < n; i++) {
    long v = hx711_read();
    if (!is_corrupt(v)) { sum += v; good++; }
    delay(110); // 10Hz = 100ms per sample, 110ms gives margin
  }
  if (good < n / 2) return LONG_MIN; // majority corrupt = fail
  return sum / good;
}

void setup() {
  pinMode(DOUT_PIN, INPUT_PULLUP);
  pinMode(SCK_PIN, OUTPUT);
  digitalWrite(SCK_PIN, LOW);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH); // LED off (active LOW on SuperMini)

  Serial.begin(115200);
  while (!Serial) { delay(10); }
  delay(1000);

  Serial.println("========================================");
  Serial.println("HW_VERIFY - hardware verification sketch");
  Serial.println("========================================");
  Serial.println("");

  // --- CHECK 1: HX711 responding ---
  Serial.println("CHECK 1: HX711 responding...");
  long first = hx711_read();
  if (first == LONG_MIN) {
    Serial.println("FAIL: DOUT never went LOW. HX711 not responding.");
    Serial.println("      Check: VDD wired? GND wired? DOUT=GPIO4? SCK=GPIO3?");
    blink_fail();
    return;
  }
  if (is_corrupt(first)) {
    Serial.print("FAIL: first read is corrupt value: ");
    Serial.println(first);
    Serial.println("      Check: load cell A+/A-/E+/E- connections.");
    blink_fail();
    return;
  }
  Serial.print("PASS: HX711 responding. First raw = ");
  Serial.println(first);
  blink_pass();
  delay(5000);

  // --- CHECK 2: stable reads (10 samples, count corrupt) ---
  Serial.println("");
  Serial.println("CHECK 2: stability - taking 10 samples...");
  int corrupt_count = 0;
  long minVal = 0, maxVal = 0;
  bool first_sample = true;
  for (int i = 0; i < 10; i++) {
    long v = hx711_read();
    if (is_corrupt(v)) {
      corrupt_count++;
      Serial.print("  sample "); Serial.print(i+1); Serial.println(": CORRUPT");
    } else {
      Serial.print("  sample "); Serial.print(i+1); Serial.print(": "); Serial.println(v);
      if (first_sample) { minVal = maxVal = v; first_sample = false; }
      else { if (v < minVal) minVal = v; if (v > maxVal) maxVal = v; }
    }
    delay(110);
  }
  Serial.print("Corrupt: "); Serial.print(corrupt_count); Serial.println("/10");
  Serial.print("Spread: "); Serial.println(maxVal - minVal);

  if (corrupt_count > 2) {
    Serial.println("FAIL: too many corrupt reads. Check wiring.");
    blink_fail();
    return;
  }
  Serial.println("PASS: stable reads.");
  blink_pass();
  delay(500);

  // --- CHECK 3: load cell responds to weight ---
  Serial.println("");
  Serial.println("CHECK 3: load cell weight response.");
  Serial.println("  Taking baseline (unloaded)...");
  long baseline = average_reads(10);
  if (baseline == LONG_MIN) {
    Serial.println("FAIL: could not get clean baseline.");
    blink_fail();
    return;
  }
  Serial.print("  Baseline (unloaded): "); Serial.println(baseline);
  Serial.println("  >>> PLACE A WEIGHT ON THE LOAD CELL NOW <<<");
  Serial.println("  Press ENTER in Serial Monitor when weight is placed...");
  while (!Serial.available()) { delay(100); }
  while (Serial.available()) Serial.read();

  Serial.println("  Taking loaded reading...");
  long loaded = average_reads(10);
  if (loaded == LONG_MIN) {
    Serial.println("FAIL: could not get clean loaded reading.");
    blink_fail();
    return;
  }
  Serial.print("  Loaded: "); Serial.println(loaded);
  long delta = loaded - baseline;
  Serial.print("  Delta: "); Serial.println(delta);

  // Delta should be positive (weight makes raw less negative = higher value)
  // Accept anything > 500 raw as a real response (even a finger press)
  if (delta < 500) {
    Serial.println("FAIL: load cell not responding to weight.");
    Serial.println("      Check: E+/E-/A+/A- load cell connections.");
    Serial.println("      Check: weight was actually on the cell when ENTER was pressed.");
    blink_fail();
    return;
  }

  Serial.println("");
  Serial.println("========================================");
  Serial.println("ALL CHECKS PASSED. Hardware wiring OK.");
  Serial.println("========================================");
  Serial.print("Baseline: "); Serial.println(baseline);
  Serial.print("Loaded:   "); Serial.println(loaded);
  Serial.print("Delta:    "); Serial.println(delta);
  long rough_cal = delta / 30; // assumes 30g weight - adjust comment if different
  Serial.print("Rough cal_factor (~30g weight assumed): "); Serial.print(rough_cal); Serial.println(" raw/g");
  Serial.println("");
  Serial.println("Entering continuous raw read mode. Place/remove weights to observe.");
  blink_pass();
  blink_pass();
}

void loop() {
  // After all checks pass: continuous raw read so you can observe weight changes live
  long v = hx711_read();
  if (is_corrupt(v)) {
    Serial.print("CORRUPT: "); Serial.println(v);
  } else {
    Serial.print("RAW: "); Serial.println(v);
  }
}
