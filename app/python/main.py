import os
import random
import threading
import time

from arduino.app_bricks.web_ui import WebUI
from arduino.app_utils import App, Bridge, Logger

logger = Logger("SecurityHub")

# ── Mock-mode resolution ───────────────────────────────────────────────────
_mock_env = os.getenv("MOCK", "auto").lower()
if _mock_env in ("1", "true", "yes"):
    MOCK = True
elif _mock_env in ("0", "false", "no"):
    MOCK = False
else:
    import socket as _sock
    try:
        _s = _sock.socket(_sock.AF_UNIX, _sock.SOCK_STREAM)
        _s.settimeout(2)
        _s.connect("/var/run/arduino-router.sock")
        _s.close()
        MOCK = False
    except Exception:
        MOCK = True

logger.info(f"Mode: {'MOCK (no MCU)' if MOCK else 'LIVE (Bridge → MCU)'}")

# ── Shared state ───────────────────────────────────────────────────────────
state: dict = {
    "current_event": "idle",
    "confidence": 0.0,
    "ts": 0,
    "last_updated": "",
    "history": [],
}
state_lock = threading.Lock()

# ── WebUI brick ────────────────────────────────────────────────────────────
ui = WebUI(port=7000)


def _timestamp() -> str:
    from datetime import datetime
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _update_matrix(event: str):
    pass  # MCU manages LED matrix locally — no Bridge call needed


def handle_event(event_name, confidence=0.0, ts=0):
    """Called whenever an acoustic event arrives (Bridge or mock)."""
    entry = {
        "event": str(event_name),
        "confidence": round(float(confidence), 2),
        "ts": int(ts) if ts else int(time.time() * 1000),
        "last_updated": _timestamp(),
    }
    with state_lock:
        state["current_event"] = entry["event"]
        state["confidence"] = entry["confidence"]
        state["ts"] = entry["ts"]
        state["last_updated"] = entry["last_updated"]
        state["history"] = [entry] + state["history"][:49]
        snapshot = dict(state)
    logger.info(f"Event: {event_name}  confidence={confidence:.2f}")
    ui.send_message("acoustic_event", snapshot)
    _update_matrix(entry["event"])


# ── REST endpoints ─────────────────────────────────────────────────────────
ui.expose_api("GET", "/state", lambda: dict(state))
ui.expose_api("GET", "/history", lambda: list(state["history"]))
ui.expose_api("GET", "/health", lambda: {"status": "ok", "mock": MOCK})


@ui.on_connect
def on_connect(sid):
    """Send current state snapshot to a newly connected client."""
    with state_lock:
        snapshot = dict(state)
    ui.send_message("acoustic_event", snapshot, sid)


# ── Mock event generator ───────────────────────────────────────────────────
def _mock_loop():
    _events = [
        ("presence", 0.86, 3),
        ("anomaly", 0.91, 1),
        ("manual_trigger", 0.88, 1),
        ("idle", 0.95, 5),
    ]
    _labels = [e[0] for e in _events]
    _confs  = [e[1] for e in _events]
    _wts    = [e[2] for e in _events]
    logger.info("Mock generator started — fake acoustic events every 3–8 s")
    while True:
        idx = random.choices(range(len(_labels)), weights=_wts)[0]
        conf = _confs[idx] + random.uniform(-0.05, 0.05)
        handle_event(_labels[idx], max(0.70, min(0.99, conf)))
        time.sleep(random.uniform(3, 8))


# ── Startup ────────────────────────────────────────────────────────────────
if MOCK:
    threading.Thread(target=_mock_loop, daemon=True, name="mock-events").start()
else:
    Bridge.provide(
        "acoustic_event",
        lambda event_name, confidence=0.0, ts=0: handle_event(event_name, confidence, ts),
    )
    logger.info("Bridge: registered 'acoustic_event' provider")

App.run()
