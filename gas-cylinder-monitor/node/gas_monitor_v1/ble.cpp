#include "ble.h"
#include <NimBLEDevice.h>

#define SERVICE_UUID "aa206b91-235b-42aa-b370-453a3feedf35"
#define CHAR_UUID    "b9b25bb1-f2a9-4545-b48f-295ab2789f41"

static NimBLECharacteristic* s_char    = nullptr;
static NimBLEService*        s_service = nullptr;
NimBLECharacteristic*        g_log_char = nullptr;

// ---- Command write callback ----

static void ble_on_command_received(const uint8_t* data, size_t len) {
    char buf[65];
    size_t n = (len < 64) ? len : 64;
    memcpy(buf, data, n);
    buf[n] = '\0';

    if (strcmp(buf, "TARE") == 0) {
        g_cmd_tare_pending = true;
    } else if (strcmp(buf, "SKIP_TARE") == 0) {
        g_cmd_skip_tare_pending = true;
    } else if (strncmp(buf, "SET_CAL:", 8) == 0) {
        g_cmd_set_cal_pending = true;
        g_cmd_cal_value = (float)atof(buf + 8);
    } else if (strcmp(buf, "RETARE") == 0) {
        g_cmd_retare_pending = true;
    } else if (strcmp(buf, "DUMP_LOG") == 0) {
        g_cmd_dump_log_pending = true;
    } else if (strcmp(buf, "CLEAR_LOG") == 0) {
        g_cmd_clear_log_pending = true;
    } else {
        Serial.printf("[CMD] Unknown command: %s\n", buf);
        return;
    }
    Serial.printf("[CMD] Received: %s\n", buf);
}

class CmdCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
        std::string val = c->getValue();
        ble_on_command_received((const uint8_t*)val.data(), val.length());
    }
};

static CmdCallbacks s_cmd_callbacks;

// ---- Public API ----

void ble_init_command_char() {
    NimBLECharacteristic* cmd_char = s_service->createCharacteristic(
        BLE_CMD_CHAR_UUID,
        NIMBLE_PROPERTY::WRITE_NR
    );
    cmd_char->setCallbacks(&s_cmd_callbacks);

    g_log_char = s_service->createCharacteristic(
        BLE_LOG_CHAR_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );
}

void ble_init() {
    NimBLEDevice::init("GasCylMonitor");

    NimBLEServer* server = NimBLEDevice::createServer();
    s_service = server->createService(SERVICE_UUID);

    s_char = s_service->createCharacteristic(
        CHAR_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    ble_init_command_char();

    s_service->start();

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
