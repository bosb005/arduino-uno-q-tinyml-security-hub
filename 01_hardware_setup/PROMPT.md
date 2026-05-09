# Task: Hardware Setup — INMP441 Microphone + Arduino UNO Q

## Context

Board: Arduino UNO Q (dual-core: STM32 MCU + Linux module)
Hardware docs: https://docs.arduino.cc/tutorials/uno-q/user-manual/
Microphone: INMP441 (digital I2S MEMS microphone)
Adapter: QWIIC breakout adapter with I2S header (note: the electrical interface is I2S, not QWIIC protocol)

## Your Task

Produce the following deliverables for this directory:

### 1. `WIRING.md`
A detailed wiring guide:
- List all INMP441 pins (VDD, GND, SD, WS, SCK, L/R) and their function
- Map each pin to the correct Arduino UNO Q I2S / GPIO header pin
- Include a text-based pinout table
- Note correct L/R pin setting for mono capture (left channel: L/R = GND)
- Power supply requirements (3.3 V)
- Any decoupling capacitor recommendations

### 2. `SCHEMATIC.md` (ASCII or description)
A simple text schematic or step-by-step connection description that a beginner can follow.
If possible, describe a Fritzing-compatible wiring.

### 3. `CHECKLIST.md`
A hardware validation checklist:
- Voltage levels verified
- I2S pins connected correctly
- No short circuits
- Board powers up with microphone attached
- Serial monitor shows no error on I2S init

## Notes
- The QWIIC connector is used only for mechanical convenience; the actual signals are I2S lines
- The Arduino UNO Q I2S peripheral must be identified from the user manual linked above
- Do NOT use PDM — the INMP441 outputs standard I2S (not PDM)
- Target: 16 kHz, mono, 32-bit I2S frames (data in upper 24 bits)
