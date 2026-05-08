import json
import logging
import os
import queue
import threading
from datetime import datetime
from typing import Dict, List

from flask import Flask, Response, jsonify, render_template, stream_with_context

from serial_reader import SerialEventReader

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

state = {
    "current_event": "idle",
    "confidence": 0.0,
    "ts": 0,
    "last_updated": "",
    "history": [],
}

state_lock = threading.Lock()
subscriber_lock = threading.Lock()
subscribers: List[queue.Queue] = []


def _timestamp_label() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def _safe_float(value) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _state_snapshot() -> Dict:
    with state_lock:
        return {
            "current_event": state["current_event"],
            "confidence": state["confidence"],
            "ts": state["ts"],
            "last_updated": state["last_updated"],
            "history": [entry.copy() for entry in state["history"]],
        }


def _broadcast(snapshot: Dict):
    with subscriber_lock:
        active_subscribers = list(subscribers)

    for subscriber in active_subscribers:
        try:
            subscriber.put_nowait(snapshot)
        except queue.Full:
            try:
                subscriber.get_nowait()
            except queue.Empty:
                pass
            try:
                subscriber.put_nowait(snapshot)
            except queue.Full:
                logger.debug("Dropping SSE update for a slow subscriber")


def handle_serial_event(event: Dict):
    event_name = str(event.get("event", "idle"))
    confidence = _safe_float(event.get("confidence", 0.0))
    event_ts = event.get("ts", 0)
    updated_at = _timestamp_label()

    history_entry = {
        "event": event_name,
        "confidence": confidence,
        "ts": event_ts,
        "last_updated": updated_at,
    }

    with state_lock:
        state["current_event"] = event_name
        state["confidence"] = confidence
        state["ts"] = event_ts
        state["last_updated"] = updated_at
        state["history"] = [history_entry, *state["history"][:49]]
        snapshot = {
            "current_event": state["current_event"],
            "confidence": state["confidence"],
            "ts": state["ts"],
            "last_updated": state["last_updated"],
            "history": [entry.copy() for entry in state["history"]],
        }

    logger.info("Event received: %s confidence=%.2f ts=%s", event_name, confidence, event_ts)
    _broadcast(snapshot)


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/state")
def api_state():
    return jsonify(_state_snapshot())


@app.get("/api/history")
def api_history():
    return jsonify(_state_snapshot()["history"])


@app.get("/stream")
def stream():
    @stream_with_context
    def event_stream():
        subscriber: queue.Queue = queue.Queue(maxsize=10)
        with subscriber_lock:
            subscribers.append(subscriber)

        try:
            yield f"data: {json.dumps(_state_snapshot())}\n\n"
            while True:
                try:
                    snapshot = subscriber.get(timeout=15)
                    yield f"data: {json.dumps(snapshot)}\n\n"
                except queue.Empty:
                    yield ": keepalive\n\n"
        finally:
            with subscriber_lock:
                if subscriber in subscribers:
                    subscribers.remove(subscriber)

    response = Response(event_stream(), mimetype="text/event-stream")
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    return response


if __name__ == "__main__":
    serial_port = os.getenv("SERIAL_PORT", "/dev/ttyS1")
    serial_baud = int(os.getenv("SERIAL_BAUD", "115200"))
    reader = SerialEventReader(serial_port, serial_baud, handle_serial_event)
    reader.start()

    try:
        app.run(host="0.0.0.0", port=5000, threaded=True, use_reloader=False)
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received, shutting down")
    finally:
        reader.stop()
