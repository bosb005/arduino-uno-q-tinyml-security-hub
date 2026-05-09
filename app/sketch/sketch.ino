// Security Hub — MCU firmware
// Bit-bang I2S audio → Edge Impulse MFCC+NN acoustic classification
// → grayscale LED matrix icons + Bridge events to Linux dashboard.
// Pins: D7=L/R, D8=SD(in), D9=SCK, D10=WS
//
// Edge Impulse library is auto-installed by deploy.sh before compilation.

// Suppress EI logging: on Zephyr, ei_printf() writes to Serial which is the
// Bridge MsgPack transport. Any extra serial byte corrupts router framing.
#ifdef __cplusplus
extern "C" {
#endif
void ei_printf(const char* /*format*/, ...) {}
void ei_printf_float(float /*f*/) {}
#ifdef __cplusplus
}
#endif

#include "Arduino_RouterBridge.h"
#include "Arduino_LED_Matrix.h"
#include "audio_capture.h"
#include <cstring>

#define SKIP_INFERENCE 1

#ifndef SKIP_INFERENCE
#include <both-project-1_inferencing.h>
#endif

ArduinoLEDMatrix matrix;

// ── Grayscale icons (13×8, row-major, brightness 0-7) ────────────────────
// Physical: x=0=RIGHT, x=12=LEFT. Icons are mirrored relative to logical x.
// They're centred on logical cols 4-8 (physical cols 4-8 from right).

static const uint8_t ICON_IDLE[104] = {
  0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,7,7,7,7,7,0,0,0,0,0,
  0,0,7,0,0,0,0,0,7,0,0,0,0,
  0,0,7,0,0,0,0,0,7,0,0,0,0,
  0,0,7,0,0,0,0,0,7,0,0,0,0,
  0,0,7,0,0,0,0,0,7,0,0,0,0,
  0,0,0,7,7,7,7,7,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,
};

static const uint8_t ICON_PRESENCE[104] = {
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,7,7,7,7,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,7,0,0,7,0,0,0,0,0,0,
  0,0,0,7,0,0,7,0,0,0,0,0,0,
};

static const uint8_t ICON_ANOMALY[104] = {
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,4,4,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
};

static const uint8_t ICON_ERROR[104] = {
  0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,7,7,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,
};

// ── Status bar (cols 10-12, physical left side) ───────────────────────────
// Col 10: dim separator
// Cols 11-12 rows 0-1: Web indicator (always bright)
// Cols 11-12 rows 2-3: Mic indicator (bright = live audio)
// Cols 11-12 rows 4-5: Bridge indicator (bright = MCU connected)
// Cols 11-12 rows 6-7: Heartbeat (pulses)

static bool _heartbeat = false;

static void draw_with_status(const uint8_t* icon) {
  uint8_t frame[104];
  memcpy(frame, icon, 104);
  _heartbeat = !_heartbeat;
  uint8_t hb = _heartbeat ? 5 : 2;
  for (int r = 0; r < 8; r++) {
    frame[r * 13 + 10] = 1;
    uint8_t br = (r < 6) ? 5 : hb;
    frame[r * 13 + 11] = br;
    frame[r * 13 + 12] = br;
  }
  matrix.draw(frame);
}

// ── EI label → icon ───────────────────────────────────────────────────────

static const uint8_t* label_to_icon(const char* label) {
  if (strcmp(label, "presence")       == 0) return ICON_PRESENCE;
  if (strcmp(label, "anomaly")        == 0) return ICON_ANOMALY;
  if (strcmp(label, "manual_trigger") == 0) return ICON_PRESENCE; // reuse presence icon
  if (strcmp(label, "error")          == 0) return ICON_ERROR;
  return ICON_IDLE;
}

// ── Edge Impulse signal callback ──────────────────────────────────────────

static int16_t* g_audio_frame = nullptr;
#ifndef SKIP_INFERENCE
static ei_impulse_result_t g_result;
#endif

static int get_signal_data(size_t offset, size_t length, float* out_ptr) {
  if (g_audio_frame == nullptr || out_ptr == nullptr) return -1;
  if ((offset + length) > AUDIO_FRAME_SAMPLES)        return -1;
  for (size_t ix = 0; ix < length; ++ix) {
    out_ptr[ix] = static_cast<float>(g_audio_frame[offset + ix]) / 32768.0f;
  }
  return 0;
}

// ── Classification loop ───────────────────────────────────────────────────
#define CONFIDENCE_THRESHOLD  0.75f
#define BRIDGE_INTERVAL_MS   2000u   // frequent keepalive for bridge stability
#define WAIT_READY_MS        15000UL // allow app/router to bind before inference
#define CAPTURE_STEP_SAMPLES    256  // keep loop responsive during audio capture

static const char*   _label       = "idle";
static unsigned long _last_bridge = 0;
static unsigned long _last_heartbeat = 0;
static bool          _ready       = false;
static bool          _capture_started = false;

static int confidence_pct(float confidence) {
  if (confidence <= 0.0f) return 0;
  if (confidence >= 1.0f) return 100;
  return (int)(confidence * 100.0f + 0.5f);
}

static void emit_heartbeat(unsigned long now) {
  if (now - _last_heartbeat < BRIDGE_INTERVAL_MS) return;
  _last_heartbeat = now;
  draw_with_status(label_to_icon(_label));
  Bridge.notify("acoustic_event", _label, 0, (int)(now / 1000));
}

static void run_inference() {
  unsigned long now = millis();
  if (!_ready) {
    if (now < WAIT_READY_MS) return;
    _ready = true;
  }

  const char* best_label = _label;
  float       best_value = 0.0f;
  bool        changed    = false;

#ifndef SKIP_INFERENCE
  if (!_capture_started) {
    audio_start_frame_capture();
    _capture_started = true;
  }
  if (!audio_capture_frame_step(CAPTURE_STEP_SAMPLES)) return;
  _capture_started = false;

  g_audio_frame = audio_get_frame();
  if (g_audio_frame == nullptr) {
    audio_clear_ready();
    best_label = "error";
    best_value = 0.0f;
    changed = (strcmp(best_label, _label) != 0);
    if (changed) {
      _label = best_label;
      _last_bridge = now;
      draw_with_status(label_to_icon(_label));
      Bridge.notify("acoustic_event", _label, confidence_pct(best_value), (int)(now / 1000));
    }
    return;
  }


  signal_t signal;
  signal.total_length = EI_CLASSIFIER_RAW_SAMPLE_COUNT;  // must equal 16000
  signal.get_data     = get_signal_data;

  memset(&g_result, 0, sizeof(g_result));
  EI_IMPULSE_ERROR err = run_classifier(&signal, &g_result, false);
  audio_clear_ready();
  g_audio_frame = nullptr;

  if (err != EI_IMPULSE_OK) {
    // Inference error — surface it to the dashboard instead of staying silent.
    best_label = "error";
    best_value = 0.0f;
    changed = (strcmp(best_label, _label) != 0);
    if (changed) {
      _label       = best_label;
      _last_bridge = now;
      draw_with_status(label_to_icon(_label));
      Bridge.notify("acoustic_event", _label, confidence_pct(best_value), (int)(now / 1000));
    }
    return;
  }

  // Pick the highest-confidence label.
  best_label = "idle";
  best_value = -1.0f;
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; ++i) {
    if (g_result.classification[i].value > best_value) {
      best_value = g_result.classification[i].value;
      best_label = g_result.classification[i].label;
    }
  }

  // Suppress low-confidence results to "idle".
  if (best_value < CONFIDENCE_THRESHOLD) {
    best_label = "idle";
  }

  changed = (strcmp(best_label, _label) != 0);
#else
  // SKIP_INFERENCE: test LEDs + Bridge without running the EI model.
  audio_clear_ready();
  g_audio_frame = nullptr;
  best_label = "idle";
  best_value = 0.0f;
  changed    = false;
#endif

  if (changed) {
    _label       = best_label;
    _last_bridge = now;
    draw_with_status(label_to_icon(_label));
    Bridge.notify("acoustic_event", _label, confidence_pct(best_value), (int)(now / 1000));
  }
}

void setup() {
  matrix.begin();
  matrix.clear();
  // Draw BEFORE Bridge.begin() — if this icon shows, the LLEXT loaded and
  // LED matrix works.  If it doesn't, the LLEXT itself is broken.
  draw_with_status(ICON_IDLE);
  Bridge.begin();
  audio_init();
  _last_heartbeat = millis() - BRIDGE_INTERVAL_MS;
}

void loop() {
  emit_heartbeat(millis());
  run_inference();
}
