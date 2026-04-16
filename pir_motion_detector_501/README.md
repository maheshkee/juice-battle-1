# PIR Motion Detector — Arduino UNO Q

A motion detection system using the HC-SR501 PIR sensor on the Arduino UNO Q.
The MCU detects motion in real time and drives the onboard RGB LED.
The Linux side logs events and serves a live web dashboard over the local network.

## Hardware

- **Board:** Arduino UNO Q (SKU ABX00162 / ABX00173)
- **MCU:** STM32U585 — reads PIR sensor, drives RGB LED, communicates via Bridge
- **MPU:** Qualcomm QRB2210 — runs Python, serves WebUI dashboard
- **Sensor:** HC-SR501 PIR motion sensor

## Wiring

| HC-SR501 Pin | UNO Q Pin | Header         |
|--------------|-----------|----------------|
| VCC          | +5V       | JANALOG pin 5  |
| GND          | GND       | JANALOG pin 6  |
| OUT          | D2 (PB3)  | JDIGITAL pin 3 |

## Sensor Setup

Set the jumper on the HC-SR501 to **H (repeatable trigger)** — output stays
HIGH as long as motion continues.

Adjust the two potentiometers on the sensor:
- **Sx** — sensitivity (detection range 3–7 m)
- **Tx** — hold time (how long OUT stays HIGH after motion stops, 3 s – 5 min)

## LED Behaviour

Onboard MCU RGB LED 3 gives instant hardware feedback:

| State   | LED colour |
|---------|------------|
| Standby | Green      |
| Motion  | Red        |

## Project Structure

```
pir_motion_detector/
├── app.yaml
├── README.md
├── assets/
│   ├── index.html        # Dashboard UI
│   ├── style.css         # Dashboard styles
│   ├── app.js            # WebSocket client logic
│   └── libs/
│       └── socket.io.min.js
├── python/
│   └── main.py           # Linux side — Bridge receiver + WebUI
└── sketch/
    ├── sketch.ino        # MCU side — PIR read + LED + Bridge
    └── sketch.yaml       # Board and library config
```

## Importing into Arduino App Lab

1. Open **Arduino App Lab** on your PC or directly on the UNO Q in SBC mode.
2. Click **My Apps** in the top left.
3. Click the **Import** button (or drag and drop the project zip file).
4. Select the `pir_motion_detector` zip file — App Lab will extract and load
   all files automatically.
5. The project will appear in your apps list. Click it to open.

## First Run on a New Board

1. **Wire the sensor** — connect HC-SR501 VCC, GND and OUT as per the wiring
   table above before powering on.

2. **Connect the board** — plug the UNO Q into your PC via USB-C data cable
   (PC-hosted mode), or just power it for SBC mode.

3. **Check the files** — open the Editor and confirm these files are present:
   - `sketch/sketch.ino`
   - `sketch/sketch.yaml`
   - `python/main.py`
   - `assets/index.html`, `assets/style.css`, `assets/app.js`
   - `assets/libs/socket.io.min.js`

4. **Hit Run** — App Lab will compile and flash the sketch to the STM32U585,
   then start the Python container on the Linux side. This takes up to a minute
   on first run.

5. **Wait for warm-up** — the sketch waits 10 seconds on startup for the
   HC-SR501 to stabilise. The green LED will turn on after this delay.

6. **Open the dashboard** — once the Python console shows:
   ```
   Network URL: http://<board-ip>:7000
   ```
   Open that URL in any browser on the same network.

7. **Test** — wave your hand in front of the sensor. The onboard LED should
   turn red and the dashboard should update within 100 ms.

## How It Works

The STM32U585 MCU polls D2 every 100 ms. When the PIR state changes it
updates the onboard LED and calls `Bridge.call("motion_event", state)` to
notify the Linux side.

The QRB2210 Linux side receives this via `Bridge.provide("motion_event", ...)`,
timestamps the event, and pushes a `motion_update` WebSocket message to all
connected browser clients.


## Notes

- The HC-SR501 has a ~10 second warm-up delay on power-on — the sketch
  waits for this before starting detection (`delay(10000)` in `setup()`).
- OUT pin is 3.3 V HIGH regardless of supply voltage — no level shifting needed.
- All MCU GPIOs are 3.3 V logic. A0 and A1 are not 5 V tolerant.
- If the dashboard shows "Connecting..." check that `assets/libs/socket.io.min.js`
  exists in the project.
- Bridge function name `"motion_event"` must match exactly in both
  `sketch.ino` and `main.py` — it is case sensitive.