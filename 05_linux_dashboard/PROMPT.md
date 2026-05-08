# Task: Linux Dashboard — Web Server + Real-Time Event Display

## Context

Platform: Linux side of Arduino UNO Q (likely OpenWRT or Debian-based)
Language: Python 3 with Flask (preferred) — available on the embedded Linux environment
IPC input: Events arrive from MCU via `/dev/ttyS1` (or equivalent UART) as JSON lines
Goal: Serve a local web dashboard over Wi-Fi showing current security state in real time

## Your Task

### 1. `app.py` — Flask web application
- Read JSON events from the MCU UART (`/dev/ttyS1`, 115200 baud) in a background thread
- Maintain a state object: `{"current_event": "idle", "confidence": 0.0, "ts": 0, "history": [...]}`
- Expose:
  - `GET /` → serve `templates/index.html`
  - `GET /stream` → Server-Sent Events (SSE) endpoint streaming state updates
  - `GET /api/state` → JSON snapshot of current state
- Keep last 50 events in history list

### 2. `templates/index.html` — Dashboard UI
Single-page dashboard:
- Large status indicator: colored badge showing current event
  - 🟢 `idle` → green
  - 🟡 `presence` → yellow  
  - 🔴 `anomaly` → red
  - 🔵 `manual_trigger` → blue
- Confidence score (percentage)
- Scrollable event history table (timestamp, event, confidence)
- Auto-reconnect SSE on disconnect
- No external CDN dependencies — plain HTML/CSS/JS only

### 3. `serial_reader.py` — UART reader module
- Class `SerialEventReader(port, baud)` with `start()` / `stop()` methods
- Calls a callback on each parsed JSON event
- Handles UART errors gracefully (reconnect after 2 s)

### 4. `wifi_setup.md`
- How to configure the UNO Q Linux side to connect to a home Wi-Fi network
- How to find the board's IP address
- How to set Flask to start on boot (systemd service or rc.local)

### 5. `security_hub.service` — systemd unit file
```ini
[Unit]
Description=Security Hub Dashboard
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/user/dashboard/app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

## Notes
- Flask SSE: use `response = Response(stream_with_context(event_stream()), mimetype='text/event-stream')`
- UART device name: verify with `ls /dev/tty*` on the Linux side; may be `/dev/ttyS1` or `/dev/ttyAML1`
- Set `FLASK_ENV=production` and bind to `0.0.0.0:5000` for LAN access
- The dashboard must work in a mobile browser (responsive CSS)
