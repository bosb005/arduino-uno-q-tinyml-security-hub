# Export Guide

Follow these steps after the model has been trained and validated in Edge Impulse.

## Export the Model as an Arduino Library

1. In your Edge Impulse project, navigate to **Deployment**.
2. Select **Arduino library**.
3. Click **Build**.
4. Wait about **2 minutes** for the build to complete.
5. Download the generated ZIP file.
   - The file name will look similar to:

```text
security-hub-acoustic_inferencing.zip
```

## Add the Library in Arduino IDE

1. Open **Arduino IDE**.
2. Go to **Sketch → Include Library → Add .ZIP Library...**
3. Select the downloaded ZIP file.
4. After import, the library name will be:

```text
security-hub-acoustic_inferencing
```

5. In your firmware, include the main header:

```cpp
#include <security-hub-acoustic_inferencing.h>
```

## Save a Reference Copy in This Repository

1. Keep the original ZIP download from Edge Impulse.
2. Copy the same ZIP file into:

```text
../04_firmware_inference/
```

3. This makes it easy to track which exported model version is used by the firmware.

## Recommended Post-Export Checks

1. Confirm the exported package is the quantized **INT8** version.
2. Open the library folder examples, if provided, to inspect generated usage patterns.
3. Verify the memory estimate still fits the Arduino UNO Q limits.
4. Update firmware code if the exported model name changes.

## Quick Summary

| Item | Value |
|---|---|
| Export format | Arduino library |
| Expected ZIP name | `security-hub-acoustic_inferencing.zip` |
| Arduino include | `#include <security-hub-acoustic_inferencing.h>` |
| Reference copy location | `../04_firmware_inference/` |
