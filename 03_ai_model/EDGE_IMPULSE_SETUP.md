# Edge Impulse Setup Guide

This guide walks you through creating, training, validating, quantizing, and exporting the AI model for the **Edge AI Smart Security Hub**.

## Project Summary

| Item | Value |
|---|---|
| Platform | Edge Impulse |
| Project name | `security-hub-acoustic` |
| Target device | Arduino UNO Q |
| Microcontroller | Renesas RA4M1 |
| Audio input | INMP441 microphone |
| Sample rate | 16 kHz mono |
| Classes | `presence`, `anomaly`, `manual_trigger`, `idle` |

---

## A. Project Creation

### Option 1: Create the project in the browser

1. Open [https://edgeimpulse.com](https://edgeimpulse.com).
2. Sign up for an account, or log in if you already have one.
3. Click **Create new project**.
4. Enter the project name: **`security-hub-acoustic`**.
5. Open the new project dashboard.
6. Go to **Devices**.
7. Click **Connect a new device**.
8. Select **Arduino UNO Q** if it is available in the device list.
9. If you are collecting data from a computer instead of directly from the board, continue with the CLI option below.

### Option 2: Connect using the Edge Impulse CLI

1. Install Node.js if it is not already installed.
2. Install the Edge Impulse CLI tools:

```bash
npm install -g edge-impulse-cli
```

3. Start the device/data connection tool:

```bash
edge-impulse-daemon
```

4. Follow the prompts:
   1. Log in to your Edge Impulse account.
   2. Select the project **`security-hub-acoustic`**.
   3. Confirm the device or audio source.
5. Once connected, verify that the device appears in **Dashboard → Devices**.

### Recommended acquisition settings

When recording or uploading data, use these settings:

| Setting | Value |
|---|---|
| Audio type | Mono |
| Sample rate | 16000 Hz |
| Sample length | 1000 ms |
| Window increase | 500 ms |

---

## B. Impulse Design

After data collection starts, create the impulse pipeline.

1. In Edge Impulse, open **Impulse design**.
2. Set the input block to **Audio**.
3. Use these exact parameters:

| Parameter | Value |
|---|---|
| Sample rate | 16000 Hz |
| Window size | 1000 ms |
| Window increase | 500 ms |

4. Click **Add processing block** and select **MFCC**.
5. Click **Add learning block** and select **Classification (Neural Network)**.
6. Save the impulse.

### MFCC settings

Open the MFCC processing block and enter these exact values:

| Setting | Value |
|---|---|
| Frame length | 25 ms |
| Frame stride | 10 ms |
| Num coefficients | 13 |
| FFT length | 512 |
| Low frequency | 300 Hz |
| High frequency | 8000 Hz |
| Noise floor | -52 dB |

7. Generate features after applying the settings.
8. Review the feature explorer to check whether classes start to separate visually.

---

## C. Neural Network Architecture

Use a simple dense classifier as the first production model.

### Recommended architecture

```text
Input (MFCC features: ~1170 values for 1 s window)
→ Dense(64, relu)
→ Dropout(0.25)
→ Dense(32, relu)
→ Dropout(0.25)
→ Dense(4, softmax)
```

### Training settings

| Setting | Value |
|---|---|
| Epochs | 100 |
| Learning rate | 0.0005 |
| Batch size | 32 |
| Data augmentation | Add noise |

### Steps

1. Open the **Classifier** or **NN Classifier** page in Edge Impulse.
2. If Edge Impulse auto-generates a different model, switch to expert/custom settings if needed.
3. Configure the network to match the architecture above.
4. Set **epochs** to `100`.
5. Set the **learning rate** to `0.0005`.
6. Set the **batch size** to `32`.
7. Enable **data augmentation** and add noise augmentation.
8. Start training.

### Why this architecture fits the Arduino UNO Q

- It is small enough to have a good chance of fitting on the RA4M1.
- It is simple to debug and retrain.
- It is a strong baseline for four-class acoustic classification.

---

## D. Training and Validation

After training finishes, validate the model carefully before export.

### Targets

| Check | Goal |
|---|---|
| Test accuracy | Greater than 85% |
| Quantization | INT8 enabled |
| RAM usage | Must fit within 128 KB |
| Flash usage | Must fit within 256 KB |

### Validation steps

1. Open the **Model testing** page.
2. Run inference on the held-out test data.
3. Confirm that the overall test accuracy is **above 85%**.
4. Review the **confusion matrix**.
5. Pay special attention to **`presence` vs `idle`**, because this is usually the hardest pair.
6. Check whether `manual_trigger` is clearly separated from `anomaly`.
7. If the model performs poorly:
   1. Add more real-world data.
   2. Improve class balance.
   3. Add more examples of quiet presence events.
   4. Add more realistic idle/background recordings.

### Memory check

Before export, verify the estimated model size:

- **RAM limit:** 128 KB
- **Flash limit:** 256 KB

If the model is too large:

1. Reduce Dense layer sizes.
2. Reduce MFCC complexity only if accuracy remains acceptable.
3. Retrain and test again.

---

## E. INT8 Quantization and Export

Use quantization before deployment to reduce memory usage.

### Quantization steps

1. In the training or deployment workflow, enable **INT8 quantization**.
2. Open **Model testing** and run tests with the **quantized model**.
3. Confirm that accuracy remains acceptable after quantization.

### Export steps

1. Open the **Deployment** tab.
2. Select **Arduino library**.
3. Click **Build**.
4. Wait for the build to finish.
5. Download the generated ZIP file.
6. Save the ZIP for use in the Arduino firmware project.

---

## Final Checklist

- [ ] Project name is `security-hub-acoustic`
- [ ] Audio input is 16 kHz mono
- [ ] Window size is 1000 ms
- [ ] Window increase is 500 ms
- [ ] MFCC settings match the table exactly
- [ ] Neural network matches the recommended architecture
- [ ] Training used 100 epochs, LR 0.0005, batch size 32
- [ ] Noise augmentation is enabled
- [ ] Test accuracy is above 85%
- [ ] Confusion matrix reviewed
- [ ] INT8 quantization enabled and tested
- [ ] RAM and flash fit the Arduino UNO Q limits
- [ ] Arduino library ZIP exported
