# gas_monitor_v1 - Arduino dependencies

## Required libraries (install via Arduino IDE Library Manager)

| Library | Author | Purpose |
|---|---|---|
| NimBLE-Arduino | h2zero | BLE GATT server |
| ArduinoJson | Benoit Blanchon | config.json read/write |
| SPIFFS | built-in (ESP32 core) | flash filesystem - no install needed |

## Board

- ESP32C3 Dev Module
- esp32 by Espressif v3.0.7 (NOT v3.3.9)
- USB CDC On Boot: ENABLED

## Flash

- SCP sketch from AQ3 to Windows
- Open gas_monitor_v1.ino in Arduino IDE v3.0.7
- Port: COM11
- Upload
