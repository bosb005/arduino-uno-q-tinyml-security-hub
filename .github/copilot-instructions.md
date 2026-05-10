# Copilot Instructions for `arduino-uno-q-tinyml-security-hub`

## Build, test, and lint commands

Use the root `deploy.sh` workflow as the source of truth for build/deploy/test.

```bash
# One-time local setup (tooling + deploy.env template)
bash scripts/setup.sh

# Build + flash MCU firmware (app/sketch) and auto-install EI ZIP if needed
./deploy.sh firmware

# Deploy full app stack (MCU firmware + app container)
./deploy.sh all

# Full deploy + test loop (recommended end-to-end cycle)
./deploy.sh cycle
```

Test commands:

```bash
# Full test pipeline (pre/post health + bridge test + restore)
./deploy.sh test

# Single focused integration test: bridge path only
./deploy.sh bridge-test

# Quick health probe (JSON output)
bash scripts/health-check.sh --json
```

There is no dedicated repository lint command configured.

## High-level architecture

This project has two tightly-coupled runtimes:

1. **MCU firmware (`app/sketch/`)**  
   Captures INMP441 audio via bit-banged I2S, runs classification logic, drives the UNO Q LED matrix, and publishes events through `Bridge.notify("acoustic_event", ...)`.
2. **Linux app (`app/python/`)**  
   Runs as an Arduino App (`arduino:web_ui` brick) on port **7000**, exposes `/state`, `/history`, `/health`, pushes live updates to browser clients, and can run in mock mode when router/MCU are unavailable.
3. **Deployment orchestration (`deploy.sh`)**  
   Handles local compile/flash (`arduino-cli` + `remoteocd`), app packaging/upload via `arduino-app-cli` REST on device localhost, router-aware restarts, and integrated health/bridge tests.

## Key repository-specific conventions

- **Primary code path is `app/`** (`app/sketch` + `app/python`), not `05_linux_dashboard/` or `04_firmware_inference/` (those are legacy/reference docs and earlier flow).
- **Dashboard/API port is 7000**. Use `http://<device-ip>:7000` and `http://localhost:7000/health` for checks.
- **Use `scripts/cycle.sh` or `./deploy.sh cycle` as the default dev loop**; this repo is optimized around deploy/test automation rather than ad hoc per-component commands.
- **Never write extra bytes to Bridge transport on MCU serial path**; `sketch.ino` intentionally suppresses EI printf output to avoid MsgPack/router framing corruption.
- **Edge Impulse library ZIP is expected at `03_ai_model/security-hub-acoustic_inferencing.zip`** and is installed automatically during firmware build.
- **App deployment uses app-cli over SSH-localhost** (`http://localhost:${APP_CLI_PORT}/v1/apps` on device), not direct external HTTP calls.
