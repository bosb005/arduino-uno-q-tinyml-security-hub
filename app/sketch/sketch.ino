// Security Hub — MCU firmware
// Bit-bang I2S audio → Edge Impulse MFCC+NN acoustic classification
// → grayscale LED matrix icons + Bridge events to Linux dashboard.
// Pins: D7=L/R, D8=SD(in), D9=SCK, D10=WS
//
// Edge Impulse library is auto-installed by deploy.sh before compilation.

// Suppress EI logging: on Zephyr, ei_printf() writes to Serial which IS the
// Bridge's MsgPack transport — any stray byte corrupts the RPC framing.
void ei_printf(const char* /*format*/, ...) {}
void ei_printf_float(float /*f*/) {}

#include <both-project-1_inferencing.h>

#include "Arduino_RouterBridge.h"
#include "Arduino_LED_Matrix.h"
#include "audio_capture.h"
#include <cstring>

Arduino_LED_Matrix matrix;

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
  return ICON_IDLE;
}

// ── Edge Impulse signal callback ──────────────────────────────────────────

static int16_t* g_audio_frame = nullptr;

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
#define BRIDGE_INTERVAL_MS  10000u   // heartbeat even without change
#define WAIT_READY_MS         5000UL // let Bridge.begin() complete before audio

static const char*   _label       = "idle";
static unsigned long _last_bridge = 0;
static bool          _ready       = false;

static void run_inference() {
  unsigned long now = millis();
  if (!_ready) {
    if (now < WAIT_READY_MS) return;
    _ready = true;
  }

  bool heartbeat_due = (now - _last_bridge >= BRIDGE_INTERVAL_MS);

#ifndef SKIP_INFERENCE
  // audio_ready() is blocking: captures AUDIO_FRAME_SAMPLES then returns true.
  if (!audio_ready()) return;

  g_audio_frame = audio_get_frame();
  if (g_audio_frame == nullptr) {
    audio_clear_ready();
    if (heartbeat_due) { _last_bridge = now; draw_with_status(label_to_icon(_label)); }
    return;
  }


  signal_t signal;
  signal.total_length = EI_CLASSIFIER_RAW_SAMPLE_COUNT;  // must equal 16000
  signal.get_data     = get_signal_data;

  ei_impulse_result_t result = {0};
  EI_IMPULSE_ERROR err = run_classifier(&signal, &result, false);
  audio_clear_ready();
  g_audio_frame = nullptr;

  if (err != EI_IMPULSE_OK) {
    // Inference error — still pulse heartbeat so LEDs stay alive.
    if (heartbeat_due) {
      _last_bridge = now;
      draw_with_status(label_to_icon(_label));
    }
    return;
  }

  // Pick the highest-confidence label.
  const char* best_label = "idle";
  float       best_value = -1.0f;
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; ++i) {
    if (result.classification[i].value > best_value) {
      best_value = result.classification[i].value;
      best_label = result.classification[i].label;
    }
  }

  // Suppress low-confidence results to "idle".
  if (best_value < CONFIDENCE_THRESHOLD) {
    best_label = "idle";
  }

  bool changed = (strcmp(best_label, _label) != 0);
#else
  // SKIP_INFERENCE: test LEDs + Bridge without running the EI model.
  audio_clear_ready();
  g_audio_frame = nullptr;
  const char* best_label = "idle";
  float       best_value = 0.0f;
  bool        changed    = false;
#endif

  if (changed || heartbeat_due) {
    _label       = best_label;
    _last_bridge = now;
    draw_with_status(label_to_icon(_label));
    Bridge.notify("acoustic_event", _label, best_value, (int)(now / 1000));
  }
}

void setup() {
  matrix.begin();
  matrix.setGrayscaleBits(3);
  matrix.clear();
  // Draw BEFORE Bridge.begin() — if this icon shows, the LLEXT loaded and
  // LED matrix works.  If it doesn't, the LLEXT itself is broken.
  draw_with_status(ICON_IDLE);
  Bridge.begin();
  audio_init();
}

void loop() {
  run_inference();
}
