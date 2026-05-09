# TinyML inference firmware

This folder contains the Arduino UNO Q inference sketch for the Edge AI Smart Security Hub.

## Files

- `inference_main.ino` - audio capture + Edge Impulse inference + UART event output
- `event_protocol.h` / `event_protocol.cpp` - JSON event and heartbeat helpers for `Serial1`
- `../02_firmware_audio/audio_capture.h` / `audio_capture.cpp` - reused non-blocking I2S capture backend

## 1) Install the Edge Impulse Arduino library ZIP

1. In Edge Impulse, export the trained model as an **Arduino library** ZIP.
2. Open **Arduino IDE** (or Arduino App Lab).
3. Go to **Sketch -> Include Library -> Add .ZIP Library...**.
4. Select the exported ZIP for **`security-hub-acoustic_inferencing`** from `../03_ai_model/`.
5. Re-open or re-verify the sketch. If the library is missing, the build stops with a clear `#error` message.

## 2) Open and build the sketch

1. Open `04_firmware_inference/inference_main.ino`.
2. Select **Arduino UNO Q** as the target board.
3. You can either keep the repository folder layout intact **or** copy `audio_capture.h` / `audio_capture.cpp` into the sketch folder for a combined deployment package.
4. Verify that `event_protocol.cpp` appears as a companion source file in the sketch.
5. Build and upload.

## 3) Wire `Serial1` to the Linux UART

`Serial` (USB) is used for debug logs. `Serial1` is used for MCU -> Linux IPC.

- **D1 / TX1** -> **Linux UART RX**
- **D0 / RX1** -> **Linux UART TX** (optional for future bidirectional use)
- **GND** -> **GND**

Notes:
- Cross TX to RX.
- Use **115200 baud**.
- Use **TTL UART levels only** (not RS-232 voltage levels).
- For one-way event streaming, TX1 + GND is the minimum required connection.

## 4) Verify via Serial Monitor

1. Open **Serial Monitor** on the USB port at **115200 baud**.
2. After boot, you should see:

```text
Security Hub ready
probs: presence=0.0123 anomaly=0.0011 manual_trigger=0.0004 idle=0.9862 best=idle conf=0.9862 idle_suppressed
```

3. On the Linux UART side (`Serial1`), you should receive newline-delimited JSON:

```json
{"v":1,"event":"heartbeat","uptime":0,"ts":0,"free_mem":0}
{"v":1,"event":"presence","confidence":0.92,"ts":12345}
{"v":1,"event":"anomaly","confidence":0.81,"ts":18762}
```

`idle` is never emitted on `Serial1`; it is only reported on the debug console.

## 5) Expected output format

Event message:

```json
{"v":1,"event":"presence","confidence":0.92,"ts":12345}
```

Heartbeat message every 10 seconds:

```json
{"v":1,"event":"heartbeat","uptime":12345,"ts":12345,"free_mem":0}
```

## 6) Tuning `CONFIDENCE_THRESHOLD`

The sketch uses:

```cpp
#define CONFIDENCE_THRESHOLD 0.75f
```

Tuning guidance:
- Raise it if you see too many false positives.
- Lower it if true events are being missed.
- Review the debug probability lines in `Serial Monitor` while testing real sounds in the target room.
- Change the define in `inference_main.ino`, rebuild, and upload again.

## 7) Latency expectation

Target inference latency is **under 200 ms per 1024-sample frame** on the STM32-based UNO Q. Actual latency depends on the exported model size, DSP block settings, and board core version.
