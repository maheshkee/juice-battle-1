#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define PIR_PIN      4
#define LED_PIN      8

#define SERVICE_UUID "a00c0000-0000-0000-0000-000000000000"
#define MOTION_UUID  "a00c0001-0000-0000-0000-000000000000"
#define DEVICE_NAME  "PIR-ESP32"

BLEServer*         pServer         = nullptr;
BLECharacteristic* pMotionChar     = nullptr;
bool               deviceConnected = false;
bool               lastPirState    = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    digitalWrite(LED_PIN, HIGH);
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    digitalWrite(LED_PIN, LOW);
    Serial.println("[BLE] Client disconnected — restarting advertising");
    BLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(PIR_PIN, INPUT);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Serial.println("[PIR] Warming up sensor (10s)...");
  delay(10000);
  Serial.println("[PIR] Sensor ready");

  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pMotionChar = pService->createCharacteristic(
    MOTION_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pMotionChar->addDescriptor(new BLE2902());

  uint8_t initVal = 0;
  pMotionChar->setValue(&initVal, 1);

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising as PIR-ESP32");
  Serial.println("[BLE] Waiting for UNO Q to connect...");
}

void loop() {
  bool current = digitalRead(PIR_PIN) == HIGH;

  if (current != lastPirState) {
    lastPirState = current;

    uint8_t val = current ? 1 : 0;
    pMotionChar->setValue(&val, 1);

    if (deviceConnected) {
      pMotionChar->notify();
    }

    Serial.print("[PIR] ");
    Serial.println(current ? "DETECTED" : "CLEAR");
  }

  delay(100);
}