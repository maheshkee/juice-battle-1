#include "ble.h"
#include <NimBLEDevice.h>

#define SERVICE_UUID  "aa206b91-235b-42aa-b370-453a3feedf35"
#define CHAR_UUID     "b9b25bb1-f2a9-4545-b48f-295ab2789f41"

static NimBLECharacteristic* s_char = nullptr;

void ble_init() {
    NimBLEDevice::init("GasCylMonitor");

    NimBLEServer*         server  = NimBLEDevice::createServer();
    NimBLEService*        service = server->createService(SERVICE_UUID);

    s_char = service->createCharacteristic(
        CHAR_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    service->start();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SERVICE_UUID);
    adv->start();
}

void ble_notify(float grams, const char* quality_str, float sigma_g) {
    if (s_char == nullptr) return;
    if (NimBLEDevice::getServer()->getConnectedCount() == 0) return;

    char buf[96];
    snprintf(buf, sizeof(buf),
             "{\"grams\":%.1f,\"quality\":\"%s\",\"sigma\":%.2f}",
             grams, quality_str, sigma_g);

    s_char->setValue((uint8_t*)buf, strlen(buf));
    s_char->notify();
}
