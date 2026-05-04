#ifndef FAKE_ARDUINO_H
#define FAKE_ARDUINO_H

#include <stdint.h>

static const int LOW = 0;
static const int HIGH = 1;
static const int INPUT = 0;
static const int OUTPUT = 1;
static const int INPUT_PULLUP = 2;

void pinMode(int pin, int mode);
void digitalWrite(int pin, int value);
int digitalRead(int pin);
unsigned long millis();
void noInterrupts();
void interrupts();
void delay(unsigned long ms);
void delayMicroseconds(unsigned int us);
void yield();

#endif
