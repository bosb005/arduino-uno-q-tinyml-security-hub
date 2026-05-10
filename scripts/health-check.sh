#!/bin/bash
# Health check script — Quick system connectivity validation
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ENV="$PROJECT_ROOT/deploy.env"

JSON_MODE=false
REQUIRE_BRIDGE_FRESH=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_MODE=true ;;
    --require-bridge-fresh) REQUIRE_BRIDGE_FRESH=true ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

[ -f "$DEPLOY_ENV" ] || { printf '{"status":"error","error":"deploy.env missing"}\n'; exit 1; }

source "$DEPLOY_ENV"
DEVICE_USER="${DEVICE_USER:-root}"
pass=0; fail=0; checks=()
health_json=""

record_ok() { checks+=("$1"); ((pass+=1)); }
record_fail() { checks+=("$1"); ((fail+=1)); }

check_usb() {
  ls /dev/cu.usbmodem* >/dev/null 2>&1 && record_ok "USB_OK" || record_fail "USB_FAIL"
}

check_ssh() {
  ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_KEY:+-i "$SSH_KEY"} "${DEVICE_USER}@${DEVICE_IP}" "echo ok" >/dev/null 2>&1 \
    && record_ok "SSH_OK" || record_fail "SSH_FAIL"
}

check_dashboard() {
  health_json=$(ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_KEY:+-i "$SSH_KEY"} "${DEVICE_USER}@${DEVICE_IP}" \
    "curl -sf 'http://localhost:7000/health'" 2>/dev/null || true)
  if [ -z "$health_json" ]; then
    record_fail "DASHBOARD_FAIL(unreachable)"
    return
  fi

  if printf '%s' "$health_json" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('dashboard',{}).get('healthy') is True else 1)"; then
    record_ok "DASHBOARD_OK"
  else
    record_fail "DASHBOARD_FAIL(unhealthy)"
  fi
}

check_bridge_fresh() {
  [ -n "$health_json" ] || { record_fail "BRIDGE_FAIL(no_health_payload)"; return; }
  local bridge_diag
  if bridge_diag=$(printf '%s' "$health_json" | python3 -c "import json,sys
d=json.load(sys.stdin)
b=d.get('bridge',{}) or {}
if d.get('mock', False):
  print('MOCK')
  sys.exit(0)
alive=bool(b.get('alive', False))
state=b.get('state') or 'unknown'
age=b.get('last_event_age_ms')
stale_after=b.get('stale_after_ms')
provider=bool(b.get('provider_registered', False))
err=b.get('provider_registration_error')
failure=b.get('failure_point')
age_s='unknown' if age is None else str(age)
stale_s='unknown' if stale_after is None else str(stale_after)
if alive:
  print(f'OK(age_ms={age_s},stale_after_ms={stale_s})')
  sys.exit(0)
msg=f'FAIL(state={state},age_ms={age_s},stale_after_ms={stale_s},provider_registered={str(provider).lower()}'
if err: msg += f',provider_error={err}'
if failure: msg += f',failure_point={failure}'
msg += ')'
print(msg)
sys.exit(1)"); then
    [ "$bridge_diag" = "MOCK" ] && record_ok "BRIDGE_OK(mock_mode)" || record_ok "BRIDGE_OK(${bridge_diag#OK(}"
  else
    record_fail "BRIDGE_FAIL(${bridge_diag#FAIL(}"
  fi
}

check_usb
check_ssh
check_dashboard
[ "$REQUIRE_BRIDGE_FRESH" = true ] && check_bridge_fresh

if [ "$JSON_MODE" = true ]; then
  check_json=$(printf '%s\n' "${checks[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  printf '{"status":"%s","pass":%d,"fail":%d,"require_bridge_fresh":%s,"checks":%s}\n' \
    "$([ $fail -eq 0 ] && echo ok || echo degraded)" "$pass" "$fail" "$REQUIRE_BRIDGE_FRESH" "$check_json"
else
  printf 'Health Check: %d pass, %d fail\n' "$pass" "$fail"
  for c in "${checks[@]}"; do
    [[ "$c" == *"FAIL"* ]] && printf '  %bx%b %s\n' "$RED" "$NC" "$c" || printf '  %bo%b %s\n' "$GREEN" "$NC" "$c"
  done
fi

exit "$fail"
