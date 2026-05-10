// Security Hub — MCU firmware
// Bit-bang I2S audio → Edge Impulse MFCC+NN acoustic classification
// → grayscale LED matrix icons + Bridge events to Linux dashboard.
// Pins: D7=L/R, D8=SD(in), D9=SCK, D10=WS
//
// Edge Impulse library is auto-installed by deploy.sh before compilation.

// Suppress EI logging: on Zephyr, ei_printf() writes to Serial which is the
// Bridge MsgPack transport. Any extra serial byte corrupts router framing.
void ei_printf(const char* /*format*/, ...) {}
void ei_printf_float(float /*f*/) {}

#include "Arduino_RouterBridge.h"
#include "Arduino_LED_Matrix.h"
#include "audio_capture.h"
#include <cstring>

#define SKIP_INFERENCE 1
#define DEBUG_BYPASS_CLASSIFIER 0

#if !SKIP_INFERENCE
#include <security-hub-acoustic_inferencing.h>
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
  if (strcmp(label, "manual_trigger") == 0) return ICON_PRESENCE;
  if (strcmp(label, "error")          == 0) return ICON_ERROR;
  return ICON_IDLE;
}

// ── Edge Impulse signal callback ──────────────────────────────────────────

static int16_t* g_audio_frame = nullptr;
#if !SKIP_INFERENCE && !DEBUG_BYPASS_CLASSIFIER
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
#define BRIDGE_INTERVAL_MS      2000u   // frequent keepalive for bridge stability
#define BRIDGE_WARMUP_MS        1500UL  // short post-begin quiet period
#define WAIT_READY_MS          15000UL  // allow app/router to bind before inference
#define CAPTURE_STEP_SAMPLES      256   // keep loop responsive during audio capture
#define STARTUP_ANIM_STEP_MS      120u  // startup graph animation speed

static const char*   _label       = "idle";
static float         _confidence  = 0.0f;
static unsigned long _last_heartbeat = 0;
static unsigned long _bridge_warmup_until = 0;
static bool          _ready       = false;
static bool          _capture_started = false;
static bool          _bridge_flow_ack = false;

static void on_bridge_flow_ack(int enabled = 1, int /*ts*/ = 0) {
  _bridge_flow_ack = (enabled != 0);
  if (_bridge_flow_ack) {
    Bridge.notify("bridge_flow_ack_seen", 1, (int)(millis() / 1000));
  }
}

static int confidence_pct(float confidence) {
  if (confidence <= 0.0f) return 0;
  if (confidence >= 1.0f) return 100;
  return (int)(confidence * 100.0f + 0.5f);
}

static bool bridge_can_emit(unsigned long now) {
  return now >= _bridge_warmup_until;
}

static void draw_startup_graph(unsigned long now) {
  // Startup graph is shown until Linux confirms first bridge-delivered event.
  // Bars sweep across icon area (cols 0-9), status bar stays visible on cols 10-12.
  static const uint8_t bars[10] = {1, 2, 3, 4, 5, 6, 7, 6, 4, 2};
  uint8_t frame[104] = {0};
  const int phase = (int)((now / STARTUP_ANIM_STEP_MS) % 10u);

  for (int col = 0; col < 10; ++col) {
    const uint8_t h = bars[(col + phase) % 10];
    for (int row = 7; row >= (8 - (int)h); --row) {
      frame[row * 13 + col] = (row <= 2) ? 4 : 6;
    }
  }

  _heartbeat = !_heartbeat;
  const uint8_t hb = _heartbeat ? 5 : 2;
  for (int r = 0; r < 8; ++r) {
    frame[r * 13 + 10] = 1;
    // web + mic indicators bright during startup wait
    if (r < 4) {
      frame[r * 13 + 11] = 5;
      frame[r * 13 + 12] = 5;
    }
    // bridge indicator dim while waiting for ack
    else if (r < 6) {
      frame[r * 13 + 11] = 2;
      frame[r * 13 + 12] = 2;
    }
    // heartbeat pulse always visible
    else {
      frame[r * 13 + 11] = hb;
      frame[r * 13 + 12] = hb;
    }
  }

  matrix.draw(frame);
}

static void emit_acoustic_event(const char* label, float confidence, unsigned long now) {
  if (!bridge_can_emit(now)) return;
  Bridge.notify("acoustic_event", label, confidence_pct(confidence), (int)(now / 1000));
  _last_heartbeat = now; // avoid immediate duplicate heartbeat frame after event
}

static void emit_heartbeat(unsigned long now) {
  if (!bridge_can_emit(now)) return;
  if (now - _last_heartbeat < BRIDGE_INTERVAL_MS) return;
  _last_heartbeat = now;
  if (_bridge_flow_ack) {
    draw_with_status(label_to_icon(_label));
  } else {
    draw_startup_graph(now);
  }
  Bridge.notify("acoustic_event", _label, confidence_pct(_confidence), (int)(now / 1000));
}

static void process_acoustic_loop() {
  unsigned long now = millis();
  if (!_ready) {
    if (now < WAIT_READY_MS) return;
    _ready = true;
    _bridge_warmup_until = now + BRIDGE_WARMUP_MS;
  }

  const char* best_label = _label;
  float       best_value = 0.0f;
  bool        changed    = false;

#if !SKIP_INFERENCE
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
      draw_with_status(label_to_icon(_label));
      emit_acoustic_event(_label, best_value, now);
    }
    return;
  }

#if DEBUG_BYPASS_CLASSIFIER
  audio_clear_ready();
  g_audio_frame = nullptr;
  best_label = "idle";
  best_value = 0.0f;
#else
  signal_t signal;
  signal.total_length = EI_CLASSIFIER_RAW_SAMPLE_COUNT;
  signal.get_data     = get_signal_data;

  memset(&g_result, 0, sizeof(g_result));
  EI_IMPULSE_ERROR err = run_classifier(&signal, &g_result, false);
  audio_clear_ready();
  g_audio_frame = nullptr;

  if (err != EI_IMPULSE_OK) {
    best_label = "error";
    best_value = 0.0f;
    changed = (strcmp(best_label, _label) != 0);
    if (changed) {
      _label       = best_label;
      draw_with_status(label_to_icon(_label));
      emit_acoustic_event(_label, best_value, now);
    }
    return;
  }

  best_label = "idle";
  best_value = -1.0f;
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; ++i) {
    if (g_result.classification[i].value > best_value) {
      best_value = g_result.classification[i].value;
      best_label = g_result.classification[i].label;
    }
  }
#endif

  _confidence = best_value;
  if (best_value < CONFIDENCE_THRESHOLD) {
    best_label = "idle";
  }

  changed = (strcmp(best_label, _label) != 0);
#else
  audio_clear_ready();
  g_audio_frame = nullptr;
  best_label = "idle";
  best_value = 0.0f;
  _confidence = best_value;
  changed    = false;
#endif

  if (changed) {
    _label = best_label;
    draw_with_status(label_to_icon(_label));
    emit_acoustic_event(_label, best_value, now);
  }
}

void setup() {
  matrix.begin();
  matrix.clear();
  draw_with_status(ICON_IDLE);
  Bridge.begin();
  Bridge.provide("bridge_flow_ack", on_bridge_flow_ack);
  audio_init();
  unsigned long now = millis();
  _last_heartbeat = now - BRIDGE_INTERVAL_MS;
  _bridge_warmup_until = now + BRIDGE_WARMUP_MS;
}

void loop() {
  unsigned long now = millis();
  emit_heartbeat(now);
  process_acoustic_loop();
}
