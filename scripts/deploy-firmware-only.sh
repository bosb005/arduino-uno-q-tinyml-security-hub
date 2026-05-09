#!/usr/bin/env bash
# deploy-firmware-only.sh — Simplified MCU firmware deployment
# 
# Compile and flash firmware to Arduino UNO Q via USB
# No Linux side involvement, no app-cli, no routing
#
# Usage: bash scripts/deploy-firmware-only.sh

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}▶${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}!${NC} $*"; }
die()     { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Config ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ENV="$PROJECT_ROOT/deploy.env"

# Load config
if [ ! -f "$DEPLOY_ENV" ]; then
  die "deploy.env not found. Run: bash scripts/setup.sh"
fi
source "$DEPLOY_ENV"

ARDUINO_PORT="${ARDUINO_PORT:-auto}"
ARDUINO_FQBN="${ARDUINO_FQBN:-arduino:zephyr:unoq}"
SKETCH_DIR="${SKETCH_DIR:-app/sketch}"
MONITOR_BAUD="${MONITOR_BAUD:-115200}"

# ── Helpers ────────────────────────────────────────────────────────
check_tool() {
  command -v "$1" &>/dev/null || die "Missing: $1 (install with: bash scripts/setup.sh)"
}

resolve_port() {
  if [ "$ARDUINO_PORT" = "auto" ]; then
    local port
    port=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)
    [ -n "$port" ] || die "No USB device found. Check: Arduino UNO Q is plugged in?"
    echo "$port"
  else
    [ -e "$ARDUINO_PORT" ] || die "Port not found: $ARDUINO_PORT"
    echo "$ARDUINO_PORT"
  fi
}

ensure_ei_library() {
  local zip="$PROJECT_ROOT/03_ai_model/security-hub-acoustic_inferencing.zip"
  [ -f "$zip" ] || die "EI library not found: $zip (run: bash scripts/ei_workflow.sh --step export)"
  
  # Check if already installed
  local lib_name
  lib_name=$(unzip -l "$zip" 2>/dev/null | awk '{print $NF}' | grep '/$' | head -1 | tr -d '/')
  [ -n "$lib_name" ] || die "Corrupt EI library ZIP"
  
  local lib_dir="$HOME/Documents/Arduino/libraries/$lib_name"
  if [ -d "$lib_dir" ]; then
    success "EI library already installed"
    return 0
  fi
  
  info "Installing EI library: $lib_name ..."
  arduino-cli lib install --zip-path "$zip" || die "Failed to install EI library"
  success "Installed: $lib_name"
}

# ── MAIN ───────────────────────────────────────────────────────────

echo -e "${BOLD}╔════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Security Hub — Firmware Deploy       ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════╝${NC}"

check_tool arduino-cli
ensure_ei_library

port=$(resolve_port)

step "Compiling firmware"
info "Sketch: $SKETCH_DIR"
info "FQBN:   $ARDUINO_FQBN"
info "Port:   $port"

build_path="/tmp/arduino-build-unoq"
mkdir -p "$build_path"

arduino-cli compile \
  --fqbn "$ARDUINO_FQBN" \
  --build-path "$build_path" \
  --clean \
  "$PROJECT_ROOT/$SKETCH_DIR" || die "Compilation failed"

success "Compilation OK"

step "Uploading firmware"

# Extract MCU serial number for remoteocd
serial_no=$(arduino-cli board list --format json 2>/dev/null \
  | python3 -c "
import json, sys
for p in json.load(sys.stdin).get('detected_ports', []):
    if p['port']['address'] == '$port':
        print(p['port'].get('properties', {}).get('serialNumber', ''))
        break
" 2>/dev/null || true)

[ -n "$serial_no" ] || die "Could not detect MCU serial number. Is the board plugged in?"

# Find tools (arduino-cli should have installed them)
remoteocd=$(ls ~/Library/Arduino15/packages/arduino/tools/remoteocd/*/remoteocd 2>/dev/null | head -1)
[ -n "$remoteocd" ] || die "remoteocd tool not found. Run: bash scripts/setup.sh"

adb_path=$(dirname "$(ls ~/Library/Arduino15/packages/arduino/tools/adb/*/adb 2>/dev/null | head -1)")
[ -n "$adb_path" ] || die "adb tool not found"

variant_dir="$HOME/Library/Arduino15/packages/arduino/hardware/zephyr/0.55.0/variants/arduino_uno_q_stm32u585xx"
[ -d "$variant_dir" ] || die "Zephyr variant not found: $variant_dir"

firmware="$build_path/sketch.ino.elf-zsk.bin"
[ -f "$firmware" ] || die "Compiled firmware not found: $firmware"

info "Serial: $serial_no"
info "Firmware: $firmware"

"$remoteocd" upload \
  --adb-path "$adb_path/adb" \
  -s "$serial_no" \
  -f "$variant_dir/flash_sketch.cfg" \
  "$firmware" || die "Upload failed"

success "Upload complete"
success "Firmware deployed successfully"

echo
info "MCU will restart. Monitor output with:"
echo -e "  ${CYAN}./deploy.sh monitor${NC}"
