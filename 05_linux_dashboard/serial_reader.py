import json
import logging
import threading
import time
from typing import Callable, Optional

import serial

logger = logging.getLogger(__name__)

MAX_LINE_LENGTH = 256


class SerialEventReader:
    def __init__(self, port: str, baud: int, callback: Callable[[dict], None]):
        self.port = port
        self.baud = baud
        self.callback = callback
        self._stop_event = threading.Event()
        self._callback_lock = threading.Lock()
        self._serial_lock = threading.Lock()
        self._thread: Optional[threading.Thread] = None
        self._serial: Optional[serial.Serial] = None

    def start(self):
        if self._thread and self._thread.is_alive():
            return

        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, name="serial-event-reader", daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        with self._serial_lock:
            if self._serial is not None:
                try:
                    self._serial.close()
                except serial.SerialException:
                    logger.debug("Serial port close failed during shutdown", exc_info=True)
                self._serial = None

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

    def _run(self):
        while not self._stop_event.is_set():
            try:
                with serial.Serial(self.port, self.baud, timeout=1) as ser:
                    with self._serial_lock:
                        self._serial = ser
                    logger.info("Connected to serial device %s at %s baud", self.port, self.baud)
                    try:
                        ser.reset_input_buffer()
                    except serial.SerialException:
                        logger.debug("Unable to reset serial input buffer", exc_info=True)
                    self._read_loop(ser)
            except (serial.SerialException, OSError) as exc:
                if self._stop_event.is_set():
                    break
                logger.warning("Serial connection error on %s: %s", self.port, exc)
                self._stop_event.wait(2)
            finally:
                with self._serial_lock:
                    self._serial = None

    def _discard_overflow(self, ser: serial.Serial, initial_chunk: bytes):
        chunk = initial_chunk
        while chunk and not chunk.endswith(b"\n") and not self._stop_event.is_set():
            chunk = ser.readline(MAX_LINE_LENGTH + 1)

    def _read_loop(self, ser: serial.Serial):
        while not self._stop_event.is_set():
            try:
                raw_line = ser.readline(MAX_LINE_LENGTH + 1)
            except (serial.SerialException, OSError) as exc:
                raise serial.SerialException(str(exc)) from exc

            if not raw_line:
                continue

            if len(raw_line) > MAX_LINE_LENGTH and not raw_line.endswith(b"\n"):
                logger.warning("Discarding oversized serial line (> %s bytes)", MAX_LINE_LENGTH)
                self._discard_overflow(ser, raw_line)
                continue

            line = raw_line.decode("utf-8", errors="ignore").strip()
            if not line:
                continue

            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                logger.warning("Skipping malformed serial JSON: %s", line)
                continue

            if event.get("event") == "heartbeat":
                logger.info(
                    "Heartbeat received: uptime=%s free_mem=%s",
                    event.get("uptime", "n/a"),
                    event.get("free_mem", "n/a"),
                )
                continue

            try:
                with self._callback_lock:
                    self.callback(event)
            except Exception:
                logger.exception("Serial event callback failed for payload: %s", event)

        time.sleep(0.05)
