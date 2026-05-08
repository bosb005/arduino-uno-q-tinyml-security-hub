#ifndef EVENT_PROTOCOL_H
#define EVENT_PROTOCOL_H

#include <Arduino.h>

enum class AcousticEvent { IDLE, PRESENCE, ANOMALY, MANUAL_TRIGGER };

constexpr uint8_t IPC_PROTOCOL_VERSION = 1;

const char* event_name(AcousticEvent ev);
// Emits JSON on Serial1: {"v":1,"event":"presence","confidence":0.92,"ts":12345}
// Does NOT emit for IDLE (returns without sending)
void emit_event(AcousticEvent ev, float confidence, unsigned long ts_ms);
// Emits heartbeat every 10 s: {"v":1,"event":"heartbeat","uptime":12345,"ts":12345,"free_mem":45678}
void emit_heartbeat(unsigned long uptime_ms);

#endif
