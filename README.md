# Industrial Dashboard using FPGA – Basys 3

A real-time environmental monitoring dashboard implemented on the Digilent **Basys 3 Artix-7 FPGA** using a **Pmod HYGRO (HDC1080)** sensor. The system reads temperature and humidity over I2C, displays readings through VGA and the onboard seven-segment display, reports status on LEDs, and transmits measurements to an ESP32 over UART.

## Features

- HDC1080 temperature and relative-humidity acquisition over I2C
- 100 kHz synchronous I2C command engine
- Temperature conversion in Celsius and Fahrenheit
- Humidity conversion in percentage-relative-humidity units
- 640×480 VGA environmental dashboard
- Temperature and humidity classification display
- Segmented visual gauges
- Four-digit seven-segment display with switch selection
- Diagnostic LED indicators
- UART transmission of measurements every second
- Dedicated Basys 3 pin constraints for Pmod and onboard peripherals

## Hardware

- Digilent Basys 3, XC7A35T
- Digilent Pmod HYGRO (TI HDC1080)
- VGA monitor
- ESP32 for UART receiving
- 100 MHz system clock

## Pin Connections

| Interface | Basys 3 connector/pin | Signal |
|---|---|---|
| Pmod HYGRO SCL | JB3 / B15 | `hyg_scl` |
| Pmod HYGRO SDA | JB4 / B16 | `hyg_sda` |
| UART TX | JC1 / L17 | `tx` |
| Reset button | BTNC / U18 | `btnC` |
| Display selector | SW0 / V17 | `sw0` |
| VGA | VGA connector | `vgaRed`, `vgaGreen`, `vgaBlue`, `Hsync`, `Vsync` |

## Controls

- **BTNC:** Reset the FPGA design.
- **SW0 = 0:** The seven-segment display shows temperature in Fahrenheit.
- **SW0 = 1:** The seven-segment display shows relative humidity.

## Data Interface

The ESP32 UART receiver should use:

- Baud rate: `9600`
- Format: `T:XX H:YY\n`
- Update interval: one second
- Temperature: Celsius without the decimal point, for example `25`
- Humidity: integer percentage, for example `48`

Example:

```text
T:25 H:48
```

## Repository Structure

```text
.
├── src/
│   ├── i2c_master.v
│   ├── pmod_hygro_controller.v
│   ├── top_pmod_hygro_vga.v
│   ├── hygro_vga_renderer.v
│   ├── seven_segment_display.v
│   ├── vga_640x480.v
│   └── uart_tx.v
└── constraints/
    └── pmod_hygro_xdc.xdc
```

> If the repository is missing the renderer or UART source, add `src/hygro_vga_renderer.v` and `src/uart_tx.v` to match the top-level instantiations.

## Module Overview

### `top_pmod_hygro_vga.v`

Top-level design that connects:

- HDC1080 sensor acquisition
- VGA timing and dashboard rendering
- Seven-segment display
- Status LEDs
- UART transmission

### `pmod_hygro_controller.v`

Controls the HDC1080 measurement sequence:

1. Wait after power-up
2. Write register `0x00` to start a measurement
3. Wait for conversion
4. Read temperature and humidity bytes
5. Convert raw values into fixed-point tenths
6. Wait one second before the next sample

### `i2c_master.v`

Reusable low-level I2C command engine supporting:

- START
- STOP
- Write byte
- Read byte with ACK
- Read byte with NACK

The bus runs at an approximate 100 kHz I2C clock from the 100 MHz system clock.

### `hygro_vga_renderer.v`

Generates the 640×480 VGA dashboard, including:

- Environmental title and panel headings
- Temperature in Fahrenheit and Celsius
- Relative humidity
- Segmented temperature and humidity gauges
- Temperature and humidity classifications
- Sensor-valid and I2C-error indicators

### `vga_640x480.v`

Produces 640×480 timing from the 100 MHz FPGA clock using a divide-by-four pixel clock enable. It provides pixel coordinates and active-low horizontal and vertical sync signals.

### `seven_segment_display.v`

Formats fixed-point tenths and multiplexes them onto the four common-anode digits. Values above `999.9` are saturated.

### `uart_tx.v`

Outputs UART frames using an 8-N-1 protocol. At a 100 MHz clock, `CLKS_PER_BIT` must be set to `10416` for approximately 9600 baud.

## Fixed-Point Format

Sensor values are stored in tenths:

- `724` represents `72.4°F`
- `223` represents `22.3°C`
- `386` represents `38.6% RH`

## Building with AMD Vivado

1. Create or open a Vivado RTL project for the **Basys 3 (XC7A35T)**.
2. Add every Verilog file from `src/` to the project.
3. Add `constraints/pmod_hygro_xdc.xdc` as the constraint file.
4. Set `top_pmod_hygro_vga` as the top module.
5. Run synthesis, implementation, and bitstream generation.
6. Connect the Pmod HYGRO to **JB**:
   - SCL on JB3
   - SDA on JB4
7. Connect VGA output to a VGA monitor.
8. Connect UART TX at JC1 to the ESP32 RX pin.
9. Program the Basys 3 with the generated `.bit` file.

## Required External Pull-Ups

I2C SDA and SCL require external pull-up resistors, normally around **4.7 kΩ**, to 3.3 V. The Pmod HYGRO module may already provide appropriate pull-ups; verify the board configuration before connecting it.

## Status Indicators

The LEDs expose sensor and acquisition information:

- Valid sensor data
- I2C or sensor error
- SW0 selection status
- Measurement activity
- Raw temperature or humidity data on LEDs 7–0

## License

This project is intended for educational and hardware-development use. Add a license file if you plan to distribute the project under specific terms.
