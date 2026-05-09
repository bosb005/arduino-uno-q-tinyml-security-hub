🔒 EDGE AI SMART SECURITY HUB
Privacy-first acoustic event detection at the edge using TinyML on Arduino UNO Q

========================================================================
**🧰 THINGS USED IN THIS PROJECT**
========================================================================

🔧 Hardware:
- Arduino UNO Q (MCU + Linux on one board)
- INMP441 MEMS microphone (digital I2S mic, 16 kHz mono capture)
- QWIIC breakout adapter (used as physical adapter only; signal is I2S, not I2C)
- 100 nF ceramic capacitor (local decoupling for mic board)
- Jumper wires + USB-C cable

💻 Software:
- Arduino IDE / Arduino App Lab
- Edge Impulse
- Flask
- Python 3 + pyserial
- Server-Sent Events (SSE)

========================================================================
**📖 STORY**
========================================================================

**❗ The problem**
Most consumer security devices stream data to cloud services. For always-on home audio sensing, this is bad for privacy and reliability. If network or APIs fail, the product gets worse exactly when needed. I wanted a local-first node that reacts to important sounds without sending raw audio away.

**✅ The solution**
Edge AI Smart Security Hub runs the detection pipeline on Arduino UNO Q:
- INMP441 -> STM32 MCU (audio capture + TinyML inference)
- Linux side -> Flask dashboard over Wi-Fi
- only compact event messages are shared internally

This split uses the board well: deterministic real-time work on MCU, networking/UI on Linux.

========================================================================
**🔌 HARDWARE SETUP**
========================================================================

Full wiring details:
../01_hardware_setup/WIRING.md

Key connections:
- VDD -> 3.3V
- GND -> GND
- SD  -> D8   (I2S serial data)
- WS  -> D10  (I2S word select / LRCLK)
- SCK -> D9   (I2S bit clock / BCLK)
- L/R -> GND  (force left channel for mono)

Place 100 nF capacitor between VDD and GND near the mic breakout.

========================================================================
**🏗️ SYSTEM ARCHITECTURE**
========================================================================

INMP441 mic
-> I2S 16 kHz mono
-> UNO Q MCU (STM32)
-> Edge Impulse MFCC DSP
-> TinyML classifier (presence/anomaly/manual_trigger/idle)
-> Serial1 UART JSON (115200, 8N1, newline messages)
-> UNO Q Linux side
-> Python + Flask
-> SSE
-> Browser dashboard over Wi-Fi

📈 Stage flow:
1) Audio capture
2) Frame buffering
3) MFCC feature extraction
4) Inference
5) Event transport
6) Local dashboard update

========================================================================
**🎙️ FIRMWARE: AUDIO CAPTURE (MCU)**
========================================================================

Audio frontend:
02_firmware_audio/audio_capture.h
02_firmware_audio/audio_capture.cpp

It exposes a small API:
- initialize capture
- check frame ready
- get frame pointer
- release frame

Internally it uses a ping-pong buffer so capture and processing can overlap.

========================================================================
**🧠 AI MODEL: EDGE IMPULSE**
========================================================================

Workflow doc:
../03_ai_model/EDGE_IMPULSE_SETUP.md

Current baseline:
- input: 16 kHz mono
- window size: 1000 ms
- window increase: 500 ms
- features: MFCC
- MFCC: 25 ms length, 10 ms stride, 13 coeff, 512 FFT, 300-8000 Hz
- classifier: small dense NN
- classes: presence, anomaly, manual_trigger, idle
- export: Arduino library, INT8 quantized

Meaning of classes:
- presence: footsteps/voices/movement-like sounds
- anomaly: sudden high-energy sounds (bang/crash/glass-like)
- manual_trigger: intentional triple clap
- idle: background ambience

========================================================================
**⚙️ FIRMWARE: TINYML INFERENCE (MCU)**
========================================================================

Inference sketch reference:
../04_firmware_inference/inference_main.ino

Important implementation points:
- Serial is USB debug
- Serial1 is production IPC
- idle is suppressed on IPC to reduce noise
- heartbeat at boot + every 10s for liveness

========================================================================
**🖥️ DASHBOARD: REAL-TIME WEB UI (LINUX)**
========================================================================

Dashboard source:
../05_linux_dashboard/

Behavior:
- reads UART messages
- tracks current state + history
- exposes /stream SSE for live browser updates

UI intent:
- clear status badge
- confidence percentage
- last update time
- recent event history
- color coding per event

========================================================================
**📡 IPC PROTOCOL**
========================================================================

Protocol doc:
../06_integration/IPC_PROTOCOL.md

Transport:
- link: internal UART (Serial1 <-> /dev/ttyS1)
- baud: 115200
- framing: one JSON object per line
- version field: "v":1 in all messages

🧪 Examples:
📨 Event:
{"v":1,"event":"presence","confidence":0.92,"ts":12345}

💓 Heartbeat:
{"v":1,"event":"heartbeat","uptime":12345,"free_mem":45678}

========================================================================
**📊 RESULTS**
========================================================================

This is a working prototype architecture:
- digital audio capture on MCU
- on-device MFCC + TinyML inference
- compact JSON IPC between MCU and Linux
- local Wi-Fi dashboard without cloud dependency

🎯 Prototype targets:
- test-set accuracy: >85%
- inference latency: <200 ms per frame
- event transport: near real-time over UART
- dashboard update latency: typically 1-2 s end-to-end

========================================================================
**🌱 SUSTAINABILITY**
========================================================================

- no cloud audio streaming
- on-device inference reduces recurring cloud compute
- minimal BOM (one board + one mic)
- low idle activity
- better long-term maintainability without cloud lock-in

========================================================================
**🚀 FUTURE WORK**
========================================================================

- MQTT output (Home Assistant integration)
- multi-node support (multiple rooms)
- retraining for additional events
- stronger App Lab deployment pipeline
- better temporal logic for robust pattern detection
- richer dashboard liveness/error diagnostics

========================================================================
**🗂️ CODE STRUCTURE**
========================================================================

- 01_hardware_setup/      wiring + hardware checklist
- 02_firmware_audio/      I2S audio capture backend
- 03_ai_model/            Edge Impulse workflow and retraining notes
- 04_firmware_inference/  TinyML inference sketch + event protocol
- 05_linux_dashboard/     Flask app + SSE dashboard
- 06_integration/         IPC spec, tests, troubleshooting
- 07_submission/          submission assets and article material
- DECISIONS.md            architecture decisions and rationale

========================================================================
**🌐 LIVE URL / PORT**
========================================================================

🔗 Dashboard endpoint:
http://<board-ip>:7000
