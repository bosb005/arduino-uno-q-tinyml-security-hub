import os
import random
import threading
import time

from arduino.app_bricks.web_ui import WebUI
from arduino.app_utils import App, Bridge, Logger

logger = Logger("SecurityHub")
BRIDGE_STALE_MS = int(os.getenv("BRIDGE_STALE_MS", "15000"))
USE_EI_BRICK = os.getenv("USE_EI_BRICK", "0").lower() in ("1", "true", "yes")
USE_EI_WAV_CLASSIFIER = os.getenv("USE_EI_WAV_CLASSIFIER", "0").lower() in ("1", "true", "yes")
EI_WAV_PATH = os.getenv("EI_WAV_PATH", "/home/arduino/ArduinoApps/audio-test/test.wav")
EI_WAV_CONFIDENCE = float(os.getenv("EI_WAV_CONFIDENCE", "0.80"))
EI_WAV_POLL_SEC = float(os.getenv("EI_WAV_POLL_SEC", "2.0"))
EI_BRICK_LABELS = [
    s.strip()
    for s in os.getenv("EI_BRICK_LABELS", "presence,anomaly,manual_trigger,idle").split(",")
    if s.strip()
]

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
    "bridge_last_event_ms": 0,
    "bridge_provider_registered": MOCK,
    "bridge_provider_registration_error": "",
    "event_source": "mock" if MOCK else "bridge",
    "bridge_first_event_seen": False,
    "bridge_flow_ack_sent": MOCK,
    "bridge_flow_ack_seen_by_mcu": MOCK,
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


def _normalize_confidence(confidence) -> float:
    c = float(confidence)
    if c > 1.0:
        c = c / 100.0
    return max(0.0, min(1.0, c))


def _send_bridge_flow_ack():
    if MOCK:
        return

    should_send = False
    with state_lock:
        if not bool(state.get("bridge_flow_ack_sent", False)):
            state["bridge_flow_ack_sent"] = True
            should_send = True
    if not should_send:
        return

    try:
        Bridge.notify("bridge_flow_ack", 1, int(time.time()))
        logger.info("Bridge flow ACK sent to MCU")
    except Exception:
        with state_lock:
            state["bridge_flow_ack_sent"] = False
        logger.exception("Failed to send bridge flow ACK")


def handle_event(event_name, confidence=0.0, ts=0, source="bridge"):
    """Called whenever an acoustic event arrives."""
    conf = _normalize_confidence(confidence)
    now_ms = int(time.time() * 1000)
    entry = {
        "event": str(event_name),
        "confidence": round(conf, 2),
        "ts": int(ts) if ts else int(time.time() * 1000),
        "last_updated": _timestamp(),
    }
    with state_lock:
        state["current_event"] = entry["event"]
        state["confidence"] = entry["confidence"]
        state["ts"] = entry["ts"]
        state["last_updated"] = entry["last_updated"]
        state["event_source"] = source
        state["bridge_last_event_ms"] = now_ms
        state["bridge_first_event_seen"] = True
        state["history"] = [entry] + state["history"][:49]
        snapshot = dict(state)
    if entry["event"] == "anomaly":
        logger.warning(f"Anomaly detected  confidence={conf:.2f} ts={entry['ts']}")
    else:
        logger.info(f"Event: {event_name}  confidence={conf:.2f}")
    ui.send_message("acoustic_event", snapshot)
    _update_matrix(entry["event"])
    if source == "bridge":
        _send_bridge_flow_ack()


def _handle_acoustic_event(event_name, confidence=0.0, ts=0, *_):
    """Bridge callback for MCU acoustic events.

    The bridge may append implementation-specific metadata, so keep the handler
    permissive like the audio-test app does.
    """
    handle_event(event_name, confidence, ts)


def _handle_bridge_flow_ack_seen(enabled=1, *_):
    with state_lock:
        state["bridge_flow_ack_seen_by_mcu"] = bool(int(enabled))
    logger.info("MCU confirmed bridge flow ACK")


def _health_state():
    with state_lock:
        last_event_ms = int(state.get("bridge_last_event_ms", 0) or 0)
        provider_registered = bool(state.get("bridge_provider_registered", False))
        provider_error = str(state.get("bridge_provider_registration_error", "") or "")
        first_event_seen = bool(state.get("bridge_first_event_seen", False))
        ack_sent = bool(state.get("bridge_flow_ack_sent", False))
        ack_seen = bool(state.get("bridge_flow_ack_seen_by_mcu", False))
        event_source = str(state.get("event_source", "bridge"))

    if MOCK:
        return {
            "status": "ok",
            "mock": True,
            "dashboard": {"healthy": True},
            "bridge": {
                "alive": True,
                "mode": "mock",
                "provider_registered": True,
                "no_events_yet": last_event_ms == 0,
                "first_event_seen": first_event_seen,
                "flow_ack_sent": ack_sent,
                "flow_ack_seen_by_mcu": ack_seen,
            },
        }

    now_ms = int(time.time() * 1000)
    age_ms = now_ms - last_event_ms if last_event_ms > 0 else None
    no_events_yet = last_event_ms == 0
    alive = age_ms is not None and age_ms <= BRIDGE_STALE_MS and provider_registered
    stale = age_ms is not None and age_ms > BRIDGE_STALE_MS
    status = "degraded" if stale or provider_error else "ok"
    return {
        "status": status,
        "mock": False,
        "dashboard": {"healthy": True},
        "bridge": {
            "alive": alive,
            "mode": event_source,
            "provider_registered": provider_registered,
            "provider_registration_error": provider_error or None,
            "last_event_age_ms": age_ms,
            "stale_after_ms": BRIDGE_STALE_MS,
            "no_events_yet": no_events_yet,
            "first_event_seen": first_event_seen,
            "flow_ack_sent": ack_sent,
            "flow_ack_seen_by_mcu": ack_seen,
            "stale": stale,
            "state": "waiting_for_events" if no_events_yet else ("stale" if stale else "alive"),
            "failure_point": (
                "KeywordSpotting brick callback starvation"
                if event_source.startswith("ei_keyword_spotting")
                else "AudioClassification WAV pipeline idle"
                if event_source.startswith("ei_audio_classification_wav")
                else "Bridge.provide(acoustic_event) callback starvation"
            ),
        },
    }


def _state_snapshot():
    with state_lock:
        snapshot = dict(state)
    health = _health_state()
    bridge = health.get("bridge", {})
    snapshot["bridge_health"] = {
        "mode": bridge.get("mode"),
        "alive": bridge.get("alive"),
        "stale": bridge.get("stale", False),
        "no_events_yet": bridge.get("no_events_yet", False),
        "provider_registered": bridge.get("provider_registered", False),
        "provider_registration_error": bridge.get("provider_registration_error"),
        "last_event_age_ms": bridge.get("last_event_age_ms"),
        "stale_after_ms": bridge.get("stale_after_ms"),
        "first_event_seen": bridge.get("first_event_seen", False),
        "flow_ack_sent": bridge.get("flow_ack_sent", False),
        "flow_ack_seen_by_mcu": bridge.get("flow_ack_seen_by_mcu", False),
        "state": bridge.get("state", "mock"),
    }
    return snapshot


# ── REST endpoints ─────────────────────────────────────────────────────────
ui.expose_api("GET", "/state", _state_snapshot)
ui.expose_api("GET", "/history", lambda: list(state["history"]))
ui.expose_api("GET", "/health", _health_state)


@ui.on_connect
def on_connect(sid):
    """Send current state snapshot to a newly connected client."""
    snapshot = _state_snapshot()
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


def _handle_keyword_detected(label):
    handle_event(label, 1.0, int(time.time()), source="ei_keyword_spotting")


def _classify_wav_once():
    try:
        from arduino.app_bricks.audio_classification import (
            AudioClassification,
            AudioClassificationException,
        )
    except Exception as exc:
        logger.exception("AudioClassification brick import failed")
        return {"ok": False, "error": str(exc)}

    try:
        result = AudioClassification.classify_from_file(EI_WAV_PATH, EI_WAV_CONFIDENCE)
    except AudioClassificationException as exc:
        logger.warning(f"WAV classification failed: {exc}")
        return {"ok": False, "error": str(exc), "path": EI_WAV_PATH}
    except Exception as exc:
        logger.exception("Unexpected WAV classification error")
        return {"ok": False, "error": str(exc), "path": EI_WAV_PATH}

    if not result:
        return {"ok": True, "path": EI_WAV_PATH, "result": None}

    class_name = str(result.get("class_name", "idle"))
    confidence = float(result.get("confidence", 0.0))
    handle_event(class_name, confidence, int(time.time()), source="ei_audio_classification_wav")
    return {"ok": True, "path": EI_WAV_PATH, "result": result}


def _wav_classifier_loop():
    logger.info(
        f"WAV classifier mode enabled path={EI_WAV_PATH} confidence={EI_WAV_CONFIDENCE:.2f} poll={EI_WAV_POLL_SEC:.1f}s"
    )
    last_mtime = 0.0
    while True:
        try:
            if os.path.exists(EI_WAV_PATH):
                mtime = os.path.getmtime(EI_WAV_PATH)
                if mtime > last_mtime:
                    last_mtime = mtime
                    _classify_wav_once()
        except Exception:
            logger.exception("WAV classifier loop error")
        time.sleep(max(0.5, EI_WAV_POLL_SEC))

# Expose manual WAV classification after helper is defined.
ui.expose_api("GET", "/classify-wav-now", _classify_wav_once)


# ── Startup ────────────────────────────────────────────────────────────────
if MOCK:
    threading.Thread(target=_mock_loop, daemon=True, name="mock-events").start()
else:
    using_brick = False
    if USE_EI_BRICK:
        try:
            from arduino.app_bricks.keyword_spotting import KeywordSpotting

            spotter = KeywordSpotting()
            for label in EI_BRICK_LABELS:
                spotter.on_detect(label, lambda lbl=label: _handle_keyword_detected(lbl))

            with state_lock:
                state["bridge_provider_registered"] = True
                state["bridge_provider_registration_error"] = ""
                state["event_source"] = "ei_keyword_spotting"
            logger.info(f"EI brick mode enabled: keyword_spotting labels={EI_BRICK_LABELS}")
            using_brick = True
        except Exception as exc:
            with state_lock:
                state["bridge_provider_registered"] = False
                state["bridge_provider_registration_error"] = str(exc)
                state["event_source"] = "ei_keyword_spotting_error"
            logger.exception("KeywordSpotting brick registration failed")

    if not using_brick:
        try:
            Bridge.provide("acoustic_event", _handle_acoustic_event)
            Bridge.provide("bridge_flow_ack_seen", _handle_bridge_flow_ack_seen)
            with state_lock:
                state["bridge_provider_registered"] = True
                state["bridge_provider_registration_error"] = ""
                state["event_source"] = "bridge"
            logger.info("Bridge: registered providers 'acoustic_event' + 'bridge_flow_ack_seen'")
        except Exception as exc:
            with state_lock:
                state["bridge_provider_registered"] = False
                state["bridge_provider_registration_error"] = str(exc)
                state["event_source"] = "bridge_error"
            logger.exception("Bridge provider registration failed")

    if USE_EI_WAV_CLASSIFIER:
        threading.Thread(target=_wav_classifier_loop, daemon=True, name="ei-wav-classifier").start()

App.run()
