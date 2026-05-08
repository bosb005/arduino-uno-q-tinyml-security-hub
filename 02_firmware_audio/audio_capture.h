#ifndef AUDIO_CAPTURE_H
#define AUDIO_CAPTURE_H

#include <Arduino.h>

#define AUDIO_SAMPLE_RATE   16000
#define AUDIO_FRAME_SAMPLES 1024   // 64 ms at 16 kHz

// Initializes the board-specific I2S backend and starts continuous capture.
bool audio_init();

// Returns true when a full 1024-sample frame is available.
bool audio_ready();

// Returns a pointer to the ready frame. The pointer remains valid until
// audio_clear_ready() is called.
int16_t* audio_get_frame();

// Releases the current frame so the capture backend can reuse that buffer.
void audio_clear_ready();

#endif
