#include <Arduino_RouterBridge.h>

const int PIR_PIN = 2;      // D2 on JDIGITAL header — wire SR602 OUT here
bool lastPirState = false;  // tracks previous reading for edge detection

void setup() {
  pinMode(PIR_PIN, INPUT);  // PIR OUT pin is pure output — no pull-up needed
  Bridge.begin();           // start the Bridge RPC channel to Linux side
  delay(60000);             // PIR warm-up: ignore first 60s of random signals
}

void loop() {
  bool currentState = digitalRead(PIR_PIN);  // HIGH = motion, LOW = no motion

  // Only act on CHANGE — not on every loop tick
  if (currentState != lastPirState) {
    lastPirState = currentState;

    // Tell Python side: "motion_event" happened, pass true/false
    Bridge.call("motion_event", currentState);
  }

  delay(100);  // poll every 100ms — fast enough, not wasteful
}