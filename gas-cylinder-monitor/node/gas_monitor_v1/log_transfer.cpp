#include "log_transfer.h"
#include "journal.h"
#include "ble.h"
#include <SPIFFS.h>

static const char* LOG_FILE_PATH  = "/node_journal.log";
static const char* SENTINEL_START = "LOG_START\n";
static const char* SENTINEL_END   = "LOG_END\n";

LogTransferState g_lt_state  = LT_IDLE;
static File      s_log_file;
static bool      s_file_open  = false;
static uint16_t  s_line_count = 0;

// Shared path for all sentinel sends - avoids repeating setValue/notify pair
static void _notify_str(const char* msg) {
    g_log_char->setValue((uint8_t*)msg, strlen(msg));
    g_log_char->notify();
}

void log_transfer_start() {
    if (!g_mtu_ready) {
        // Hub hasn't negotiated MTU yet - sending now risks truncated packets
        Serial.println("[LOG] start rejected - MTU not yet exchanged");
        return;
    }
    if (g_lt_state == LT_SENDING || g_lt_state == LT_DONE) {
        // Previous transfer still in flight - don't start a second one
        Serial.println("[LOG] start rejected - transfer already in progress");
        return;
    }
    if (g_log_char == nullptr) {
        // BLE not fully initialised - log characteristic not created yet
        Serial.println("[LOG] start rejected - log characteristic not initialised");
        return;
    }

    // Hub uses LOG_START to know a stream is beginning, even if file is empty
    _notify_str(SENTINEL_START);

    s_log_file = SPIFFS.open(LOG_FILE_PATH, "r");
    if (!s_log_file || s_log_file.size() == 0) {
        // Nothing to stream - close immediately and signal end
        if (s_log_file) s_log_file.close();
        Serial.println("[LOG] file empty or missing - sending LOG_END immediately");
        _notify_str(SENTINEL_END);
        g_lt_state = LT_DONE;
        return;
    }

    s_file_open  = true;
    s_line_count = 0;
    g_lt_state   = LT_SENDING;
    Serial.printf("[LOG] transfer start - file size %u bytes\n", (unsigned)s_log_file.size());
}

void log_transfer_tick() {
    if (g_lt_state != LT_SENDING || !s_file_open) return;

    // Read one line into stack buffer - char-by-char to avoid String heap churn
    char line[256];
    int  idx = 0;
    int  c;
    while (idx < 255 && (c = s_log_file.read()) != -1) {
        line[idx++] = (char)c;
        if ((char)c == '\n') break;
    }
    line[idx] = '\0';

    if (idx == 0) {
        // EOF - all lines consumed, signal hub the stream is complete
        s_log_file.close();
        s_file_open = false;
        _notify_str(SENTINEL_END);
        g_lt_state = LT_DONE;
        Serial.printf("[LOG] transfer complete - %u lines sent\n", (unsigned)s_line_count);
        return;
    }

    // Send exactly idx bytes so the hub receives the trailing \n as line delimiter
    g_log_char->setValue((uint8_t*)line, (size_t)idx);
    g_log_char->notify();
    s_line_count++;
    if (s_line_count % 10 == 0) {
        Serial.printf("[LOG] sent %u lines\n", (unsigned)s_line_count);
    }
}

void log_transfer_abort() {
    if (s_file_open) {
        s_log_file.close();
        s_file_open = false;
    }
    g_lt_state = LT_IDLE;
    // File deliberately left on SPIFFS - hub can issue DUMP_LOG again after reconnect
    Serial.println("[LOG] transfer aborted - BLE dropped, SPIFFS file preserved");
}

void log_transfer_clear() {
    if (s_file_open) {
        s_log_file.close();
        s_file_open = false;
        Serial.println("[LOG] file handle closed");
    }
    if (SPIFFS.exists(LOG_FILE_PATH)) {
        SPIFFS.remove(LOG_FILE_PATH);
        Serial.println("[LOG] SPIFFS journal deleted");
    }
    g_journal_file_bytes = 0;
    g_transfer_pending   = false;
    g_lt_state           = LT_IDLE;
    Serial.println("[LOG] SPIFFS journal cleared");
}
