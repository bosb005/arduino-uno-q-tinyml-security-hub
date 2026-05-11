# Edge AI Smart Security Hub

**Privacy-first acoustic event detection at the edge using TinyML on Arduino UNO Q**

![Hero shot placeholder](docs/hero-shot.jpg)

## What is this project about?

This project is a local-first home security node that listens for meaningful **acoustic events**:

- `presence` (voices, footsteps, nearby movement)
- `anomaly` (bang/crash-like sudden sounds)
- `manual_trigger` (intentional triple clap)
- `idle` (background ambience)

The key idea is simple: **do inference on-device and never stream raw audio to cloud services**.

## The story: why I built it

Most consumer security products push audio or telemetry to cloud backends. For always-on sensing, that creates two problems:

1. privacy risk (raw home data leaves the device)
2. reliability risk (cloud/API outages reduce system usefulness)

I wanted a beginner-friendly prototype that proves an alternative: a compact edge AI stack that runs fully on Arduino UNO Q. The board is ideal because it combines an MCU side (deterministic real-time DSP/inference) and a Linux side (networking + dashboard) on one platform.

## How it works

![Architecture placeholder](docs/architecture.png)

```text
INMP441 (I2S mic)
  -> UNO Q MCU side (16 kHz capture + MFCC + TinyML)
  -> Serial1 JSON events (internal UART)
  -> UNO Q Linux side (Flask + SSE)
  -> Local browser dashboard on :7000
```

Pipeline stages:
1. Audio capture
2. Frame buffering
3. MFCC feature extraction
4. TinyML inference
5. Event transport
6. Dashboard update

## Things used in this project

See the full BOM: [BOM.md](BOM.md)

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

## Full instructions (beginner reproducible)

### Step 1: Wire the hardware

Reference: [../01_hardware_setup/WIRING.md](../01_hardware_setup/WIRING.md)

Required connections:
- `VDD -> 3.3V`
- `GND -> GND`
- `SD -> D8`
- `WS -> D10`
- `SCK -> D9`
- `L/R -> D7` (forced low for mono)

Add a 100 nF capacitor between VDD and GND close to the microphone module.

### Step 2: Prepare the model

Reference: [../03_ai_model/EDGE_IMPULSE_SETUP.md](../03_ai_model/EDGE_IMPULSE_SETUP.md)

Baseline used:
- 16 kHz mono input
- 1000 ms window / 500 ms stride
- MFCC features
- classes: `presence`, `anomaly`, `manual_trigger`, `idle`

Export as Arduino library ZIP:
`03_ai_model/security-hub-acoustic_inferencing.zip`

### Step 3: Build and deploy firmware + app

From repository root:

```bash
bash scripts/setup.sh
./deploy.sh all
```

Dashboard endpoint:
`http://<board-ip>:7000`

### Step 4: Run the end-to-end validation cycle

```bash
./deploy.sh cycle
```

Useful focused checks:

```bash
./deploy.sh bridge-test
bash scripts/health-check.sh --json
```

### Step 5: Trigger and observe events

1. Open dashboard on port 7000.
2. Speak/walk near mic -> `presence` (amber).
3. Sharp knock/clap -> `anomaly` (red).
4. Triple clap -> `manual_trigger` (blue).
5. Confirm event history updates.

## Results and demo evidence

Prototype behavior observed:
- edge inference running on MCU with no cloud dependency
- live event updates on local dashboard
- compact internal JSON event transport between MCU and Linux

Target metrics used in this build:
- test-set accuracy: `>85%`
- inference latency target: `<200 ms/frame`
- dashboard update: typically `~1-2 s` end-to-end

Media evidence to include in Hackster post:
- hero photo
- wiring close-up
- dashboard screenshots for all states
- serial monitor screenshot
- 30-60 s demo video (idle -> presence -> anomaly -> manual trigger)

Checklist: [PHOTO_CHECKLIST.md](PHOTO_CHECKLIST.md)  
Live demo flow: [DEMO_SCRIPT.md](DEMO_SCRIPT.md)

## Creativity and sustainability

Creativity angle:
- fresh use of UNO Q dual-runtime architecture (MCU + Linux in one board)
- gesture-based local trigger (triple clap) for hands-free interaction
- privacy-first smart-home security without cloud lock-in

Sustainability angle:
- no continuous cloud audio streaming
- lower network and backend compute footprint
- minimal hardware (single board + one digital mic)
- maintainable local deployment model

## Schematics and wiring evidence

- Wiring guide: [../01_hardware_setup/WIRING.md](../01_hardware_setup/WIRING.md)
- Schematic notes: [../01_hardware_setup/SCHEMATIC.md](../01_hardware_setup/SCHEMATIC.md)
- Wiring photo checklist item: [PHOTO_CHECKLIST.md](PHOTO_CHECKLIST.md)

## Code and contribution

Primary implementation paths:
- MCU firmware (current): `app/sketch/`
- Linux web app (current): `app/python/`
- Deployment workflow: `deploy.sh`, `scripts/`

Supporting references:
- Integration protocol: [../06_integration/IPC_PROTOCOL.md](../06_integration/IPC_PROTOCOL.md)
- Architecture decisions: [../DECISIONS.md](../DECISIONS.md)

## Known limitations

- acoustic models are environment-sensitive and require retraining/tuning
- very noisy rooms can reduce gesture/event reliability
- this is a prototype, not a certified security product

## Future work

- MQTT/Home Assistant integration
- multi-node room coverage
- expanded class set (glass break, alarm, distress)
- stronger App Lab deployment automation
- richer diagnostics in dashboard
