#!/usr/bin/env bash
# setup.sh — One-time developer environment setup
# Run once before using deploy.sh
# Usage: bash scripts/setup.sh

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[setup]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Security Hub — Developer Setup          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo

# ── 1. Homebrew ───────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  die "Homebrew not found. Install it first: https://brew.sh"
fi
success "Homebrew found: $(brew --version | head -1)"

# ── 2. arduino-cli ───────────────────────────────────────────
if ! command -v arduino-cli &>/dev/null; then
  info "Installing arduino-cli..."
  brew install arduino-cli
else
  success "arduino-cli found: $(arduino-cli version)"
fi

# ── 3. fswatch (for watch/auto-deploy mode) ──────────────────
if ! command -v fswatch &>/dev/null; then
  info "Installing fswatch..."
  brew install fswatch
else
  success "fswatch found: $(fswatch --version 2>&1 | head -1)"
fi

# ── 4. Arduino UNO Q board package ───────────────────────────
info "Updating arduino-cli core index..."
arduino-cli core update-index

RENESAS_CORE="arduino:renesas_uno"
if arduino-cli core list | grep -q "$RENESAS_CORE"; then
  success "Board core already installed: $RENESAS_CORE"
else
  info "Installing Arduino Renesas UNO board core (includes UNO Q)..."
  arduino-cli core install "$RENESAS_CORE"
fi

echo
info "Available Renesas UNO boards:"
arduino-cli board listall | grep -i "renesas_uno" || warn "No boards found — check core installation"

# ── 5. deploy.env setup ──────────────────────────────────────
echo
DEPLOY_ENV="$PROJECT_ROOT/deploy.env"
if [ -f "$DEPLOY_ENV" ]; then
  success "deploy.env already exists — skipping template copy"
else
  cp "$SCRIPT_DIR/deploy.env.template" "$DEPLOY_ENV"
  warn "Created deploy.env from template."
  warn ">>> EDIT deploy.env with your device IP and USB port before using deploy.sh <<<"
fi

# ── 6. .gitignore ────────────────────────────────────────────
GITIGNORE="$PROJECT_ROOT/.gitignore"
if ! grep -q "deploy.env" "$GITIGNORE" 2>/dev/null; then
  echo "deploy.env" >> "$GITIGNORE"
  success "Added deploy.env to .gitignore"
else
  success "deploy.env already in .gitignore"
fi

# ── 7. SSH connectivity check ────────────────────────────────
echo
if [ -f "$DEPLOY_ENV" ] && grep -q "^DEVICE_IP=" "$DEPLOY_ENV"; then
  # shellcheck source=/dev/null
  source "$DEPLOY_ENV"
  DEVICE_IP="${DEVICE_IP:-}"
  DEVICE_USER="${DEVICE_USER:-root}"
  if [ -n "$DEVICE_IP" ] && [ "$DEVICE_IP" != "192.168.1.100" ]; then
    info "Testing SSH connection to ${DEVICE_USER}@${DEVICE_IP}..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${DEVICE_USER}@${DEVICE_IP}" "echo ok" &>/dev/null; then
      success "SSH connection to device OK"
    else
      warn "SSH connection failed — check DEVICE_IP/DEVICE_USER in deploy.env"
      warn "To set up passwordless SSH: ssh-copy-id ${DEVICE_USER}@${DEVICE_IP}"
    fi
  else
    warn "DEVICE_IP not configured in deploy.env — skipping SSH check"
  fi
fi

# ── 8. Summary ───────────────────────────────────────────────
echo
echo -e "${BOLD}Setup complete. Next steps:${NC}"
echo -e "  1. Edit ${CYAN}deploy.env${NC} with your device IP and USB port"
echo -e "     Run: ${CYAN}arduino-cli board list${NC} (with board plugged in) to find port"
echo -e "     Run: ${CYAN}arduino-cli board listall | grep -i 'uno q'${NC} to confirm FQBN"
echo -e "  2. Train the model (if not already done):"
echo -e "     ${CYAN}bash scripts/ei_record.sh${NC}          # record samples"
echo -e "     ${CYAN}bash scripts/ei_workflow.sh --step all${NC}  # train + export ZIP"
echo -e "  3. Run: ${CYAN}./deploy.sh all${NC}"
echo -e "     (The Edge Impulse library ZIP is installed automatically during firmware compile)"
