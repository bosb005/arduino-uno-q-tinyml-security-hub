# Troubleshooting Guide

Use this guide to diagnose common integration issues in the Edge AI Smart Security Hub.

Format used in each section:
- **Problem** - what you observe
- **Cause** - the most likely reason
- **Fix** - step-by-step corrective action

---

## Hardware / I2S

### 1. I2S init fails (no audio data)

| Item | Details |
| --- | --- |
| Problem | `audio_init()` fails, the sketch prints an initialization error, or no audio capture starts. |
| Cause | Wrong board selected, missing UNO Q core support, unsupported I2S backend, or invalid microphone wiring. |
| Fix | 1. In Arduino IDE, confirm **Arduino UNO Q** is selected. 2. Update the Arduino UNO Q board package to the latest available version. 3. Reopen the sketch after updating the board core. 4. Verify the INMP441 is wired to the board's I2S-capable pins, not arbitrary GPIOs. 5. Recheck `VDD`, `GND`, `SCK`, `WS/LRCLK`, and `SD`. 6. Upload `02_firmware_audio/audio_capture_test.ino` and verify capture before returning to inference. |

### 2. Constant 0 amplitude / clipping

| Item | Details |
| --- | --- |
| Problem | The audio test prints constant zero values, or values pin near full scale all the time. |
| Cause | No microphone data, wrong channel selection, bad power, broken clocking, or incorrect 24-bit-to-16-bit handling. |
| Fix | 1. Verify the microphone is powered from **3.3 V**, not 5 V unless the module explicitly supports it. 2. Confirm common ground between microphone and board. 3. Tie the INMP441 `L/R` pin correctly so the firmware reads the active slot. 4. Check that I2S word select and bit clock are present on the expected pins. 5. Run the audio capture test in silence and while tapping near the mic. 6. If values stay at `32767` or `-32768`, inspect sample shifting/scaling in the audio capture path. |

### 3. Noise/hum in audio

| Item | Details |
| --- | --- |
| Problem | The system reacts to background hum, mains noise, or unstable peaks even in a quiet room. |
| Cause | Poor grounding, long unshielded wires, noisy power, or microphone placement near interference sources. |
| Fix | 1. Shorten microphone wiring where possible. 2. Twist or route clock/data lines away from noisy power wiring. 3. Ensure all grounds are firmly connected. 4. Move the microphone away from Wi-Fi modules, switching regulators, and speakers. 5. Test from a stable USB power source. 6. Re-record model samples if the deployment environment is much noisier than training conditions. |

---

## Inference

### 4. Inference too slow (>300 ms)

| Item | Details |
| --- | --- |
| Problem | Events appear noticeably late, or profiling/debug logs suggest inference takes more than 300 ms. |
| Cause | Model too large, DSP block too expensive, board running slower than expected, or debug output adding overhead. |
| Fix | 1. Measure time from sound to output using Serial Monitor logs. 2. Re-export a smaller Edge Impulse model if needed. 3. Reduce model complexity or feature window size in Edge Impulse. 4. Temporarily reduce verbose debug printing and compare latency. 5. Retest on the same board/core version intended for deployment. |

### 5. All classifications return `idle`

| Item | Details |
| --- | --- |
| Problem | The debug console always reports `idle`, even when speaking or clapping near the microphone. |
| Cause | Audio level too low, wrong feature extraction input, model mismatch, or confidence threshold too high. |
| Fix | 1. First verify raw amplitude using `audio_capture_test.ino`. 2. Confirm the correct Edge Impulse ZIP is installed and matches the intended project. 3. Make sure the inference sketch is using the expected sample rate and frame length. 4. Inspect printed class probabilities to see whether the target class is close but below threshold. 5. If needed, lower `CONFIDENCE_THRESHOLD` slightly and retest. 6. If probabilities remain poor, retrain the model with better representative samples. |

### 6. Low confidence on all classes

| Item | Details |
| --- | --- |
| Problem | The correct class sometimes appears, but with weak confidence across all labels. |
| Cause | Training data quality is poor, room acoustics differ from training, microphone gain/noise is inconsistent, or the wrong exported model is loaded. |
| Fix | 1. Compare deployment environment sounds to the recordings used during training. 2. Re-collect clean examples for `presence`, `anomaly`, `manual_trigger`, and `idle`. 3. Balance class counts in Edge Impulse. 4. Re-export and reinstall the updated ZIP library. 5. Retest each class at least five times and log the confidence values. |

### 7. Edge Impulse library not found

| Item | Details |
| --- | --- |
| Problem | The sketch fails to compile and reports that `security-hub-acoustic_inferencing.h` is missing. |
| Cause | The Arduino ZIP library was not installed, was installed incorrectly, or the wrong export was used. |
| Fix | 1. In Edge Impulse, export the project as an **Arduino library** ZIP. 2. In Arduino IDE, use **Sketch -> Include Library -> Add .ZIP Library...**. 3. Select the ZIP you just exported. 4. Reopen the sketch. 5. Verify the compile error is gone before flashing. |

---

## IPC / Serial

### 8. No data on `/dev/ttyS1`

| Item | Details |
| --- | --- |
| Problem | `cat /dev/ttyS1` shows nothing, even when the MCU is running. |
| Cause | Wiring issue, wrong Linux device, wrong baud rate, boot not completed, or MCU not sending on `Serial1`. |
| Fix | 1. Verify Linux has finished booting. 2. Check UART wiring: MCU `TX1` -> Linux RX, optional RX return line, and common ground. 3. Run `stty -F /dev/ttyS1 115200 cs8 -cstopb -parenb -ixon -ixoff`. 4. Power-cycle the MCU and look for the boot heartbeat first. 5. Confirm the inference firmware is flashed, not the audio-only test sketch. 6. If available, use an oscilloscope or logic analyzer on `TX1` to confirm activity. |

### 9. Garbage/corrupted data

| Item | Details |
| --- | --- |
| Problem | The Linux terminal shows unreadable characters or broken JSON fragments. |
| Cause | Baud mismatch, wrong UART mode, noise on the serial lines, missing ground, or voltage-level mismatch. |
| Fix | 1. Confirm both MCU and Linux use **115200 8N1**. 2. Re-run `stty` on Linux with explicit settings. 3. Verify the link is TTL UART, not RS-232 levels. 4. Recheck common ground. 5. Shorten wiring and keep UART lines away from noisy power paths. 6. Retest with only the UART path connected if needed. |

### 10. Events arrive but JSON parse fails

| Item | Details |
| --- | --- |
| Problem | The serial reader logs malformed JSON warnings, even though bytes are arriving. |
| Cause | Lines are truncated, oversized, corrupted by noise, or multiple messages are merged due to framing issues. |
| Fix | 1. Inspect raw UART output with `cat /dev/ttyS1`. 2. Confirm each message is a single line ending in `\n`. 3. Verify line length stays below 256 characters. 4. Check that the MCU is emitting compact JSON with no debug text on `Serial1`. 5. Verify only `Serial` is used for USB debug logs and `Serial1` is dedicated to IPC. 6. If corruption persists, fix baud, grounding, or electrical noise first. |

### 11. Serial1 not available on this board

| Item | Details |
| --- | --- |
| Problem | The selected board/core does not expose `Serial1`, or compilation/runtime behavior suggests it is unavailable. |
| Cause | Wrong board package, outdated core, or using a board variant that does not match the project assumptions. |
| Fix | 1. Confirm you selected **Arduino UNO Q** specifically. 2. Update the board package and review its hardware serial support notes. 3. Test a minimal sketch that writes to `Serial1`. 4. If `Serial1` truly is unavailable in your environment, remap the IPC path to a supported hardware UART before continuing integration. |

---

## Dashboard

### 12. Dashboard not loading (connection refused)

| Item | Details |
| --- | --- |
| Problem | The browser cannot open `http://<board-ip>:7000` and reports connection refused or timeout. |
| Cause | App is not running on device, wrong IP, router/app-cli startup issue, or network/firewall block. |
| Fix | 1. Run `./deploy.sh status` from repo root. 2. Run `curl -sf http://<board-ip>:7000/health` and confirm JSON is returned. 3. If app is missing/stopped, redeploy with `./deploy.sh all`. 4. If needed, inspect runtime output with `./deploy.sh logs`. 5. Recheck `DEVICE_IP` and SSH reachability (`bash scripts/health-check.sh --json`). |

### 13. Dashboard loads but badge never updates

| Item | Details |
| --- | --- |
| Problem | Dashboard is reachable, but event state appears stuck/empty even after known sound triggers. |
| Cause | Bridge callback starvation, first-event not yet observed, provider registration failure, stale event stream, or client stream issue. |
| Fix | 1. Check health bridge fields: `curl -sf http://<board-ip>:7000/health | python3 -m json.tool`. 2. Interpret `bridge.state`: `waiting_for_events` (no events yet), `alive` (events flowing), `stale` (callback starvation). 3. Check `provider_registered`, `provider_registration_error`, `last_event_age_ms`, and `stale_after_ms`. 4. Run `bash scripts/health-check.sh --json --require-bridge-fresh` (this fails when dashboard is healthy but bridge events are stale/not advancing). 5. Compare `/state` snapshots a few seconds apart: `curl -sf http://<board-ip>:7000/state | python3 -m json.tool` and verify `bridge_last_event_ms` advances after a trigger. 6. If `/health` reports bridge alive but UI still does not update, confirm browser `/stream` connection and console errors. |

### 14. SSE disconnects frequently

| Item | Details |
| --- | --- |
| Problem | The dashboard updates briefly, then stops or reconnects repeatedly. |
| Cause | Reverse proxy buffering, unstable network, browser timeout, or the Flask app restarting. |
| Fix | 1. Verify Flask stays running without crashes. 2. Confirm the app sends SSE keepalive comments periodically. 3. If using a proxy, disable response buffering for `/stream`. 4. Test on the same LAN to rule out Wi-Fi instability. 5. Watch browser network tools for reconnect timing and HTTP errors. |

### 15. History table not scrolling

| Item | Details |
| --- | --- |
| Problem | New rows appear but the history panel does not scroll as expected or becomes hard to use. |
| Cause | CSS overflow settings, container height limits, or browser rendering differences. |
| Fix | 1. Inspect the history container in browser developer tools. 2. Verify `overflow-y` and height constraints are applied to the table wrapper. 3. Trigger enough events to exceed the visible panel height. 4. Test in another browser to determine whether the issue is browser-specific. 5. If needed, adjust the dashboard CSS while preserving the responsive layout. |

---

## Boot / Service

### 16. App process fails to start after deploy

| Item | Details |
| --- | --- |
| Problem | `./deploy.sh all` uploads firmware/app, but dashboard never becomes reachable on port 7000. |
| Cause | App import/start failure, app-cli/router unavailable, bad environment config, or deployment interruption. |
| Fix | 1. Run `./deploy.sh status` and confirm app-cli API + dashboard checks. 2. Run `./deploy.sh app-list` to verify the app is installed. 3. Restart app by redeploying (`./deploy.sh all`) or use app start/stop commands if needed. 4. Review startup output via `./deploy.sh logs`. 5. Verify `deploy.env` values (`DEVICE_IP`, `APP_CLI_PORT`, `APP_NAME`) are correct. |

### 17. App starts but bridge registration fails

| Item | Details |
| --- | --- |
| Problem | `/health` returns `provider_registered=false` and `provider_registration_error` is populated. |
| Cause | `Bridge.provide("acoustic_event", ...)` registration failed (router socket/runtime issue). |
| Fix | 1. Query `curl -sf http://<board-ip>:7000/health | python3 -m json.tool`. 2. Inspect `provider_registration_error` details. 3. Restart deployment path with `./deploy.sh all` (restarts app/runtime path). 4. Re-run `bash scripts/health-check.sh --json --require-bridge-fresh`. 5. If still failing, capture `./deploy.sh logs` and verify router/app-cli availability with `./deploy.sh status`. |

### 18. Deploy test passes preflight but post-restore events do not recover

| Item | Details |
| --- | --- |
| Problem | `./deploy.sh test` fails on bridge freshness or continuity checks after bridge/audio test restore. |
| Cause | Dashboard endpoint is healthy, but `acoustic_event` callback is no longer advancing (stale bridge path). |
| Fix | 1. Run `./deploy.sh test` again and note the bridge health summary in failure output. 2. Query `/health` and check `bridge.state`, `last_event_age_ms`, and `failure_point`. 3. Trigger known audio events and confirm `/state` `bridge_last_event_ms` changes. 4. Run `bash scripts/health-check.sh --json --require-bridge-fresh` until it returns `status=ok`. 5. If still stale, redeploy full stack with `./deploy.sh all` before retesting. |

---

## Quick triage order

When the system fails end to end, debug in this order:
1. **Audio capture** - does the microphone produce changing amplitude?
2. **Inference** - do debug logs classify real sounds?
3. **UART** - does `/dev/ttyS1` receive valid JSON?
4. **Dashboard health** - does `curl -sf http://<board-ip>:7000/health` report `dashboard.healthy=true`?
5. **Bridge freshness** - does `bash scripts/health-check.sh --json --require-bridge-fresh` pass?
6. **State advancement** - does `/state` show `bridge_last_event_ms` moving after real triggers?
7. **Browser stream** - does `/stream` stay connected and update the UI?
