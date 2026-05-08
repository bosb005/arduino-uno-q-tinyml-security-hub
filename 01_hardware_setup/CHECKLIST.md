# Hardware validation checklist

- [ ] **3.3 V supply verified:** INMP441 `VDD` measures about **3.3 V** relative to `GND`
- [ ] **Ground connected:** microphone `GND` and UNO Q `GND` are common
- [ ] **I2S data line connected:** `INMP441 SD -> UNO Q D8`
- [ ] **I2S word-select connected:** `INMP441 WS -> UNO Q D10`
- [ ] **I2S bit-clock connected:** `INMP441 SCK -> UNO Q D9`
- [ ] **Channel-select strap confirmed:** `INMP441 L/R -> GND` for left-channel mono capture
- [ ] **Decoupling fitted:** 100 nF capacitor installed between `VDD` and `GND` near the microphone
- [ ] **No short circuits:** multimeter continuity check confirms no shorts between `3.3V` and `GND`
- [ ] **Board powers up normally:** UNO Q boots with microphone attached
- [ ] **No I2S init error:** serial monitor does not show an I2S initialization failure message
- [ ] **Audio activity visible:** serial plotter or serial monitor shows peak amplitude changes when you clap, tap, or speak near the microphone
- [ ] **Final pin-map recheck complete:** confirmed project mapping `D10 = WS`, `D9 = SCK`, `D8 = SD` against the UNO Q documentation / installed board package
