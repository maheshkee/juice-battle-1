# PIR BLE Receiver — Arduino UNO Q

Receives PIR motion data from an ESP32 C3 over BLE and displays it
on a live web dashboard. The UNO Q onboard LED3 mirrors the motion
state in real time.

---

## System Architecture

```
HC-SR501 → ESP32 C3 (BLE GATT server "PIR-ESP32")
                ↓  BLE notify
           UNO Q Linux (BLE GATT client)
                ↓  Bridge
           UNO Q MCU (LED3 red / green)
                ↓
           WebUI at http://<board-ip>:7000
```

---

## Hardware

### ESP32 C3

| HC-SR501 | ESP32 C3  | Notes             |
|----------|-----------|-------------------|
| VCC      | VIN (5V)  | HC-SR501 needs 5V |
| GND      | GND       |                   |
| OUT      | GPIO 4    | Digital input     |

### UNO Q

No extra wiring. Onboard LED3 gives visual feedback.

| State   | LED   |
|---------|-------|
| Standby | Green |
| Motion  | Red   |

---

## BLE UUIDs

| Name    | UUID                                 |
|---------|--------------------------------------|
| Service | a00c0000-0000-0000-0000-000000000000 |
| Motion  | a00c0001-0000-0000-0000-000000000000 |

---

## Project Structure

```
pir_ble_501/
├── app.yaml                        # Must contain network_mode: "host"
├── README.md
├── setup/
│   └── setup.sh                    # Run once on every new board
├── assets/
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   └── libs/
│       └── socket.io.min.js
├── python/
│   ├── main.py
│   └── requirements.txt
├── sketch/
│   ├── sketch.ino
│   └── sketch.yaml
├── typelibs/                       # GLib typelibs for dbus-python
└── wheels/                         # Pre-built Python wheels + shared libs
```

---

## ESP32 C3 — Arduino IDE Setup

1. File → Preferences → Additional boards manager URLs — paste:
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

2. Tools → Board → Boards Manager → search esp32 → install esp32 by Espressif Systems

3. Tools → Board → ESP32 Arduino → ESP32C3 Dev Module

4. Tools → USB CDC On Boot → Enabled

5. Tools → Partition Scheme → Huge APP (3MB No OTA)

6. Tools → Port → select your ESP32 port

7. Open pir_esp32.ino and click Upload

8. Open Serial Monitor at 115200 — confirm:
   [BLE] Advertising as PIR-ESP32

---

## UNO Q — First Time Setup

### 1. Copy wheels and typelibs from the BLE project

```bash
cp -r ~/ArduinoApps/ble_arduino/wheels ~/ArduinoApps/pir_ble_501/
cp -r ~/ArduinoApps/ble_arduino/typelibs ~/ArduinoApps/pir_ble_501/
```

### 2. Run the setup script

```bash
chmod +x ~/ArduinoApps/pir_ble_501/setup/setup.sh
bash ~/ArduinoApps/pir_ble_501/setup/setup.sh
```

This writes the dbus-bridge service, enables it, and confirms the socket is created.

### 3. Hit Run in App Lab

---

## Running Order

1. Flash ESP32 C3 and confirm advertising in Serial Monitor
2. On UNO Q — verify dbus-bridge is running and dbus.sock exists
3. Hit Run in App Lab
4. Watch Python console for:
   [BLE] Connected to PIR-ESP32
   [BLE] Ready — waiting for motion events from ESP32
5. Open dashboard at http://<board-ip>:7000
6. Wave in front of sensor — LED3 goes red, dashboard updates

---

## After Every Reboot

```bash
sudo systemctl status dbus-bridge.service
ls -la ~/ArduinoApps/pir_ble_501/dbus.sock
```

If dbus.sock is missing:

```bash
sudo systemctl restart dbus-bridge.service
```

---

## Useful Commands

```bash
# Check service
sudo systemctl status dbus-bridge.service

# Restart service
sudo systemctl restart dbus-bridge.service

# Check socket
ls -la ~/ArduinoApps/pir_ble_501/dbus.sock

# View logs
sudo journalctl -u dbus-bridge.service -n 20

# Clear App Lab cache
rm -rf ~/ArduinoApps/pir_ble_501/.cache
```

---

## Troubleshooting

| Problem                  | Fix                                                      |
|--------------------------|----------------------------------------------------------|
| No module named dbus     | Check python/requirements.txt has the wheel paths        |
| dbus.sock not found      | Run sudo systemctl restart dbus-bridge.service           |
| SystemBus failed         | Check service is running and sock exists                 |
| ESP32 not in nRF Connect | Confirm Serial Monitor shows advertising, check Partition Scheme |
| Dashboard not loading    | Check libs/socket.io.min.js exists and board IP is correct |
| LED not responding       | Check sketch flashed — see App launch tab in console     |
| Not working after reboot | Check dbus-bridge.service status                         |