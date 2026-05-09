// audio_capture.cpp — Bit-bang I2S driver for INMP441 microphone.
//
// Wiring (from hardware description):
//   D9  → SCK  (bit clock output, master)
//   D10 → WS   (word select output, master)
//   D8  → SD   (serial data input from mic)
//
// Protocol: Philips I2S, 24-bit in 32-bit frame.
// The Arduino UNO Q (Renesas RA4M1) uses bit-banging for I2S—hardware I2S
// is exposed but GPIO bit-bang is simpler for this application. The actual
// sample rate is determined by GPIO toggle speed (typically 3–8 kHz on this
// platform) and is measured at runtime and reported back to Python so the
// WAV header is accurate.

#include "audio_capture.h"
#include <Arduino.h>

static int16_t  s_frame[AUDIO_FRAME_SAMPLES];
static bool     s_frame_ready  = false;
static bool     s_initialized  = false;

// Actual sample rate measured during the first frame capture.
// Exposed so sketch.ino can include it in the Bridge "done" notification.
int g_actual_sample_rate = 0;

// Read one stereo I2S frame.  Returns the left-channel sample as int16_t.
// Philips I2S format:
//   1. WS goes LOW → left channel starts
//   2. One "dummy" SCK cycle (MSB appears one clock after WS transitions)
//   3. 24 data bits, MSB first, sampled on SCK rising edge
//   4. 7 trailing zero-padding clocks (to complete 32 bits)
//   5. WS goes HIGH → right channel (32 clocks, ignored)
static int16_t read_one_sample() {
    int32_t raw = 0;

    // Left channel
    digitalWrite(WS_PIN, LOW);

    // One dummy clock (Philips I2S: data MSB is 1 SCK after WS transition)
    digitalWrite(SCK_PIN, HIGH);
    digitalWrite(SCK_PIN, LOW);

    // 24 data bits, MSB first
    for (int i = 23; i >= 0; i--) {
        digitalWrite(SCK_PIN, HIGH);
        if (digitalRead(SD_PIN)) raw |= (1L << i);
        digitalWrite(SCK_PIN, LOW);
    }

    // 7 trailing padding clocks (32 total = 1 dummy + 24 data + 7 padding)
    for (int i = 0; i < 7; i++) {
        digitalWrite(SCK_PIN, HIGH);
        digitalWrite(SCK_PIN, LOW);
    }

    // Right channel — 32 clocks, data ignored (L/R pin driven LOW by D7 → left channel only)
    digitalWrite(WS_PIN, HIGH);
    for (int i = 0; i < 32; i++) {
        digitalWrite(SCK_PIN, HIGH);
        digitalWrite(SCK_PIN, LOW);
    }

    // Sign-extend 24-bit → 32-bit, then scale to 16-bit
    if (raw & 0x800000L) raw |= 0xFF000000L;
    return static_cast<int16_t>(raw >> 8);
}

bool audio_init() {
    pinMode(SCK_PIN, OUTPUT);
    pinMode(WS_PIN,  OUTPUT);
    pinMode(SD_PIN,  INPUT);
    pinMode(LR_PIN,  OUTPUT);

    digitalWrite(SCK_PIN, LOW);
    digitalWrite(WS_PIN,  HIGH); // idle with WS high
    digitalWrite(LR_PIN,  LOW);  // default: left channel

    s_frame_ready = false;
    s_initialized = true;
    return true;
}

// Blocking capture of AUDIO_FRAME_SAMPLES samples.
// Measures elapsed time to compute g_actual_sample_rate.
bool audio_ready() {
    if (!s_initialized) return false;
    if (s_frame_ready) return true;

    unsigned long t0 = micros();
    for (int i = 0; i < AUDIO_FRAME_SAMPLES; i++) {
        s_frame[i] = read_one_sample();
    }
    unsigned long elapsed_us = micros() - t0;

    if (elapsed_us > 0) {
        g_actual_sample_rate =
            static_cast<int>((long)AUDIO_FRAME_SAMPLES * 1000000L / elapsed_us);
    }

    s_frame_ready = true;
    return true;
}

int16_t* audio_get_frame() {
    return s_frame_ready ? s_frame : nullptr;
}

void audio_clear_ready() {
    s_frame_ready = false;
}

void audio_capture_chunk(int16_t* buf, int n) {
    unsigned long t0 = micros();
    for (int i = 0; i < n; i++) {
        buf[i] = read_one_sample();
    }
    unsigned long elapsed_us = micros() - t0;
    if (elapsed_us > 0) {
        g_actual_sample_rate = (int)((long)n * 1000000L / elapsed_us);
    }
}

// Map peak absolute value to LED level 0–8.
static int level_from_peak(int32_t peak) {
    if (peak < 300)   return 0;
    if (peak < 900)   return 1;
    if (peak < 2500)  return 2;
    if (peak < 6000)  return 3;
    if (peak < 11000) return 4;
    if (peak < 18000) return 5;
    if (peak < 24000) return 6;
    if (peak < 29000) return 7;
    return 8;
}

int audio_read_level(int n_samples) {
    if (!s_initialized) return 0;
    int32_t peak = 0;
    for (int i = 0; i < n_samples; i++) {
        int16_t s = read_one_sample();
        int32_t a = s < 0 ? -(int32_t)s : (int32_t)s;
        if (a > peak) peak = a;
    }
    return level_from_peak(peak);
}

int audio_frame_level(const int16_t* buf, int n) {
    int32_t peak = 0;
    for (int i = 0; i < n; i++) {
        int32_t a = buf[i] < 0 ? -(int32_t)buf[i] : (int32_t)buf[i];
        if (a > peak) peak = a;
    }
    return level_from_peak(peak);
}
