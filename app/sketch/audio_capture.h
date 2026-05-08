#ifndef AUDIO_CAPTURE_H
#define AUDIO_CAPTURE_H

#include <Arduino.h>

// Must match EI_CLASSIFIER_RAW_SAMPLE_COUNT (16000) so run_classifier() gets
// the expected number of samples.  At bit-bang ~5 kHz this takes ~3 seconds.
#define AUDIO_FRAME_SAMPLES 16000

// Pin assignments (exposed so sketch.ino can use them in diagnostics)
#define SCK_PIN  9   // D9  — output: I2S bit clock
#define WS_PIN   10  // D10 — output: I2S word select (low=left, high=right)
#define SD_PIN   8   // D8  — input:  I2S serial data from INMP441
#define LR_PIN   7   // D7  — output: INMP441 L/R channel select (LOW=left, HIGH=right)

// Initializes the board-specific I2S backend.
bool audio_init();

// Returns true when a full 1024-sample frame is available (used by legacy code).
bool audio_ready();

// Returns a pointer to the ready frame.
int16_t* audio_get_frame();

// Releases the current frame so the capture backend can reuse that buffer.
void audio_clear_ready();

// Actual sample rate (Hz) measured during the most recent chunk capture.
// Valid after the first successful audio_capture_chunk() or audio_ready() call.
extern int g_actual_sample_rate;

// Capture exactly n samples into buf.  Measures g_actual_sample_rate on first call.
// Blocking: takes n/sample_rate seconds.
void audio_capture_chunk(int16_t* buf, int n);

// Read n_samples via bit-bang and return peak level scaled 0–8.
int audio_read_level(int n_samples);

// Compute peak level 0–8 from an already-captured buffer.
int audio_frame_level(const int16_t* buf, int n);

#endif
