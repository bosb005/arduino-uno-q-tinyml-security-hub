#!/usr/bin/env bash
# deploy.sh — Security Hub deployment tool
#
# Usage:
#   ./deploy.sh <command> [options]
#
# Commands:
#   firmware    Compile and flash MCU sketch via USB
#   dashboard   Sync dashboard to device, restart service
#   all         firmware + dashboard
#   test        Health check + audio capture validation
#   cycle       Full deploy + test loop
#   monitor     Open serial monitor (MCU debug output)
#   logs        Tail dashboard service logs (SSH)
#   status      Show device ping + service status
#   shell       SSH into the Linux side
#   watch       Auto-redeploy on file changes (firmware or dashboard)
#   help        Show this help
#
# First run: bash scripts/setup.sh

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ENV="$SCRIPT_DIR/deploy.env"

# ── Colour helpers ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
info()    { echo -e "${CYAN}▶${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}!${NC} $*"; }
die()     { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Load config ───────────────────────────────────────────────
load_config() {
  if [ ! -f "$DEPLOY_ENV" ]; then
    die "deploy.env not found. Run: bash scripts/setup.sh"
  fi
  # shellcheck source=/dev/null
  source "$DEPLOY_ENV"
  DEVICE_IP="${DEVICE_IP:-}"
  DEVICE_USER="${DEVICE_USER:-root}"
  DEVICE_DASH_PATH="${DEVICE_DASH_PATH:-/home/user/dashboard}"
  SERVICE_NAME="${SERVICE_NAME:-security_hub}"
  ARDUINO_PORT="${ARDUINO_PORT:-auto}"
  ARDUINO_FQBN="${ARDUINO_FQBN:-arduino:zephyr:unoq}"
  SKETCH_DIR="${SKETCH_DIR:-app/sketch}"
  MONITOR_BAUD="${MONITOR_BAUD:-115200}"
  SSH_KEY="${SSH_KEY:-}"
  APP_CLI_PORT="${APP_CLI_PORT:-8800}"
  APP_NAME="${APP_NAME:-security-hub}"
}

# ── Ensure Edge Impulse library is installed ──────────────────
ensure_ei_library() {
  local zip="$SCRIPT_DIR/03_ai_model/security-hub-acoustic_inferencing.zip"
  if [ ! -f "$zip" ]; then
    die "EI library ZIP not found: $zip — run: bash scripts/ei_workflow.sh --step export"
  fi

  local has_inferencing_header
  has_inferencing_header=$(unzip -l "$zip" 2>/dev/null | awk '{print $NF}' | grep -E '_inferencing\.h$' | head -1 || true)

  # Get the top-level library folder name from the ZIP
  local lib_name
  lib_name=$(unzip -l "$zip" 2>/dev/null | awk '{print $NF}' | grep '/$' | head -1 | tr -d '/')

  if [ -z "$lib_name" ]; then
    die "Could not read library name from $zip — ZIP may be corrupt."
  fi

  # arduino-cli stores user libraries in ~/Arduino/libraries or ~/Documents/Arduino/libraries
  local lib_path
  lib_path=$(arduino-cli config dump 2>/dev/null | grep -E "^\s+user:" | awk '{print $2}' || echo "")
  if [ -z "$lib_path" ]; then
    lib_path="$HOME/Documents/Arduino"
  fi
  local lib_dir="$lib_path/libraries/$lib_name"

  if [ -z "$has_inferencing_header" ]; then
    warn "EI ZIP looks incomplete (no *_inferencing.h): $zip"
    local installed_header
    installed_header=$(find "$lib_path/libraries" -maxdepth 3 -type f -name '*_inferencing.h' 2>/dev/null | head -1 || true)
    if [ -n "$installed_header" ]; then
      success "Using already installed EI library header: $(basename "$installed_header")"
      return 0
    fi
    die "No installed Edge Impulse *_inferencing.h found. Re-export model ZIP via scripts/ei_workflow.sh."
  fi

  if [ -d "$lib_dir" ]; then
    success "EI library already installed: $lib_name"
    return 0
  fi

  info "Installing Edge Impulse library: $lib_name ..."
  arduino-cli lib install --zip-path "$zip"
  success "EI library installed: $lib_name"
}

# ── Prerequisites check ───────────────────────────────────────
check_prereqs() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      warn "Missing tool: $cmd  →  run: bash scripts/setup.sh"
      missing=1
    fi
  done
  [ $missing -eq 0 ] || die "Install missing tools then retry."
}

# ── SSH helper ────────────────────────────────────────────────
ssh_args() {
  local args=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
  [ -n "${SSH_KEY:-}" ] && args+=(-i "$SSH_KEY")
  echo "${args[@]}"
}

run_ssh() {
  # shellcheck disable=SC2046
  ssh $(ssh_args) "${DEVICE_USER}@${DEVICE_IP}" "$@"
}

check_device_ip() {
  [ -n "$DEVICE_IP" ] && [ "$DEVICE_IP" != "192.168.1.100" ] || \
    die "DEVICE_IP not set. Edit deploy.env."
}

# ── Auto-detect Arduino port ──────────────────────────────────
resolve_port() {
  if [ "$ARDUINO_PORT" = "auto" ]; then
    local port
    port=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)
    if [ -z "$port" ]; then
      die "No USB serial device found. Plug in the Arduino UNO Q and retry."
    fi
    echo "$port"
  else
    [ -e "$ARDUINO_PORT" ] || die "Port $ARDUINO_PORT not found. Check ARDUINO_PORT in deploy.env."
    echo "$ARDUINO_PORT"
  fi
}

# ── arduino-app-cli REST API helpers ─────────────────────────
app_cli_url() { echo "http://${DEVICE_IP}:${APP_CLI_PORT}"; }

# The app ID is base64 of "user:{name-lowercased-dashes}".
app_id() {
  local name="${1:-$APP_NAME}"
  local folder
  folder=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  echo -n "user:$folder" | base64
}

# arduino-app-cli API only listens on localhost on the device.
# We SCP the ZIP to the device, then run curl over SSH.
app_cli_ssh()  { run_ssh "curl -sf $*"; }
app_cli_get()  { run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}$1'"; }
app_cli_post() { run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}$1' ${*:2}"; }

# ══════════════════════════════════════════════════════════════
# Commands
# ══════════════════════════════════════════════════════════════

cmd_firmware() {
  check_prereqs arduino-cli
  local port
  port=$(resolve_port)

  ensure_ei_library

  # Restart the router BEFORE flashing so the MCU boots into a stable router.
  # If the router restarts after the MCU, Bridge.begin() catches a dead socket
  # and the handshake never completes.
  step "Restarting arduino-router before flash"
  run_ssh "echo 'arduino' | sudo -S systemctl restart arduino-router 2>/dev/null; sleep 3; \
    systemctl is-active arduino-router" \
    && success "Router ready" || warn "Router restart failed — continuing anyway"

  # Stable build output directory so we can find the binary for upload
  local build_path="/tmp/arduino-build-unoq"
  mkdir -p "$build_path"

  step "Compiling firmware"
  info "Sketch : $SKETCH_DIR"
  info "FQBN   : $ARDUINO_FQBN"
  arduino-cli compile \
    --fqbn "$ARDUINO_FQBN" \
    --build-path "$build_path" \
    --clean \
    "$SCRIPT_DIR/$SKETCH_DIR"
  success "Compilation OK"

  step "Uploading firmware"
  info "Port: $port"
  # arduino-cli 1.4.x does not substitute {upload.port.properties.serialNumber}
  # in the remoteocd command, so we call remoteocd directly.
  local serial_no
  serial_no=$(arduino-cli board list --format json 2>/dev/null \
    | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('detected_ports',[]):
    if p['port']['address'] == '$port':
        print(p['port'].get('properties',{}).get('serialNumber',''))
        break
" 2>/dev/null || true)

  if [ -z "$serial_no" ]; then
    die "Could not read USB serial number for $port. Is the board plugged in?"
  fi

  local remoteocd
  remoteocd=$(ls ~/Library/Arduino15/packages/arduino/tools/remoteocd/*/remoteocd 2>/dev/null | head -1)
  local adb_path
  adb_path=$(dirname "$(ls ~/Library/Arduino15/packages/arduino/tools/adb/*/adb 2>/dev/null | head -1)")
  local variant_dir="$HOME/Library/Arduino15/packages/arduino/hardware/zephyr/0.55.0/variants/arduino_uno_q_stm32u585xx"
  local firmware="$build_path/sketch.ino.elf-zsk.bin"

  # flash_sketch.cfg (0.55.0): flash ELF to 0x8100000, reset MCU, then write
  # magic word 0xCAFFEEEE to 0x40036400 100ms after boot while MCU is running.
  # Kernel polls that register; when it finds the magic it loads the LLEXT from
  # 0x8100000.  We compile with wait_linux_boot=no (immediate mode) so the
  # sketch starts right away without waiting for a GPIO-70 edge.
  info "Serial: $serial_no"
  "$remoteocd" upload \
    --adb-path "$adb_path/adb" \
    -s "$serial_no" \
    -f "$variant_dir/flash_sketch.cfg" \
    "$firmware"
  success "Upload complete"
  info "Waiting for MCU/router to settle..."
  sleep 10

  # After flashing the MCU reboots and handshakes with the already-running router.
  # Re-register the Python app's Bridge.provide() binding against the current router.
  step "Reconnecting Python app to Bridge"
  run_ssh "
    APP_ID=\$(curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps' | \
      python3 -c \"import json,sys; apps=json.load(sys.stdin).get('apps',[]); \
        [print(a['id']) for a in apps if '${APP_NAME}' in a.get('name','').lower() and a.get('status')=='running']\" 2>/dev/null | head -1)
    if [ -n \"\$APP_ID\" ]; then
      curl -sf -X POST \"http://localhost:${APP_CLI_PORT}/v1/apps/\${APP_ID}/stop\" >/dev/null 2>&1; sleep 2
      curl -sf -X POST \"http://localhost:${APP_CLI_PORT}/v1/apps/\${APP_ID}/start\" --max-time 60 >/dev/null 2>&1
      echo \"App \${APP_ID} restarted\"
    else
      echo 'No running app found — run: ./deploy.sh app'
    fi" \
    && success "Python app reconnected" || warn "App reconnect failed — run: ./deploy.sh app"
}

# Deploy the Arduino App (app/ directory) via arduino-app-cli REST API.
# Zips app/, base64-encodes it, uploads to POST /v1/apps/import, then starts.
cmd_app() {
  local app_dir="${1:-$SCRIPT_DIR/app}"
  local app_name_override="${2:-}"
  local target_app_name="${app_name_override:-$APP_NAME}"

  check_prereqs curl zip
  check_device_ip

  [ -d "$app_dir" ] || die "app directory not found at $app_dir"
  [ -f "$app_dir/app.yaml" ] || die "app.yaml not found in $app_dir"

  step "Packaging app"
  local tmp_zip="/tmp/security-hub-$$.zip"
  # Zip the app/ contents (not the directory itself — app-cli needs the files at zip root).
  # Exclude sketch/ — MCU firmware is flashed directly via 'deploy.sh firmware'; the
  # device does not need to re-compile it and the EI inferencing library is not on the device.
  (cd "$app_dir" && zip -r "$tmp_zip" . \
    --exclude '*.DS_Store' \
    --exclude '__pycache__/*' \
    --exclude '*.pyc' \
    --exclude '.cache/*' \
    --exclude 'sketch/*')
  info "Packaged: $tmp_zip ($(du -sh "$tmp_zip" | cut -f1))"

  step "Uploading app to device"
  # The app ID is derived from the zip filename — keep it aligned with target_app_name.
  local remote_zip="/tmp/${target_app_name}.zip"
  # SCP the zip to the device, then import via SSH curl (API only listens on localhost)
  # shellcheck disable=SC2046
  scp $(ssh_args) "$tmp_zip" "${DEVICE_USER}@${DEVICE_IP}:${remote_zip}"
  rm -f "$tmp_zip"

  # Delete any existing app versions with this name (prevent duplicate accumulation)
  run_ssh "
    curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps' | \
    python3 -c \"
import json, sys, subprocess
apps = json.load(sys.stdin).get('apps', [])
for a in apps:
    if '${target_app_name}' in a['name'].lower() and not a.get('example'):
        if a.get('status') == 'running':
            subprocess.run(['curl','-sf','-X','POST','http://localhost:${APP_CLI_PORT}/v1/apps/'+a['id']+'/stop'], capture_output=True)
        subprocess.run(['curl','-sf','-X','DELETE','http://localhost:${APP_CLI_PORT}/v1/apps/'+a['id']], capture_output=True)
        print('Removed old app:', a['name'], a['id'])
\"" 2>/dev/null || true

  local response
  response=$(run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/import' -F 'file=@${remote_zip}' && rm -f '${remote_zip}'") || {
    warn "Import failed on device."
    run_ssh "rm -f '${remote_zip}'" 2>/dev/null || true
    die "App import failed"
  }
  success "App imported: $response"

  # ID is returned in response; fall back to computed app_id
  local id
  id=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "")
  [ -z "$id" ] && id=$(app_id "$target_app_name")

  # App Lab runs one user app at a time. Stop any other running user app first,
  # otherwise the start stream can return INTERNAL_SERVER_ERROR.
  run_ssh "
    curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps' | \
    python3 -c \"
import json, sys, subprocess
target='${id}'
apps=json.load(sys.stdin).get('apps', [])
for a in apps:
    if a.get('example'):
        continue
    if a.get('status') == 'running' and a.get('id') != target:
        subprocess.run(
            ['curl','-sf','-X','POST','http://localhost:${APP_CLI_PORT}/v1/apps/'+a['id']+'/stop'],
            capture_output=True
        )
        print('Stopped running app:', a['name'], a['id'])
\"" 2>/dev/null || true

  step "Starting app"
  info "App ID: $id"
  # start returns SSE — stream it via SSH; break on progress=100 or error
  run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/start' -H 'Accept: text/event-stream' --no-buffer --max-time 300" 2>&1 | while IFS= read -r line; do
      echo -e "  ${DIM}$line${NC}"
      echo "$line" | grep -q '"progress":100' && break
      echo "$line" | grep -q '"progress":1}'   && break
      echo "$line" | grep -qi '"code":"INTERNAL' && { warn "Start error — check: ./deploy.sh logs"; break; }
    done
  success "App started → dashboard at http://${DEVICE_IP}:7000"
}

cmd_app_stop() {
  check_prereqs curl
  check_device_ip
  step "Stopping app"
  local id
  id=$(app_id)
  run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/stop'" && success "App stopped" || warn "Stop failed (app may not be running)"
}

cmd_app_start() {
  check_prereqs ssh
  check_device_ip
  step "Starting app"
  local id
  id=$(app_id)
  run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/start' -H 'Accept: text/event-stream' --no-buffer" 2>&1 | while IFS= read -r line; do
      echo -e "  ${DIM}$line${NC}"
      echo "$line" | grep -q '"progress":1' && break
    done
  success "App started → http://${DEVICE_IP}:7000"
}

cmd_app_logs() {
  check_prereqs ssh
  check_device_ip
  step "App logs (Ctrl+C to exit)"
  local id
  id=$(app_id)
  run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/logs' --no-buffer" || \
    warn "Could not retrieve logs — is app running? Try: ./deploy.sh app-start"
}

cmd_app_list() {
  check_prereqs ssh
  check_device_ip
  step "Installed apps on device"
  run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps'" | python3 -m json.tool 2>/dev/null || true
}

cmd_audio_test() {
  step "Deploying audio capture test app"
  warn "This replaces the running app. Restore with: ./deploy.sh app"
  step "Restarting arduino-router before audio-test start"
  run_ssh "echo 'arduino' | sudo -S systemctl restart arduino-router 2>/dev/null; \
    for i in \$(seq 1 20); do \
      [ -S /var/run/arduino-router.sock ] && curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps' >/dev/null 2>&1 && exit 0; \
      sleep 1; \
    done; \
    exit 1" \
    && success "Router ready" || warn "Router not ready yet — attempting app deploy anyway"
  cmd_app "$SCRIPT_DIR/app_audio_test" "audio-test"
  info "Watch logs with: ./deploy.sh audio-logs"
  info "When done, copy WAV: scp arduino@\${DEVICE_IP}:/home/arduino/ArduinoApps/audio-test/test.wav ./"
  info "Restore main app:   ./deploy.sh app"
}

cmd_audio_test_firmware() {
  check_prereqs arduino-cli
  ensure_ei_library

  local port
  port=$(resolve_port)

  step "Restarting arduino-router before audio-test flash"
  run_ssh "echo 'arduino' | sudo -S systemctl restart arduino-router 2>/dev/null; sleep 3; \
    systemctl is-active arduino-router" \
    && success "Router ready" || warn "Router restart failed — continuing anyway"

  local build_path="/tmp/arduino-build-audio-test"
  mkdir -p "$build_path"

  step "Compiling audio-test firmware"
  info "Sketch : app_audio_test/sketch"
  info "FQBN   : $ARDUINO_FQBN"
  arduino-cli compile \
    --fqbn "$ARDUINO_FQBN" \
    --build-path "$build_path" \
    --clean \
    "$SCRIPT_DIR/app_audio_test/sketch"
  success "Compilation OK"

  step "Uploading audio-test firmware"
  info "Port: $port"
  local serial_no
  serial_no=$(arduino-cli board list --format json 2>/dev/null \
    | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('detected_ports', []):
    if p['port']['address'] == '$port':
        print(p['port'].get('properties', {}).get('serialNumber', ''))
        break
" 2>/dev/null || true)

  [ -n "$serial_no" ] || die "Could not read USB serial number for $port. Is the board plugged in?"

  local remoteocd
  remoteocd=$(ls ~/Library/Arduino15/packages/arduino/tools/remoteocd/*/remoteocd 2>/dev/null | head -1)
  local adb_path
  adb_path=$(dirname "$(ls ~/Library/Arduino15/packages/arduino/tools/adb/*/adb 2>/dev/null | head -1)")
  local variant_dir="$HOME/Library/Arduino15/packages/arduino/hardware/zephyr/0.55.0/variants/arduino_uno_q_stm32u585xx"
  local firmware="$build_path/sketch.ino.elf-zsk.bin"

  info "Serial: $serial_no"
  "$remoteocd" upload \
    --adb-path "$adb_path/adb" \
    -s "$serial_no" \
    -f "$variant_dir/flash_sketch.cfg" \
    "$firmware"
  success "Audio-test firmware uploaded"
  info "Waiting for MCU/router to settle..."
  sleep 10
}

cmd_bridge_test() {
  step "Bridge isolation test"
  info "Stopping security-hub container directly"
  run_ssh "docker stop security-hub-main-1 >/dev/null 2>&1 || true"
  info "Waiting for security-hub app container to stop"
  for _ in $(seq 1 12); do
    if ! run_ssh "docker ps --format '{{.Names}}' | grep -qx 'security-hub-main-1'" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done
  cmd_audio_test
  step "Resetting MCU path with audio-test app already running"
  cmd_audio_test_firmware
  run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/dXNlcjphdWRpby10ZXN0/stop' >/dev/null 2>&1; \
    sleep 2; \
    curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/dXNlcjphdWRpby10ZXN0/start' --max-time 60 >/dev/null 2>&1" \
    && success "Audio-test app restarted after firmware flash" || warn "Audio-test restart failed"

  local wav_path="/home/arduino/ArduinoApps/audio-test/test.wav"
  info "Waiting for bridge WAV: $wav_path"
  if wait_for_remote_file "$wav_path" 150; then
    local wav_size
    wav_size=$(run_ssh "stat -c '%s' '$wav_path'" | tr -d '\r' || true)
    [ -n "$wav_size" ] || die "Bridge test WAV size could not be read"
    success "Bridge test produced test.wav (${wav_size} bytes)"
  else
    die "Bridge test did not produce $wav_path"
  fi

  step "Restoring main deployment (firmware + app)"
  cmd_all
}

wait_for_remote_file() {
  local path="$1"
  local timeout="${2:-120}"
  local interval=5
  local deadline=$((SECONDS + timeout))

  while [ "$SECONDS" -lt "$deadline" ]; do
    if run_ssh "test -s '$path'" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$interval"
  done

  return 1
}

cmd_audio_bridge_fix() {
  check_prereqs ssh
  check_device_ip
  step "Restarting arduino-router + audio-test app (Bridge handshake fix)"
  run_ssh "echo 'arduino' | sudo -S systemctl restart arduino-router 2>/dev/null"
  sleep 5
  run_ssh "curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/dXNlcjphdWRpby10ZXN0/stop' >/dev/null 2>&1; sleep 2; \
    curl -sf -X POST 'http://localhost:${APP_CLI_PORT}/v1/apps/dXNlcjphdWRpby10ZXN0/start' --max-time 60 >/dev/null 2>&1"
  success "Bridge restarted — watch: ./deploy.sh audio-logs"
}

cmd_audio_logs() {
  check_prereqs ssh
  check_device_ip
  local saved_app="$APP_NAME"
  APP_NAME="audio-test"
  step "Audio test logs (Ctrl+C to exit)"
  local id
  id=$(app_id)
  APP_NAME="$saved_app"
  run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/logs' --no-buffer" || \
    warn "Could not retrieve logs — is audio-test app running?"
}


cmd_dashboard() {
  check_prereqs rsync ssh
  check_device_ip

  local src="$SCRIPT_DIR/app/python/"
  local dst="${DEVICE_USER}@${DEVICE_IP}:${DEVICE_DASH_PATH}/"

  step "Syncing dashboard"
  info "Source : $src"
  info "Target : $dst"

  # shellcheck disable=SC2046
  rsync -avz --delete \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    --exclude '.DS_Store' \
    -e "ssh $(ssh_args)" \
    "$src" "$dst"
  success "Files synced"

  step "Restarting service"
  run_ssh "systemctl restart ${SERVICE_NAME} && systemctl --no-pager status ${SERVICE_NAME}"
  success "Service restarted"
}

cmd_all() {
  cmd_firmware
  cmd_app
}

cmd_test() {
  check_prereqs ssh curl
  check_device_ip

  step "Pre-flight health check"
  local pre_ok="no"
  for _ in $(seq 1 10); do
    if "$SCRIPT_DIR"/scripts/health-check.sh --json; then
      pre_ok="yes"
      break
    fi
    sleep 2
  done
  [ "$pre_ok" = "yes" ] || die "Pre-flight health check failed"

  step "Bridge transport test"
  cmd_bridge_test

  step "Live dashboard event check"
  local got_event="no"
  for _ in $(seq 1 15); do
    if curl -sf "http://${DEVICE_IP}:7000/state" 2>/dev/null | grep -q '"last_updated":"[^"]'; then
      got_event="yes"
      break
    fi
    sleep 2
  done
  [ "$got_event" = "yes" ] || die "No live event observed on /state after restore"

  step "Post-test health check"
  "$SCRIPT_DIR"/scripts/health-check.sh --json
  success "Device test cycle complete"
}

cmd_cycle() {
  step "Deploying full app cycle"
  cmd_all
  cmd_test
}

cmd_monitor() {
  check_prereqs arduino-cli
  local port
  port=$(resolve_port)
  step "Serial monitor"
  info "Port: $port  Baud: $MONITOR_BAUD"
  info "Press Ctrl+C to exit"
  arduino-cli monitor --port "$port" --config "baudrate=$MONITOR_BAUD"
}

cmd_logs() {
  check_prereqs curl ssh
  check_device_ip
  step "App logs (Ctrl+C to exit)"
  # Try app-cli via SSH first, fall back to journalctl
  local id
  id=$(app_id)
  run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}/logs' --no-buffer" 2>/dev/null || {
    warn "app-cli logs unavailable, falling back to journalctl"
    run_ssh "journalctl -u ${SERVICE_NAME} -f --no-pager"
  }
}

cmd_status() {
  check_prereqs ssh
  check_device_ip

  step "Device connectivity"
  if ping -c1 -W2 "$DEVICE_IP" &>/dev/null; then
    success "Ping OK: $DEVICE_IP"
  else
    warn "Ping failed: $DEVICE_IP"
  fi

  step "arduino-app-cli daemon"
  local api_ok
  api_ok=$(run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps' > /dev/null 2>&1 && echo ok || echo fail" 2>/dev/null || echo "fail")
  if [ "$api_ok" = "ok" ]; then
    success "app-cli API responding on port ${APP_CLI_PORT}"
    local id
    id=$(app_id)
    run_ssh "curl -sf 'http://localhost:${APP_CLI_PORT}/v1/apps/${id}'" 2>/dev/null | python3 -m json.tool 2>/dev/null || true
  else
    warn "app-cli API not responding — check service: ./deploy.sh shell → systemctl status arduino-app-cli"
  fi

  step "Dashboard endpoint"
  if curl -sf --max-time 5 "http://${DEVICE_IP}:7000/health" &>/dev/null; then
    success "Dashboard responding at http://${DEVICE_IP}:7000"
  else
    warn "Dashboard not responding on port 7000"
  fi
}

cmd_shell() {
  check_prereqs ssh
  check_device_ip
  info "Opening shell on ${DEVICE_USER}@${DEVICE_IP} ..."
  # shellcheck disable=SC2046
  ssh $(ssh_args) "${DEVICE_USER}@${DEVICE_IP}"
}

cmd_watch() {
  check_prereqs fswatch
  local target="${1:-dashboard}"
  case "$target" in
    firmware)
      local watch_dirs=("$SCRIPT_DIR/app/sketch")
      step "Watch mode: firmware (Ctrl+C to stop)"
      info "Watching: app/sketch/"
      info "Will re-flash on any .ino/.h/.cpp change"
      fswatch -o --event Updated --include '\.(ino|h|cpp)$' "${watch_dirs[@]}" | \
        while read -r; do
          echo -e "\n${YELLOW}[watch]${NC} Change detected → deploying firmware..."
          cmd_firmware && success "Firmware updated" || warn "Firmware deploy failed"
        done
      ;;
    dashboard|app)
      local watch_dirs=("$SCRIPT_DIR/app/python")
      step "Watch mode: app/python (Ctrl+C to stop)"
      info "Watching: app/python/"
      info "Will re-deploy app on any .py/.html/.css change"
      fswatch -o --event Updated --include '\.(py|html|css|js)$' "${watch_dirs[@]}" | \
        while read -r; do
          echo -e "\n${YELLOW}[watch]${NC} Change detected → deploying app..."
          cmd_app && success "App updated" || warn "App deploy failed"
        done
      ;;
    all)
      warn "Watch mode 'all' monitors both dirs and deploys the changed target"
      local fw_dirs=("$SCRIPT_DIR/app/sketch")
      local dash_dirs=("$SCRIPT_DIR/app/python")
      fswatch -o --event Updated --include '\.(ino|h|cpp)$' "${fw_dirs[@]}" | \
        while read -r; do
          echo -e "\n${YELLOW}[watch/fw]${NC} Change → firmware..."
          cmd_firmware && success "Firmware updated" || warn "Failed"
        done &
      fswatch -o --event Updated --include '\.(py|html|css|js)$' "${dash_dirs[@]}" | \
        while read -r; do
          echo -e "\n${YELLOW}[watch/app]${NC} Change → app..."
          cmd_app && success "App updated" || warn "Failed"
        done &
      info "Watching all targets. Press Ctrl+C to stop."
      wait
      ;;
    *)
      die "Unknown watch target: $target. Use: firmware | dashboard | all"
      ;;
  esac
}

cmd_help() {
  echo -e "${BOLD}Security Hub deploy tool${NC}"
  echo
  echo -e "${BOLD}Usage:${NC}  ./deploy.sh <command> [target]"
  echo
  echo -e "${BOLD}Primary commands (arduino-app-cli):${NC}"
  echo -e "  ${CYAN}app${NC}                 Package app/ as ZIP → upload + start via app-cli REST API"
  echo -e "  ${CYAN}app-start${NC}           Start the app on device (app-cli)"
  echo -e "  ${CYAN}app-stop${NC}            Stop the app on device (app-cli)"
  echo -e "  ${CYAN}app-logs${NC}            Stream app logs (app-cli)"
  echo -e "  ${CYAN}app-list${NC}            List all apps on device (app-cli)"
  echo -e "  ${CYAN}audio-test${NC}          Deploy mic test app → records 5s WAV to /home/arduino/ArduinoApps/audio-test/test.wav"
  echo -e "  ${CYAN}audio-logs${NC}          Stream audio-test app logs"
  echo -e "  ${CYAN}bridge-test${NC}         Flash audio-test firmware + app → verify WAV bridge path"
  echo
  echo -e "${BOLD}MCU firmware:${NC}"
  echo -e "  ${CYAN}firmware${NC}            Compile + flash MCU sketch via USB (arduino-cli)"
  echo -e "  ${CYAN}all${NC}                 firmware + app"
  echo -e "  ${CYAN}test${NC}                health check + audio capture validation"
  echo -e "  ${CYAN}cycle${NC}               full deploy + test loop"
  echo -e "  ${CYAN}monitor${NC}             Open arduino-cli serial monitor"
  echo
  echo -e "${BOLD}Dev tools:${NC}"
  echo -e "  ${CYAN}watch [target]${NC}      Auto-deploy on save  (target: firmware|app|all)"
  echo -e "  ${CYAN}logs${NC}                Stream app logs (app-cli, falls back to journalctl)"
  echo -e "  ${CYAN}status${NC}              Ping + app-cli + dashboard health check"
  echo -e "  ${CYAN}shell${NC}               SSH into the Linux side"
  echo -e "  ${CYAN}dashboard${NC}           Rsync app/python/ → device via SSH (fallback)"
  echo -e "  ${CYAN}help${NC}                Show this help"
  echo
  echo -e "${BOLD}First run:${NC}  bash scripts/setup.sh"
  echo -e "${BOLD}Config:${NC}     edit deploy.env  (DEVICE_IP, ARDUINO_PORT, APP_CLI_PORT)"
  echo
  echo -e "${DIM}Recommended dev cycle:${NC}"
  echo -e "  ${DIM}# Full deploy (firmware + app):${NC}"
  echo -e "  ./deploy.sh all"
  echo -e "  ${DIM}# Fast iteration on Python/HTML only:${NC}"
  echo -e "  ./deploy.sh watch app"
  echo -e "  ${DIM}# Fast iteration on sketch only:${NC}"
  echo -e "  ./deploy.sh watch firmware"
  echo -e "  ${DIM}# Live MCU debug output:${NC}"
  echo -e "  ./deploy.sh monitor"
}

# ── Dispatch ──────────────────────────────────────────────────
CMD="${1:-help}"
shift || true

# help and setup don't need config
case "$CMD" in
  help|--help|-h) cmd_help; exit 0 ;;
esac

load_config

case "$CMD" in
  app)        cmd_app       ;;
  app-start)  cmd_app_start ;;
  app-stop)   cmd_app_stop  ;;
  app-logs)   cmd_app_logs  ;;
  app-list)   cmd_app_list  ;;
  audio-test) cmd_audio_test ;;
  audio-logs) cmd_audio_logs ;;
  bridge-test) cmd_bridge_test ;;
  audio-bridge-fix) cmd_audio_bridge_fix ;;
  firmware)   cmd_firmware  ;;
  dashboard)  cmd_dashboard ;;
  all)        cmd_all       ;;
  test)       cmd_test      ;;
  cycle)      cmd_cycle     ;;
  monitor)    cmd_monitor   ;;
  logs)       cmd_logs      ;;
  status)     cmd_status    ;;
  shell)      cmd_shell     ;;
  watch)      cmd_watch "${1:-app}" ;;
  help|--help|-h) cmd_help ;;
  *)
    warn "Unknown command: $CMD"
    echo
    cmd_help
    exit 1
    ;;
esac
