# Task: MCU Firmware — TinyML Inference + Event Output

## Context

Board: Arduino UNO Q (MCU core: STM32)
Dependencies:
- Audio buffer API from `../02_firmware_audio/` (`audio_ready()`, `audio_get_frame()`)
- Edge Impulse exported Arduino library (ZIP from `../03_ai_model/`)
Classes: `presence`, `anomaly`, `manual_trigger`, `idle`
IPC: Output events to Linux side via Serial (UART) as single-line JSON

## Your Task

### 1. `inference_main.ino`
Complete Arduino sketch that:
1. Includes the Edge Impulse library (`#include "your-model_inferencing.h"`)
2. Calls `audio_ready()` in the main loop
3. When a frame is ready, calls `run_classifier()` with the 1024-sample int16 buffer
4. Reads the output probabilities; picks the highest-confidence class
5. If confidence > 0.75 threshold, emits a JSON event on `Serial1` (Linux UART):
   ```json
   {"event":"presence","confidence":0.92,"ts":12345}
   ```
6. Calls `audio_clear_ready()` to consume the frame
7. Blinks LED on event detection (visual feedback)

### 2. `event_protocol.h`
Header defining event types and the serial output helper:
```cpp
enum class AcousticEvent { IDLE, PRESENCE, ANOMALY, MANUAL_TRIGGER };
void emit_event(AcousticEvent ev, float confidence, unsigned long ts_ms);
```

### 3. `README.md`
- How to install the Edge Impulse library in Arduino IDE
- How to verify inference is running (Serial Monitor output)
- Tuning the confidence threshold
- Expected inference latency (target < 200 ms per frame)

## Notes
- Use `Serial` (USB) for debug output and `Serial1` (hardware UART) for Linux IPC
- The Edge Impulse library expects a `signal_t` with `get_data` callback — wrap the int16 buffer
- Do NOT emit events for `idle` class to reduce IPC noise (only log at debug level)
- Confidence threshold 0.75 is a starting point; tune after testing
