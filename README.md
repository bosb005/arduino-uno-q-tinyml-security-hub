# Edge AI Smart Security Hub

> Privacy-first acoustic event detection at the edge — Arduino UNO Q + INMP441 + TinyML

A home security node that detects acoustic events (`presence`, `anomaly`, `manual_trigger`)
using on-device TinyML inference. No cloud. No audio streaming. Fully private.

## Story

Most consumer security devices stream sensor data to cloud services, which hurts privacy and reliability for always-on home sensing. This project keeps detection local-first: real-time acoustic classification runs on the MCU, while Linux handles networking and UI. Only compact event messages are exchanged internally.

## Hardware
- Arduino UNO Q
- INMP441 I2S MEMS microphone
- Dupont jumper wires
- 100 nF ceramic capacitor (local mic decoupling)
- USB-C cable

## Quick Start

### 1. Wire the hardware
See [01_hardware_setup/WIRING.md](01_hardware_setup/WIRING.md)

### 2. Train the AI model
See [03_ai_model/EDGE_IMPULSE_SETUP.md](03_ai_model/EDGE_IMPULSE_SETUP.md)

### 3. Flash the firmware
See [04_firmware_inference/README.md](04_firmware_inference/README.md)

### 4. Run the dashboard
```bash
cd 05_linux_dashboard
pip3 install -r requirements.txt
python3 app.py
```
Open http://<board-ip>:7000

For the full device flow, use:
```bash
bash scripts/cycle.sh
```

## Automated deploy/test cycle (repo root)

```bash
./deploy.sh all         # flash main firmware + deploy app
./deploy.sh test        # bridge transport test + restore main firmware/app + health checks
./deploy.sh cycle       # full deploy + test in one command
./deploy.sh bridge-test # isolated Bridge WAV test (auto-restores main deployment)
```

Dashboard/API endpoint: `http://<board-ip>:7000`

## Architecture

```text
INMP441 ──I2S──► MCU (STM32)
                  │ DMA Buffer
                  ▼
            Edge Impulse MFCC
                  │
                  ▼
            TinyML NN Inference
                  │ Serial1 JSON
                  ▼
            Linux (UNO Q)
                  │ Flask SSE
                  ▼
            Browser Dashboard
```

Pipeline stages:
1. Audio capture
2. Frame buffering
3. MFCC feature extraction
4. Inference
5. Event transport
6. Local dashboard update

## Event Classes
| Event | Trigger | Dashboard Color |
|-------|---------|----------------|
| presence | Footsteps, voices | 🟡 Amber |
| anomaly | Loud crash, bang | 🔴 Red |
| manual_trigger | Triple clap | 🔵 Blue |
| idle | Silence | 🟢 Green |

## Project Structure

| Directory | Purpose |
|---|---|
| `01_hardware_setup/` | INMP441 wiring, schematic, checklist |
| `02_firmware_audio/` | I2S DMA audio capture backend |
| `03_ai_model/` | Edge Impulse training pipeline and export notes |
| `04_firmware_inference/` | TinyML inference sketch and event protocol |
| `05_linux_dashboard/` | Flask app, SSE dashboard, systemd service |
| `06_integration/` | IPC specification, test plan, troubleshooting |
| `07_submission/` | Hackster article, BOM, demo script, submission assets |
| `DECISIONS.md` | Architecture decisions and rationale |

## Results

Working prototype with digital audio capture on the MCU, on-device MFCC + TinyML inference, JSON IPC between MCU and Linux, and a local Wi-Fi dashboard without cloud dependency.

Prototype targets:
- Test-set accuracy: >85%
- Inference latency: <200 ms per frame
- Dashboard update latency: typically 1-2 s end-to-end

## Sustainability

- No cloud audio streaming
- On-device inference reduces recurring cloud compute
- Minimal BOM (single board + one mic)
- Better long-term maintainability without cloud lock-in

## Future Work

- MQTT output (Home Assistant integration)
- Multi-node support (multiple rooms)
- Retraining for additional events
- Stronger deployment pipeline
- Richer dashboard liveness/error diagnostics

## License
MIT
