# Demo Script — Edge AI Smart Security Hub

## Setup (before audience)

1. Deploy latest build: `./deploy.sh all`.
2. Confirm health endpoint responds: `http://<board-ip>:7000/health`.
3. Open dashboard once on backup device to verify UI loads.
4. Keep Arduino Serial Monitor ready at `115200` baud (USB debug).
5. Keep a hard surface nearby for anomaly trigger (knock/clap).
6. Quiet the room briefly before live trigger sequence.

## Live demo sequence (4-6 minutes)

### Step 1 — Power on and story hook
**Action:** Apply power and explain the problem while Linux boots.

**Say:**  
"Cloud-connected security products can leak privacy and fail when internet is unreliable. This project keeps inference local on Arduino UNO Q."

### Step 2 — Open local dashboard
**Action:** Open `http://<board-ip>:7000` and show idle state.

**Say:**  
"The dashboard is local to the board, and only compact event messages are shown."

### Step 3 — Trigger `presence`
**Action:** Walk/speak near microphone.

**Expected:** Yellow/presence state appears with confidence and history entry.

### Step 4 — Trigger `anomaly`
**Action:** Sharp knock or loud clap.

**Expected:** Red/anomaly state appears.

### Step 5 — Trigger `manual_trigger`
**Action:** Clear triple-clap pattern.

**Expected:** Blue/manual trigger state appears.

### Step 6 — Show evidence panel
**Action:** Scroll event history and open Serial Monitor.

**Say:**  
"History shows timestamps and confidence; serial output shows the raw class behavior used for tuning."

### Step 7 — Prove offline-first behavior
**Action:** Disconnect upstream internet (keep local Wi-Fi) and retrigger one event.

**Say:**  
"Inference still works because compute is on-device; no raw audio is sent to cloud APIs."

### Step 8 — Close on architecture
**Action:** Point to board and summarize split runtime.

**Say:**  
"MCU side does audio + TinyML, Linux side does UI + networking. UNO Q lets both run on one board."

## Capture list during demo (for Hackster article proof)

1. Dashboard idle screenshot.
2. Presence/anomaly/manual_trigger screenshots.
3. Event history screenshot.
4. Serial monitor screenshot.
5. 30-60s video clip of full trigger sequence.

## Backup plan

### If dashboard does not load
- Recheck board IP and port `7000`.
- Run `bash scripts/health-check.sh --json`.
- If needed, use pre-recorded proof clip and continue explanation.

### If events are not updating
- Verify microphone wiring and shared ground.
- Run `./deploy.sh bridge-test`.
- Use Serial Monitor output as fallback evidence of MCU inferencing.

### If room noise is too high
- Move mic closer to source.
- Demonstrate anomaly first (higher energy), then manual trigger.
