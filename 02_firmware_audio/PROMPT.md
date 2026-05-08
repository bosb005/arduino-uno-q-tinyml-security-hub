# Task: MCU Firmware — I2S Audio Capture

## Context

Board: Arduino UNO Q (MCU core: Renesas RA4M1)
IDE: Arduino IDE / Arduino App Lab
Microphone: INMP441 via I2S
Target: 16 kHz, mono, continuous capture into a circular buffer
Hardware wiring: see `../01_hardware_setup/WIRING.md`

## Your Task

Implement MCU-side Arduino firmware for audio capture. Deliverables:

### 1. `audio_capture.ino` (or `.h` / `.cpp` pair)
- Initialize the I2S peripheral at 16 kHz, mono, 32-bit frames
- Use DMA for continuous, non-blocking capture
- Maintain a circular buffer of at least 1024 samples (one inference frame)
- Expose a simple API:
  ```cpp
  bool audio_ready();          // returns true when a full frame is available
  int16_t* audio_get_frame();  // returns pointer to the current 1024-sample frame
  void audio_clear_ready();    // marks frame as consumed
  ```
- Include error handling for I2S init failures (print to Serial)

### 2. `README.md`
- How to configure the I2S peripheral in Arduino IDE for UNO Q
- Required Arduino libraries (e.g., ArduinoSound, PDM, or Renesas HAL)
- How to verify audio capture works (e.g., print peak amplitude to Serial)

## Notes
- INMP441 outputs I2S with data in the upper 24 bits of a 32-bit frame; shift right by 8
- Use left channel only (L/R pin tied to GND on the sensor)
- Do NOT use blocking reads — DMA is required for real-time operation
- The audio buffer will be consumed by the MFCC feature extraction task (`04_firmware_inference`)
