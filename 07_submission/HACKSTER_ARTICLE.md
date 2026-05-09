# Edge AI Smart Security Hub
> Privacy-first acoustic event detection at the edge using TinyML on Arduino UNO Q

## Things Used in This Project

| Type | Item | Notes |
|---|---|---|
| Hardware | Arduino UNO Q | Contest hardware with MCU + Linux environments on one board |
| Hardware | INMP441 MEMS microphone | Digital I2S microphone for 16 kHz mono audio capture |
| Hardware | QWIIC breakout adapter | Used as a convenient physical adapter; signals remain I2S, not QWIIC/I2C |
| Hardware | 100 nF ceramic capacitor | Local decoupling for the microphone breakout |
| Hardware | Jumper wires + USB-C cable | Wiring, power, and programming |
| Software | Arduino IDE / Arduino App Lab | Firmware build, upload, deployment, and board management |
| Software | Edge Impulse | Data collection, MFCC pipeline, model training, INT8 export |
| Software | Flask | Local Linux-side dashboard server |
| Software | Python 3 + pyserial | UART ingestion and dashboard backend |
| Software | Server-Sent Events (SSE) | Real-time browser updates without polling |

## Story

### The Problem
Most consumer security products default to the cloud: cameras upload footage, smart speakers stream audio, and event detection often depends on remote servers. That creates a privacy problem, especially for always-on sensors in bedrooms, hallways, and living spaces. It also creates a reliability problem: if the network drops or a cloud API changes, the system becomes less useful exactly when it matters most. For a simple home security node, sending raw audio away is overkill. I wanted a local-first design that reacts to important sounds, keeps private data on the device, and still gives users a clean real-time interface.

### The Solution
Edge AI Smart Security Hub pushes the entire detection pipeline onto the Arduino UNO Q. An INMP441 digital microphone feeds 16 kHz mono audio into the STM32 MCU, where a TinyML model built with Edge Impulse extracts MFCC features and classifies acoustic events locally. Only compact event messages are forwarded over UART to the Linux side of the board, which hosts a Flask dashboard over Wi-Fi for live monitoring.

This split makes the UNO Q especially compelling: the MCU handles deterministic real-time audio capture and inference, while Linux handles networking and the browser UI. Arduino App Lab fits naturally into this workflow because it can be used to manage the dual-core setup, deploy and test the embedded application, host the dashboard, and manage connectivity during iteration. No raw audio is streamed to the cloud, and the system still feels connected and interactive. In its current form, this is a prototype security node designed to prove the architecture, validate the user experience, and show that privacy-first acoustic monitoring can be practical on low-cost embedded hardware.

## Hardware Setup
Full wiring details are documented in [`01_hardware_setup/WIRING.md`](../01_hardware_setup/WIRING.md).

### Key connections

| INMP441 pin | Arduino UNO Q pin | Notes |
|---|---|---|
| `VDD` | `3.3V` | Microphone must be powered from 3.3 V |
| `GND` | `GND` | Common ground |
| `SD` | `D8` | I2S serial data into the MCU |
| `WS` | `D10` | I2S word select / LRCLK |
| `SCK` | `D9` | I2S bit clock / BCLK |
| `L/R` | `GND` | Forces left-channel output for mono capture |

> A 100 nF ceramic capacitor should be placed across `VDD` and `GND` close to the microphone breakout.

## System Architecture

```text
INMP441 mic
   │  I2S (16 kHz mono)
   ▼
Arduino UNO Q MCU (STM32)
   │  ping-pong audio buffer via I2S backend
   ▼
Edge Impulse DSP
   │  MFCC feature extraction
   ▼
TinyML neural network
   │  classify: presence / anomaly / manual_trigger / idle
   ▼
Serial1 UART JSON
   │  115200 8N1, newline-delimited, v=1
   ▼
UNO Q Linux side
   │  Python serial reader + Flask app
   ▼
Server-Sent Events (SSE)
   │
   ▼
Browser dashboard over Wi-Fi
```

### Stage-by-stage flow

1. **Audio capture** - The INMP441 provides digital I2S audio, avoiding analog front-end noise and simplifying signal routing.
2. **Frame buffering** - The MCU collects audio into a non-blocking ping-pong buffer so capture and inference can coexist cleanly.
3. **Feature extraction** - Edge Impulse MFCC preprocessing converts raw waveform data into compact spectral features.
4. **Inference** - A small INT8 neural network classifies each audio window as `presence`, `anomaly`, `manual_trigger`, or `idle`.
5. **Event transport** - Only non-idle events plus periodic heartbeats are sent to Linux as newline-terminated JSON.
6. **Local dashboard** - Flask reads UART messages, maintains state/history, and pushes updates to browsers via SSE.

## Firmware: Audio Capture (MCU)
The audio frontend is implemented in `02_firmware_audio/audio_capture.h/.cpp`. It exposes a small API: initialize I2S capture, poll for a ready frame, read the current buffer, and release it after inference. Internally, it uses a two-buffer scheme so one frame can be processed while the next is being filled.

This matters for embedded ML: dropping frames or blocking the capture path can make the classifier unstable. The ping-pong design keeps the firmware simple while matching the real-time constraints of 16 kHz audio.

```cpp
if (!audio_init()) {
  Serial.println(F("I2S init failed"));
}

void loop() {
  if (audio_ready()) {
    int16_t* frame = audio_get_frame();
    // Pass frame to Edge Impulse signal wrapper
    audio_clear_ready();
  }
}
```

## AI Model: Training with Edge Impulse
The model workflow is documented in [`03_ai_model/EDGE_IMPULSE_SETUP.md`](../03_ai_model/EDGE_IMPULSE_SETUP.md). The current baseline design uses:

- **Input:** 16 kHz mono audio
- **Window size:** 1000 ms
- **Window increase:** 500 ms
- **Features:** MFCC
- **MFCC config:** 25 ms frame length, 10 ms stride, 13 coefficients, 512 FFT, 300-8000 Hz band
- **Classifier:** small dense neural network
- **Output classes:** `presence`, `anomaly`, `manual_trigger`, `idle`
- **Deployment format:** Edge Impulse Arduino library, INT8 quantized

The goal of the model is not speech recognition; it is lightweight acoustic scene understanding for a narrow set of home-security-relevant cues. `presence` captures footsteps, voices, and movement-like sounds. `anomaly` covers sudden, high-energy events such as a bang, crash, or glass-like break. `manual_trigger` is an intentional triple-clap pattern for user interaction. `idle` represents background silence and normal room ambience.

## Firmware: TinyML Inference (MCU)
The inference sketch in [`04_firmware_inference/inference_main.ino`](../04_firmware_inference/inference_main.ino) wraps the current audio frame in an Edge Impulse `signal_t`, calls `run_classifier()`, selects the top label, and emits an IPC event when the confidence passes a threshold.

Important implementation details:

- `Serial` is reserved for USB debug output.
- `Serial1` carries production IPC to Linux.
- `idle` is intentionally suppressed on IPC to reduce unnecessary dashboard churn.
- A heartbeat is emitted at boot and every 10 seconds for liveness.

```cpp
if (audio_ready()) {
  g_audio_frame = audio_get_frame();

  signal_t signal;
  signal.total_length = AUDIO_FRAME_SAMPLES;
  signal.get_data = get_signal_data;

  ei_impulse_result_t result = {0};
  run_classifier(&signal, &result, false);

  if (best_value >= CONFIDENCE_THRESHOLD) {
    const AcousticEvent event = label_to_event(best_label);
    emit_event(event, best_value, millis());
  }

  audio_clear_ready();
}
```

## Dashboard: Real-Time Web UI (Linux)
The Linux side runs a Flask application from [`05_linux_dashboard/`](../05_linux_dashboard/). It listens to UART data, stores the latest state plus recent history, and exposes a `/stream` SSE endpoint so the browser can update without manual refresh.

The UI is intentionally simple and readable: a dark layout, a large status badge, confidence percentage, last-updated timestamp, and a scrolling event history table. Event colors map cleanly to meaning: green for idle, amber/yellow for presence, red for anomaly, and blue for manual trigger.

```python
@app.get("/stream")
def stream():
    @stream_with_context
    def event_stream():
        subscriber = queue.Queue(maxsize=10)
        subscribers.append(subscriber)
        try:
            yield f"data: {json.dumps(_state_snapshot())}\n\n"
            while True:
                try:
                    snapshot = subscriber.get(timeout=15)
                    yield f"data: {json.dumps(snapshot)}\n\n"
                except queue.Empty:
                    yield ": keepalive\n\n"
        finally:
            subscribers.remove(subscriber)

    return Response(event_stream(), mimetype="text/event-stream")
```

## IPC Protocol
The integration contract is documented in [`06_integration/IPC_PROTOCOL.md`](../06_integration/IPC_PROTOCOL.md).

### Transport
- **Link:** internal UART (`Serial1` -> `/dev/ttyS1`)
- **Baud:** `115200`
- **Format:** `8N1`
- **Framing:** one JSON object per line, newline terminated
- **Versioning:** all messages include `"v":1`

### Example messages

Event:

```json
{"v":1,"event":"presence","confidence":0.92,"ts":12345}
```

Heartbeat:

```json
{"v":1,"event":"heartbeat","uptime":12345,"free_mem":45678}
```

`idle` remains a local debug/UI state and is not emitted as an action event over IPC.

## Results
This project is currently a working prototype architecture rather than a finished commercial product. The key result is that the full offline pipeline is feasible on the Arduino UNO Q:

- digital audio capture on the MCU
- on-device MFCC + TinyML inference
- compact JSON IPC between the two processing domains
- live Wi-Fi dashboard with no cloud dependency

Target performance for the prototype is:

| Metric | Target |
|---|---|
| Test-set accuracy | >85% |
| Inference latency | <200 ms per frame |
| Event transport | Near real-time over local UART |
| Dashboard update latency | Typically within 1-2 s end to end |

In a typical home-like environment, the intended events can be triggered and visualized cleanly. As with any acoustic classifier, performance depends heavily on training data quality, room acoustics, microphone placement, and background noise. That is why the current write-up treats the system honestly as a prototype node with a solid architecture and clear upgrade paths.

## Sustainability
This project is intentionally designed as a more sustainable alternative to cloud-heavy smart security products:

- **No cloud audio streaming** reduces network usage and avoids always-on server processing.
- **On-device inference** keeps compute local and eliminates recurring cloud infrastructure needs.
- **Minimal hardware BOM** uses one board and one microphone for a useful baseline system.
- **Low idle activity** keeps the system lightweight when no relevant events are happening.
- **Longer-term maintainability** improves because the core function does not depend on a third-party cloud service staying online.

## Future Work
There is a clear path from prototype to deployable product:

- add **MQTT output** for Home Assistant or other automation platforms
- support **multi-node deployment** across multiple rooms
- retrain the model for **glass break**, **industrial anomalies**, or **elderly monitoring**
- add a more formal **App Lab deployment pipeline** for MCU firmware + Linux services
- improve temporal detection logic for more robust pattern recognition beyond single-window classification
- add optional liveness/error indicators to the dashboard for UART disconnect diagnosis

## Code
Full source is organized in the repository and separated by build stage.

| Directory | Purpose |
|---|---|
| `01_hardware_setup/` | Wiring, schematic, hardware checklist |
| `02_firmware_audio/` | I2S audio capture backend |
| `03_ai_model/` | Edge Impulse workflow, model config, retraining notes |
| `04_firmware_inference/` | TinyML inference sketch and UART event protocol |
| `05_linux_dashboard/` | Flask app, SSE dashboard, service files |
| `06_integration/` | IPC spec, integration tests, troubleshooting |
| `07_submission/` | Hackster article, demo assets, README, submission docs |
| `DECISIONS.md` | Architecture decisions and rationale |

This structure made the project easier to build incrementally: hardware first, then audio capture, then model design, then inference, then Linux integration, and finally the submission material.
