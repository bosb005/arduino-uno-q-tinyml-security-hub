# Demo Script — Edge AI Smart Security Hub

## Setup (before audience)
- Flash the latest MCU firmware and verify the Edge Impulse library is installed.
- Install or restart the dashboard service on the Linux side.
- Confirm the board has joined Wi-Fi and write down the local IP address.
- Open the dashboard once on a backup laptop/phone to confirm it loads.
- Keep a hard surface nearby for the clap/knock demo.
- Keep Arduino Serial Monitor ready at `115200` baud on the USB debug port.
- Quiet the room briefly before starting so the audience sees a stable idle state.

## Live Demo (5 minutes)

### Step 1 — 0:00 — Power on the board
**Action:** Apply power and begin speaking while Linux boots.

**Talking points:**
- “This is a privacy-first smart security node built on the Arduino UNO Q.”
- “The microphone feeds the MCU side for real-time audio inference, while the Linux side hosts the dashboard.”
- “Boot takes about 30 seconds because the board also runs a Linux environment.”

### Step 2 — 0:30 — Open the dashboard
**Action:** Open `http://[board-ip]:5000` in a browser and show the idle state.

**Talking points:**
- “The dashboard is served locally over Wi-Fi from the board itself.”
- “Idle is the baseline state, shown in green, with no cloud connection required.”
- “The browser only receives compact events, not raw audio.”

### Step 3 — 1:00 — Trigger `presence`
**Action:** Walk past the microphone or speak near it.

**Talking points:**
- “This class represents occupancy-like sound: footsteps, voices, or movement near the device.”
- “The model runs on-device and returns a confidence score in real time.”
- “You can see the badge change and the event appear in history immediately.”

### Step 4 — 1:30 — Trigger `anomaly`
**Action:** Knock firmly on the table or create a sharp loud impact.

**Talking points:**
- “Anomaly is for sudden, high-energy sounds like a bang, crash, or glass-like break.”
- “This is the kind of event a security workflow could escalate.”
- “Notice that the dashboard color changes to red for a more urgent state.”

### Step 5 — 2:00 — Trigger `manual_trigger`
**Action:** Perform a clear triple-clap pattern.

**Talking points:**
- “Manual trigger is an intentional user command implemented as a triple-clap pattern.”
- “That gives the system a hands-free local control gesture.”
- “Because inference is local, the response works without internet access.”

### Step 6 — 2:30 — Show event history
**Action:** Scroll through the event history table.

**Talking points:**
- “The dashboard keeps a recent history so users can see what happened without reading logs.”
- “Newest events are shown first with timestamps and confidence.”
- “This is enough for a lightweight local monitoring interface.”

### Step 7 — 3:00 — Show Serial Monitor
**Action:** Switch to Arduino Serial Monitor on USB.

**Talking points:**
- “USB Serial is reserved for debug output.”
- “Here you can see the raw class probabilities: presence, anomaly, manual trigger, and idle.”
- “That made threshold tuning and model validation much easier during development.”

### Step 8 — 3:30 — Prove it is offline-first
**Action:** Put your phone in airplane mode, then re-enable Wi-Fi only if needed so it stays on the local network, or otherwise disconnect upstream internet access.

**Talking points:**
- “This system does not depend on a cloud API.”
- “Detection continues because the model runs on the MCU and the dashboard is served locally.”
- “No raw audio leaves the device.”

### Step 9 — 4:00 — Explain the split architecture
**Action:** Point to the board while summarizing the two processing domains.

**Talking points:**
- “This side is the MCU: audio capture, MFCC extraction, and TinyML inference.”
- “This side is Linux: UART ingestion, Flask, SSE, and the Wi-Fi dashboard.”
- “The UNO Q makes this architecture neat because both roles live on one board.”

### Step 10 — 4:30 — Q&A
**Action:** Pause on the dashboard and invite questions.

**Suggested closing line:**
- “The main idea is simple: meaningful acoustic awareness, processed privately at the edge.”

## Backup Plan

### If the dashboard does not load
- Refresh once and confirm the IP address.
- SSH into the Linux side and restart the Flask service.
- If Wi-Fi is unstable, use a previously loaded browser page or local screen recording for the visual portion.

### If UART events are not arriving
- Check the `Serial1` wiring and shared ground.
- Confirm the service is reading the correct Linux UART device.
- Show the USB Serial Monitor to prove inference is still running on the MCU.

### If the classifier misses a gesture
- Repeat the trigger more clearly and closer to the microphone.
- Use the debug probabilities to explain that this is a prototype and environment matters.
- Fall back to a recorded short demo clip if the room is too noisy.

### If Linux boot is slower than expected
- Start the explanation earlier and use the boot time to introduce the problem and solution.
- Keep the browser tab ready so the dashboard appears as soon as the service is available.

### If the room is too loud
- Move the microphone closer to the demo area.
- Reduce audience chatter before the manual trigger step.
- Prioritize presence and anomaly first, then attempt triple-clap once the room settles.
