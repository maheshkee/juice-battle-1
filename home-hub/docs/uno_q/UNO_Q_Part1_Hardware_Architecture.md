# Arduino UNO Q — Complete Learning Guide
## Part 1: Hardware Architecture, Pinout & Power System

> **First-Principles Edition** — Not just *what*, but *why* and *how it works underneath*.
> Sources: Official Datasheet (ABX00162/ABX00173), Full Pinout (Feb 2026), Schematics, User Manual (Mar 2026), Field Notes.

---

## 1. What Is the Arduino UNO Q? — The Mental Model

The Arduino UNO Q is **not a microcontroller board**. It is a **hybrid single-board computer** combining two fundamentally different computing paradigms on one PCB — each solving a problem the other cannot.

```
Classic Arduino UNO:          Arduino UNO Q:
┌──────────────────┐          ┌─────────────────────────────────────┐
│  ATmega328P MCU  │          │  QRB2210 MPU  ←Bridge→  STM32 MCU  │
│  Real-time only  │          │  Debian Linux        Zephyr RTOS    │
│  No OS           │          │  Python, AI, WiFi    GPIO, PWM, ADC │
└──────────────────┘          └─────────────────────────────────────┘
```

**Why two processors?** A Linux kernel cannot guarantee that a GPIO pin will toggle in exactly 10 microseconds — the scheduler can preempt your task at any moment. An MCU running an RTOS *can* make that timing guarantee. The UNO Q gives you both:
- **MPU (QRB2210):** High-level computing — AI, networking, Python, cameras, complex logic
- **MCU (STM32U585):** Real-time I/O — GPIO, PWM, ADC, precise timing, sensor polling

The "Q" in the name stands for **Qualcomm** — the company that acquired Arduino in October 2025 and whose processor powers the MPU side.

---

## 2. Board Variants

| SKU | RAM | Storage | Recommended For |
|---|---|---|---|
| ABX00162 | 2 GB LPDDR4X | 16 GB eMMC | General development, PC-hosted mode |
| ABX00173 | 4 GB LPDDR4X | 32 GB eMMC | SBC standalone mode, AI-heavy apps |

**Form factor:** 68.58 mm × 53.34 mm — UNO-compatible mounting hole pattern and header layout. Bottom-side parts kept below 2 mm for carrier board stacking.

---

## 3. Processor Deep Dive

### MPU — Qualcomm Dragonwing™ QRB2210

```
QRB2210 (SOC1)
├── 4× ARM Cortex-A53 cores @ 2.0 GHz (64-bit)
├── Adreno 702 GPU @ 845 MHz   ← 3D graphics & ML acceleration
├── Dual ISPs: 13MP+13MP or 25MP @ 30fps  ← machine vision
├── OS: Debian Linux (upstream supported)
├── I/O voltage: 1.8V  ← CRITICAL
├── USB: 3.1 Gen 1 with role-switching (host/device/OTG)
├── Interfaces: SDIO 3.0, 4-lane MIPI-CSI-2, 4-lane MIPI-DSI
└── Handles: WiFi, Bluetooth, USB-C PD negotiation, DisplayPort output
```

The MPU's I/O operates at **1.8V** throughout — this is the single most important hardware fact to remember about the UNO Q.

### MCU — STMicroelectronics STM32U585

```
STM32U585 (MCU1)
├── ARM Cortex-M33 @ up to 160 MHz
├── 2 MB Flash, 786 kB SRAM
├── OS: Zephyr RTOS + Arduino Core  ← your .ino sketches run here
├── I/O voltage: 3.3V
└── Manages: ADC (14-bit), PWM, CAN, SPI, I²C, UART, LED matrix, timers
```

The MCU is what makes the UNO Q feel like an Arduino — it provides the familiar `setup()`/`loop()`, `digitalRead()`, `analogWrite()` API through the Arduino Core on top of Zephyr.

### How They Communicate

The two processors share **no memory**. They communicate exclusively through the **Bridge RPC layer** — a software messaging system running on both sides. Physical transport: a dedicated UART line between the chips (`/dev/ttyHS1` on Linux, `Serial1` on the MCU). The Arduino Router service manages this link.

```
┌──────────────────┐   /dev/ttyHS1 (115200 baud)   ┌──────────────┐
│  QRB2210 (MPU)   │◄─────────────────────────────►│  STM32U585   │
│  Debian Linux    │   arduino-router daemon         │  Zephyr RTOS │
│  Python runs     │   MessagePack RPC protocol      │  .ino runs   │
└──────────────────┘                                  └──────────────┘
```

**⚠️ Reserved:** Never open `/dev/ttyHS1` (Linux) or `Serial1` (Arduino sketch) directly — both are exclusively locked by the `arduino-router` service. Doing so breaks Bridge communication.

---

## 4. Complete Hardware Specifications

### Processing & Memory

| Component | Specification |
|---|---|
| MPU | Qualcomm QRB2210 — 4× Cortex-A53 @ 2.0 GHz, 64-bit |
| GPU | Adreno 702 @ 845 MHz |
| Dual ISP | 13MP + 13MP or 25MP @ 30fps |
| MCU | STM32U585 — Cortex-M33 @ up to 160 MHz |
| MCU Flash | 2 MB |
| MCU SRAM | 786 kB |
| System RAM | 2 GB or 4 GB LPDDR4X |
| Storage | 16 GB or 32 GB eMMC |

### Connectivity

| Feature | Detail |
|---|---|
| WiFi | 802.11a/b/g/n/ac dual-band (2.4+5 GHz) — WiFi 5 |
| Bluetooth | BT 5.1 (BLE supported) |
| Wireless Chip | WCBN3536A (Qualcomm WCN3980) |
| WiFi Interface | SDIO (data) + UART (BT control) |
| USB | USB 3.1 Gen 1 (5 Gb/s), role-switching host/device/OTG |
| USB Power Delivery | 5V / 3A only — does NOT negotiate higher voltage profiles |
| DisplayPort | Via ANX7625 chip: converts MPU's MIPI-DSI to DP Alt-Mode on USB-C |
| ANX7625 | DSI→DP bridge + USB-C PD policy chip |

### Key Support Chips

| Component | Part | Role |
|---|---|---|
| PMIC | PM4125 (Qualcomm) | Power management, generates 1.8V rail |
| DP Bridge | ANX7625 | Converts MIPI-DSI to DisplayPort Alt-Mode |
| WiFi/BT | WCBN3536A | Dual-band WiFi 5 + BT 5.1 |
| RAM | LPDDR4X | 2 or 4 GB system memory |
| Storage | eMMC | 16 or 32 GB persistent storage |
| Buck 1 | TPS62A02A (U2801) | 5V → 3.8V |
| Buck 2 | TPS62A02A (U2802) | 3.8V → 3.3V |
| VIN Buck | LMR51440 (U2803) | 7-24V → 5V |
| Schottky diodes | SX34 (D2801, D2803) | Diode-OR combines USB-C VBUS and VIN buck |
| USB VBUS switch | PJA3413 P-MOSFET (Q2801) | Back-drive protection |
| 3.0V LDO | TPS7A2030 (U3004) | 3.3V → 3.0V for ANX7625 analog rail |

---

## 5. Power System — How the Board Stays Alive

### Two Input Paths

The UNO Q accepts power from multiple sources, **simultaneously**:

```
USB-C VBUS (5V, ≤3A)  ──[Schottky D2801]──┐
                                             ├──► 5V_SYS
VIN (7-24V) ─[LMR51440 buck]─5V ─[D2803]──┘
                                             
5V pin on JANALOG ──────────────────────────►  (directly to 5V_SYS)
```

**Diode-OR:** The Schottky diodes allow both sources to connect without conflict. The higher-voltage side (after diode drop) wins. There is a small forward voltage drop (Vf):
- At 1.0A load: Vf = 0.35V, dissipating 0.35W as heat
- At 2.0A load: Vf = 0.39V, dissipating 0.78W as heat

> **Why Schottky diodes?** They have very low Vf (0.3–0.4V vs silicon's 0.6–0.7V), minimizing power loss in the OR-ing circuit.

### Power Rail Derivation Tree

```
USB-C VBUS (5V)  OR  7-24V via LMR51440 Buck  OR  5V pin
                         │
                    [Schottky OR]
                         │
                      5V_SYS ──────────────────────────────────────────
                         │                                             │
              [TPS62A02A U2801 Buck]                          PM4125 PMIC
                         │                                    (L15A LDO)
                      3.8V (PWR_3P8V)                              │
                      [reserved for                            1.8V (VREG_L15A_1P8V)
                       system/future]                     Powers: SoC I/O, ANX7625 DVDD18,
                         │                               WiFi digital, level shifters,
              [TPS62A02A U2802 Buck]                     JMISC & JCTL pins
                         │
                      3.3V (PWR_3P3V)
                Powers: STM32U585 (VDD, VDDA, VDDUSB, VREF+),
                        ANX7625 3.3V domain, WiFi 3.3V,
                        JDIGITAL, JANALOG, JSPI, QWIIC headers
```

### Power Sequencing (Why Order Matters)

1. VIN rises above ~4.3V → soft start begins (~2ms)
2. 3.3V rail (PWR_3P3V) stabilizes first
3. ~1ms later, PMIC enables 1.8V rail (VREG_L15A_1P8V)
4. QRB2210 boots Linux system
5. ~20 seconds later, QRB2210 signals readiness to STM32U585

**On shutdown:** 1.8V turns off BEFORE 3.3V. This prevents back-powering through the level shifters and keeps high-speed interfaces in a known state.

### Special Power Pins

| Pin | Net | Purpose |
|---|---|---|
| VCOIN | PMIC RTC supply | Powers only the PM4125's real-time clock (not Linux or MCU) |
| VBAT | MCU RTC supply | Powers only the STM32U585's real-time clock |
| PWR_3P8V | 3.8V intermediate | Reserved for system design and future features |
| 5V pin (JANALOG) | 5V_USB_VBUS | Can be used as alternate 5V power input to the board |

### Operating Limits

| Parameter | Min | Typical | Max | Unit |
|---|---|---|---|---|
| USB-C VBUS | 4.5 | 5.0 | 5.5 | V |
| DC Input (VIN) | 7.0 | — | 24.0 | V |
| 3.3V Rail | 3.1 | 3.3 | 3.5 | V |
| Operating temperature | -10 | — | 60 | °C |

**Schottky diode forward drop measurements (measured at JANALOG VIN injection):**

| Load Current | Forward Drop (Vf) | Diode Dissipation |
|---|---|---|
| 1.0 A | 0.35 V | 0.35 W |
| 1.5 A | 0.37 V | 0.56 W |
| 2.0 A | 0.39 V | 0.78 W |

---

## 6. Voltage Domains — The #1 Safety Critical Topic

### Three Domains on One Board

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1.8V DOMAIN — MPU (QRB2210) I/O
  • JMEDIA connector (ALL signals)
  • JMISC connector (MPU GPIO pins only — mixed header)
  • JCTL connector (ALL signals)
  • Absolute maximum: 2.1V
  ⚠️ NEVER connect 3.3V or 5V logic to these pins
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  3.3V DOMAIN — MCU (STM32U585) I/O
  • JDIGITAL connector (ALL signals)
  • JANALOG connector (GPIO signals)
  • JSPI connector (ALL signals)
  • QWIIC connector
  • JMISC connector (MCU pins only — mixed header)
  • Most MCU pins are ALSO 5V tolerant in digital mode
  • EXCEPTION: A0, A1 — NOT 5V tolerant
  • Absolute maximum: 3.6V
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ANALOG DOMAIN
  • A0–A5: ADC input range 0V to VREF+ (~3.3V)
  • A0 (PA4), A1 (PA5): absolute max = VDD+0.3V ≈ 3.6V
  • ADC mode removes 5V tolerance even on pins that have it in digital mode
  • A4/A5 as I²C3: use 3.3V pull-ups ONLY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Pin-Level Safety Table

| Signal Bank | Nominal I/O | Absolute Maximum |
|---|---|---|
| Processor I/O (JMEDIA, JMISC MPU pins, JCTL) | 1.8V | 2.1V |
| Maker I/O (JDIGITAL, JANALOG, JSPI, QWIIC) | 3.3V | 3.6V |

### Crossing Voltage Domains

If you need an MPU GPIO (1.8V) to signal an MCU GPIO (3.3V), you **must** use:
- A dedicated bidirectional level-shifter IC, **or**
- An open-drain configuration with a 3.3V pull-up resistor on the MCU side

**Much better option:** Use Bridge RPC software communication instead of direct GPIO wiring between the two processors.

### Critical Voltage Rules (Memorize These)

| Rule | Why It Matters |
|---|---|
| JCTL = 1.8V ONLY | MPU GPIO pins — 3.3V will damage QRB2210 |
| A0, A1 NOT 5V tolerant | ADC input clamp breaks at VDD+0.3V ≈ 3.6V; protection diodes begin conducting |
| ADC pins lose 5V tolerance | Even STM32U585 pads that are 5V tolerant in digital mode lose that tolerance when configured as ADC inputs |
| A4/A5 as I²C: 3.3V pull-ups only | PC1/PC0 = I2C3; 5V pull-ups exceed safe input range |
| JMISC is mixed voltage | MCU pins are 3.3V, MPU GPIO are 1.8V, audio pins are analog — check each pin |
| IOREF is output only | Mirrors 3.3V rail for shield reference. Do NOT back-feed power into it |
| 5V on JANALOG/JSPI = power only | These 5V pins are for powering peripherals, not logic signals |

---

## 7. Connectors & Headers — Complete Map

```
              ┌─────────────────────────────────────────────┐
              │             UNO Q — Top View                 │
  ┌──────┐    │                                             │    ┌──────────┐
  │ JCTL │    │    [8×13 LED Matrix — MCU controlled]       │    │ JDIGITAL │
  │  A1  │    │                                             │    │    A2    │
  │ 10-p │    │   [QRB2210 MPU]         [STM32U585 MCU]    │    │  18 pins │
  │ 1.8V │    │   [LPDDR4X RAM]         [eMMC Storage]     │    │  3.3V    │
  └──────┘    │                                             │    └──────────┘
              │   [WCBN3536A]  [ANX7625]  [PM4125]          │
              │                                             │
  ┌──────┐    │        [USB-C]    [Power Button]            │    ┌──────────┐
  │ JSPI │    │        [PWR LED]                            │    │ JANALOG  │
  │  A5  │    │             [QWIIC A4]                      │    │    A3    │
  │  6-p │    │   [4× RGB LEDs]                             │    │  14 pins │
  │ 3.3V │    │                                             │    │  3.3V    │
  └──────┘    └─────────────────────────────────────────────┘    └──────────┘
         ┌──────────────────────┐    ┌──────────────────────────┐
         │   JMISC (B1) 60-pin  │    │   JMEDIA (B2) 60-pin     │
         │   Mixed 1.8V / 3.3V  │    │   1.8V MIPI signals       │
         └──────────────────────┘    └──────────────────────────┘
```

### Connector Summary

| Connector | Label | Pins | Voltage | Controller | Primary Use |
|---|---|---|---|---|---|
| JDIGITAL | A2 | 18 | 3.3V | MCU | Digital I/O: SPI, I²C, UART, PWM, CAN |
| JANALOG | A3 | 14 | 3.3V | MCU | Analog I/O: ADC, DAC, power |
| JSPI | A5 | 6 | 3.3V | MCU | Dedicated SPI + 5V power pin |
| QWIIC | A4 | 4 | 3.3V | MCU | I²C Qwiic/Modulino ecosystem |
| JCTL | A1 | 10 | **1.8V** | **MPU** | Boot control, debug UART console, PMIC reset |
| JMISC | B1 | 60 | **Mixed** | MCU+MPU | PSSI camera bus, audio, MPU GPIO, power rails |
| JMEDIA | B2 | 60 | **1.8V** | **MPU** | MIPI-CSI camera, MIPI-DSI display |
| USB-C | JUSB1 | — | — | MPU | USB 3.1 + DisplayPort Alt-Mode + Power |

---

## 8. JDIGITAL (A2) — Complete Pin Reference

All 18 pins are 3.3V logic, driven by the STM32U585 MCU.

| Pin | Arduino | MCU Pin | Alt Function 1 | Alt Function 2 | PWM? |
|---|---|---|---|---|---|
| 1 | D0 / RX | PB7 | USART1_RX | TIM4_CH2 | — |
| 2 | D1 / TX | PB6 | USART1_TX | TIM4_CH1 | — |
| 3 | D2 | PB3 | TIM2_CH2 | — | — |
| 4 | ~D3 | PB0 | OPAMP2_OUTPUT | TIM3_CH3 | ✓ |
| 5 | D4 | PA12 | FDCAN1_TX | TIM1_ETR | — |
| 6 | ~D5 | PA11 | FDCAN1_RX | TIM1_CH4 | ✓ |
| 7 | ~D6 | PB1 | TIM3_CH4 | — | ✓ |
| 8 | D7 | PB2 | TIM8_CH4N | — | — |
| 9 | D8 | PB4 | TIM3_CH1 | — | — |
| 10 | ~D9 | PB8 | TIM4_CH3 | — | ✓ |
| 11 | ~D10 | PB9 | SPI2_SS | TIM4_CH4 | ✓ |
| 12 | ~D11 | PB15 | SPI2_MOSI | TIM1_CH3N | ✓ |
| 13 | D12 | PB14 | SPI2_MISO | TIM1_CH2N | — |
| 14 | D13 | PB13 | SPI2_SCK | TIM1_CH1N | — |
| 15 | GND | — | Ground | — | — |
| 16 | AREF | — | Analog reference | — | — |
| 17 | D20 / SDA | PB11 | I2C2_SDA | TIM2_CH4 | — |
| 18 | D21 / SCL | PB10 | I2C2_SCL | TIM2_CH3 | — |

> **SPI sharing:** D10 (SS), D11 (MOSI), D12 (MISO), D13 (SCK) share the **SPI2 peripheral** with the JSPI connector. They cannot be used simultaneously as SPI.

**PWM pins:** D3, D5, D6, D9, D10, D11. PWM frequency is fixed at **500 Hz**. Default resolution is 8-bit (0-255); configurable via `analogWriteResolution()`.

---

## 9. JANALOG (A3) — Complete Pin Reference

| Pin | Label | MCU Pin / Net | Function | Safety Notes |
|---|---|---|---|---|
| 1 | BOOT | MCU_BOOT0 | Boot-mode select | 3.3V |
| 2 | IOREF | PWR_3P3V | I/O voltage reference output | ⚠️ OUTPUT ONLY — do not back-feed |
| 3 | RESET | MCU_NRST | MCU hardware reset | 3.3V |
| 4 | +3V3 | PWR_3P3V | 3.3V supply output | Power rail |
| 5 | +5V | 5V_USB_VBUS | 5V supply (pass-through) | Power only — not for ADC |
| 6 | GND | — | Ground | — |
| 7 | GND | — | Ground | — |
| 8 | VIN | DC_IN | 7–24V power input | Power in — not logic |
| 9 | A0 / D14 | PA4 | ADC, DAC0, TIM2_CH1 | ⚠️ NOT 5V tolerant. Max 3.6V |
| 10 | A1 / D15 | PA5 | ADC, DAC1, TIM3_CH1 | ⚠️ NOT 5V tolerant. Max 3.6V |
| 11 | A2 / D16 | PA6 | ADC, OPAMP2_INPUT+, TIM3_CH2 | Max 3.3V in ADC mode |
| 12 | A3 / D17 | PA7 | ADC, OPAMP2_INPUT− | Max 3.3V in ADC mode |
| 13 | A4 / D18 | PC1 | ADC, I2C3_SDA, LPTIM1_CH1 | 3.3V pull-ups only when used as I²C |
| 14 | A5 / D19 | PC0 | ADC, I2C3_SCL, LPTIM1_IN1 | 3.3V pull-ups only when used as I²C |

**ADC specifications:**
- **Resolution:** Configurable — 14-bit (default, 0–16383), 12, 10, or 8-bit via `analogReadResolution(bits)`
- **Reference:** Default = 3.3V (VREF+). Configurable via `analogReference()`:
  - `AR_INTERNAL1V5` — 1.5V internal
  - `AR_INTERNAL1V8` — 1.8V internal
  - `AR_INTERNAL2V05` — 2.048V internal
  - `AR_INTERNAL2V5` — 2.5V internal
  - `AR_EXTERNAL` — External via AREF pin

**DAC pins:** A0 (PA4) = DAC0, A1 (PA5) = DAC1. Resolution configurable from 8 to 12-bit via `analogWriteResolution()`.

**Measuring 5V signals safely on ADC:** Use a resistor voltage divider (e.g., 10kΩ over 20kΩ → 3.3V at 5V input). Add 100nF capacitor to ground for anti-aliasing. Add ~1kΩ series resistor to limit injection current if the pin clamps.

---

## 10. JSPI (A5), QWIIC (A4), JCTL (A1)

### JSPI (A5) — 6 Pins

| Pin | Label | MCU Pin | Notes |
|---|---|---|---|
| 1 | MISO | PC2 (SPI2_MISO) | 5V tolerant as input |
| 2 | +5V | 5V_USB_VBUS | Power only |
| 3 | SCK | PD1 (SPI2_SCK) | 3.3V |
| 4 | MOSI | PC3 (SPI2_MOSI) | 3.3V |
| 5 | RESET | MCU_NRST | MCU reset |
| 6 | GND | — | — |

> JSPI and JDIGITAL (D10–D13) share **SPI2**. Cannot be used simultaneously.

### QWIIC (A4) — 4 Pins

| Pin | Label | MCU Pin | Notes |
|---|---|---|---|
| 1 | GND | — | Ground |
| 2 | +3V3 | PWR_3P3V | 3.3V supply for Qwiic devices |
| 3 | SDA | PD13 (I2C4_SDA) | Maps to `Wire1` object |
| 4 | SCL | PD12 (I2C4_SCL) | Maps to `Wire1` object |

The QWIIC connector maps to the **secondary I²C bus (I²C4)** using `Wire1.begin()`, not `Wire.begin()`. This is the gateway to the Modulino ecosystem. Note: **3.3V only** — no 5V tolerance here.

### JCTL (A1) — 10 Pins — ALL 1.8V

| Pin | Label | MPU Net | Role |
|---|---|---|---|
| 1 | GND | — | Ground |
| 2 | USB_BOOT | — | Force USB EDL boot mode (jumper this to flash firmware) |
| 3 | VOL_DOWN | GPIO_36 | MPU GPIO |
| 4 | SOC_SE4_TX | — | System UART console TX — DO NOT repurpose |
| 5 | VOL_UP | GPIO_96 | MPU GPIO |
| 6 | SOC_SE4_RX | — | System UART console RX — DO NOT repurpose |
| 7 | GND | — | Ground |
| 8 | PMIC_RESET | — | Resets PM4125 PMIC |
| 9 | +1V8 | VREG_L15A_1P8V | 1.8V reference output |
| 10 | VBUS_DISABLE | — | Disables USB VBUS power switch |

> **SE4 UART (pins 4 & 6):** This is the hardware debug console — the low-level shell that shows early boot logs before SSH is available. Use a **1.8V** USB-to-TTL converter at 115200 baud. Never connect user hardware here.

> **USB_BOOT (pin 2):** Shorting this to GND before connecting USB puts the board into Emergency Download Mode (EDL, USB VID 05C6 PID 9008) for firmware flashing. Always remove the jumper before normal boot.

---

## 11. JMISC (B1) — 60-Pin Mixed Header

JMISC carries three distinct signal families in one 60-pin connector:

**MCU signals at 3.3V (pins 1–25):**
- PSSI (parallel camera/sensor bus): D0–D7, PDCK, RDY, DE (PC6–PC9, PE4, PI4, PI6, PI7, PD9, PI5, PD8)
- SDMMC1 CMD test pin (PD2)
- ETM Trace: CLK (PE2), D0 (PE3), D2 (PE5), D3 (PE6)
- GPIO: PE7, PE8
- I²C4: SCL (PF14), SDA (PF15) — separate instance from QWIIC's I²C4 on PD12/13
- MCU clock out (PA8), CRS sync (PA10)
- OPAMP1: VOUT (PA3), VINP (PA0), VINM (PA1) — analog pins

**Audio signals (analog, pins 28–42):**
- Mic2: INP, INM, BIAS
- Headphone: L, R, REF
- LineOut: P, M
- Earpiece: P_R, M_R
- Headset detect (HS_DET)

**MPU SoC GPIO at 1.8V (pins 37–52):**
- SE0 bank: GPIO_0, 1, 2, 3, 86, 82 (interface-dedicated, reserved in Linux device tree)
- General: GPIO_18, 28, 98, 99, 100, 101

**Power rails (pins 53–60):**
- +3V3 (OUT) × 2
- +5V_USB (OUT) × 2
- +1V8 (IN)
- VCOIN (IN) — PMIC RTC only
- VBAT (IN) — MCU RTC only
- GND

> **Key rule:** MCU pins at 3.3V, MPU GPIO at 1.8V. Check each pin before connecting anything. SoC GPIO lines on JMISC are NOT maker GPIO — they are interface-dedicated and reserved in the Linux device tree.

---

## 12. JMEDIA (B2) — 60-Pin High-Speed Header

JMEDIA carries high-speed differential signals. **These are NOT general-purpose I/O.**

| Signal Group | Pins | Purpose |
|---|---|---|
| MIPI-DSI (4-lane) | CLK+/−, L0–L3 +/− | Display output to ANX7625 chip |
| MIPI-CSI0 (4-lane) | LN0–LN3 +/−, CLK+/− | Camera 0 input |
| MIPI-CSI1 (4-lane) | LN0–LN3 +/−, CLK+/− | Camera 1 input |
| CCI I²C camera control | SDA0/SCL0 (GPIO_22/23), SDA1/SCL1 (GPIO_29/30) | I²C bus for camera modules |
| Camera master clocks | MCLK0 (GPIO_20), MCLK1 (GPIO_21) | Clock out to image sensors |
| Power | VIN (7-24V in) × 2, +3V3 (out) × 2, GND × many | Power rails |

MIPI lanes are D-PHY differential pairs — impedance-controlled traces. Do not add loads, stubs, or pull-resistors on carrier boards.

---

## 13. UI & Indicators — Complete Reference

### LED Matrix

- **Layout:** 8 rows × 13 columns = **104 monochrome blue LEDs**
- **Driver:** STM32U585 MCU via `Arduino_LED_Matrix` library
- **Grayscale:** 3-bit (8 levels, 0–7) or 8-bit (0–255, auto-mapped) via `setGrayscaleBits()`
- **Boot behavior:** Shows Arduino logo animation for ~20–30 seconds during Linux startup
- **Warning:** Do not access the matrix until boot animation completes

```cpp
// Example: Draw custom 8×13 frame
#include <Arduino_LED_Matrix.h>
uint8_t frame[104] = { /* 0=off, 1=on, values per pixel */ };
Arduino_LED_Matrix matrix;
void setup() {
  matrix.begin();
  matrix.setGrayscaleBits(1);  // 1-bit = on/off only
  matrix.draw(frame);
}
```

### RGB LEDs — 4 Total, Split Control

**MPU-controlled (Linux `/sys/class/leds/`):**

| LED | Component | Red | Green | Blue | Default Meaning |
|---|---|---|---|---|---|
| RGB LED 1 (D27301) | QRB2210 GPIO | GPIO_41 (red:user) | GPIO_42 (green:user) | GPIO_60 (blue:user) | User-controlled |
| RGB LED 2 (D27302) | QRB2210 GPIO | GPIO_39 (red:panic) | GPIO_40 (green:wlan) | GPIO_47 (blue:bt) | System status |

LED 2 defaults: red = kernel panic, green = WiFi activity, blue = Bluetooth. Can be overridden.

**Control from Linux shell:**
```bash
echo 1 | tee /sys/class/leds/red:user/brightness   # ON
echo 0 | tee /sys/class/leds/green:wlan/brightness  # OFF
```

**Control from Python:**
```python
from arduino.app_utils import Leds
Leds.set_led1_color(1, 0, 0)  # LED1 red (R, G, B)
Leds.set_led2_color(0, 1, 0)  # LED2 green
```

**MCU-controlled (Arduino sketch `digitalWrite()`):**

| LED | Component | Red | Green | Blue |
|---|---|---|---|---|
| RGB LED 3 (D27401) | STM32U585 | LED3_R (PH10) | LED3_G (PH11) | LED3_B (PH12) |
| RGB LED 4 (D27402) | STM32U585 | LED4_R (PH13) | LED4_G (PH14) | LED4_B (PH15) |

> **Active-low:** All four RGB LEDs turn ON when their pin is driven to logic `0` (LOW). Writing HIGH turns them off.

```cpp
// MCU sketch to cycle LED3 colors
void setup() {
  pinMode(LED3_R, OUTPUT); pinMode(LED3_G, OUTPUT); pinMode(LED3_B, OUTPUT);
  digitalWrite(LED3_R, HIGH); digitalWrite(LED3_G, HIGH); digitalWrite(LED3_B, HIGH); // all off
}
void loop() {
  digitalWrite(LED3_R, LOW);  delay(1000);  // red on
  digitalWrite(LED3_R, HIGH); digitalWrite(LED3_G, LOW);  delay(1000);  // green on
  digitalWrite(LED3_G, HIGH); digitalWrite(LED3_B, LOW);  delay(1000);  // blue on
  digitalWrite(LED3_B, HIGH);
}
```

### Power LED (D27201)

Green LED tied to the 3.3V rail. On = board has power. Cannot be software-controlled.

### Power Button (JBTN1)

- **Long press (≥5 seconds):** Reboots the Linux environment (MPU). Does NOT cut power to the board.
- **Normal boot:** Automatic on power application — button press is NOT required.

---

## 14. USB-C Connector — Full Capabilities

| Feature | Description |
|---|---|
| Power input | 5V / 3A (15W) — USB PD negotiates only 5V/3A |
| USB standard | USB 3.1 Gen 1 (5 Gb/s) |
| Display | DisplayPort Alt-Mode via ANX7625 bridge |
| Role switching | Host / Device / OTG |

**Via USB-C dongle:**

| Feature | Description |
|---|---|
| Video | HDMI output |
| Camera | USB camera input |
| Audio | USB or 3.5mm headset |
| Ethernet | Wired internet |
| HID | Keyboard, mouse |
| Storage | USB drive, microSD |

> **⚠️ Trade-off:** When DisplayPort Alt-Mode is active, USB data speed is reduced. The SuperSpeed lanes are shared between DP and USB 3.1 data.

> **USB-C hub compatibility:** Do NOT use Apple USB-C dongles — they are incompatible with the UNO Q. Tested working: Anker USB-C Hub, Noovoo USB Hub (includes Ethernet).

---

## 15. Digital I/O — Programming Reference

### Configuration

```cpp
#include <Arduino_RouterBridge.h>  // required for Bridge + Monitor

void setup() {
  pinMode(D5, OUTPUT);              // set as output
  pinMode(D4, INPUT_PULLUP);        // set as input with internal pull-up
  Monitor.begin();                   // use Monitor, not Serial, for App Lab console
}

void loop() {
  int state = digitalRead(D4);      // read input
  digitalWrite(D5, state ? HIGH : LOW);  // write output
  Monitor.println(state);            // print to App Lab console
}
```

> **Serial vs Monitor:** `Serial.println()` sends over UART (D0/D1) and does NOT appear in the App Lab console. Use `Monitor.println()` instead.

### I²C

```cpp
#include <Wire.h>
Wire.begin();   // Primary I²C: D20 (SDA/PB11) + D21 (SCL/PB10) — UNO headers
Wire1.begin();  // Secondary I²C: Qwiic connector PD13/PD12 (I²C4)
```

### SPI

```cpp
#include <SPI.h>
#define SS D10
SPI.begin();           // SCK=D13, MOSI=D11, MISO=D12
digitalWrite(SS, LOW); // select device
SPI.transfer(0x35);    // send byte
digitalWrite(SS, HIGH);
```

### UART

```cpp
Serial.begin(115200);   // D0=RX (PB7), D1=TX (PB6) — hardware UART
// Note: Serial goes over physical pins, not App Lab console
// For App Lab console output, use Monitor.print()
```

### PWM

```cpp
analogWriteResolution(10);  // 10-bit = 0–1023
analogWrite(D3, 512);       // ~50% duty cycle on D3 (PB0)
// PWM pins: D3, D5, D6, D9, D10, D11
// Fixed frequency: 500 Hz
```

---

## 16. Wireless Connectivity

### WiFi

The WCBN3536A module connects to the QRB2210 via SDIO for WiFi data. From the Linux side, WiFi is managed by NetworkManager (`nmcli`):

```bash
# Connect to WiFi
sudo nmcli device wifi connect "MyNetwork" password "mypassword"

# Disconnect
sudo nmcli device disconnect wlan0

# Forget network
sudo nmcli connection delete "MyNetwork"

# WPA2-Enterprise (e.g., Eduroam)
nmcli con add type wifi connection.id Eduroam wifi.ssid eduroam \
  wifi.mode infrastructure wifi-sec.key-mgmt wpa-eap \
  802-1x.eap peap 802-1x.phase2-auth mschapv2 \
  802-1x.identity "your@identity"
```

**From MCU sketch** (using Bridge for TCP over WiFi):
```cpp
#include <Arduino_RouterBridge.h>
BridgeTCPClient<> client(Bridge);

if (client.connect("time.nist.gov", 13)) {
  // WiFi TCP connection tunneled through Bridge to Linux WiFi stack
}
```

### Bluetooth

Bluetooth is controlled by BlueZ on the Linux side:

```bash
bluetoothctl power on          # turn on
bluetoothctl scan on           # scan for devices
bluetoothctl connect AA:BB:CC:DD:EE:FF  # pair by MAC
```

From Python (using D-Bus/BlueZ), the BLE GATT server can expose custom services. See the BLE App section in Part 4 for complete implementation.

---

## 17. Critical Warnings Reference Card

Copy this mentally before touching any hardware:

```
⚠️  JCTL pins = 1.8V ONLY. 3.3V will damage QRB2210.
⚠️  A0, A1 (PA4, PA5) = NOT 5V tolerant. Max 3.6V absolute.
⚠️  ADC mode removes 5V tolerance from ALL analog pins.
⚠️  A4, A5 as I²C: use 3.3V pull-ups only.
⚠️  JMISC is mixed voltage — check EACH pin before connecting.
⚠️  JSPI + JDIGITAL D10-D13 share SPI2 — cannot use both simultaneously.
⚠️  IOREF is output only — do NOT back-feed power into it.
⚠️  Do NOT open /dev/ttyHS1 (Linux) or Serial1 (MCU sketch).
⚠️  Do NOT access LED matrix during Linux boot animation (~20-30s).
⚠️  Do NOT use CCI I²C lines (JMEDIA) as general-purpose GPIO.
⚠️  DisplayPort Alt-Mode reduces USB data speed to USB 2.0 speeds.
⚠️  Reverse polarity on VIN: protection verified to -24V, but don't do it.
```

---

## 18. First-Principles Challenge Questions (Part 1)

Work through these before proceeding to Part 2:

**Q1 — Architecture:** Why can't a Linux kernel guarantee that `digitalWrite()` will toggle a pin in exactly 10 microseconds? Name the specific kernel subsystem that makes this impossible.

**Q2 — Power:** The board uses a Schottky diode OR circuit. If you connect a 12V DC supply AND a 5V USB-C simultaneously, what happens? Which source "wins" on 5V_SYS, and why is there a voltage drop to consider?

**Q3 — Voltage domains:** You have a 5V sensor with a push-pull digital output. You want to connect it to D4 (PA12). Is this safe? What about connecting it to A0 (PA4) configured as ADC? What changes between these two cases?

**Q4 — Power sequencing:** Why does the 3.3V rail come up BEFORE the 1.8V rail? What would happen if they came up in the opposite order?

**Q5 — LED matrix:** The LED matrix is driven by the MCU, not the MPU. Yet the documentation says "do not access it until Linux boot completes." What does the Linux boot process have to do with an MCU-driven peripheral?

---

*End of Part 1. Continue to Part 2: App Lab, Bridge RPC & Development Environment.*
