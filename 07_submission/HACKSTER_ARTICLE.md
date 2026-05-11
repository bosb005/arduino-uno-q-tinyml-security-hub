🔒 EDGE AI SMART SECURITY HUB
Privacy-first acoustic event detection at the edge using TinyML on Arduino UNO Q

📸 Add image: Hero shot of UNO Q + INMP441 here.

💡 WHAT IS THIS PROJECT ABOUT?
This project is a local-first home security node that detects acoustic events:
- presence (voices, footsteps, nearby movement)
- anomaly (bang/crash-like sudden sounds)
- manual_trigger (intentional triple clap)
- idle (background ambience)

✅ Core idea: run inference on-device and do not stream raw audio to cloud services.

📖 THE STORY: WHY I BUILT IT
Most consumer security products send audio or telemetry to cloud backends. For always-on sensing, that creates two practical risks:
1. 🔐 Privacy risk: raw home data can leave the device.
2. ⚠️ Reliability risk: cloud/API outages reduce usefulness at the worst time.

I wanted a beginner-friendly prototype that proves a local alternative. Arduino UNO Q is a good fit because it has an MCU side for real-time DSP/inference and a Linux side for networking and dashboard UI.

⚙️ HOW IT WORKS
🖼️ Add image: Architecture diagram here.

Signal flow:
INMP441 (I2S mic)
-> UNO Q MCU side (16 kHz capture + MFCC + TinyML)
-> Serial1 JSON events (internal UART)
-> UNO Q Linux side (Flask + SSE)
-> Local browser dashboard on port 7000

Pipeline:
1. Audio capture
2. Frame buffering
3. MFCC feature extraction
4. TinyML inference
5. Event transport
6. Dashboard update

🧰 THINGS USED IN THIS PROJECT
Hardware:
- Arduino UNO Q
- INMP441 MEMS I2S microphone
- Dupont jumper wires
- 100 nF ceramic capacitor
- USB-C cable

Software and tools:
- Arduino CLI / Arduino IDE
- Arduino App Lab
- Edge Impulse
- Python 3
- Flask + SSE

📄 Full BOM is in repository file: 07_submission/BOM.md

🛠️ FULL INSTRUCTIONS (BEGINNER REPRODUCIBLE)
Step 1 - Wire the hardware
Reference: 01_hardware_setup/WIRING.md
Required connections:
- VDD -> 3.3V
- GND -> GND
- SD -> D8
- WS -> D10
- SCK -> D9
- L/R -> D7 (forced low for mono)
Add a 100 nF capacitor between VDD and GND near the microphone module.

Step 2 - Prepare the model
Reference: 03_ai_model/EDGE_IMPULSE_SETUP.md
Baseline:
- 16 kHz mono input
- 1000 ms window / 500 ms stride
- MFCC features
- classes: presence, anomaly, manual_trigger, idle
Export ZIP used in this project:
03_ai_model/security-hub-acoustic_inferencing.zip

Step 3 - Build and deploy firmware + app
Run from repository root:
bash scripts/setup.sh
./deploy.sh all

🌐 Dashboard URL:
http://<board-ip>:7000

Step 4 - Run end-to-end validation
./deploy.sh cycle

Focused checks:
./deploy.sh bridge-test
bash scripts/health-check.sh --json

Step 5 - Trigger and observe events
1. Open dashboard on port 7000.
2. Speak/walk near mic -> presence (🟡 amber).
3. Sharp knock/clap -> anomaly (🔴 red).
4. Triple clap -> manual_trigger (🔵 blue).
5. Confirm event history updates.

📊 RESULTS AND DEMO EVIDENCE
Observed behavior:
- Edge inference runs on MCU with no cloud dependency.
- Dashboard updates live over local network.
- Internal JSON event transport works between MCU and Linux.

Target metrics:
- Test-set accuracy: >85%
- Inference latency target: <200 ms per frame
- Dashboard update: typically about 1-2 seconds end-to-end

Media to include in Hackster entry:
- Hero photo
- Wiring close-up
- Dashboard screenshots for idle/presence/anomaly/manual_trigger
- Event history screenshot
- Serial monitor screenshot
- 30-60 second demo video (idle -> presence -> anomaly -> manual_trigger)

🔎 See:
- 07_submission/PHOTO_CHECKLIST.md
- 07_submission/DEMO_SCRIPT.md

🌱 CREATIVITY AND SUSTAINABILITY
Creativity:
- Uses UNO Q split runtime (MCU + Linux) on one board.
- Includes a local gesture control path (triple clap).
- Privacy-first smart home concept without cloud lock-in.

Sustainability:
- No continuous cloud audio streaming.
- Lower network/backend compute footprint.
- Minimal hardware (one board + one digital mic).

🔌 SCHEMATICS AND WIRING EVIDENCE
- 01_hardware_setup/WIRING.md
- 01_hardware_setup/SCHEMATIC.md
- 07_submission/PHOTO_CHECKLIST.md

💻 CODE AND CONTRIBUTION
Primary implementation:
- app/sketch (MCU firmware)
- app/python (Linux web app)
- deploy.sh and scripts/ (deployment/test workflow)

Supporting docs:
- 06_integration/IPC_PROTOCOL.md
- DECISIONS.md

⚠️ KNOWN LIMITATIONS
- Acoustic models are environment-sensitive and may need retraining.
- Very noisy rooms can reduce gesture/event reliability.
- This is a prototype, not a certified security product.

🚀 FUTURE WORK
- MQTT / Home Assistant integration
- Multi-node room coverage
- Expanded class set (glass break, alarm, distress)
- Stronger App Lab deployment automation
- Richer dashboard diagnostics
