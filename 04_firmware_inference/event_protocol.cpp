#include "event_protocol.h"

namespace {

unsigned long free_mem_bytes() {
#if defined(ESP8266) || defined(ESP32)
  return static_cast<unsigned long>(ESP.getFreeHeap());
#else
  return 0UL;
#endif
}

}  // namespace

const char* event_name(AcousticEvent ev) {
  switch (ev) {
    case AcousticEvent::PRESENCE:
      return "presence";
    case AcousticEvent::ANOMALY:
      return "anomaly";
    case AcousticEvent::MANUAL_TRIGGER:
      return "manual_trigger";
    case AcousticEvent::IDLE:
    default:
      return "idle";
  }
}

void emit_event(AcousticEvent ev, float confidence, unsigned long ts_ms) {
  if (ev == AcousticEvent::IDLE) {
    return;
  }

  Serial1.print(F("{\"v\":"));
  Serial1.print(IPC_PROTOCOL_VERSION);
  Serial1.print(F(",\"event\":\""));
  Serial1.print(event_name(ev));
  Serial1.print(F("\",\"confidence\":"));
  Serial1.print(confidence, 2);
  Serial1.print(F(",\"ts\":"));
  Serial1.print(ts_ms);
  Serial1.println(F("}"));
}

void emit_heartbeat(unsigned long uptime_ms) {
  Serial1.print(F("{\"v\":"));
  Serial1.print(IPC_PROTOCOL_VERSION);
  Serial1.print(F(",\"event\":\"heartbeat\",\"uptime\":"));
  Serial1.print(uptime_ms);
  Serial1.print(F(",\"ts\":"));
  Serial1.print(uptime_ms);
  Serial1.print(F(",\"free_mem\":"));
  Serial1.print(free_mem_bytes());
  Serial1.println(F("}"));
}
