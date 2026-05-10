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

### 4. Deploy firmware + app
```bash
bash scripts/setup.sh
./deploy.sh all
```
Open `http://<board-ip>:7000`

For the full deploy + validation loop, use:
```bash
./deploy.sh cycle
```

## Automated deploy/test cycle (repo root)

```bash
./deploy.sh all         # flash main firmware + deploy app
./deploy.sh test        # bridge transport test + restore main firmware/app + health checks
./deploy.sh cycle       # full deploy + test in one command
./deploy.sh bridge-test # isolated Bridge WAV test (auto-restores main deployment)
```

Dashboard/API endpoint: `http://<board-ip>:7000`

## Audio-test rolling WAV mode

`app_audio_test` now writes rolling WAV windows (not just a single overwrite):
- per-window files: `/home/arduino/ArduinoApps/audio-test/windows/window-*.wav`
- latest window (SCP-friendly): `/home/arduino/ArduinoApps/audio-test/test.wav`

Runtime knobs in `app_audio_test/python/main.py`:
- `WINDOW_OUTPUT_DIR`
- `WINDOW_KEEP_COUNT`
- `OUTPUT_PATH`
- `ENABLE_CLASSIFY` and `CLASSIFY_CONFIDENCE` (optional classify-from-file on each window)

## Edge Impulse App Lab brick path

The app now includes the `arduino:audio_classification` brick wired to model `ei-model-129923-1` in `app/app.yaml`.
On deploy, App Lab starts a sidecar runner container (`ei-audio-classifier-runner`) for that model.

Notes:
- This keeps an App Lab-compatible EI model path available even when MCU inferencing is being debugged.
- `keyword_spotting` brick was intentionally not enabled in this app because it hard-fails startup on this device when no Linux microphone is available.
- A WAV-based fallback is exposed at `GET /classify-wav-now` (uses `AudioClassification.classify_from_file`).
  Configure via env vars in the app container:
  - `USE_EI_WAV_CLASSIFIER=1` (optional background watcher mode)
  - `EI_WAV_PATH` (default `/home/arduino/ArduinoApps/audio-test/test.wav`)
  - `EI_WAV_CONFIDENCE` (default `0.80`)
  - `EI_WAV_POLL_SEC` (default `2.0`)

## Bridge diagnostics (dashboard healthy but no events)

If the UI opens but events never change, triage with bridge-aware health checks:

```bash
curl -sf http://<board-ip>:7000/health | python3 -m json.tool
bash scripts/health-check.sh --json
bash scripts/health-check.sh --json --require-bridge-fresh
```

Check `bridge` fields in `/health`:
- `state=waiting_for_events` + `no_events_yet=true`: dashboard is up, callback registered, waiting for first event.
- `state=stale` + `alive=false`: callback starvation/stale bridge path (`last_event_age_ms` exceeded `stale_after_ms`).
- `provider_registered=false` or `provider_registration_error` non-empty: bridge provider registration failed.

`--require-bridge-fresh` is the actionable gate for deploy/test workflows because it fails when the dashboard is reachable but bridge events are not advancing.

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
| `app/` | **Primary runtime path** (`app/sketch` firmware + `app/python` Linux web app on port 7000) |
| `04_firmware_inference/` | Legacy/reference inference docs and earlier flow |
| `05_linux_dashboard/` | Legacy/reference dashboard docs and earlier flow |
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
