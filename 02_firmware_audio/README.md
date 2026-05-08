# MCU audio capture

This folder contains a non-blocking I2S capture module for the Arduino UNO Q plus a standalone microphone test sketch.

## Files

- `audio_capture.h` / `audio_capture.cpp` - public capture API and ping-pong frame buffer implementation
- `audio_capture_test.ino` - prints frame peak amplitude so you can verify the microphone before adding MFCC + inference

## Required Arduino support

- **Board package:** install the latest **Arduino UNO Q** board support in Arduino IDE / Arduino App Lab.
- **I2S backend:** this implementation expects the UNO Q core to expose an `I2S.h`-compatible API for the board.
- **No extra PDM library:** `PDM` is **not** suitable for the INMP441 because the microphone outputs standard **I2S**, not PDM.

> At the time of writing, a standalone Library Manager package dedicated to UNO Q I2S support is not clearly documented. In practice, the I2S support needs to come from the board core / App Lab image. If `audio_init()` fails immediately or `I2S.h` is missing at compile time, update the UNO Q core first.

## How the capture path works

- Configures I2S for **16 kHz**, **32-bit Philips/I2S framing**
- Uses a **ping-pong (double) buffer** of two `1024`-sample `int16_t` frames
- Keeps only the **left slot** because the INMP441 `L/R` pin is connected to **D7**, which the firmware drives LOW
- Converts each 32-bit I2S word to `int16_t` by removing the padding byte and scaling the 24-bit sample down to 16-bit storage

## Flashing the test sketch

1. Open Arduino IDE or Arduino App Lab.
2. Open `02_firmware_audio/audio_capture_test.ino`.
3. Select **Arduino UNO Q** as the target board.
4. Verify that `audio_capture.cpp` and `audio_capture.h` appear as companion tabs/files in the sketch.
5. Build and upload.
6. Open **Serial Monitor** at **115200 baud**.

## Expected Serial output

When the microphone and clocking are working, you should see lines like:

```text
audio_capture_test: starting
audio_capture_test: capture running
peak=142
peak=388
peak=2750
peak=910
```

Typical behavior:
- quiet room -> small peaks
- talking / tapping near the mic -> much larger peaks
- sustained values near full scale -> clipping or wrong gain/format handling

## Troubleshooting

### `audio_init()` fails
- Re-check that the **UNO Q board core** you installed actually includes I2S support.
- Rebuild after updating the board package.
- Confirm you selected the correct board in Arduino IDE / App Lab.

### No data / always zero
- Verify `VDD` is **3.3 V** and ground is common.
- Confirm the wiring for **SCK**, **WS/LRCLK**, and **SD**.
- Make sure the microphone `L/R` pin is connected to **D7** and that `audio_init()` sets D7 LOW for the left channel.
- Check that the UNO Q pin mapping you are using is the board's I2S-capable header, not plain SPI/I2C pins.

### Garbage data / unstable peaks
- Double-check the microphone is being sampled in **Philips/I2S mode** at **32-bit slots**.
- If every other sample looks wrong, your software may be consuming both left and right slots instead of only the left slot.
- If the waveform looks byte-swapped, inspect the board core's I2S endianness and adjust the `read_i2s_word()` packing order.

### Clipping / distorted levels
- The INMP441 delivers **24-bit audio left-justified inside a 32-bit frame**.
- This code strips the pad byte and scales down to `int16_t` storage before handing frames to the MFCC pipeline.
- If values pin at `32767` / `-32768`, revisit the shift/scaling logic for your specific core.

## 32-bit -> 16-bit note

The microphone places valid audio in the upper 24 bits of each 32-bit I2S slot. The code therefore:

1. right-shifts to discard the unused low byte
2. scales the 24-bit signed sample into `int16_t` storage for downstream MFCC work

That keeps the public API simple while still matching the INMP441 framing format.
