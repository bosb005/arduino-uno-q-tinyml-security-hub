# IPC Protocol Specification

## Overview

This document defines the serial IPC between the Arduino UNO Q MCU firmware and the Linux dashboard stack for the Edge AI Smart Security Hub.

**Pipeline:** `INMP441 -> I2S -> MCU DMA buffer -> MFCC (Edge Impulse) -> TinyML inference -> Serial1 JSON -> Linux UART -> Flask SSE -> Browser`

## 1. Transport layer

| Item | Value |
| --- | --- |
| Physical link | TTL UART |
| MCU endpoint | `Serial1` |
| Linux endpoint | `/dev/ttyS1` |
| Baud rate | `115200` |
| Data bits | `8` |
| Parity | `N` |
| Stop bits | `1` |
| Flow control | None |
| Direction | MCU -> Linux (current implementation) |
| Encoding | UTF-8 |

Notes:
- `Serial` over USB is reserved for debug logging.
- `Serial1` is the production IPC channel used by the Linux application.
- TX/RX must be crossed and grounds must be common.

## 2. Framing

Each IPC message is sent as:
- one UTF-8 JSON object
- terminated by a single newline character (`\n`)
- exactly one message per line
- maximum line length: **256 characters**

Example wire format:

```text
{"v":1,"event":"heartbeat","uptime":0,"ts":0,"free_mem":0}\n
{"v":1,"event":"presence","confidence":0.92,"ts":12345}\n
```

Receiver requirements:
- read by line boundary (`\n`)
- treat each line as an independent JSON object
- ignore empty lines
- discard lines longer than 256 characters
- skip malformed JSON without terminating the reader loop

## 3. Versioning

All messages include a top-level version field:

| Field | Type | Required | Value |
| --- | --- | --- | --- |
| `v` | integer | yes | `1` |

Purpose:
- allows future schema evolution
- lets Linux support multiple protocol revisions if needed
- keeps backward-incompatible changes explicit

## 4. Message types

### 4.1 Summary table

| Message type | When emitted | Required fields |
| --- | --- | --- |
| `event` | When inference detects a non-idle class above threshold | `v`, `event`, `confidence`, `ts` |
| `heartbeat` | At boot and then periodically every 10 seconds | `v`, `event`, `uptime`, `ts`, `free_mem` |

### 4.2 Event message schema

`event` messages are emitted only for actionable classes. `idle` is **not** emitted over IPC.

| Field | Type | Required | Constraints | Description |
| --- | --- | --- | --- | --- |
| `v` | integer | yes | must be `1` | Protocol version |
| `event` | string | yes | one of `presence`, `anomaly`, `manual_trigger` | Classified acoustic event |
| `confidence` | float | yes | `0.0` to `1.0`, formatted to 2 decimal places | Confidence score for the emitted class |
| `ts` | unsigned integer | yes | `millis()` since MCU boot | Event timestamp from the MCU |

JSON schema:

```json
{
  "type": "object",
  "required": ["v", "event", "confidence", "ts"],
  "properties": {
    "v": { "type": "integer", "const": 1 },
    "event": {
      "type": "string",
      "enum": ["presence", "anomaly", "manual_trigger"]
    },
    "confidence": {
      "type": "number",
      "minimum": 0.0,
      "maximum": 1.0
    },
    "ts": {
      "type": "integer",
      "minimum": 0
    }
  },
  "additionalProperties": false
}
```

### 4.3 Heartbeat message schema

Heartbeats provide liveness and runtime status.

| Field | Type | Required | Constraints | Description |
| --- | --- | --- | --- | --- |
| `v` | integer | yes | must be `1` | Protocol version |
| `event` | string | yes | must be `heartbeat` | Message discriminator |
| `uptime` | unsigned integer | yes | `millis()` since MCU boot | MCU uptime in milliseconds |
| `ts` | unsigned integer | yes | normally identical to `uptime` | Timestamp included for uniform downstream handling |
| `free_mem` | unsigned integer | yes | board-specific value | Free memory estimate from the MCU |

JSON schema:

```json
{
  "type": "object",
  "required": ["v", "event", "uptime", "ts", "free_mem"],
  "properties": {
    "v": { "type": "integer", "const": 1 },
    "event": { "type": "string", "const": "heartbeat" },
    "uptime": {
      "type": "integer",
      "minimum": 0
    },
    "ts": {
      "type": "integer",
      "minimum": 0
    },
    "free_mem": {
      "type": "integer",
      "minimum": 0
    }
  },
  "additionalProperties": false
}
```

## 5. Event classes

Only the following inference classes are emitted to Linux:

| Class | Meaning | Emitted over `Serial1` |
| --- | --- | --- |
| `presence` | Human speech / occupancy-like acoustic presence | Yes |
| `anomaly` | Sudden abnormal acoustic event | Yes |
| `manual_trigger` | Explicit alarm pattern such as triple-clap | Yes |
| `idle` | No actionable event | **No** |

`idle` remains available on the USB debug console but is intentionally suppressed from IPC to avoid unnecessary dashboard churn.

## 6. Timestamp semantics

- `ts` uses `millis()` measured from MCU boot.
- `millis()` overflows after approximately **49.7 days** on a 32-bit unsigned counter.
- Linux consumers must treat `ts` as a relative device uptime marker, not as wall-clock time.
- If absolute time is needed, Linux should add its own receipt timestamp when a message arrives.

## 7. Startup behavior

Expected boot sequence:
1. MCU boots.
2. `Serial1` is initialized.
3. MCU emits an initial heartbeat with `uptime=0` and `ts=0`.
4. Audio capture and inference loop run continuously.
5. Non-idle events are emitted on detection.
6. Additional heartbeat messages are emitted every 10 seconds.

This boot heartbeat must be sent **before the first inference result** so the Linux side can distinguish "alive but idle" from "not connected".

## 8. Error handling requirements

### Linux receiver

The Linux side must:
- skip malformed JSON lines and continue reading
- discard lines longer than 256 characters
- tolerate UTF-8 decode issues by dropping invalid bytes or skipping the line
- recover from UART disconnects by reopening the serial device
- continue serving the dashboard even when serial input is temporarily unavailable

### MCU sender

The MCU side should:
- emit only complete newline-terminated JSON objects
- never emit partial multi-line JSON payloads
- suppress `idle` IPC messages
- keep each line within the 256-character framing limit

## 9. Example messages

```json
{"v":1,"event":"heartbeat","uptime":0,"ts":0,"free_mem":0}
{"v":1,"event":"presence","confidence":0.92,"ts":12345}
{"v":1,"event":"anomaly","confidence":0.81,"ts":18762}
{"v":1,"event":"manual_trigger","confidence":0.95,"ts":24110}
{"v":1,"event":"heartbeat","uptime":30000,"ts":30000,"free_mem":0}
```

## 10. State machine

Text description of the MCU communication state machine:

1. **MCU starts**
   - Hardware initializes.
   - `Serial1` becomes available.
2. **Emit boot heartbeat**
   - Send a heartbeat with `uptime=0` and `ts=0`.
   - This confirms the IPC path is alive before any classification output exists.
3. **Enter inference loop**
   - Read I2S audio via DMA-backed buffers.
   - Run MFCC + Edge Impulse inference.
4. **Emit events**
   - If the top class is `presence`, `anomaly`, or `manual_trigger` and exceeds threshold, emit one event message.
   - If the top class is `idle`, do not emit an IPC event.
5. **Emit periodic heartbeats**
   - Every 10 seconds, send a heartbeat regardless of classification activity.
6. **Continue until reset or power loss**
   - On reboot, the state machine restarts from step 1.

## 11. Consumer notes for the Flask dashboard

Recommended Linux handling flow:
1. Open `/dev/ttyS1` at `115200 8N1`.
2. Read newline-delimited messages.
3. Parse JSON.
4. Ignore heartbeats for UI state transitions unless explicitly displaying liveness.
5. Update current event state from non-heartbeat messages.
6. Push state updates to browsers over SSE.

