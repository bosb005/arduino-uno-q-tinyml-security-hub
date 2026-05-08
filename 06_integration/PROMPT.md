# Task: Integration — MCU ↔ Linux End-to-End System

## Context

This task ties all previous components together and validates the full pipeline:

```
INMP441 → I2S → MCU (DMA buffer) → MFCC → TinyML inference → Serial JSON → Linux UART → Flask → Browser
```

Dependencies (must be complete before this task):
- `../02_firmware_audio/` — I2S audio capture firmware
- `../04_firmware_inference/` — Inference + serial event output
- `../05_linux_dashboard/` — Flask web server + SSE

## Your Task

### 1. `IPC_PROTOCOL.md` — Formal IPC specification
Document the serial protocol between MCU and Linux:

**Transport:** UART (`Serial1` on MCU ↔ `/dev/ttyS1` on Linux), 115200 8N1

**Message format:** newline-terminated JSON
```json
{"event":"<class>","confidence":<0.0-1.0>,"ts":<ms_since_boot>}
```

**Event classes:** `presence`, `anomaly`, `manual_trigger`
(idle is NOT emitted — absence of events implies idle)

**Error/heartbeat message (every 10 s):**
```json
{"event":"heartbeat","uptime":<ms>,"free_mem":<bytes>}
```

### 2. `integration_test_plan.md`
Step-by-step validation procedure:
1. Flash MCU firmware (tasks 02 + 04 combined sketch)
2. Verify audio capture: Serial monitor shows amplitude values
3. Verify inference: Serial monitor shows classification output
4. Verify IPC: `cat /dev/ttyS1` on Linux shows JSON lines
5. Start Flask dashboard, open browser at `http://<board-ip>:5000`
6. Trigger each event class; verify dashboard updates within 2 s
7. Simulate UART disconnect; verify Flask reconnects

### 3. `combined_firmware/` (directory stub)
Placeholder with a `README.md` explaining how to combine sketches from 02 + 04 into a single `.ino` project for flashing.

### 4. `TROUBLESHOOTING.md`
Common issues and fixes:
- I2S init fails → check wiring, verify I2S library version
- Inference too slow → reduce MFCC coefficients or Dense layer size
- UART garbage data → verify baud rate matches on both sides
- Dashboard not updating → check SSE connection, check UART device name
- Flask crashes → check Python version, install pyserial

## Notes
- The MCU and Linux side boot independently; the Linux daemon must tolerate MCU not being ready yet
- Use heartbeat messages to detect MCU resets from the Linux side
- Test Wi-Fi range in the intended deployment location
