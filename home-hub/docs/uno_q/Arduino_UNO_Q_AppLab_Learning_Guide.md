# Arduino UNO Q — AppLab Learning Guide

> **First-Principles Edition** — Not just *what*, but *why* and *how it works underneath*.
> Sources: Official Arduino UNO Q Datasheet (ABX00162/ABX00173), Full Pinout (17 Feb 2026), Schematics, and AppLab field notes.

---

## Table of Contents

1. [What is the Arduino UNO Q? — The Big Picture](#1-what-is-the-arduino-uno-q--the-big-picture)
2. [The Dual-Processor Architecture — Why Two Chips?](#2-the-dual-processor-architecture--why-two-chips)
3. [Hardware Specifications at a Glance](#3-hardware-specifications-at-a-glance)
4. [Power System — How the Board Stays Alive](#4-power-system--how-the-board-stays-alive)
5. [Voltage Domains — The #1 Danger Zone](#5-voltage-domains--the-1-danger-zone)
6. [Connectors & Headers — The Full Map](#6-connectors--headers--the-full-map)
7. [Pin Reference — JDIGITAL & JANALOG (Your Primary Playground)](#7-pin-reference--jdigital--janalog-your-primary-playground)
8. [Pin Reference — JSPI, QWIIC, JCTL](#8-pin-reference--jspi-qwiic-jctl)
9. [Pin Reference — JMISC & JMEDIA (Advanced)](#9-pin-reference--jmisc--jmedia-advanced)
10. [UI & Indicators — The Board Speaks to You](#10-ui--indicators--the-board-speaks-to-you)
11. [Bridge RPC — How the Two Processors Talk](#11-bridge-rpc--how-the-two-processors-talk)
12. [Arduino App Lab — The Unified Development Environment](#12-arduino-app-lab--the-unified-development-environment)
13. [Bricks — Modular Building Blocks](#13-bricks--modular-building-blocks)
14. [App Structure — Anatomy of an App Lab Project](#14-app-structure--anatomy-of-an-app-lab-project)
15. [Real-World Field Notes from AppLab Testing](#15-real-world-field-notes-from-applab-testing)
16. [Critical Warnings & Safety Rules — Never Forget These](#16-critical-warnings--safety-rules--never-forget-these)
17. [First-Principles Challenge Questions](#17-first-principles-challenge-questions)

---

## 1. What is the Arduino UNO Q? — The Big Picture

The Arduino UNO Q is **not a classic microcontroller board**. It is a **single-board computer (SBC)** that fuses two completely different computing paradigms onto one PCB:

| Layer | What it is | Why it exists |
|---|---|---|
| **Application Processor (MPU)** | Qualcomm QRB2210, runs full Debian Linux | To handle AI, networking, complex logic, high-level software |
| **Real-Time Microcontroller (MCU)** | STM32U585, runs Zephyr OS + Arduino Core | To handle precise timing, GPIO, PWM, ADC — things Linux can't do reliably |

**Why does this matter?** A Linux kernel is a general-purpose OS. It was never designed to guarantee that a GPIO pin toggles in *exactly* 10 microseconds. Interrupt latency is non-deterministic. An MCU running bare-metal or a real-time OS (RTOS) *can* make that guarantee. The UNO Q gives you both worlds on one board.

**The form factor** is UNO-compatible (68.58 mm × 53.34 mm), so existing shields and carrier boards still mechanically fit — but the electrical compatibility depends on voltage levels (see Section 5).

**Board variants:**

| SKU | RAM | Storage |
|---|---|---|
| ABX00162 | 2 GB LPDDR4X | 16 GB eMMC |
| ABX00173 | 4 GB LPDDR4X | 32 GB eMMC |

> **First-Principles Question:** Why would a Linux system be bad at toggling a GPIO pin at a precise frequency? Think about what a kernel scheduler does, and when it might preempt your code.

---

## 2. The Dual-Processor Architecture — Why Two Chips?

### The MPU: Qualcomm Dragonwing™ QRB2210

```
Qualcomm QRB2210
├── 4× ARM Cortex-A53 cores @ 2.0 GHz (64-bit)
├── Adreno 702 GPU @ 845 MHz  ← 3D graphics & ML acceleration
├── Dual ISPs: 13MP + 13MP, or 25MP @ 30fps  ← machine vision
├── Debian Linux (upstream support)
├── I/O voltage: 1.8V
└── Interfaces: USB 3.1, SDIO 3.0, MIPI-CSI-2 (4-lane), MIPI-DSI (4-lane)
```

The MPU handles: WiFi/BT (via WCBN3536A module), USB-C role switching & Power Delivery negotiation, DisplayPort output (via ANX7625 bridge chip), camera input, and high-level application logic running in Python or any Linux language.

### The MCU: STMicroelectronics STM32U585

```
STM32U585
├── ARM Cortex-M33 @ up to 160 MHz
├── Arduino Core on Zephyr OS  ← your .ino sketches run here
├── 2 MB Flash, 786 kB SRAM
├── I/O voltage: 3.3V
└── Manages: ADC, PWM, CAN, LED matrix, timers, SPI, I²C, UART
```

The MCU handles: all real-time I/O, the 8×13 LED matrix, driving the 3.3V headers (JDIGITAL, JANALOG, JSPI, Qwiic), and executing Arduino sketches with deterministic timing.

### How They Relate

```
┌─────────────────────────────────────────────────────┐
│                    UNO Q Board                       │
│                                                      │
│  ┌──────────────────┐    Bridge RPC    ┌──────────┐  │
│  │  QRB2210 (MPU)   │◄────────────────►│ STM32U585│  │
│  │  Debian Linux    │  (USB CDC/UART/  │  (MCU)   │  │
│  │  Python runs     │   SPI transport) │ .ino runs│  │
│  │  here            │                  │ here     │  │
│  └──────────────────┘                  └──────────┘  │
│         │                                    │        │
│    JMEDIA, JMISC                    JDIGITAL, JANALOG │
│    JCTL (1.8V)                      JSPI, QWIIC (3.3V)│
└─────────────────────────────────────────────────────┘
```

The two processors **share no memory**. They communicate exclusively through the **Bridge RPC layer** — a software messaging system that runs on both sides and lets each processor call functions on the other.

---

## 3. Hardware Specifications at a Glance

### Processing & Memory

| Component | Specification |
|---|---|
| MPU | Qualcomm QRB2210 — 4× Cortex-A53 @ 2.0 GHz, 64-bit |
| GPU | Adreno 702 @ 845 MHz |
| MCU | STM32U585 — Cortex-M33 @ up to 160 MHz |
| MCU Flash | 2 MB |
| MCU SRAM | 786 kB |
| System RAM | 2 GB or 4 GB LPDDR4X |
| Storage | 16 GB or 32 GB eMMC |

### Connectivity

| Feature | Detail |
|---|---|
| Wi-Fi | 802.11a/b/g/n/ac (dual-band 2.4 GHz + 5 GHz) — Wi-Fi 5 |
| Bluetooth | BT 5.1 |
| Wireless Chip | WCBN3536A (Qualcomm WCN3980) |
| Wireless Interface | SDIO (for Wi-Fi data) + UART (for BT control) |
| USB | USB 3.1 with role-switching (host/device/OTG) |
| USB Power Delivery | 5 V / 3 A only (no higher voltage PD profiles) |
| DisplayPort | Via ANX7625 MIPI-DSI → DP Alt-Mode bridge |

### Board Dimensions

- **Size:** 68.58 mm × 53.34 mm
- **Form factor:** UNO-compatible mounting holes and header layout
- **Bottom-side parts:** kept below 2 mm for carrier board stacking

---

## 4. Power System — How the Board Stays Alive

### Two Input Paths

The UNO Q accepts power from two sources, **simultaneously if needed**:

```
USB-C VBUS (5V, up to 3A)  ──┐
                               ├──[Schottky OR]──► 5V_SYS
DC VIN (7–24V) → [Buck]──5V ──┘
```

Both paths are **diode-OR combined** through Schottky rectifiers. This means:
- If both are connected, the higher-voltage source dominates (after diode drop)
- There is **no conflict** — they don't fight each other
- There is a small forward voltage drop (Vf) across the Schottky:
  - At 1.0 A load: Vf = 0.35 V, dissipating 0.35 W as heat
  - At 2.0 A load: Vf = 0.39 V, dissipating 0.78 W as heat

> **Why Schottky diodes?** Schottky diodes have very low forward voltage drop (0.3–0.4 V instead of silicon's 0.6–0.7 V), making them ideal for power-path OR-ing with minimal loss.

### Power Rail Derivation Tree

```
USB-C VBUS (5V)  OR  DC VIN (7-24V) via Buck
             │
             ▼
          5V_SYS  ──────────────────────────────────────────
             │                                              │
    [Buck: Step-down]                              PM4125 PMIC (L15A LDO)
             │                                              │
          3.8V (PWR_3P8V)                              1.8V (VREG_L15A_1P8V)
             │                          Powers: SoC I/O, ANX7625, WiFi digital,
    [Buck: Step-down]                   on-board level shifters, JMISC
             │
          3.3V (PWR_3P3V)
          Powers: STM32U585, ANX7625 (3.3V rails), WiFi 3.3V,
                  3.3V header pins (JDIGITAL, JANALOG, JSPI, Qwiic)
```

### Operating Limits

| Parameter | Min | Typical | Max | Unit |
|---|---|---|---|---|
| USB-C VBUS | 4.5 | 5.0 | 5.5 | V |
| DC Input (VIN) | 7.0 | — | 24.0 | V |
| 3.3V Rail (PWR_3P3V) | 3.1 | 3.3 | 3.5 | V |
| Operating temperature | -10 | — | 60 | °C |

### Special Power Pins

- **VCOIN:** Powers only the PMIC's real-time clock (not the Linux or MCU domains). Think of it as a coin-cell backup for the RTC.
- **VBAT:** Powers only the MCU's real-time clock.
- **5V pin (JANALOG):** A regulated 5V input path — can be used as an alternative to USB-C to power the board directly.

> **Observed startup behavior:** Startup current stays below 200 mA during the boot animation sequence. Running WiFi + a couple of apps stays below 500 mA average — well within a USB3 port's 900 mA limit.

---

## 5. Voltage Domains — The #1 Danger Zone

This is the single most critical concept to internalize before touching any external hardware.

### The Three Domains

```
┌─────────────────────────────────────────────────┐
│  1.8V Domain — MPU (QRB2210) GPIO               │
│  • JMEDIA connector (all signals)                │
│  • JMISC connector (MPU GPIO pins only)          │
│  • JCTL connector (all signals)                  │
│  • WARNING: Never connect 3.3V or 5V logic here! │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  3.3V Domain — MCU (STM32U585) GPIO             │
│  • JDIGITAL connector (all signals)              │
│  • JANALOG connector (GPIO signals)              │
│  • JSPI connector (all signals)                  │
│  • QWIIC connector                               │
│  • JMISC connector (MCU pins only)               │
│  • Most pins are also 5V tolerant (digital mode) │
│  • EXCEPTION: A0, A1 — NOT 5V tolerant          │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Analog Domain                                   │
│  • A0–A5: ADC input range 0 V to VREF+ (~3.3V)  │
│  • A0, A1 (PA4, PA5): absolute max = VDD+0.3V   │
│    ≈ 3.6V. Above this, protection diodes conduct │
│  • Audio pins on JMISC                           │
└─────────────────────────────────────────────────┘
```

### Critical Rules

| Rule | Why |
|---|---|
| **JCTL pins are 1.8V ONLY** | Applying 3.3V will damage the MPU |
| **A0 and A1 are NOT 5V tolerant** | The STM32U585's ADC input clamp breaks at VDD+0.3V ≈ 3.6V |
| **A4, A5 as I²C: use 3.3V pull-ups only** | These pins map to I2C3 (PC1/PC0); 5V pull-ups will exceed safe input range |
| **JMISC is mixed voltage** | MCU pins are 3.3V, MPU GPIO are 1.8V — check each pin before connecting |
| **ADC pins in analog mode are NOT 5V tolerant** | Even if the same pin is 5V tolerant in digital mode, analog mode removes that tolerance |
| **IOREF is output only** | It mirrors the 3.3V rail for shield compatibility. Do not back-feed power into it |

### Level Shifting Between MPU and MCU

If you need an MPU GPIO (1.8V) to signal an MCU GPIO (3.3V), you **must** use:
- A dedicated level-shifter IC, **or**
- An open-drain configuration with a pull-up to the MCU's 3.3V rail

The Bridge RPC layer handles software-level communication without you needing level shifters — use Bridge instead of direct GPIO wiring between the two processors wherever possible.

---

## 6. Connectors & Headers — The Full Map

```
                    ┌──────────────────────┐
                    │      UNO Q Top View  │
     ┌──────┐       │                      │  ┌──────────┐
     │ JCTL │       │  [LED Matrix 8×13]   │  │ JDIGITAL │
     │ A1   │       │                      │  │ A2       │
     │ 10p  │       │  [QRB2210]  [STM32]  │  │ 18 pins  │
     │ 1.8V │       │                      │  │ 3.3V MCU │
     └──────┘       │  [WCBN3536A] [eMMC]  │  └──────────┘
                    │                      │
     ┌──────┐       │  [ANX7625]  [PM4125] │  ┌──────────┐
     │ JSPI │       │                      │  │ JANALOG  │
     │ A5   │       │          [QWIIC A4]  │  │ A3       │
     │ 6p   │       │                      │  │ 14 pins  │
     │ 3.3V │       └──────────────────────┘  │ 3.3V MCU │
     └──────┘                                  └──────────┘
         ┌───────────────────┐  ┌───────────────────────┐
         │ JMISC (B1) 60-pin │  │ JMEDIA (B2) 60-pin    │
         │ Mixed 1.8V/3.3V   │  │ 1.8V MIPI signals     │
         └───────────────────┘  └───────────────────────┘
```

### Connector Summary Table

| Connector | Label | Pins | Voltage | Owner | Primary Use |
|---|---|---|---|---|---|
| JDIGITAL | A2 | 18 | 3.3V | MCU | Digital I/O: SPI, I²C, UART, PWM, CAN |
| JANALOG | A3 | 14 | 3.3V | MCU | Analog I/O: ADC, DAC, power |
| JSPI | A5 | 6 | 3.3V | MCU | Dedicated SPI port + 5V power |
| QWIIC | A4 | 4 | 3.3V | MCU | I²C (Qwiic ecosystem) |
| JCTL | A1 | 10 | **1.8V** | **MPU** | Boot control, UART console, PMIC reset |
| JMISC | B1 | 60 | Mixed | MCU+MPU | Parallel camera (PSSI), trace, audio, misc GPIO |
| JMEDIA | B2 | 60 | **1.8V** | **MPU** | MIPI-CSI camera, MIPI-DSI display |
| USB-C | JUSB1 | — | — | MPU | USB 3.1 + DisplayPort Alt-Mode + Power |

---

## 7. Pin Reference — JDIGITAL & JANALOG (Your Primary Playground)

These two connectors are where you do most of your sketch-based hardware work. They are driven by the STM32U585 MCU at 3.3V logic.

### JDIGITAL (A2) — 18 Pins

| Pin | Arduino Label | MCU Pin | Key Alternate Functions | PWM? |
|---|---|---|---|---|
| 1 | D0 | PB7 | USART1_RX, TIM4_CH2 | — |
| 2 | D1 | PB6 | USART1_TX, TIM4_CH1 | — |
| 3 | D2 | PB3 | TIM2_CH2 | — |
| 4 | ~D3 | PB0 | OPAMP2_OUTPUT, TIM3_CH3 | ✓ |
| 5 | D4 | PA12 | FDCAN1_TX, TIM1_ETR | — |
| 6 | ~D5 | PA11 | FDCAN1_RX, TIM1_CH4 | ✓ |
| 7 | ~D6 | PB1 | TIM3_CH4 | ✓ |
| 8 | D7 | PB2 | TIM8_CH4N | — |
| 9 | D8 | PB4 | TIM3_CH1 | — |
| 10 | ~D9 | PB8 | TIM4_CH3 | ✓ |
| 11 | ~D10 | PB9 | SPI2_SS, TIM4_CH4 | ✓ |
| 12 | ~D11 | PB15 | SPI2_MOSI, TIM1_CH3N | ✓ |
| 13 | D12 | PB14 | SPI2_MISO, TIM1_CH2N | — |
| 14 | D13 | PB13 | SPI2_SCK, TIM1_CH1N | — |
| 15 | GND | — | — | — |
| 16 | AREF | — | Analog reference | — |
| 17 | D20 | PB11 | I2C2_SDA, TIM2_CH4 | — |
| 18 | D21 | PB10 | I2C2_SCL, TIM2_CH3 | — |

> **Note:** D13/D12/D11/D10 share the SPI2 peripheral with the JSPI connector. They **cannot** be used as SPI and regular GPIO simultaneously.

### JANALOG (A3) — 14 Pins

| Pin | Label | MCU Pin / Net | Function | Notes |
|---|---|---|---|---|
| 1 | BOOT | MCU_BOOT0 | Boot-mode select | 3.3V |
| 2 | IOREF | PWR_3P3V | I/O voltage reference | Output only — do not back-feed |
| 3 | RESET | MCU_NRST | MCU hardware reset | 3.3V |
| 4 | +3V3 | PWR_3P3V | 3.3V supply out | Power |
| 5 | +5V | 5V_USB_VBUS | 5V supply (pass-through) | Power only |
| 6 | GND | — | Ground | — |
| 7 | GND | — | Ground | — |
| 8 | VIN | DC_IN | 7–24V power input | Power in |
| 9 | A0 / D14 | PA4 | ADC, DAC0, TIM2_CH1 | ⚠️ NOT 5V tolerant |
| 10 | A1 / D15 | PA5 | ADC, DAC1, TIM3_CH1 | ⚠️ NOT 5V tolerant |
| 11 | A2 / D16 | PA6 | ADC, OPAMP2_INPUT+, TIM3_CH2 | 3.3V max |
| 12 | A3 / D17 | PA7 | ADC, OPAMP2_INPUT− | 3.3V max |
| 13 | A4 / D18 | PC1 | ADC, I2C3_SDA, LPTIM1_CH1 | 3.3V pull-ups only |
| 14 | A5 / D19 | PC0 | ADC, I2C3_SCL, LPTIM1_IN1 | 3.3V pull-ups only |

> **ADC Reference:** All analog inputs are referenced to VREF+ which is tied to the 3.3V rail. Maximum valid input = 3.3V. Absolute maximum at A0/A1 = VDD + 0.3V ≈ 3.6V.

---

## 8. Pin Reference — JSPI, QWIIC, JCTL

### JSPI (A5) — 6 Pins

| Pin | Label | MCU Pin | Notes |
|---|---|---|---|
| 1 | MISO | PC2 (SPI2_MISO) | 5V tolerant as input |
| 2 | +5V | 5V_USB_VBUS | Power only |
| 3 | SCK | PD1 (SPI2_SCK) | |
| 4 | MOSI | PC3 (SPI2_MOSI) | |
| 5 | RESET | MCU_NRST | MCU reset |
| 6 | GND | — | |

> JSPI and JDIGITAL (D10–D13) share the **SPI2 MCU peripheral**. If you use JSPI for an external device, you cannot use D10–D13 as SPI simultaneously.

### QWIIC (A4) — 4 Pins

| Pin | Label | MCU Pin | Notes |
|---|---|---|---|
| 1 | GND | — | Ground |
| 2 | +3V3 | PWR_3P3V | Supply for Qwiic devices |
| 3 | SDA | PD13 (I2C4_SDA) | 3.3V |
| 4 | SCL | PD12 (I2C4_SCL) | 3.3V |

The Qwiic connector is the primary entry point for the **Modulino® ecosystem** — plug-and-play sensor/actuator nodes (Knob, Pixels, Distance, Movement, Buzzer, Thermo, Buttons).

### JCTL (A1) — 10 Pins — ⚠️ ALL 1.8V

| Pin | Label | MPU GPIO / Net | Role |
|---|---|---|---|
| 1 | GND | — | Ground |
| 2 | USB_BOOT | — | Force USB boot mode (bootstrap) |
| 3 | VOL_DOWN | GPIO_36 | MPU GPIO |
| 4 | SOC_SE4_TX | — | System console UART TX — **do not repurpose** |
| 5 | VOL_UP | GPIO_96 | MPU GPIO |
| 6 | SOC_SE4_RX | — | System console UART RX — **do not repurpose** |
| 7 | GND | — | Ground |
| 8 | PMIC_RESET | — | Resets PM4125 PMIC |
| 9 | +1V8 | VREG_L15A_1P8V | 1.8V reference output |
| 10 | VBUS_DISABLE | — | Disables USB VBUS power switch |

> The SE4 UART (pins 4 & 6) is the **system debug console**. It is separate from any application UART and should never be connected to user hardware.

---

## 9. Pin Reference — JMISC & JMEDIA (Advanced)

### JMISC (B1) — 60 Pins — Mixed Domain

JMISC is the most complex connector on the board. It carries **three different signal families in one connector**:

1. **MCU signals at 3.3V** — PSSI (parallel camera bus), SDMMC1 test, TRACE, I²C4, OPAMP1, MCO, CRS_SYNC (pins 1–25)
2. **Audio signals (analog)** — Mic2, Headphone L/R, LineOut, Earpiece, HS_DET (pins 28–42)
3. **MPU SoC GPIO at 1.8V** — GPIO banks SE0 and others (pins 37–52)
4. **Power rails** — +3V3 (out), +5V_USB (out), +1V8 (in), VCOIN (in), VBAT (in), GND (pins 53–60)

**Before connecting anything to JMISC, always check whether a given pin is MCU (3.3V), MPU (1.8V), or analog.**

Key callouts:
- **OPAMP1 pins** (PA0, PA1, PA3): Analog — these expose the STM32U585's internal operational amplifier
- **SoC GPIO SE0 bank**: Interface-dedicated (not maker GPIO) — reserved in the Linux device tree
- **I²C4** on JMISC (PF14/PF15) is separate from the Qwiic I²C4 (PD12/PD13)

### JMEDIA (B2) — 60 Pins — 1.8V Only

JMEDIA carries high-speed differential signals. These are **not general-purpose I/O**.

| Signal Group | Signals | Purpose |
|---|---|---|
| MIPI-DSI (4-lane) | CLK+/−, L0–L3 +/− | Display output (to ANX7625) |
| MIPI-CSI0 (4-lane) | LN0–LN3 +/−, CLK+/− | Camera 0 input |
| MIPI-CSI1 (4-lane) | LN0–LN3 +/−, CLK+/− | Camera 1 input |
| CCI I²C (Camera Control) | SDA0/1, SCL0/1 (GPIO_22/23/29/30) | I²C for camera modules |
| Camera clocks | SOC_CAM_MCLK0 (GPIO_20), MCLK1 (GPIO_21) | Master clock out to camera sensors |
| Power | VIN (in), +3V3 (out), GND | Power rails |

> MIPI lanes are D-PHY differential pairs. Treat them like PCIe or USB SuperSpeed lanes — impedance-matched traces, no loose connections.

---

## 10. UI & Indicators — The Board Speaks to You

### RGB LEDs

The UNO Q has four RGB LEDs — two controlled by the MPU (Linux), two by the MCU (Arduino sketch).

**MPU-controlled (via `/sys/class/leds/` in Linux):**

| LED | Component | Red | Green | Blue |
|---|---|---|---|---|
| RGB LED 1 (D27301) | MPU GPIO | GPIO_41 (user) | GPIO_42 (user) | GPIO_60 (user) |
| RGB LED 2 (D27302) | MPU GPIO | GPIO_39 (panic) | GPIO_40 (wlan) | GPIO_47 (bt) |

RGB LED 2 has a **default system meaning**: its channels indicate kernel panic, WiFi activity, and Bluetooth state. It can be overridden by user code.

**MCU-controlled (via Arduino sketch):**

| LED | Component | Red | Green | Blue |
|---|---|---|---|---|
| RGB LED 3 (D27401) | STM32U585 | PH10 | PH11 | PH12 |
| RGB LED 4 (D27402) | STM32U585 | PH13 | PH14 | PH15 |

> **Active-low logic:** All RGB LEDs turn ON when the pin is driven to logic `0`. Writing `LOW` lights them up, `HIGH` turns them off.

### LED Matrix (D27001–D27104)

- **Layout:** 8 rows × 13 columns = **104 monochrome blue LEDs**
- **Driver:** STM32U585 MCU
- **Boot behavior:** Displays the Arduino logo animation for ~20–30 seconds while Linux boots
- **Warning:** Do not attempt to access the matrix before boot completes — it may interfere with MCU initialization

### Power LED (D27201)

- Green indicator, tied to the 3.3V rail
- On = board has power
- Cannot be controlled by software

### Power Button (JBTN1)

- **Long press (≥ 5 seconds):** Reboots the Linux environment (MPU). Does not cut power to the board.
- **Normal boot:** Happens automatically when power is applied — button press is not required.

---

## 11. Bridge RPC — How the Two Processors Talk

### The Problem Bridge Solves

Two processors, no shared memory, physically separate — how do they coordinate? They need a **communication protocol** that:
- Is type-safe (the MCU shouldn't receive a string when it expects an integer)
- Supports both **request/response** (synchronous calls) and **push notifications** (async events)
- Can route messages even if the physical transport changes (USB CDC today, UART tomorrow)

That protocol is **Bridge** — Arduino's RPC (Remote Procedure Call) layer.

### How Bridge Works

```
Python code on Linux (MPU)           Arduino sketch on MCU
──────────────────────               ─────────────────────
bridge.call("setLED", True)  ──────► MCU receives call, executes setLED(true)
                                     MCU returns result
bridge.get("temperature")    ◄──────  MCU pushes notification with temp value
```

Bridge is not a raw serial protocol. It is a **service-oriented API**:
- Each side **registers services** (named functions) it exposes
- The other side **calls** those services by name
- Bridge handles serialization, routing, and acknowledgment

### Physical Transports

Bridge can operate over multiple physical layers:
- **USB CDC** (USB serial device — default in PC-connected mode)
- **UART** (direct serial — used in some carrier configurations)
- **SPI** (for high-throughput use cases)

The transport is abstracted away. Your Python code and Arduino sketch use the same Bridge API regardless of the underlying wire.

### In Practice (App Lab)

When you press **Run** in App Lab:
1. The MCU sketch is compiled and flashed
2. The Python app is deployed to the Linux side
3. Bridge starts on both processors
4. Your Python code and sketch can now call each other's registered functions

You do **not** need to manually configure Bridge — App Lab handles it as part of the build+deploy pipeline.

---

## 12. Arduino App Lab — The Unified Development Environment

### What is App Lab?

App Lab is Arduino's IDE for the UNO Q. It is fundamentally different from the classic Arduino IDE because it must manage **two processors simultaneously**:

```
App Lab (running on PC or on-board)
├── Editor
│   ├── main.py  (Python — runs on Linux/MPU)
│   └── sketch.ino  (C++ Arduino — runs on MCU)
├── Build system
│   ├── Compiles sketch.ino for STM32U585 (ARM Cortex-M33)
│   └── Packages main.py for deployment to Linux
├── Deploy system
│   ├── Flashes MCU sketch over USB/WiFi
│   └── Deploys Python app to Linux filesystem
└── Console (3 tabs)
    ├── Start-up (launch logs)
    ├── Main (Python stdout)
    └── Sketch (Arduino Serial.println output)
```

### Two Operating Modes

**PC-Hosted Mode:**
- App Lab runs on your PC
- UNO Q connects via USB-C data cable (first setup) or WiFi (SSH) thereafter
- PC compiles and deploys to the board
- Required for first-time WiFi configuration

**Single-Board Computer (SBC) Mode:**
- App Lab runs directly on the UNO Q's Linux system
- Access via the board's own display (via USB-C DisplayPort) + keyboard/mouse via USB-C hub
- 4 GB RAM variant recommended for this mode
- Useful for standalone deployment

### First-Time Setup Sequence

1. Install App Lab on your PC (or boot UNO Q in SBC mode)
2. Connect UNO Q via USB-C data cable
3. App Lab discovers the board (takes a moment to scan USB)
4. Select the board to connect
5. App Lab scans for nearby WiFi networks
6. Choose your network and enter password
7. App Lab checks for firmware updates — **install all updates if prompted**
8. After updates, restart App Lab
9. You can now choose USB or WiFi connection going forward
10. Set the device name and password (default: `arduino` / `arduino`)
11. Run the "Blink LED" example to verify the setup

### File System Notes (from field testing)

Using `df` on the Linux side reveals three primary partitions:
- `/` (root) — contains the OS, Docker system, and App Lab infrastructure
- `/home/arduino` — your project files live here
- `/boot/efi` — boot partition

**Important:** The Docker system used by Bricks is stored in the `/` partition. At initial setup, `/` is already ~68% consumed. AI-capable Bricks (object detection, etc.) can quickly consume the remaining space. Monitor with `df -h` before deploying large AI Bricks.

---

## 13. Bricks — Modular Building Blocks

### What is a Brick?

A Brick is a **pre-packaged service** that runs on the Linux side of the UNO Q. Think of it as a ready-made backend component you can drop into your project without writing the underlying infrastructure.

Bricks encapsulate things like:
- **AI models** — object classification, keyword spotting, face detection
- **Web UI / REST API** — serve a browser dashboard from the board (e.g., WebUI Brick at port 7000)
- **Databases** — store and retrieve time-series data (Database Brick)
- **External integrations** — API clients for cloud services

### How Bricks Fit Into an App

```
Your App (App Lab project)
├── main.py  ← imports and initializes Bricks
├── sketch.ino  ← talks to Bricks via Bridge RPC
└── Bricks/
    ├── WebUI Brick  ← serves browser UI at board_ip:7000
    └── Database Brick  ← stores sensor readings from MCU
```

### Brick Workflow

1. Create an App in App Lab
2. Select Bricks from the Bricks library (left menu)
3. In `main.py`, import the Brick and initialize it following its API
4. The MCU sketch sends data to the Linux side via Bridge; `main.py` feeds that data to the Brick
5. Press **Run** — App Lab deploys the Python app, flashes the MCU, starts Bricks as background services

### Real Example: Home Climate App

The built-in "Home Climate" example demonstrates the full stack:

```
Modulino Thermo (I²C via Qwiic)
         │  (temperature + humidity readings)
         ▼
    sketch.ino  (MCU)
         │  (Bridge RPC push notification)
         ▼
    main.py  (Linux)
         ├── Database Brick  (stores readings to on-board DB)
         └── WebUI Brick  (serves live chart to browser at board_ip:7000)
```

**Important field note:** The official "Home Climate" example app is **read-only**. If you get a Zephyr linking error during compilation, **copy the example to create your own editable version**. The copy compiles without errors even without changing any source code. This is because Zephyr needs permissions to update the sketch directory during certain recompilations.

---

## 14. App Structure — Anatomy of an App Lab Project

Every App Lab project follows this structure:

```
MyApp/
├── main.py          ← Python — runs on Linux (MPU)
├── sketch.ino       ← Arduino C++ — runs on MCU
└── Bricks/          ← Optional modular services (Linux-side)
    └── [BrickName]/
```

### main.py — The Linux Side

- Runs as a Python process on Debian Linux
- Can use the full Python ecosystem (pip packages, system calls, file I/O)
- Communicates with the MCU via the Bridge Python library
- Imports and initializes Bricks
- Output visible in App Lab console → "Main (Python®)" tab

```python
# Example main.py skeleton
from bridge import Bridge
from bricks.webui import WebUI
from bricks.database import Database

bridge = Bridge()
webui = WebUI(port=7000)
db = Database()

@bridge.on("temperature_reading")
def handle_temperature(data):
    db.store("temperature", data["value"])
    webui.update("temp", data["value"])
```

### sketch.ino — The MCU Side

- Standard Arduino C++ sketch
- Runs on STM32U585 via Zephyr OS + Arduino Core
- Uses the Bridge Arduino library to call Linux services
- Reads sensors, drives actuators, generates PWM
- Output visible in App Lab console → "Sketch (Microcontroller)" tab

```cpp
// Example sketch.ino skeleton
#include <Bridge.h>
#include <Modulino.h>

ModulinoThermo thermo;

void setup() {
  Bridge.begin();
  thermo.begin();
}

void loop() {
  float temp = thermo.getTemperature();
  Bridge.notify("temperature_reading", {{"value", temp}});
  delay(1000);
}
```

### The Console — Your Debugging Window

| Tab | Shows |
|---|---|
| Start-up | MCU compilation output, Linux deployment logs, launch sequence |
| Main (Python®) | `print()` output from main.py |
| Sketch (Microcontroller) | `Serial.println()` output from sketch.ino |

> **Tip:** An App can launch successfully and still have runtime failures. Always check both the Python and Sketch console tabs after pressing Run, not just the Start-up tab.

---

## 15. Real-World Field Notes from AppLab Testing

These are observations from actual hardware testing (April 2026), not theory:

### Power & Startup

- **Startup animation current:** Stays below 200 mA during boot (Linux startup + LED matrix logo)
- **Idle + WiFi + 2 apps:** Stays below 500 mA average
- **Safe for standard USB3 port (900 mA limit):** Yes, with comfortable margin
- **Boot time:** ~20–30 seconds from power-on to idle (LED matrix animation is the visual indicator)

### App Lab Discovery

- App Lab takes "a little while" to find the board on USB — be patient after first connection
- Once WiFi is configured, SSH/WiFi connection is faster and preferred for day-to-day development
- There can only be **one active connection** at a time (USB or WiFi, not both)

### File System Health

```bash
# Run this on the board to check available space:
df -h
```

Watch the `/` partition — Docker images for AI Bricks can be large. If you plan to use vision or ML Bricks, verify free space before deployment.

### Example App Inventory

As of App Lab v0.6.0, there are **29 example apps** available, covering:
- LED control (Blink LED, Blink LED with UI)
- Modulino sensor integration (Thermo, Distance, Movement, Pixels, Knob, Buttons, Buzzer)
- Home climate monitoring
- AI/vision examples
- Web UI demonstrations

### Known Issue: Zephyr Compilation Error with Read-Only Examples

**Symptom:** Linking failure during compilation of certain example apps.

**Root cause:** Zephyr OS needed to recompile certain components and didn't have write permission to the example's read-only sketch directory.

**Fix:** Create a copy of the example app. The copy has write permissions and compiles without error, even without modifying the source code.

### Enhanced Home Climate App (Custom Example)

A real custom app was built by:
1. Starting from the "Home Climate" example (Thermo sensor → WebUI)
2. Adding a Distance (time-of-flight) Modulino module
3. Modifying `sketch.ino` to read distance
4. Adding logic: display temperature on LED matrix **only** when a person is detected within 500mm

Component stack used:
- Modulino Thermo (I²C temperature + humidity)
- Modulino Distance (I²C time-of-flight proximity)
- Database Brick (time-series storage)
- WebUI Brick (browser dashboard at `board_ip:7000`)
- RouterBridge library (MCU–Linux communication)
- Modulino library (MCU sketch)

---

## 16. Critical Warnings & Safety Rules — Never Forget These

These are copied directly from the official documentation and verified through testing:

### ⚠️ Voltage Warnings

> **"All MCU GPIOs are 3.3V logic and 5V tolerant, EXCEPT A0 and A1 (not 5V tolerant)."**

> **"A0 and A1 are not 5V tolerant."** — Repeated twice in the pinout for emphasis.

> **"JCTL pins are 1.8V logic only."** — Connecting 3.3V here risks MPU damage.

> **"Be aware of the pin logic level"** on JMISC — it carries both 1.8V and 3.3V signals.

### ⚠️ Interface-Reserved Pins

> **"Do not use the QRB2210 lines reserved for I²C (CCI), JMEDIA CCI, or MI2S0 (I²S audio) as general-purpose I/O."**

These signals are reserved in the Linux device tree and are interface-dedicated.

### ⚠️ SPI Sharing

> **"JSPI and JDIGITAL SPI share the SPI2 MCU peripheral. Cannot be used simultaneously as SPI."**

If you connect a device to JSPI, you lose D10–D13 as SPI pins.

### ⚠️ Boot Sequence

> **"Accessing the LED matrix before Linux startup completes may interfere with MCU operation."**

Wait for the LED matrix boot animation to finish (≈20–30 seconds) before sending commands to the MCU.

### ⚠️ IOREF

> **"IOREF is an output only. Do not back-feed power into it."**

It tells shields what voltage the board uses. It is not a power rail input.

### ⚠️ DisplayPort / USB Speed Trade-off

> **"When DisplayPort Alt-Mode is active, USB data speed is reduced."**

This is a physical constraint of USB-C Alt-Mode — the SuperSpeed lanes are shared between DP and USB 3.1 data.

### ⚠️ USB CLI Tools vs App Lab

> **"While an App is bound and running, USB interfaces may be occupied by the system. To use external CLI tools over USB, stop the App or disconnect the board."**

---

## 17. First-Principles Challenge Questions

Work through these before moving to hands-on lab work. Each question links back to a concept in this document.

**Q1 — Architecture:**
The STM32U585 runs Arduino Core on Zephyr OS. What does "Arduino Core" actually provide on top of Zephyr? Why can't you just run an Arduino sketch on bare-metal (no RTOS)?

**Q2 — Voltage domains:**
You want to connect an external 5V sensor (with a 5V digital output signal) to pin A0. The datasheet says A0 is "not 5V tolerant." What physically happens inside the STM32U585 if you apply 5V to A0 in analog mode? What component starts to conduct and why is that dangerous for the chip?

**Q3 — Bridge RPC:**
Bridge can operate over USB CDC, UART, or SPI. What changes when you switch from USB CDC to UART as the transport? What stays exactly the same? Why does the transport abstraction matter for production hardware designs?

**Q4 — Power system:**
The board uses a Schottky diode OR circuit to combine USB-C VBUS and the 7-24V DC input. If you connect a 12V DC supply AND a 5V USB-C simultaneously, what happens? Which source "wins"? What is the final voltage on 5V_SYS?

**Q5 — Bricks and Docker:**
Bricks run on the Linux side. You notice from `df -h` that the `/` partition is already 68% full before you deploy any Bricks. Why is Docker involved? What does Docker provide that makes Bricks portable across future UNO Q firmware versions?

**Q6 — LED matrix timing:**
The documentation says "Accessing the LED matrix before Linux startup completes may interfere with MCU operation." The LED matrix is driven by the MCU (STM32U585), not the MPU. So why would Linux startup affect the MCU's ability to drive it?

**Q7 — App Lab compilation:**
When you press "Run" in App Lab, the MCU sketch is compiled for the STM32U585 (ARM Cortex-M33, 32-bit). If you had the same sketch and tried to upload it via the classic Arduino IDE targeting an Arduino UNO R3 (ATmega328P, 8-bit AVR), what would break? Think about data types, timing, and toolchain differences.

---

## Reference: Key Component Index

| Component | Part Number | Role |
|---|---|---|
| MPU (SoC) | Qualcomm QRB2210 | Linux application processor |
| MCU | STM32U585 | Real-time microcontroller |
| Wireless | WCBN3536A (WCN3980) | WiFi 5 + BT 5.1 |
| PMIC | PM4125 | Power management (1.8V rail) |
| DP Bridge | ANX7625 | MIPI-DSI to DisplayPort Alt-Mode |
| RAM | LPDDR4X | 2 or 4 GB system memory |
| Storage | eMMC | 16 or 32 GB persistent storage |
| USB-C Protection | Q2801 (P-MOSFET) | VBUS load-switch / back-drive protection |

---

*Document compiled from:*
- *Arduino UNO Q User Manual (SKU: ABX00162-ABX00173), Rev 3, Modified 05/11/2025*
- *Arduino UNO Q Full Pinout, Last updated 17 Feb 2026*
- *Arduino UNO Q Schematics (ABX00162)*
- *AppLab field testing notes by ralphjy, Element14 community, April 2026*

*For latest updates: https://docs.arduino.cc/hardware/uno-q/*
