# Task: AI Model — Edge Impulse Training Pipeline

## Context

Platform: Edge Impulse (https://edgeimpulse.com)
Target device: Arduino UNO Q (STM32 MCU)
Audio input: 16 kHz mono from INMP441
Goal: Classify acoustic events into 4 classes: `presence`, `anomaly`, `manual_trigger`, `idle`

## Class Definitions

| Class | Examples |
|-------|---------|
| `presence` | Footsteps, voices, movement sounds, breathing |
| `anomaly` | Sudden loud noise, glass break, bang, crash |
| `manual_trigger` | 3× hand clap pattern, whistle, specific knock sequence |
| `idle` | Background noise, silence, HVAC hum |

## Your Task

### 1. `EDGE_IMPULSE_SETUP.md`
Step-by-step guide to set up the Edge Impulse project:
- Create project → select Arduino UNO Q as target device
- Configure data acquisition: 16 kHz, 1 second samples
- Recommended MFCC block settings:
  - Frame length: 0.025 s (400 samples)
  - Frame stride: 0.01 s (160 samples)
  - Num coefficients: 13
  - FFT size: 512
- Recommended NN classifier settings (first pass):
  - 2× Dense layers (64, 32 neurons), ReLU, Dropout 0.25
  - Output: Softmax × 4 classes
  - Epochs: 100, LR: 0.0005
- INT8 quantization before export

### 2. `DATA_COLLECTION.md`
Guide for collecting training data:
- Minimum samples per class: 50 × 1-second clips
- How to record with Edge Impulse CLI (`edge-impulse-daemon`)
- Tips for recording each class (where to record, how to simulate anomalies)
- Train/test split recommendation: 80/20

### 3. `EXPORT.md`
How to export the trained model:
- Export as **Arduino library** (ZIP) from Edge Impulse dashboard
- Copy the ZIP into `../04_firmware_inference/`
- Note the model name (used as `#include "your-model_inferencing.h"`)

### 4. `model_config.json` (template)
```json
{
  "project_name": "security-hub-acoustic",
  "target_device": "arduino-uno-q",
  "sample_rate_hz": 16000,
  "sample_length_ms": 1000,
  "mfcc": {
    "frame_length_ms": 25,
    "frame_stride_ms": 10,
    "num_coefficients": 13,
    "fft_size": 512
  },
  "classes": ["presence", "anomaly", "manual_trigger", "idle"],
  "quantization": "int8"
}
```

## Notes
- Edge Impulse free tier supports this project (check RAM/flash budget after training)
- If model is too large, reduce Dense layer sizes or use a 1D Conv layer instead
- The exported library will contain `run_classifier()` — used in task 04
