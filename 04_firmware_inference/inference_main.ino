#include <Arduino.h>

#if defined(__has_include)
#  if __has_include(<both-project-1_inferencing.h>)
#    include <both-project-1_inferencing.h>
#  elif __has_include(<security-hub-acoustic_inferencing.h>)
#    include <security-hub-acoustic_inferencing.h>
#  else
#    error "Install the Edge Impulse ZIP library first: Sketch > Include Library > Add .ZIP Library..., then choose the exported security-hub-acoustic_inferencing archive from ../03_ai_model/."
#  endif
#else
#  include <security-hub-acoustic_inferencing.h>
#endif

#include "event_protocol.h"

#if defined(__has_include)
#  if __has_include("audio_capture.h")
#    include "audio_capture.h"
#  elif __has_include("../02_firmware_audio/audio_capture.h")
#    include "../02_firmware_audio/audio_capture.h"
#  else
#    error "audio_capture.h not found. Copy audio_capture.h/.cpp into the sketch folder or keep the repository layout intact."
#  endif
#else
#  include "../02_firmware_audio/audio_capture.h"
#endif

#if defined(__has_include)
#  if __has_include("audio_capture.cpp")
// Arduino IDE compiles local companion .cpp files automatically.
#  elif __has_include("../02_firmware_audio/audio_capture.cpp")
#    include "../02_firmware_audio/audio_capture.cpp"
#  else
#    error "audio_capture.cpp not found. Copy audio_capture.h/.cpp into the sketch folder or keep the repository layout intact."
#  endif
#else
#  include "../02_firmware_audio/audio_capture.cpp"
#endif

#include <cstring>

#define CONFIDENCE_THRESHOLD 0.75f

namespace {

constexpr unsigned long kHeartbeatIntervalMs = 10000UL;
constexpr unsigned long kLedBlinkMs = 50UL;

int16_t* g_audio_frame = nullptr;
bool g_led_blinking = false;
unsigned long g_led_on_since_ms = 0;
unsigned long g_last_heartbeat_ms = 0;

int get_signal_data(size_t offset, size_t length, float* out_ptr) {
  if (g_audio_frame == nullptr || out_ptr == nullptr) {
    return -1;
  }

  if ((offset + length) > AUDIO_FRAME_SAMPLES) {
    return -1;
  }

  for (size_t ix = 0; ix < length; ++ix) {
    out_ptr[ix] = static_cast<float>(g_audio_frame[offset + ix]) / 32768.0f;
  }

  return 0;
}

AcousticEvent label_to_event(const char* label) {
  if (label == nullptr) {
    return AcousticEvent::IDLE;
  }

  if (strcmp(label, "presence") == 0) {
    return AcousticEvent::PRESENCE;
  }
  if (strcmp(label, "anomaly") == 0) {
    return AcousticEvent::ANOMALY;
  }
  if (strcmp(label, "manual_trigger") == 0) {
    return AcousticEvent::MANUAL_TRIGGER;
  }
  return AcousticEvent::IDLE;
}

void start_led_blink(unsigned long now_ms) {
  digitalWrite(LED_BUILTIN, HIGH);
  g_led_blinking = true;
  g_led_on_since_ms = now_ms;
}

void update_led(unsigned long now_ms) {
  if (!g_led_blinking) {
    return;
  }

  if ((now_ms - g_led_on_since_ms) >= kLedBlinkMs) {
    digitalWrite(LED_BUILTIN, LOW);
    g_led_blinking = false;
  }
}

void debug_print_probabilities(const ei_impulse_result_t& result,
                               const char* best_label,
                               float best_value,
                               bool emitted_event) {
  Serial.print(F("probs:"));
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; ++i) {
    Serial.print(' ');
    Serial.print(result.classification[i].label);
    Serial.print('=');
    Serial.print(result.classification[i].value, 4);
  }

  Serial.print(F(" best="));
  Serial.print(best_label != nullptr ? best_label : "unknown");
  Serial.print(F(" conf="));
  Serial.print(best_value, 4);

  if (best_value < CONFIDENCE_THRESHOLD) {
    Serial.print(F(" below_threshold"));
  } else if (!emitted_event) {
    Serial.print(F(" idle_suppressed"));
  }

  Serial.println();
}

void process_audio_frame() {
  g_audio_frame = audio_get_frame();
  if (g_audio_frame == nullptr) {
    Serial.println(F("audio frame missing"));
    return;
  }

  signal_t signal;
  signal.total_length = AUDIO_FRAME_SAMPLES;
  signal.get_data = get_signal_data;

  ei_impulse_result_t result = {0};
  EI_IMPULSE_ERROR err = run_classifier(&signal, &result, false);
  if (err != EI_IMPULSE_OK) {
    Serial.print(F("run_classifier failed: "));
    Serial.println(static_cast<int>(err));
    return;
  }

  const char* best_label = nullptr;
  float best_value = -1.0f;
  for (size_t i = 0; i < EI_CLASSIFIER_LABEL_COUNT; ++i) {
    if (result.classification[i].value > best_value) {
      best_value = result.classification[i].value;
      best_label = result.classification[i].label;
    }
  }

  bool emitted_event = false;
  if (best_value >= CONFIDENCE_THRESHOLD) {
    const AcousticEvent event = label_to_event(best_label);
    emit_event(event, best_value, millis());
    emitted_event = (event != AcousticEvent::IDLE);

    if (emitted_event) {
      start_led_blink(millis());
    }
  }

  debug_print_probabilities(result, best_label, best_value, emitted_event);
}

}  // namespace

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  Serial.begin(115200);
  Serial1.begin(115200);

  if (!audio_init()) {
    Serial.println(F("I2S init failed"));
    while (true) {
      update_led(millis());
    }
  }

  Serial.println(F("Security Hub ready"));
  emit_heartbeat(0);
  g_last_heartbeat_ms = millis();
}

void loop() {
  const unsigned long now_ms = millis();
  update_led(now_ms);

  if (audio_ready()) {
    process_audio_frame();
    g_audio_frame = nullptr;
    audio_clear_ready();
  }

  if ((now_ms - g_last_heartbeat_ms) >= kHeartbeatIntervalMs) {
    emit_heartbeat(now_ms);
    g_last_heartbeat_ms = now_ms;
  }
}
