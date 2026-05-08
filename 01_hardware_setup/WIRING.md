# INMP441 → Arduino UNO Q wiring

## Important notes first

- **Power the microphone from 3.3 V only.**
- The **QWIIC breakout is only a convenient connector/mechanical adapter** here. The signal set is **I2S**, **not** the QWIIC/I2C protocol.
- For this project, use **mono / left-channel capture** by connecting **L/R to D7** — the firmware drives D7 LOW to select the left channel.
- Add a **100 nF ceramic decoupling capacitor** between **VDD** and **GND**, placed as close to the INMP441 breakout as possible.

## INMP441 pin functions

| INMP441 pin | Function | Direction |
|---|---|---|
| `VDD` | 1.8-3.3 V supply input | Power in |
| `GND` | Ground reference | Power return |
| `SD` | I2S serial audio data output from microphone | Mic -> UNO Q |
| `WS` | I2S word select / LRCLK | UNO Q -> mic |
| `SCK` | I2S bit clock / BCLK | UNO Q -> mic |
| `L/R` | Channel select (`LOW` = left, `HIGH` = right) | Controlled by D7 |

## Arduino UNO Q header mapping

The current public UNO Q user manual pinout clearly exposes **D8**, **D9**, **D10**, and **D7** on the digital header. For this project, the **working I2S + L/R mapping** is:

- **D10 = WS / LRCLK**
- **D9 = SCK / BCLK**
- **D8 = SD / DIN**
- **D7 = L/R** (firmware drives LOW for left-channel mono)

> **Verify this mapping against the exact UNO Q user-manual revision / board package you are using before final power-up.** If your installed board core documents a different I2S-capable header mapping, follow that board-core mapping instead.

## Pinout table

| INMP441 pin | Connect to UNO Q | Why |
|---|---|---|
| `VDD` | `3.3V` | INMP441 must run from 3.3 V on this project |
| `GND` | `GND` | Common ground |
| `SD` | `D8` | I2S data from microphone into the MCU |
| `WS` | `D10` | I2S left/right word-select clock |
| `SCK` | `D9` | I2S bit clock |
| `L/R` | `D7` | Firmware drives LOW = left-channel mono capture |

## Recommended wiring details

1. Connect **VDD -> 3.3V**.
2. Connect **GND -> GND**.
3. Connect **SD -> D8**.
4. Connect **WS -> D10**.
5. Connect **SCK -> D9**.
6. Connect **L/R -> D7** (firmware sets D7 LOW = left channel).
7. Solder or place a **100 nF capacitor** directly across **VDD** and **GND** at the microphone breakout.

## Mono capture note

The INMP441 always transmits one I2S channel selected by `L/R`:

- `L/R = LOW` -> **left channel**
- `L/R = HIGH` -> **right channel**

For this Edge AI Smart Security Hub, **D7** is connected to `L/R` and driven `LOW` by the firmware so the MCU can capture a single mono left-channel stream.

## Signal-format reminder

The target firmware expects:

- **16 kHz** sample rate
- **mono** capture
- **32-bit I2S frames**
- valid microphone data in the **upper 24 bits** of each 32-bit slot

That means correct **WS**, **SCK**, and **SD** wiring is critical.
