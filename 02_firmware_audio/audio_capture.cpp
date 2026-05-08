#include "audio_capture.h"

#include <string.h>

#if defined(ARDUINO_UNO_Q)
#  ifdef __has_include
#    if __has_include(<I2S.h>)
#      include <I2S.h>
#      define AUDIO_CAPTURE_HAS_I2S_BACKEND 1
#    endif
#  endif
#endif

#ifndef AUDIO_CAPTURE_HAS_I2S_BACKEND
#define AUDIO_CAPTURE_HAS_I2S_BACKEND 0
#endif

namespace {

constexpr uint8_t kBufferCount = 2;
constexpr int8_t kInvalidBuffer = -1;

int16_t s_frames[kBufferCount][AUDIO_FRAME_SAMPLES];
uint8_t s_write_buffer = 0;
size_t s_write_index = 0;
int8_t s_ready_buffer = kInvalidBuffer;
bool s_frame_ready = false;
bool s_capture_started = false;
bool s_drop_until_clear = false;
bool s_expect_left_slot = true;

void reset_state() {
  memset(s_frames, 0, sizeof(s_frames));
  s_write_buffer = 0;
  s_write_index = 0;
  s_ready_buffer = kInvalidBuffer;
  s_frame_ready = false;
  s_capture_started = false;
  s_drop_until_clear = false;
  s_expect_left_slot = true;
}

// INMP441 drives a left-justified 24-bit sample in a 32-bit slot.
// The first shift removes the padding byte; the second scales 24-bit audio down to int16_t.
int16_t convert_i2s_word_to_int16(int32_t raw_word) {
  const int32_t sample24 = raw_word >> 8;
  const int32_t sample16 = sample24 >> 8;
  return static_cast<int16_t>(sample16);
}

void commit_sample(int16_t sample) {
  if (s_drop_until_clear) {
    return;
  }

  s_frames[s_write_buffer][s_write_index++] = sample;
  if (s_write_index < AUDIO_FRAME_SAMPLES) {
    return;
  }

  if (!s_frame_ready) {
    s_ready_buffer = static_cast<int8_t>(s_write_buffer);
    s_frame_ready = true;
    s_write_buffer ^= 1U;
    s_write_index = 0;
    return;
  }

  // Both halves are effectively occupied: one is ready for inference and the other
  // just finished filling. Drop new audio until the consumer releases the ready frame.
  s_drop_until_clear = true;
}

#if defined(ARDUINO_UNO_Q) && AUDIO_CAPTURE_HAS_I2S_BACKEND
// The UNO Q board package is expected to keep the I2S peripheral moving in the
// background (typically using the core's interrupt/DMA machinery). This module
// stays non-blocking by draining already-captured words into an application-side
// ping-pong frame buffer whenever the public API is polled.
bool read_i2s_word(int32_t& raw_word) {
  if (I2S.available() < 4) {
    return false;
  }

  const uint32_t b0 = static_cast<uint8_t>(I2S.read());
  const uint32_t b1 = static_cast<uint8_t>(I2S.read());
  const uint32_t b2 = static_cast<uint8_t>(I2S.read());
  const uint32_t b3 = static_cast<uint8_t>(I2S.read());

  raw_word = static_cast<int32_t>(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
  return true;
}

void service_capture() {
  if (!s_capture_started) {
    return;
  }

  int32_t raw_word = 0;
  while (read_i2s_word(raw_word)) {
    const bool is_left_slot = s_expect_left_slot;
    s_expect_left_slot = !s_expect_left_slot;

    if (!is_left_slot) {
      continue;
    }

    commit_sample(convert_i2s_word_to_int16(raw_word));
  }
}
#else
void service_capture() {
}
#endif

}  // namespace

bool audio_init() {
  reset_state();

#if defined(ARDUINO_UNO_Q) && AUDIO_CAPTURE_HAS_I2S_BACKEND
  if (!I2S.begin(I2S_PHILIPS_MODE, AUDIO_SAMPLE_RATE, 32)) {
    return false;
  }

  s_capture_started = true;
  return true;
#else
  return false;
#endif
}

bool audio_ready() {
  service_capture();
  return s_frame_ready;
}

int16_t* audio_get_frame() {
  service_capture();
  if (!s_frame_ready || s_ready_buffer == kInvalidBuffer) {
    return nullptr;
  }

  return s_frames[s_ready_buffer];
}

void audio_clear_ready() {
  service_capture();
  if (!s_frame_ready || s_ready_buffer == kInvalidBuffer) {
    return;
  }

  const uint8_t cleared_buffer = static_cast<uint8_t>(s_ready_buffer);
  s_frame_ready = false;
  s_ready_buffer = kInvalidBuffer;

  if (s_drop_until_clear) {
    s_write_buffer = cleared_buffer;
    s_write_index = 0;
    s_drop_until_clear = false;
  }
}
