#include <Arduino_RouterBridge.h>

const int PIR_PIN = 2;
bool lastPirState = false;

void setup() {
  pinMode(PIR_PIN, INPUT);

  // LED3 and LED4 are active-low — HIGH = OFF, LOW = ON
  pinMode(LED3_R, OUTPUT); pinMode(LED3_G, OUTPUT); pinMode(LED3_B, OUTPUT);
  pinMode(LED4_R, OUTPUT); pinMode(LED4_G, OUTPUT); pinMode(LED4_B, OUTPUT);

  // Start both LEDs green — area clear
  setLEDs(false);

  Bridge.begin();
  delay(60000);  // PIR warmup
}

void loop() {
  bool currentState = digitalRead(PIR_PIN);

  if (currentState != lastPirState) {
    lastPirState = currentState;
    Bridge.call("motion_event", currentState);
    setLEDs(currentState);  // update LEDs on every state change
  }

  delay(100);
}

void setLEDs(bool motionDetected) {
  if (motionDetected) {
    // RED on both LED3 and LED4
    digitalWrite(LED3_R, LOW);  digitalWrite(LED3_G, HIGH); digitalWrite(LED3_B, HIGH);
    digitalWrite(LED4_R, LOW);  digitalWrite(LED4_G, HIGH); digitalWrite(LED4_B, HIGH);
  } else {
    // GREEN on both LED3 and LED4
    digitalWrite(LED3_R, HIGH); digitalWrite(LED3_G, LOW);  digitalWrite(LED3_B, HIGH);
    digitalWrite(LED4_R, HIGH); digitalWrite(LED4_G, LOW);  digitalWrite(LED4_B, HIGH);
  }
}
