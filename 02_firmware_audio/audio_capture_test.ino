#include "audio_capture.h"

namespace {

int32_t frame_peak(const int16_t* frame) {
  int32_t peak = 0;

  for (size_t i = 0; i < AUDIO_FRAME_SAMPLES; ++i) {
    int32_t sample = frame[i];
    if (sample < 0) {
      sample = -sample;
    }

    if (sample > peak) {
      peak = sample;
    }
  }

  return peak;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) {
  }

  Serial.println("audio_capture_test: starting");
  if (!audio_init()) {
    Serial.println("audio_capture_test: audio_init() failed");
    while (true) {
      delay(1000);
    }
  }

  Serial.println("audio_capture_test: capture running");
}

void loop() {
  if (!audio_ready()) {
    return;
  }

  int16_t* frame = audio_get_frame();
  if (frame == nullptr) {
    return;
  }

  Serial.print("peak=");
  Serial.println(frame_peak(frame));
  audio_clear_ready();
}
