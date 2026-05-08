# Combined Firmware Packaging

Arduino IDE expects one `.ino` entry file per sketch folder. The audio capture module and the inference sketch therefore need to be combined into a single deployable Arduino project folder before flashing a production build.

## Recommended layout

Create a new sketch folder:

```text
security_hub_firmware/
```

Inside that folder, place the files needed by the final sketch:
- `security_hub_firmware.ino`
- `audio_capture.h`
- `audio_capture.cpp`
- `event_protocol.h`
- `event_protocol.cpp`

A starter stub is included in:

```text
06_integration/combined_firmware/security_hub_firmware/
```

## How to build the combined sketch

1. Create or open the `security_hub_firmware/` sketch folder.
2. Copy `04_firmware_inference/inference_main.ino` into that folder.
3. Rename it to `security_hub_firmware/security_hub_firmware.ino` so the filename matches the folder name.
4. Copy `audio_capture.h` and `audio_capture.cpp` from `02_firmware_audio/` into the same folder.
5. Copy `event_protocol.h` and `event_protocol.cpp` from `04_firmware_inference/` into the same folder.
6. Keep the include line `#include "audio_capture.h"` in the `.ino` file so Arduino IDE resolves it locally inside the combined folder.
7. Install the Edge Impulse Arduino library ZIP described in `03_ai_model/EXPORT.md`.
8. Open `security_hub_firmware.ino` in Arduino IDE.
9. Select **Arduino UNO Q** as the board.
10. Select the correct upload port.
11. Build and flash the sketch.

## Why this folder is needed

Arduino IDE treats each sketch directory as a self-contained unit:
- the primary `.ino` filename must match the sketch folder name
- companion `.h` and `.cpp` files in the same folder are automatically included in the sketch project
- sibling directories are less reliable for final deployment and for sharing the project with other developers

## Included stub files

The `security_hub_firmware/` stub directory in this folder is intentionally minimal. It shows exactly which files belong in the combined sketch and where each source file should come from.

Use the stub as a packaging template, then replace the placeholder single-line files with the real source code before flashing.

