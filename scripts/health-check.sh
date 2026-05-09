#!/usr/bin/env bash
# Health check script — Quick connectivity validation
#
# Usage: bash scripts/health-check.sh [--json]

set -euo pipefail

# Colours
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ENV="$PROJECT_ROOT/deploy.env"

JSON_MODE=false
[ "${1:-}" = "--json" ] && JSON_MODE=true

if [ ! -f "$DEPLOY_ENV" ]; then
  if [ "$JSON_MODE" = true ]; then
    echo '{"status":"error","message":"deploy.env not found"}'
  else
    echo -e "${RED}✗${NC} deploy.env not found"
  fi
  exit 1
fi

source "$DEPLOY_ENV"
DEVICE_IP="${DEVICE_IP:-}"
DEVICE_USER="${DEVICE_USER:-root}"
MONITOR_BAUD="${MONITOR_BAUD:-115200}"

# SSH args
ssh_args=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
[ -n "${SSH_KEY:-}" ] && ssh_args+=(-i "$SSH_KEY")

# Counters
pass=0
fail=0
checks=()

check_usb() {
  local port
  port=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1 || true)
  if [ -n "$port" ]; then
    checks+=("USB_OK")
    ((pass++))
    return 0
  else
    checks+=("USB_FAIL")
    ((fail++))
    return 1
  fi
}

check_ssh() {
  if ssh "${ssh_args[@]}" "${DEVICE_USER}@${DEVICE_IP}" "echo ok" &>/dev/null; then
    checks+=("SSH_OK")
    ((pass++))
    return 0
  else
    checks+=("SSH_FAIL")
    ((fail++))
    return 1
  fi
}

check_dashboard() {
  if ssh "${ssh_args[@]}" "${DEVICE_USER}@${DEVICE_IP}" "curl -sf http://localhost:5000/api/state >/dev/null" &>/dev/null; then
    checks+=("DASHBOARD_OK")
    ((pass++))
    return 0
  else
    checks+=("DASHBOARD_FAIL")
    ((fail++))
    return 1
  fi
}

# Run checks
check_usb
check_ssh
check_dashboard

# Output
if [ "$JSON_MODE" = true ]; then
  cat <<EOF
{
  "status": $([ $fail -eq 0 ] && echo '"ok"' || echo '"degraded"'),
  "pass": $pass,
  "fail": $fail,
  "checks": [$(printf '"%s"' "${checks[@]}" | sed 's/" *"/, /g')]
}
EOF
else
  echo "Health Check Results:"
  for c in "${checks[@]}"; do
    if [[ "$c" == *"FAIL" ]]; then
      echo -e "  ${RED}✗${NC} $c"
    else
      echo -e "  ${GREEN}✓${NC} $c"
    fi
  done
  echo
  echo "Pass: $pass, Fail: $fail"
  [ $fail -eq 0 ] && echo -e "${GREEN}All systems OK${NC}" || echo -e "${YELLOW}Some checks failed${NC}"
fi

exit $fail
