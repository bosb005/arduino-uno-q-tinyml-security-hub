"""
record_wav.py — Collects streaming audio chunks from the MCU via Bridge and saves a WAV file.

The MCU sketch sends:
  Bridge.notify("audio_status", "noise",   duration_s, 0)           — make noise now
  Bridge.notify("audio_chunk",  chunk_id,  hex_data)                — one 256-sample chunk
  Bridge.notify("audio_status", "done",    total_chunks, sample_hz) — end signal, save WAV

Streaming mode: chunks arrive live as they are captured (no separate record/transmit phases).
Output: /app/test.wav  (actual bit-bang sample rate, 16-bit, mono)
After recording: scp arduino@hackster26.local:/home/arduino/ArduinoApps/audio-test/test.wav ./
"""

import wave
from arduino.app_utils import App, Bridge, Logger

logger = Logger("AudioRecorder")

DEFAULT_SAMPLE_RATE = 22000  # fallback if MCU does not report rate
BITS                = 16
CHANNELS            = 1
CHUNK_SAMPLES       = 256    # must match sketch CHUNK_SAMPLES
BYTES_PER_CHUNK     = CHUNK_SAMPLES * (BITS // 8)
OUTPUT_PATH         = "/app/test.wav"

_chunks: dict[int, bytes] = {}
_total_chunks   = 0
_measured_rate  = 0


def _save_wav():
    rate = _measured_rate if _measured_rate > 0 else DEFAULT_SAMPLE_RATE
    n    = _total_chunks
    logger.info(f"Assembling {n} chunks → {OUTPUT_PATH}  (rate={rate} Hz)")
    pcm = bytearray()
    missing = 0
    for i in range(n):
        if i in _chunks:
            pcm.extend(_chunks[i])
        else:
            logger.warning(f"  Missing chunk {i} — inserting silence")
            pcm.extend(b"\x00" * BYTES_PER_CHUNK)
            missing += 1

    with wave.open(OUTPUT_PATH, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(BITS // 8)
        wf.setframerate(rate)
        wf.writeframes(bytes(pcm))

    duration = len(pcm) / (rate * CHANNELS * (BITS // 8))
    logger.info(f"WAV saved: {OUTPUT_PATH}  ({duration:.1f}s, {missing} missing chunks)")
    logger.info(">>> scp arduino@hackster26.local:/home/arduino/ArduinoApps/audio-test/test.wav ./")


def _handle_status(status, value=0, extra=0, *_):
    global _total_chunks, _chunks, _measured_rate
    status = str(status)
    value  = int(value)
    rate   = int(extra) if extra else 0

    if status == "noise":
        _chunks = {}
        logger.info(f">>> MAKE SOME NOISE NOW — streaming {value}s of audio! <<<")
    elif status == "error":
        logger.error("MCU: audio_init() FAILED — check wiring on D8/D9/D10")
    elif status == "done":
        _total_chunks = value
        if rate > 0:
            _measured_rate = rate
        logger.info(f"MCU done — {value} chunks sent, rate: {_measured_rate or DEFAULT_SAMPLE_RATE} Hz")
        _save_wav()
    else:
        logger.info(f"Status: {status} value={value}")


def _handle_chunk(chunk_id, hex_data, *_):
    chunk_id = int(chunk_id)
    raw = bytes.fromhex(str(hex_data))
    _chunks[chunk_id] = raw
    if chunk_id % 20 == 0:
        logger.info(f"  chunk {chunk_id} ({len(_chunks)} received so far)")


def _handle_diag_free(count, pullup, *_):
    count  = int(count)
    pullup = int(pullup)
    if pullup > 20 and count == 0:
        verdict = "tristate/disconnected (check combo results below)"
    elif count == 0 and pullup == 0:
        verdict = "actively pulled LOW — short to GND?"
    else:
        verdict = f"partial signal ({count}/64 free)"
    logger.info(f"[DIAG] D8 (SD) idle: free={count}/64 HIGH, pullup={pullup}/32 HIGH → {verdict}")

def _handle_diag_combo(label, bits, *_):
    bits  = str(bits)
    highs = bits.count('1')
    tag   = "← DATA ✓" if highs > 2 else ("← silent" if highs == 0 else "← noise?")
    logger.info(f"[DIAG] {label}: {highs:2d}/64 HIGH  {tag}  {bits}")

Bridge.provide("diag_free",    _handle_diag_free)
Bridge.provide("diag_lr0ws0",  lambda b,*_: _handle_diag_combo("L/R=LOW  WS=LOW  (left-mic  left-slot )", b))
Bridge.provide("diag_lr0ws1",  lambda b,*_: _handle_diag_combo("L/R=LOW  WS=HIGH (left-mic  right-slot)", b))
Bridge.provide("diag_lr1ws0",  lambda b,*_: _handle_diag_combo("L/R=HIGH WS=LOW  (right-mic left-slot )", b))
Bridge.provide("diag_lr1ws1",  lambda b,*_: _handle_diag_combo("L/R=HIGH WS=HIGH (right-mic right-slot)", b))
Bridge.provide("audio_status", _handle_status)
Bridge.provide("audio_chunk",  _handle_chunk)

logger.info("Audio recorder ready — waiting for MCU (20 s startup delay)...")
App.run()
