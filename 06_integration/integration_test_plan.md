# Integration Test Plan

This plan validates the full Edge AI Smart Security Hub pipeline end to end:

`INMP441 -> I2S -> MCU DMA buffer -> MFCC -> TinyML inference -> Serial1 JSON -> Linux UART -> Flask SSE -> Browser`

## Prerequisites

Before starting, confirm all of the following:
- INMP441 microphone is wired correctly to the Arduino UNO Q I2S-capable pins.
- Linux UART is wired to MCU `Serial1` with common ground.
- The latest audio firmware and inference firmware source are present in this repository.
- The Edge Impulse Arduino library ZIP has been exported and is available.
- The Linux dashboard dependencies can be installed on the board.
- The developer has USB access for the Arduino Serial Monitor and SSH access to the Linux side.
- Browser access to `http://<board-ip>:5000` is available from the same network.

---

## Phase 1 - MCU audio capture (standalone test)

Goal: verify microphone wiring, I2S configuration, and DMA frame capture before involving inference.

1. Open Arduino IDE.
2. Load `02_firmware_audio/audio_capture_test.ino`.
3. Select **Arduino UNO Q** as the target board.
4. Select the correct USB serial port.
5. Build and flash the sketch.
6. Open **Serial Monitor** at **115200 baud**.
7. Wait for startup text confirming the capture test is running.
8. Observe the baseline peak amplitude in a quiet room.
9. Make a sound near the microphone (speak, tap the table, clap lightly).
10. Verify the printed peak amplitude increases clearly during the sound.
11. Leave the room quiet again and verify the amplitude falls back near zero.
12. Keep watching for roughly 5 seconds and verify heartbeat-style output appears about once per second, including silence samples where amplitude remains `0` or near `0`.

**Expected result**
- Sound causes a visible amplitude increase.
- Silence produces low or zero values.
- Peak amplitude should exceed `500` during an obvious nearby sound.

**Pass criterion**
- Amplitude responds to sound and returns to low values in silence.

**If this phase fails**
- Do not continue to inference or dashboard testing.
- First fix wiring, power, I2S clocking, or board configuration.

---

## Phase 2 - MCU inference (with Edge Impulse library)

Goal: confirm the model runs on-device and classifies expected sounds.

1. Export the trained model from Edge Impulse as an **Arduino library ZIP**.
2. In Arduino IDE, select **Sketch -> Include Library -> Add .ZIP Library...**.
3. Choose the exported Edge Impulse ZIP.
4. Open `04_firmware_inference/inference_main.ino`.
5. Confirm the project still has access to `event_protocol.cpp` and `../02_firmware_audio/audio_capture.h`.
6. Select **Arduino UNO Q** and the correct USB port.
7. Build and flash the sketch.
8. Open **Serial Monitor** at **115200 baud**.
9. Wait for the boot line indicating the Security Hub is ready.
10. Speak near the microphone several times.
11. Verify `presence` becomes the top classification in the debug output.
12. Clap once loudly several times.
13. Verify `anomaly` appears in the debug output.
14. Perform the intended triple-clap pattern several times.
15. Verify `manual_trigger` appears in the debug output.
16. Leave the room quiet.
17. Verify `idle` appears only in debug output and is not treated as a transmitted event.
18. Repeat each class trigger at least five times.
19. Count successful recognitions for each target class.

**Expected result**
- `presence`, `anomaly`, and `manual_trigger` can each be triggered intentionally.
- `idle` dominates in a quiet room.
- Debug output shows probabilities and the winning class.

**Pass criterion**
- Correct classification occurs in at least **3 of 5 attempts per class**.

**Notes**
- If all classes stay close together with low confidence, revisit training quality and microphone gain/noise.
- If latency becomes visibly high, record approximate time between sound and printed output for later troubleshooting.

---

## Phase 3 - IPC validation

Goal: verify that the Linux side receives newline-delimited JSON over the hardware UART.

1. SSH into the Linux side of the UNO Q.
2. Configure the UART if needed:

```bash
stty -F /dev/ttyS1 115200 cs8 -cstopb -parenb -ixon -ixoff
```

3. Start a raw terminal read:

```bash
cat /dev/ttyS1
```

4. Reset or power-cycle the MCU if necessary.
5. Verify a boot heartbeat JSON message appears first.
6. Trigger `presence` on the MCU by speaking.
7. Verify a JSON line appears on Linux within **1 second**.
8. Trigger `anomaly` with a loud clap.
9. Verify a second JSON line appears on Linux within **1 second**.
10. Trigger `manual_trigger` with the configured triple-clap pattern.
11. Verify the corresponding JSON line appears.
12. Inspect several lines and confirm they are single-line JSON objects terminated by newline.
13. Confirm each message includes `"v":1`.
14. Confirm `idle` does **not** appear on the Linux terminal.
15. Stop `cat` with `Ctrl+C`.

**Expected result**
- Linux receives valid JSON messages for the boot heartbeat and each triggered event.
- Message order is consistent with the actions performed.

**Pass criterion**
- Valid JSON is received for each triggered event.

**Recommended spot checks**
- Confirm `confidence` is between `0.0` and `1.0`.
- Confirm `ts` increases over time.
- Confirm heartbeat messages continue every ~10 seconds.

---

## Phase 4 - Dashboard

Goal: verify serial ingestion, Flask API state handling, SSE streaming, and browser rendering.

1. SSH into the Linux side.
2. Install dashboard dependencies:

```bash
cd /home/user/dashboard
pip3 install -r requirements.txt
```

3. Start the Flask dashboard:

```bash
python3 app.py
```

4. From a browser, open:

```text
http://<board-ip>:5000
```

5. Verify the page loads without HTTP errors.
6. Verify the dashboard shows the idle state with the **green** badge after page load.
7. Trigger `presence` on the MCU.
8. Verify the badge changes to the **yellow** presence state within **2 seconds**.
9. Trigger `anomaly`.
10. Verify the badge changes to the **red** anomaly state within **2 seconds**.
11. Trigger `manual_trigger`.
12. Verify the badge changes to the **blue** manual trigger state within **2 seconds**.
13. Refresh the page and verify the current state reloads correctly from `/api/state`.
14. Verify the event history table populates with recent events.
15. Trigger multiple events and verify newest entries appear first.
16. Open browser developer tools and confirm the `/stream` connection remains open.

**Expected result**
- The dashboard loads, stays connected, and reflects incoming events promptly.
- The history table records received events in order.

**Pass criterion**
- All 4 states are displayed correctly and event history updates are visible.

---

## Phase 5 - Resilience

Goal: confirm the system survives transient failures without manual recovery steps.

1. Start with the dashboard already running and visible in a browser.
2. Disconnect USB or otherwise remove MCU power.
3. Wait **30 seconds**.
4. Verify the Flask app stays up and the browser page does not crash.
5. Verify the dashboard still shows the last known state rather than a blank page.
6. Reconnect or repower the MCU.
7. Wait for the MCU boot sequence.
8. Verify the Linux serial reader reconnects automatically.
9. Confirm fresh heartbeat or event data appears within **10 seconds** of MCU boot.
10. Stop Flask with `Ctrl+C`.
11. Restart it with `python3 app.py`.
12. Verify the app starts cleanly and reconnects to the serial port.
13. Trigger another event and verify it reaches the dashboard.

**Expected result**
- No crashes occur during disconnect/reconnect.
- Serial reconnection is automatic.
- Restarting Flask does not require board reboot.

**Pass criterion**
- No crashes, and auto-recovery is confirmed.

---

## Phase 6 - Boot sequence

Goal: validate the production-like power-on flow.

1. Power cycle the full board.
2. Wait for Linux to boot completely (approximately **30 seconds**).
3. SSH into the Linux side.
4. Verify the dashboard service starts automatically:

```bash
systemctl status security_hub
```

5. Confirm the service is `active (running)`.
6. Open the browser dashboard at `http://<board-ip>:5000`.
7. Verify the page loads without manually starting Flask.
8. Wait for the first heartbeat or trigger a test event.
9. Verify the dashboard begins updating normally.

**Expected result**
- After power-on, the software stack starts automatically.
- No manual SSH commands are required for normal operation.

**Pass criterion**
- Zero manual steps are required after power-on.

---

## Optional evidence collection

For repeatable validation, record the following during test execution:
- date/time of test run
- firmware commit or version used
- Edge Impulse model export name
- board IP address
- screenshots of each dashboard state
- a short UART capture showing heartbeat plus one event of each class
- any failure notes and the corrective action taken

## Final sign-off checklist

Mark the system ready only when all items below are true:
- [ ] Audio capture responds to real sound.
- [ ] Inference identifies all target classes at acceptable accuracy.
- [ ] Linux receives valid JSON over `/dev/ttyS1`.
- [ ] Dashboard reflects state changes within the stated timing limits.
- [ ] Event history populates and remains readable.
- [ ] Disconnect/reconnect behavior is stable.
- [ ] Boot-time service startup works without intervention.

