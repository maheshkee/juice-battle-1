// STOP.ino
// Flash this to halt the ESP32-C3 when you need to stop whatever sketch is running.
// Does nothing. Prints one message then sits silently forever.
// No GPIO activity, no Serial spam, no HX711 clocking.
// Use this before rewiring or when you want the board idle.

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("STOP sketch running. Board is idle. Safe to rewire.");
}

void loop() {
  // Intentionally empty. Board sleeps here forever.
  delay(60000);
}
