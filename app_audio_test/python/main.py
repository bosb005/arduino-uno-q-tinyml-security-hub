"""
Rolling WAV capture + optional classify-from-file loop for audio-test.

The MCU sketch sends:
  Bridge.notify("audio_status", "noise",   duration_s, 0)
  Bridge.notify("audio_chunk",  chunk_id,  hex_data)
  Bridge.notify("audio_status", "done",    total_chunks, sample_hz)

For each "done", this app:
  1) assembles one WAV window under /app/windows/
  2) updates /app/test.wav (latest window, SCP-friendly path)
  3) optionally runs AudioClassification.classify_from_file(window)
"""

import os
import time
import wave
from pathlib import Path
from arduino.app_utils import App, Bridge, Logger

logger = Logger("AudioRecorder")

DEFAULT_SAMPLE_RATE  = int(os.getenv("DEFAULT_SAMPLE_RATE", "22000"))
BITS                 = 16
CHANNELS             = 1
CHUNK_SAMPLES        = 256  # must match sketch CHUNK_SAMPLES
BYTES_PER_CHUNK      = CHUNK_SAMPLES * (BITS // 8)
LATEST_OUTPUT_PATH   = Path(os.getenv("OUTPUT_PATH", "/app/test.wav"))
WINDOW_OUTPUT_DIR    = Path(os.getenv("WINDOW_OUTPUT_DIR", "/app/windows"))
WINDOW_KEEP_COUNT    = int(os.getenv("WINDOW_KEEP_COUNT", "12"))
ENABLE_CLASSIFY      = os.getenv("ENABLE_CLASSIFY", "0").lower() in ("1", "true", "yes")
CLASSIFY_CONFIDENCE  = float(os.getenv("CLASSIFY_CONFIDENCE", "0.80"))

_chunks: dict[int, bytes] = {}
_total_chunks   = 0
_measured_rate  = 0
_window_id      = 0


def _cleanup_windows():
    windows = sorted(WINDOW_OUTPUT_DIR.glob("window-*.wav"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in windows[WINDOW_KEEP_COUNT:]:
        try:
            old.unlink()
            logger.info(f"Removed old window: {old.name}")
        except Exception:
            logger.exception(f"Failed to remove old window: {old}")


def _classify_window(path: Path):
    if not ENABLE_CLASSIFY:
        return
    try:
        from arduino.app_bricks.audio_classification import (
            AudioClassification,
            AudioClassificationException,
        )
    except Exception:
        logger.exception("AudioClassification import failed")
        return

    try:
        result = AudioClassification.classify_from_file(str(path), CLASSIFY_CONFIDENCE)
    except AudioClassificationException as exc:
        logger.warning(f"Classification failed ({path.name}): {exc}")
        return
    except Exception:
        logger.exception(f"Unexpected classification failure ({path.name})")
        return

    if not result:
        logger.info(f"Classification: no confident result ({path.name})")
        return

    class_name = str(result.get("class_name", "unknown"))
    confidence = float(result.get("confidence", 0.0))
    logger.info(f"Classification: {class_name} ({confidence:.2f}) [{path.name}]")


def _save_wav():
    global _window_id
    rate = _measured_rate if _measured_rate > 0 else DEFAULT_SAMPLE_RATE
    n    = _total_chunks
    logger.info(f"Assembling {n} chunks (rate={rate} Hz)")
    pcm = bytearray()
    missing = 0
    for i in range(n):
        if i in _chunks:
            pcm.extend(_chunks[i])
        else:
            logger.warning(f"  Missing chunk {i} — inserting silence")
            pcm.extend(b"\x00" * BYTES_PER_CHUNK)
            missing += 1

    WINDOW_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    _window_id += 1
    ts_ms = int(time.time() * 1000)
    window_path = WINDOW_OUTPUT_DIR / f"window-{ts_ms}-{_window_id:06d}.wav"
    tmp_path = WINDOW_OUTPUT_DIR / f".{window_path.name}.tmp"

    with wave.open(str(tmp_path), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(BITS // 8)
        wf.setframerate(rate)
        wf.writeframes(bytes(pcm))
    tmp_path.replace(window_path)

    latest_tmp = LATEST_OUTPUT_PATH.with_suffix(".tmp.wav")
    with wave.open(str(latest_tmp), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(BITS // 8)
        wf.setframerate(rate)
        wf.writeframes(bytes(pcm))
    latest_tmp.replace(LATEST_OUTPUT_PATH)

    duration = len(pcm) / (rate * CHANNELS * (BITS // 8))
    logger.info(
        f"WAV window saved: {window_path}  ({duration:.1f}s, {missing} missing chunks)"
    )
    logger.info(f"Latest WAV updated: {LATEST_OUTPUT_PATH}")
    logger.info(">>> scp arduino@hackster26.local:/home/arduino/ArduinoApps/audio-test/test.wav ./")
    _cleanup_windows()
    _classify_window(window_path)


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
