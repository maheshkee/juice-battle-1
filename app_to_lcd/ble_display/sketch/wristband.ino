/*
  Smart Kitchen Wristband Controller
  Hardware : ESP32-C3 Super Mini
  Keypad   : 1x5 membrane keypad (6 wires)

  Wiring:
    Wire 1 (common) -> GND
    Wire 2 (btn 1)  -> GPIO 0  (seek back)
    Wire 3 (btn 2)  -> GPIO 1  (play/pause)
    Wire 4 (btn 3)  -> GPIO 2  (seek forward)
    Wire 5 (btn 4)  -> GPIO 3  (stop)
    Wire 6 (btn 5)  -> GPIO 4  (mute/unmute)

  Board name  : BLE-Hub-AQ01
  Service UUID: a00b0000-0000-0000-0000-000000000000
  Wrist char  : a00b0004-0000-0000-0000-000000000000

  Arduino IDE:
    Board           : ESP32C3 Dev Module
    USB CDC On Boot : Enabled
    Upload Speed    : 115200
*/

#include <BLEDevice.h>
#include <BLEClient.h>
#include <BLEScan.h>
#include "esp_sleep.h"
#include "driver/gpio.h"

const char* BOARD_NAME = "BLE-Hub-AQ01";
static BLEUUID SERVICE_UUID("a00b0000-0000-0000-0000-000000000000");
static BLEUUID CHAR_UUID   ("a00b0004-0000-0000-0000-000000000000");

// Button pins - direct connection to GND via 1x5 membrane
#define BTN_SEEK_BACK  GPIO_NUM_0
#define BTN_PLAY_PAUSE GPIO_NUM_1
#define BTN_SEEK_FWD   GPIO_NUM_2
#define BTN_STOP       GPIO_NUM_3
#define BTN_MUTE       GPIO_NUM_4

const gpio_num_t BTN_PINS[5] = {
  BTN_SEEK_BACK, BTN_PLAY_PAUSE, BTN_SEEK_FWD, BTN_STOP, BTN_MUTE
};

#define IDLE_MS 1500000UL  // 25 minutes in ms

bool isPlaying    = true;
bool isMuted      = false;
bool bleConnected = false;
unsigned long lastPressTime = 0;

BLEClient*               pClient = nullptr;
BLERemoteCharacteristic* pChar   = nullptr;

class ScanCB : public BLEAdvertisedDeviceCallbacks {
public:
  BLEAdvertisedDevice* found = nullptr;
  void onResult(BLEAdvertisedDevice dev) override {
    if (dev.getName() == BOARD_NAME) {
      BLEDevice::getScan()->stop();
      found = new BLEAdvertisedDevice(dev);
      Serial.println("[SCAN] Found board");
    }
  }
};

void sendRaw(const char* text) {
  if (!bleConnected || !pChar) return;
  Serial.println(String("[>>] ") + text);
  pChar->writeValue((uint8_t*)text, strlen(text), false);
  delay(80);
}

bool doConnect(BLEAdvertisedDevice* dev) {
  pClient = BLEDevice::createClient();
  if (!pClient->connect(dev)) { Serial.println("[BLE] Connect failed"); return false; }

  BLERemoteService* svc = pClient->getService(SERVICE_UUID);
  if (!svc) { pClient->disconnect(); Serial.println("[BLE] No service"); return false; }

  pChar = svc->getCharacteristic(CHAR_UUID);
  if (!pChar) { pClient->disconnect(); Serial.println("[BLE] No char"); return false; }

  Serial.println("[BLE] Connected and ready");
  return true;
}

bool scanAndConnect() {
  for (int attempt = 1; attempt <= 3; attempt++) {
    Serial.printf("[SCAN] Attempt %d/3\n", attempt);
    BLEScan* scan = BLEDevice::getScan();
    ScanCB* cb = new ScanCB();
    scan->setAdvertisedDeviceCallbacks(cb);
    scan->setActiveScan(true);
    scan->start(5, false);
    if (cb->found) {
      bool ok = doConnect(cb->found);
      delete cb;
      if (ok) return true;
    } else {
      delete cb;
    }
    if (attempt < 3) delay(1000);
  }
  Serial.println("[SCAN] Board unreachable");
  return false;
}

void setupButtons() {
  for (int i = 0; i < 5; i++) {
    gpio_reset_pin(BTN_PINS[i]);
    gpio_set_direction(BTN_PINS[i], GPIO_MODE_INPUT);
    gpio_set_pull_mode(BTN_PINS[i], GPIO_PULLUP_ONLY);
  }
}

int readButton() {
  for (int i = 0; i < 5; i++) {
    if (digitalRead(BTN_PINS[i]) == LOW) {
      delay(50);
      if (digitalRead(BTN_PINS[i]) == LOW) {
        return i;
      }
    }
  }
  return -1;
}

void goToSleep() {
  Serial.println("[SLEEP] 25 min idle -- entering light sleep");
  Serial.flush();

  if (pClient && pClient->isConnected()) {
    pClient->disconnect();
    delay(200);
  }
  bleConnected = false;
  pChar = nullptr;

  // Enable wakeup on all 5 button pins
  for (int i = 0; i < 5; i++) {
    gpio_reset_pin(BTN_PINS[i]);
    gpio_set_direction(BTN_PINS[i], GPIO_MODE_INPUT);
    gpio_set_pull_mode(BTN_PINS[i], GPIO_PULLUP_ONLY);
    gpio_wakeup_enable(BTN_PINS[i], GPIO_INTR_LOW_LEVEL);
  }
  esp_sleep_enable_gpio_wakeup();

  esp_light_sleep_start();

  // Returns here on wake
  Serial.println("[WAKE] Woke up from button press");
  lastPressTime = millis();

  // Disable wakeup triggers
  for (int i = 0; i < 5; i++) {
    gpio_wakeup_disable(BTN_PINS[i]);
  }

  // Reconnect BLE
  Serial.println("[BLE] Reconnecting...");
  bleConnected = scanAndConnect();
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("[WRISTBAND] Boot");

  setupButtons();
  BLEDevice::init("KitchenWristband");
  bleConnected = scanAndConnect();
  lastPressTime = millis();
}

void loop() {
  unsigned long now = millis();
  if (now - lastPressTime >= IDLE_MS) {
    goToSleep();
    return;
  }

  int btn = readButton();
  if (btn == -1) { delay(20); return; }

  Serial.printf("[BTN] %d pressed\n", btn);
  lastPressTime = millis();

  if (!bleConnected || !pClient->isConnected()) {
    bleConnected = false; pChar = nullptr;
    bleConnected = scanAndConnect();
    if (!bleConnected) { delay(500); return; }
  }

  switch (btn) {
    case 0:
      sendRaw("CMD:PLAYER_SEEK_BACK");
      break;
    case 1:
      if (isPlaying) { sendRaw("CMD:PLAYER_PAUSE");  isPlaying = false; }
      else           { sendRaw("CMD:PLAYER_RESUME"); isPlaying = true;  }
      break;
    case 2:
      sendRaw("CMD:PLAYER_SEEK_FWD");
      break;
    case 3:
      sendRaw("CMD:PLAYER_STOP");
      isPlaying = false;
      break;
    case 4:
      if (isMuted) { sendRaw("CMD:PLAYER_UNMUTE"); isMuted = false; }
      else         { sendRaw("CMD:PLAYER_MUTE");   isMuted = true;  }
      break;
  }

  // Wait for button release
  while (readButton() != -1) delay(10);
  delay(100);
}
