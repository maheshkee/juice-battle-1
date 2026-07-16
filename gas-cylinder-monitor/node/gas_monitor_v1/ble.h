#pragma once
#include <Arduino.h>
#include <NimBLEDevice.h>

// Command characteristic — hub sends commands to node (write-without-response)
static const char* BLE_CMD_CHAR_UUID = "c8a2f1e3-4d6b-4a7c-8e9f-1b2d3e4f5a6b";
// Log characteristic — node streams journal lines to hub (notify)
static const char* BLE_LOG_CHAR_UUID = "d7b3e2f4-5e7c-4b8d-9f1a-2c3e4f5a6b7c";

// Log characteristic handle — journal.cpp calls g_log_char->notify() to stream lines
extern NimBLECharacteristic* g_log_char;
extern bool g_mtu_ready;   // true after MTU exchange completes - gate for log transfer

// BLE command flags — defined in gas_monitor_v1.ino, set by BLE write callback
extern volatile bool  g_cmd_tare_pending;
extern volatile bool  g_cmd_skip_tare_pending;
extern volatile bool  g_cmd_set_cal_pending;
extern volatile float g_cmd_cal_value;
extern volatile bool  g_cmd_retare_pending;
extern volatile bool  g_cmd_dump_log_pending;
extern volatile bool  g_cmd_clear_log_pending;

void ble_init();
void ble_init_command_char();
void ble_notify(float grams, const char* quality_str, float sigma_g, float temp_c);
