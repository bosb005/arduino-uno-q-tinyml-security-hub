# Retraining Guide

Use this guide when the current model is no longer accurate enough or when the environment changes.

## When to Retrain

Retrain the model when:

1. Accuracy drops during real-world use.
2. The device is moved to a new room or building.
3. Background noise changes a lot, such as new HVAC, TV usage, or machinery.
4. You add new users, new trigger patterns, or new sound sources.
5. `presence` and `idle` are often confused.

## Add More Data to an Existing Edge Impulse Project

1. Open the existing **`security-hub-acoustic`** project in Edge Impulse.
2. Go to **Data acquisition**.
3. Record or upload new labeled samples.
4. Focus on the classes that are misclassified most often.
5. Keep class balance within about 20%.
6. Regenerate features after adding data.
7. Retrain the model.

## Adjust MFCC or Neural Network Settings

If accuracy is still weak, tune the pipeline carefully.

### MFCC settings you can revisit

- Frame length
- Frame stride
- Number of coefficients
- Low/high frequency range
- Noise floor

### Neural network settings you can revisit

- Dense layer sizes
- Dropout rate
- Number of epochs
- Learning rate
- Data augmentation strength

### Tuning advice

1. Change one thing at a time.
2. Retrain after each change.
3. Compare accuracy, confusion matrix, and memory use.
4. Stop increasing model size if RAM or flash gets too close to the Arduino UNO Q limit.

## Re-Export and Update Firmware

1. After retraining, run **Model testing** again.
2. Verify the quantized **INT8** model still performs well.
3. Open **Deployment**.
4. Build a new **Arduino library** export.
5. Download the new ZIP.
6. Replace the old library in the Arduino IDE if needed.
7. Copy the new ZIP into `../04_firmware_inference/`.
8. Rebuild and upload the firmware so the device uses the updated model.

## Best Practice

Keep notes on:

- Dataset size per class
- Accuracy before and after retraining
- Any MFCC changes
- Any neural network changes
- Which exported ZIP version is in firmware
