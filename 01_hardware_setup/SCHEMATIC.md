# Text schematic

## ASCII wiring diagram

```text
Arduino UNO Q                                  INMP441 microphone
-----------------                              ------------------
3.3V    -------------------------------------> VDD
GND     -------------------------------------> GND
D10     -------------------------------------> WS   (word select / LRCLK)
D9      -------------------------------------> SCK  (bit clock / BCLK)
D8      <------------------------------------- SD   (serial audio data)
D7      -------------------------------------> L/R  (LOW = left channel, driven by firmware)

Optional but strongly recommended:

VDD o----||----o GND
       100 nF
Placed close to the INMP441 breakout.
```

## Beginner step-by-step wiring

1. **Power off the UNO Q.** Do not wire the microphone with the board powered.
2. Locate the INMP441 pins: **VDD, GND, SD, WS, SCK, L/R**.
3. Run one wire from **UNO Q 3.3V** to **INMP441 VDD**.
4. Run one wire from **UNO Q GND** to **INMP441 GND**.
5. Run one wire from **UNO Q D10** to **INMP441 WS**.
6. Run one wire from **UNO Q D9** to **INMP441 SCK**.
7. Run one wire from **UNO Q D8** to **INMP441 SD** (data out from mic → MCU).
8. Connect **INMP441 L/R** to **UNO Q D7** — the firmware drives D7 LOW to select the left channel.
9. Add a **100 nF capacitor** between **VDD** and **GND** on the microphone side.
10. Re-check every wire before powering the board.

## Connection meaning

- **WS** tells the microphone which I2S slot is active.
- **SCK** is the fast serial bit clock.
- **SD** carries the captured audio bits from the microphone back into the UNO Q.
- **L/R** is connected to **D7** and driven LOW by the firmware, making the microphone output the left-channel mono stream.

## Fritzing-style connection list

If you later recreate this in Fritzing, use this exact net list:

- `UNO Q 3.3V` <-> `INMP441 VDD`
- `UNO Q GND` <-> `INMP441 GND`
- `UNO Q D10` <-> `INMP441 WS`
- `UNO Q D9` <-> `INMP441 SCK`
- `UNO Q D8` <-> `INMP441 SD`
- `UNO Q D7` <-> `INMP441 L/R` (firmware drives D7 LOW)
- `100 nF capacitor` across `INMP441 VDD` and `INMP441 GND`

## Verification note

This documentation uses the project's working UNO Q I2S header mapping:

- `D10 = WS`
- `D9 = SCK`
- `D8 = SD`
- `D7 = L/R` (firmware output, driven LOW)
