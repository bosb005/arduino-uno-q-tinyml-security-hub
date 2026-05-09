#!/bin/bash
# Health check script — Quick system connectivity validation
# 
# IMPORTANT: Dashboard runs on PORT 7000 (not 5000!)
# - 7000: Arduino app-cli dashboard
# - 5000: (not used in this project)
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ENV="$PROJECT_ROOT/deploy.env"

JSON_MODE=false
[ "${1:-}" = "--json" ] && JSON_MODE=true

[ -f "$DEPLOY_ENV" ] || { printf '{"status":"error"}\n'; exit 1; }

source "$DEPLOY_ENV"
pass=0; fail=0; checks=()

check_usb() {
  ls /dev/cu.usbmodem* >/dev/null 2>&1 && { checks+=("USB_OK"); ((pass++)); return 0; } || { checks+=("USB_FAIL"); ((fail++)); return 1; }
}

check_ssh() {
  ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_KEY:+-i "$SSH_KEY"} "${DEVICE_USER}@${DEVICE_IP}" "echo ok" >/dev/null 2>&1 && { checks+=("SSH_OK"); ((pass++)); } || { checks+=("SSH_FAIL"); ((fail++)); }
}

check_dashboard() {
  # Dashboard runs on PORT 7000 (not 5000!)
  ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_KEY:+-i "$SSH_KEY"} "${DEVICE_USER}@${DEVICE_IP}" "curl -sf http://localhost:7000/health >/dev/null" >/dev/null 2>&1 && { checks+=("DASHBOARD_OK"); ((pass++)); } || { checks+=("DASHBOARD_FAIL"); ((fail++)); }
}

check_usb; check_ssh; check_dashboard

if [ "$JSON_MODE" = true ]; then
  check_json=$(printf '%s\n' "${checks[@]}" | sed -n 's/^/"/;s/$/"/p' | paste -sd, -)
  printf '{"status":"%s","pass":%d,"fail":%d,"checks":[%s]}\n' "$([ $fail -eq 0 ] && echo ok || echo degraded)" $pass $fail "$check_json"
else
  printf 'Health Check: %d pass, %d fail\n' $pass $fail
  for c in "${checks[@]}"; do
    [[ "$c" == *"FAIL" ]] && printf '  %bx%b %s\n' "$RED" "$NC" "$c" || printf '  %bo%b %s\n' "$GREEN" "$NC" "$c"
  done
fi

exit $fail
