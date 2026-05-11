# Bill of Materials

| Component | Qty | Unit Cost (est.) | Source | Notes |
|-----------|-----|-----------------|--------|-------|
| Arduino UNO Q | 1 | Contest hardware | Arduino | Dual-core MCU + Linux |
| INMP441 MEMS Microphone | 1 | ~$2 | AliExpress/Adafruit | I2S digital output |
| Dupont jumper wires (F-F/M-F) | 1 set (~6) | ~$0.50 | Generic | Direct I2S wiring, 3.3V tolerant |
| USB-A to USB-C cable | 1 | ~$3 | Generic | Power + programming |
| 100 nF ceramic capacitor | 1 | ~$0.10 | Generic | VDD decoupling on INMP441 |
| Wi-Fi router / AP | 1 | Existing | — | Home network |

**Total additional cost (excluding contest hardware): ~$6**

## Software / services used

| Tool / Service | Purpose |
|---|---|
| Arduino CLI / Arduino IDE | Build and flash firmware |
| Arduino App Lab | Deploy and run Linux app stack |
| Edge Impulse | Train/export TinyML model |
| Python 3 | Linux-side bridge and dashboard runtime |
| Flask + SSE | Local real-time web dashboard |
| GitHub | Source control and code publication |

## Build/deploy helpers

| Script / Command | Purpose |
|---|---|
| `bash scripts/setup.sh` | Local setup |
| `./deploy.sh all` | Deploy firmware + app |
| `./deploy.sh cycle` | End-to-end deploy + test cycle |
| `./deploy.sh bridge-test` | Focused bridge-path check |
