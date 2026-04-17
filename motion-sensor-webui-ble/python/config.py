# config.py — all project constants

APP_NAME         = "AQ2-Motion"
BLE_SERVICE_UUID = "a00b0000-0000-0000-0000-000000000000"
MANUFACTURER_ID  = 0xFFFF
DBUS_SOCK        = "unix:path=/app/dbus.sock"
WHEELS_DIR       = "/app/wheels"
TYPELIBS_DIR     = "/app/typelibs"

# Remote BLE sensors — add new ones here
# char_uuid must match what the remote device advertises
REMOTE_SENSORS = {
    "ESP32-Room": {
        "mac":       "10:00:3B:CD:63:32",
        "char_uuid": "a00c0001-0000-0000-0000-000000000000",
    },
    # Uncomment when AQ1 is ready:
    # "AQ1-Room": {
    #     "mac":       "XX:XX:XX:XX:XX:XX",
    #     "char_uuid": "a00b0001-0000-0000-0000-000000000000",
    # },
}

SHARED_LIBS = [
    "libm.so.6", "libcap.so.2", "libpcre2-8.so.0",
    "libselinux.so.1", "libaudit.so.1", "libcap-ng.so.0",
    "libexpat.so.1", "libdbus-1.so.3", "libapparmor.so.1",
    "libsystemd.so.0", "libgirepository-2.0.so.0",
]
