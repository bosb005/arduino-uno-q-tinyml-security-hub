# Architecture Decisions — Edge AI Smart Security Hub

This file captures key design choices made during planning. Update it as decisions evolve.

---

## Hardware

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Microphone | INMP441 (I2S digital) | Clean signal, no analog noise, direct I2S interface on UNO Q |
| Wiring | Dupont jumper wires for I2S lines | Simple direct wiring; electrically I2S (not I2C protocol) |
| Board | Arduino UNO Q | Contest hardware; dual-core MCU + Linux on one board |

## Audio Pipeline

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sample rate | 16 kHz mono | Standard for speech/acoustic ML; fits MCU DMA budget |
| Feature extraction | MFCC on MCU | Keeps raw audio local (privacy); reduces IPC data volume |
| Frame size | 1024 samples / 64 ms window | Typical for acoustic event detection |
| MFCC coefficients | 13 | Standard baseline; enough for presence/anomaly classification |

## AI / ML

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Training platform | Edge Impulse | Fastest path to TinyML; native MFCC + NN blocks; C++ export |
| Model type | Dense NN (or small CNN) | Fits MCU flash/RAM constraints |
| Export format | Edge Impulse C++ library (Arduino library) | Drop-in integration with Arduino IDE / App Lab |
| Quantization | INT8 | Reduces model size; supported by Edge Impulse export |
| Classes | presence, anomaly, manual_trigger, idle | Covers stated security use cases |

## IPC (MCU ↔ Linux)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport | Serial over internal UART | Reliable, simple, no external hardware |
| Format | Single-line JSON per event | Human-readable, easy to parse in Python/Node |
| Message example | `{"event":"presence","confidence":0.92,"ts":12345}` | Self-describing |

## Linux Side

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Web framework | Flask (Python) | Lightweight, available on embedded Linux, easy SSE support |
| Real-time push | Server-Sent Events (SSE) | Simpler than WebSocket; one-way push is sufficient |
| Wi-Fi mode | Client (connects to home AP) | Easier for home automation integration; AP mode as fallback |
| UI | Plain HTML + minimal JS | No framework dependencies; loads fast on any device |

## Sustainability

- No cloud streaming: eliminates continuous network traffic
- Single-board design: minimal BOM, low idle power draw
- Inference on MCU: no server infrastructure needed

## Open Questions / Future Refinements

- [ ] Confirm exact I2S pinout on UNO Q (check user manual)
- [ ] Decide on MQTT output for smart home integration (optional extension)
- [ ] Evaluate if CNN improves accuracy over dense NN on this MCU
