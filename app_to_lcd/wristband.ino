/*
  Smart Kitchen Wristband Controller
  Hardware : ESP32-C3 Super Mini
  Keypad   : 5x1 Matrix Membrane Switch Keypad (6 wires)

  Wiring:
    Wire 1 (Row)  -> GND  (directly, no GPIO needed)
    Wire 2 (Col1) -> GPIO 0  (seek back 10s)
    Wire 3 (Col2) -> GPIO 1  (play/pause toggle)
    Wire 4 (Col3) -> GPIO 2  (seek forward 10s)
    Wire 5 (Col4) -> GPIO 3  (stop)
    Wire 6 (Col5) -> GPIO 4  (mute/unmute toggle)

  Service UUID: a00b0000-0000-0000-0000-000000000000
  Wrist char  : a00b0004-0000-0000-0000-000000000000

  Arduino IDE setup (fresh board):
    1. File -> Preferences -> Additional boards manager URLs:
       https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
    2. Tools -> Board -> Boards Manager -> search "esp32" -> Install
    3. Tools -> Board -> ESP32C3 Dev Module
    4. Tools -> USB CDC On Boot -> Enabled
    5. Tools -> Port -> select COM port for ESP32-C3
    6. Click Upload

  Behavior:
    - On boot: scans for the board's advertised service UUID, connects, stays connected
    - Button press: sends command instantly (already connected)
    - IDLE_MS idle: disconnects and enters light sleep
    - Any button press during sleep: wakes up, reconnects, sends command
    - Play/pause and mute toggle state maintained across light sleep

  NOTE: scans by SERVICE_UUID (a00b0000), not board name -- the board's
  advertised name can change (board_id.json / _load_board_name() on the
  main.py side defaults to "BLE-Hub" if unset), but it always advertises
  this service UUID, so matching on UUID is robust to that.
*/

#include <BLEDevice.h>
#include <BLEClient.h>
#include <BLEScan.h>
#include "esp_sleep.h"
#include "driver/gpio.h"

static BLEUUID SERVICE_UUID("a00b0000-0000-0000-0000-000000000000");
static BLEUUID CHAR_UUID   ("a00b0004-0000-0000-0000-000000000000");

// Button pins - col wires go directly to these GPIOs
// Row wire goes to GND so pressing a button pulls col LOW
#define BTN_SEEK_BACK  GPIO_NUM_0
#define BTN_PLAY_PAUSE GPIO_NUM_1
#define BTN_SEEK_FWD   GPIO_NUM_2
#define BTN_STOP       GPIO_NUM_3
#define BTN_MUTE       GPIO_NUM_4

const gpio_num_t BTN_PINS[5] = {
    BTN_SEEK_BACK, BTN_PLAY_PAUSE, BTN_SEEK_FWD, BTN_STOP, BTN_MUTE
};

// TEST value -- change to 1500000UL for production (25 min)
#define IDLE_MS 100000UL

// Toggle state -- survives light sleep (variables preserved in RAM)
bool isPlaying = true;
bool isMuted   = false;

bool bleConnected = false;
unsigned long lastPressTime = 0;

BLEClient*               pClient = nullptr;
BLERemoteCharacteristic* pChar   = nullptr;

class ScanCB : public BLEAdvertisedDeviceCallbacks {
public:
    BLEAdvertisedDevice* found = nullptr;
    void onResult(BLEAdvertisedDevice dev) override {
        if (dev.haveServiceUUID() && dev.isAdvertisingService(SERVICE_UUID)) {
            BLEDevice::getScan()->stop();
            found = new BLEAdvertisedDevice(dev);
            Serial.println("[SCAN] Found board (service UUID match)");
        }
    }
};

void sendRaw(const char* text) {
    if (!bleConnected || !pChar) return;
    Serial.println(String("[>>] ") + text);
    pChar->writeValue((uint8_t*)text, strlen(text), false);
    delay(80);
}

// Tears down any existing client before creating a new one -- prevents
// leaking a BLEClient object on every reconnect (sleep/wake, mid-loop
// reconnect, etc. all call this repeatedly over the device's lifetime).
void teardownClient() {
    if (pClient) {
        if (pClient->isConnected()) {
            pClient->disconnect();
            delay(100);
        }
        delete pClient;
        pClient = nullptr;
    }
    pChar = nullptr;
}

bool doConnect(BLEAdvertisedDevice* dev) {
    teardownClient();
    pClient = BLEDevice::createClient();
    if (!pClient->connect(dev)) {
        Serial.println("[BLE] Connect failed");
        teardownClient();
        return false;
    }
    BLERemoteService* svc = pClient->getService(SERVICE_UUID);
    if (!svc) { Serial.println("[BLE] No service"); teardownClient(); return false; }
    pChar = svc->getCharacteristic(CHAR_UUID);
    if (!pChar) { Serial.println("[BLE] No char"); teardownClient(); return false; }
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
            delete cb->found;
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
            delay(50); // debounce
            if (digitalRead(BTN_PINS[i]) == LOW) {
                return i;
            }
        }
    }
    return -1;
}

void goToSleep() {
    Serial.println("[SLEEP] Idle timeout -- entering light sleep");
    Serial.flush();

    teardownClient();
    bleConnected = false;

    // Enable wakeup on all 5 button pins
    for (int i = 0; i < 5; i++) {
        gpio_reset_pin(BTN_PINS[i]);
        gpio_set_direction(BTN_PINS[i], GPIO_MODE_INPUT);
        gpio_set_pull_mode(BTN_PINS[i], GPIO_PULLUP_ONLY);
        gpio_wakeup_enable(BTN_PINS[i], GPIO_INTR_LOW_LEVEL);
    }
    esp_sleep_enable_gpio_wakeup();

    // Light sleep -- returns here on wake
    esp_light_sleep_start();

    Serial.println("[WAKE] Button press detected");
    lastPressTime = millis();

    // Disable wakeup triggers
    for (int i = 0; i < 5; i++) {
        gpio_wakeup_disable(BTN_PINS[i]);
    }

    // Reconnect BLE
    Serial.println("[BLE] Reconnecting after sleep...");
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
    // Check idle timeout
    unsigned long now = millis();
    if (now - lastPressTime >= IDLE_MS) {
        goToSleep();
        return;
    }

    int btn = readButton();
    if (btn == -1) { delay(20); return; }

    Serial.printf("[BTN] %d pressed\n", btn);
    lastPressTime = millis();

    // Reconnect if needed
    if (!bleConnected || !pClient || !pClient->isConnected()) {
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
