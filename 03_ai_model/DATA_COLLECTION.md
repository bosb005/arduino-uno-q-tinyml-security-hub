# Data Collection Guide

Good data matters more than model complexity. This guide explains how to collect clean, balanced audio samples for the **Edge AI Smart Security Hub**.

## A. Install Edge Impulse CLI

1. Install Node.js if needed.
2. Install the Edge Impulse CLI:

```bash
npm install -g edge-impulse-cli
edge-impulse-daemon
```

3. Follow the prompts to log in and link to your **`security-hub-acoustic`** project.
4. Confirm that the device or host audio source is connected in Edge Impulse.

---

## B. Recording per Class

### General recording rules

| Rule | Recommendation |
|---|---|
| Sample length | 1 second |
| Minimum per class | 50 samples |
| Better target per class | 100+ samples |
| Recording location | Actual deployment environment |
| Audio format | 16 kHz mono |

### Before you start

1. Mount the **INMP441 microphone** close to its final installed position.
2. Keep microphone orientation consistent across sessions.
3. Record in the real room where the device will run whenever possible.
4. Use the same room layout, furniture, and background noise conditions you expect during deployment.
5. Record at different times of day so the model learns realistic variation.

### Recommended microphone placement

- Place the microphone at about chest to head height if monitoring a room.
- Keep it away from fans, vents, and vibrating surfaces when possible.
- Do not place it directly against a wall or table unless that is the final installation.
- Leave a clear path between expected sound sources and the microphone.

---

### Class: `presence`

**Goal:** Capture normal human activity without alarm-like impact sounds.

| What to record | Examples |
|---|---|
| Movement | Footsteps, walking past the mic, shifting in a chair |
| Human sound | Quiet voices, short speech, breathing |
| Interaction sound | Clothing rustle, paper shuffle, light object handling |

#### How to record

1. Place the microphone in its normal monitoring position.
2. Walk past the microphone from different directions.
3. Speak at multiple distances, such as 1 m, 2 m, and across the room.
4. Shuffle papers or create soft movement sounds.
5. Record some subtle presence events, not only obvious ones.

#### Suggested collection plan

| Activity | Repetitions |
|---|---|
| Walking past mic | 20+ |
| Speaking short phrases | 20+ |
| Paper shuffle / movement | 10+ |
| Quiet breathing / near presence | 10+ |

---

### Class: `anomaly`

**Goal:** Capture short, sudden, high-energy sounds that should trigger alert behavior.

| What to record | Examples |
|---|---|
| Impact sounds | Bang, crash, dropped object |
| Sharp transients | Loud clap, hard knock |
| Simulated security events | Glass-break sound played from a phone |

#### How to record

1. Record only one anomaly event per 1-second clip when possible.
2. Keep the event near the middle of the clip if you are trimming manually.
3. Vary the loudness and distance from the microphone.
4. Use safe simulations for dangerous sounds.

#### Suggested collection plan

| Activity | Repetitions |
|---|---|
| Loud single clap | 15+ |
| Hard table knock | 15+ |
| Drop small object safely | 10+ |
| Play glass-break sound from phone | 10+ |

**Note:** A single loud clap belongs here unless it matches the full manual trigger pattern.

---

### Class: `manual_trigger`

**Goal:** Capture an intentional acoustic command pattern.

| Accepted patterns | Examples |
|---|---|
| 3-clap pattern | Exactly 3 hand claps in 1 second |
| Finger pattern | 3 finger snaps |
| Whistle pattern | Short whistle command |
| Knock pattern | Specific repeated knock sequence |

#### How to record

1. Pick one main trigger pattern and keep it consistent.
2. Recommended default: **exactly 3 claps within 1 second**.
3. Record the trigger from different distances and directions.
4. Include variations by different people if multiple users may trigger the system.
5. Make sure the full pattern fits inside the 1-second sample.

#### Suggested collection plan

| Activity | Repetitions |
|---|---|
| 3 claps in 1 second | 30+ |
| 3 finger snaps | 10+ |
| Whistle trigger | 10+ |
| Knock sequence | 10+ |

**Important:** Label samples carefully. Three quick claps belong in `manual_trigger`, not `anomaly`.

---

### Class: `idle`

**Goal:** Teach the model what normal background sound looks like.

| What to record | Examples |
|---|---|
| Quiet background | Silence, low ambient room tone |
| Building noise | HVAC hum, fan noise, refrigerator |
| Everyday noise | Distant TV, faint street noise, nighttime room ambience |

#### How to record

1. Record with no intentional event in the room.
2. Collect clips during multiple normal conditions.
3. Include background sounds the system will see in real life.
4. Record both very quiet and mildly noisy idle states.

#### Suggested collection plan

| Activity | Repetitions |
|---|---|
| Quiet room / silence | 20+ |
| AC or HVAC running | 15+ |
| TV in background | 10+ |
| Nighttime ambience | 10+ |

---

## C. Quality Control

### Review every batch

1. Listen to samples before uploading or labeling.
2. Delete clips that contain multiple different events.
3. Remove badly clipped, distorted, or accidental recordings.
4. Check that labels match the actual sound.

### Keep the dataset balanced

- Keep class counts within **20%** of each other.
- Avoid collecting 200 `idle` samples and only 50 `manual_trigger` samples.
- If one class grows too quickly, prioritize the weaker classes next.

### Split recommendation

Use the Edge Impulse auto-split:

| Split | Recommendation |
|---|---|
| Training | 80% |
| Testing | 20% |

### Common mistakes to avoid

| Mistake | Why it hurts |
|---|---|
| Multiple events in one clip | Confuses labels |
| Recording only one loudness level | Poor generalization |
| Recording in a different room than deployment | Weak real-world accuracy |
| Unbalanced classes | Biased predictions |
| Trigger pattern not consistent | Manual trigger becomes unreliable |

---

## Minimum Dataset Target

| Class | Minimum samples | Better target |
|---|---:|---:|
| presence | 50 | 100+ |
| anomaly | 50 | 100+ |
| manual_trigger | 50 | 100+ |
| idle | 50 | 100+ |

Minimum total: **200 samples**

Recommended total: **400+ samples**

---

## Final Checklist

- [ ] Edge Impulse CLI installed
- [ ] Project linked with `edge-impulse-daemon`
- [ ] Microphone placed close to final deployment position
- [ ] At least 50 samples per class collected
- [ ] Targeting 100+ samples per class
- [ ] Samples recorded in the real deployment environment
- [ ] Samples reviewed before upload
- [ ] Classes balanced within 20%
- [ ] Train/test split set to 80/20
