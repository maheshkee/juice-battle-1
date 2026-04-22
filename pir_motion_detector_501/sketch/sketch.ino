#include <Arduino_RouterBridge.h>

const int PIR_PIN = 2;
bool lastPirState = false;

void setLED(bool motion) {
  digitalWrite(LED3_R, motion ? LOW : HIGH);
  digitalWrite(LED3_G, motion ? HIGH : LOW);
}

void setup() {
  pinMode(PIR_PIN, INPUT);
  pinMode(LED3_R, OUTPUT);
  pinMode(LED3_G, OUTPUT);
  setLED(false);
  Bridge.begin();
  delay(10000);
}

void loop() {
  bool current = digitalRead(PIR_PIN);

  if (current != lastPirState) {
    lastPirState = current;
    setLED(current);
    Bridge.call("motion_event", current);
  }

  delay(100);
}