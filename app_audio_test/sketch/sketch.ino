// INMP441 bit-bang I2S + scrolling VU meter + single WAV capture via Bridge.
// Records once at startup, sends WAV, then runs VU meter forever.
// LED matrix: 8 rows × 13 cols = 104 pixels.
//   frame[row*13 + x]:  x=0=physical RIGHT, x=12=physical LEFT
//                       row=0=top, row=7=bottom
// VU: new bar enters right (x=0), scrolls left. Height 0–8. Binary pixels.

#include "Arduino_RouterBridge.h"
#include "audio_capture.h"
#include "Arduino_LED_Matrix.h"

#define RECORD_SAMPLES    8192u
#define CHUNK_SAMPLES      256u
#define TOTAL_CHUNKS      (RECORD_SAMPLES / CHUNK_SAMPLES)
#define TX_DELAY_MS        150u
#define WAIT_READY_MS     5000UL

static int16_t s_buf[RECORD_SAMPLES];
static char    s_hex[CHUNK_SAMPLES * 4u + 1u];

ArduinoLEDMatrix matrix;

static int s_levels[13] = {};

static void push_level(int lv) {
  memmove(s_levels + 1, s_levels, 12 * sizeof(int));
  s_levels[0] = lv;
}

static void draw_vu(void) {
  uint8_t frame[104] = {};
  for (int x = 0; x < 13; x++) {
    int lv = s_levels[x];
    for (int row = 7; row > 7 - lv; row--)
      frame[row * 13 + x] = 1;
  }
  matrix.draw(frame);
}

static void chunk_to_hex(const int16_t* s, unsigned n) {
  static const char H[] = "0123456789abcdef";
  char* p = s_hex;
  for (unsigned i = 0; i < n; i++) {
    uint16_t v = (uint16_t)s[i];
    *p++ = H[(v >> 12) & 0xF]; *p++ = H[(v >>  8) & 0xF];
    *p++ = H[(v >>  4) & 0xF]; *p++ = H[ v        & 0xF];
  }
  *p = '\0';
}

typedef enum { ST_WAIT, ST_RECORD, ST_SEND, ST_VU } State;
static State         s_state    = ST_WAIT;
static unsigned      s_pos      = 0;
static unsigned      s_chunk_tx = 0;
static unsigned long s_last_tx  = 0;
static unsigned long s_last_disp = 0;

void setup() {
  matrix.begin();
  Bridge.begin();
  audio_init();
}

void loop() {
  switch (s_state) {

    case ST_WAIT:
      if (millis() >= WAIT_READY_MS) {
        Bridge.notify("audio_status", "noise", (int)TOTAL_CHUNKS, 0);
        s_pos   = 0;
        s_state = ST_RECORD;
      }
      break;

    case ST_RECORD: {
      audio_capture_chunk(&s_buf[s_pos], CHUNK_SAMPLES);
      push_level(audio_frame_level(&s_buf[s_pos], CHUNK_SAMPLES));
      draw_vu();
      s_pos += CHUNK_SAMPLES;
      if (s_pos >= RECORD_SAMPLES) {
        s_chunk_tx = 0;
        s_last_tx  = 0;
        s_state    = ST_SEND;
      }
      break;
    }

    case ST_SEND: {
      unsigned long now = millis();
      if (now - s_last_disp >= 50) {
        s_last_disp = now;
        push_level(audio_read_level(64));
        draw_vu();
      }
      if (now - s_last_tx < TX_DELAY_MS) return;
      s_last_tx = millis();

      unsigned offset = s_chunk_tx * CHUNK_SAMPLES;
      chunk_to_hex(&s_buf[offset], CHUNK_SAMPLES);
      Bridge.notify("audio_chunk", (int)s_chunk_tx, s_hex);
      s_chunk_tx++;

      if (s_chunk_tx >= TOTAL_CHUNKS) {
        Bridge.notify("audio_status", "done", (int)TOTAL_CHUNKS, g_actual_sample_rate);
        s_state     = ST_VU;   // WAV sent — never record again
        s_last_disp = 0;
      }
      break;
    }

    case ST_VU: {
      // Continuous live VU meter only — no more recording or SRAM writes
      unsigned long now = millis();
      if (now - s_last_disp >= 50) {
        s_last_disp = now;
        push_level(audio_read_level(64));
        draw_vu();
      }
      break;
    }
  }
}
