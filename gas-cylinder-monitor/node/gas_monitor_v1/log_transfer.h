#pragma once
#include <Arduino.h>

enum LogTransferState {
    LT_IDLE,     // no transfer in progress
    LT_SENDING,  // streaming lines to hub — one line per HX711 tick
    LT_DONE      // LOG_END sent, waiting for hub to issue CLEAR_LOG
};

extern LogTransferState g_lt_state;

// Initiates transfer on DUMP_LOG command. Guarded by g_mtu_ready — BLE MTU
// must be negotiated before large payloads are safe to send. Sends LOG_START\n
// sentinel so hub knows a stream is beginning.
void log_transfer_start();

// Paced by the HX711 tick (~10Hz) so BLE notify calls are naturally rate-limited
// without a separate timer. Sends one line per call; sends LOG_END\n at EOF.
void log_transfer_tick();

// Safety valve for BLE drop during transfer. Preserves the SPIFFS file so the
// hub can request retransfer after reconnect without losing log data.
void log_transfer_abort();

// Executed after hub has confirmed receipt (CLEAR_LOG command). Deletes the
// SPIFFS file and resets all transfer state so the next boot starts fresh.
void log_transfer_clear();
