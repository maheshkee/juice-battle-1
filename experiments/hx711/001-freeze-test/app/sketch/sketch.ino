#include "Arduino_RouterBridge.h"

#define DT  7
#define SCK 6

#define LOG(msg) Bridge.notify("log", String(msg))

static long hx711_read_raw() {
    long value = 0;
    noInterrupts();
    for (int i = 0; i < 24; i++) {
        digitalWrite(SCK, HIGH);
        delayMicroseconds(1);
        value = (value << 1) | digitalRead(DT);
        digitalWrite(SCK, LOW);
        delayMicroseconds(1);
    }
    digitalWrite(SCK, HIGH);
    delayMicroseconds(1);
    digitalWrite(SCK, LOW);
    delayMicroseconds(1);
    interrupts();
    if (value & 0x800000) value |= 0xFF000000;
    return value;
}

void setup() {
    pinMode(SCK, OUTPUT);
    digitalWrite(SCK, LOW);
    pinMode(DT, INPUT_PULLUP);

    Bridge.begin();
    delay(8000);

    for (;;) {
    LOG("=== HX711 freeze vs refresh test ===");
    LOG("DT=D7  SCK=D6");

    // Wait for HX711 ready (DOUT LOW)
    while (digitalRead(DT) == HIGH) { delay(1); }
    LOG("HX711 ready.");

    // --- S1 ---
    long s1 = hx711_read_raw();
    {
        String msg = "S1 = ";
        msg += String(s1);
        msg += "  at t = ";
        msg += String(millis());
        msg += " ms";
        LOG(msg);
    }

    // --- Pause preamble ---
    {
        String msg = ">>> PAUSE START at t=";
        msg += String(millis());
        msg += "ms";
        LOG(msg);
    }
    LOG(">>> ACTION WINDOW: seconds 0-10 — place new weight on scale NOW");
    LOG(">>> SETTLE WINDOW: seconds 10-30 — hands off, do not touch");
    LOG(">>> S2 will be read at t=30s");

    // --- 30-second pause loop — read-only DOUT, no SCK ---
    uint32_t pause_start = millis();
    for (int sec = 0; sec < 30; sec++) {
        while ((millis() - pause_start) < (uint32_t)(sec + 1) * 1000) { delay(1); }
        int dout = digitalRead(DT);
        String msg = "t=";
        msg += String(sec);
        msg += "s  DOUT=";
        msg += (dout == LOW) ? "LOW" : "HIGH";
        LOG(msg);
        if (sec == 10) {
            LOG(">>> ACTION WINDOW CLOSED — hands should be off scale now");
        }
    }

    // --- S2 — read immediately, no extra delay ---
    LOG(">>> PAUSE END — reading S2 now (no delay, no SCK pulses until now)");
    // Protocol requires DOUT LOW before clocking — poll without deliberate delay
    while (digitalRead(DT) == HIGH) {}
    long s2 = hx711_read_raw();
    {
        String msg = "S2 = ";
        msg += String(s2);
        msg += "  at t = ";
        msg += String(millis());
        msg += " ms";
        LOG(msg);
    }

    // --- Track DOUT HIGH then LOW for S3 ---
    LOG(">>> Now waiting for next conversion (DOUT goes HIGH then LOW again)...");
    uint32_t s2_end = millis();

    while (digitalRead(DT) == LOW) {}   // wait for DOUT to go HIGH
    uint32_t high_at = millis() - s2_end;

    while (digitalRead(DT) == HIGH) {}  // wait for DOUT to go LOW (conversion done)
    uint32_t low_at = millis() - s2_end;

    {
        String msg = "DOUT went HIGH at +";
        msg += String(high_at);
        msg += " ms, LOW again at +";
        msg += String(low_at);
        msg += " ms (total wait ";
        msg += String(low_at);
        msg += " ms)";
        LOG(msg);
    }

    // --- S3 ---
    long s3 = hx711_read_raw();
    {
        String msg = "S3 = ";
        msg += String(s3);
        msg += "  at t = ";
        msg += String(millis());
        msg += " ms";
        LOG(msg);
    }

    LOG("=== TEST COMPLETE ===");
    LOG("Interpretation:");
    LOG("  If S2 approx S1 and S3 differs (jumps to new weight) -> H1 (freeze) confirmed");
    LOG("  If S2 already reflects new weight -> H2 (refresh) confirmed");

    delay(120000);
    } // end for(;;)
}

void loop() {}
