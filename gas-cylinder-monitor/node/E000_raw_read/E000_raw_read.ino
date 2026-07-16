// E000_raw_read.ino
// Experiment E-000: ESP32-C3 + HX711 — first raw read
// Goal: confirm stable non-corrupt 24-bit counts before any calibration.
// No cal_factor, no grams, no library — raw counts only.

// Pin assignments chosen at E-000 bring-up.
// These are ESP32-C3 GPIO numbers, not Arduino UNO pin labels.
// On ESP32-C3 there are no timer conflicts on these pins — the old STM32
// "use D7/D6 only" rule does not apply here.
#define DOUT_PIN 4
#define SCK_PIN  3

// Reads one 24-bit sample from the HX711.
// Returns LONG_MIN if HX711 does not signal ready within 200 ms (timeout sentinel).
// Returns the sign-extended 32-bit value on success.
long hx711_read() {
    // Poll DOUT until LOW. HX711 pulls DOUT LOW to signal a completed conversion.
    // We poll without sleeping so we track the 10 SPS rate without missing samples.
    // 200 ms timeout: fast enough to fail promptly if something is wrong (open wire,
    // wrong VCC, wrong pin) without stalling loop() for a visible duration.
    uint32_t deadline = millis() + 200;
    while (digitalRead(DOUT_PIN) == HIGH) {
        if (millis() >= deadline) return LONG_MIN;
    }

    int32_t value = 0;

    // Disable interrupts for the entire 25-pulse sequence.
    // An ISR firing between SCK pulses stretches the SCK cycle; the HX711 counts
    // SCK pulses to determine the next gain mode. An extra pulse mid-sequence would
    // corrupt the gain selection for the following conversion.
    noInterrupts();

    for (int i = 0; i < 24; i++) {
        // Rising edge: HX711 shifts the next output bit onto DOUT.
        digitalWrite(SCK_PIN, HIGH);
        // 1 µs hold after each edge. HX711 tDH (data hold time) is 0.1 µs minimum,
        // but ESP32-C3 GPIO toggles can outpace this on some silicon revisions.
        // 1 µs is a safe margin with negligible overhead at 10 SPS.
        delayMicroseconds(1);

        // Capture the bit and build the result MSB-first.
        value = (value << 1) | digitalRead(DOUT_PIN);

        // Falling edge: completes this clock pulse.
        digitalWrite(SCK_PIN, LOW);
        delayMicroseconds(1);
    }

    // 25th SCK pulse — required, not optional.
    // HX711 uses pulse count to select channel and gain for the NEXT conversion:
    //   25 pulses → Channel A, Gain 128  (what we want for a 20 kg load cell)
    //   26 pulses → Channel B, Gain 32
    //   27 pulses → Channel A, Gain 64
    // Sending exactly 25 locks us into Channel A / Gain 128 permanently.
    digitalWrite(SCK_PIN, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK_PIN, LOW);
    delayMicroseconds(1);

    interrupts();

    // Sign-extend from 24-bit two's complement to 32-bit.
    // Bit 23 is the sign bit in the HX711 output. Without this step, a negative
    // reading (e.g. unloaded scale reading below tare) would appear as a large
    // positive number (> 8 million) instead of the correct negative value.
    if (value & 0x800000) value |= 0xFF000000;

    return (long)value;
}

// Returns true if v is a known corruption pattern that must be discarded.
//   LONG_MIN  — our own timeout sentinel from hx711_read(); not a sensor value
//   -1        — all 24 bits HIGH (0xFFFFFF); HX711 was not ready when we read
//   0x7FFFFF  — positive ADC saturation; on STM32 this meant a timer conflict;
//               on ESP32-C3 it indicates a wiring or VCC problem on the analog path
bool is_corrupt(long v) {
    return v == LONG_MIN || v == -1 || v == 0x7FFFFF;
}

void setup() {
    // INPUT_PULLUP because HX711 DOUT is open-drain: the IC pulls low to signal
    // ready, and floats otherwise. Without a pull-up, a floating DOUT reads as
    // random noise — we would see false "ready" signals and garbage bits.
    pinMode(DOUT_PIN, INPUT_PULLUP);
    pinMode(SCK_PIN, OUTPUT);

    // SCK must start LOW. If SCK is HIGH on power-up the HX711 may count it as
    // the first pulse of a gain-select sequence, corrupting the channel/gain state
    // before we have sent a single intentional pulse.
    digitalWrite(SCK_PIN, LOW);

    Serial.begin(115200);
    Serial.println("E000 raw read starting");
}

void loop() {
    long raw = hx711_read();

    if (is_corrupt(raw)) {
        // Print corrupt values so we can diagnose the failure mode:
        //   LONG_MIN   → repeated timeout: check DOUT wiring, check HX711 VCC (needs 5 V)
        //   -1         → HX711 not ready: check VCC, check RATE pin (should be LOW for 10 SPS)
        //   0x7FFFFF   → saturation: check load cell analog connections (A+/A-/E+/E-)
        Serial.print("CORRUPT ");
        Serial.println(raw);
    } else {
        Serial.print("RAW: ");
        Serial.println(raw);
    }

    // No delay. HX711 at RATE pin LOW runs at 10 SPS. The wait inside hx711_read()
    // for DOUT to go LOW is what paces this loop — we are not burning a sleep, we are
    // waiting for the hardware to be genuinely ready.
}
