#!/usr/bin/env bash
# ei_workflow.sh — Automate Edge Impulse project setup, training, and export.
#
# Usage:
#   1. Create account at https://edgeimpulse.com
#   2. Copy your API key: Dashboard → your username (top-right) → API keys
#   3. Run:  bash scripts/ei_workflow.sh --api-key ei_... [--step all|train|export]
#
# Steps:
#   setup   — verify CLI, login check
#   data    — start edge-impulse-daemon for live audio recording (interactive)
#   train   — trigger training job via REST API (non-interactive)
#   export  — download Arduino library ZIP via REST API (non-interactive)
#   all     — run setup → train → export (skips data collection; run that separately)

set -euo pipefail

EI_BASE="https://studio.edgeimpulse.com/v1/api"
PROJECT_NAME="security-hub-acoustic"
EXPORT_DIR="03_ai_model"
FIRMWARE_DIR="04_firmware_inference"
ZIP_NAME="security-hub-acoustic_inferencing.zip"

API_KEY=""
STEP="all"

# ── Parse args ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key) API_KEY="$2"; shift 2 ;;
    --step)    STEP="$2";    shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$API_KEY" ]]; then
  echo "Error: --api-key is required."
  echo "Get it at: https://studio.edgeimpulse.com → username (top-right) → API keys"
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────
ei_get()  { curl -fsSL -H "x-api-key: $API_KEY" "$EI_BASE$1"; }
ei_post() { curl -fsSL -X POST -H "x-api-key: $API_KEY" -H "Content-Type: application/json" -d "$2" "$EI_BASE$1"; }

step_setup() {
  echo "── Setup ────────────────────────────────────────────────"
  # Verify CLI
  if ! command -v edge-impulse-uploader &>/dev/null; then
    echo "Installing edge-impulse-cli..."
    npm install -g edge-impulse-cli
  fi
  echo "✓ edge-impulse-cli $(edge-impulse-uploader --version 2>/dev/null || echo 'installed')"

  # Verify API key works
  echo "Checking API key..."
  PROJECTS=$(ei_get "/projects")
  echo "$PROJECTS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('ERROR: API key rejected:', d.get('error','unknown'))
    sys.exit(1)
projects=[p['name'] for p in d.get('projects',[])]
print(f'✓ API key valid. Projects: {projects}')
"
}

step_get_project_id() {
  PROJECTS_JSON=$(ei_get "/projects")
  PROJECT_ID=$(echo "$PROJECTS_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('projects',[]):
    if p['name'] == '$PROJECT_NAME':
        print(p['id'])
        sys.exit(0)
print('')
")

  if [[ -z "$PROJECT_ID" ]]; then
    echo "Project '$PROJECT_NAME' not found. Creating..."
    CREATE=$(ei_post "/projects" "{\"name\":\"$PROJECT_NAME\"}")
    PROJECT_ID=$(echo "$CREATE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('ERROR:', d.get('error','unknown'), file=sys.stderr)
    sys.exit(1)
print(d['id'])
")
    echo "✓ Created project ID: $PROJECT_ID"
  else
    echo "✓ Found existing project ID: $PROJECT_ID"
  fi

  export PROJECT_ID
}

step_data() {
  echo "── Data Collection ──────────────────────────────────────"
  echo "This step is interactive. The daemon will prompt you to:"
  echo "  1. Select the '$PROJECT_NAME' project"
  echo "  2. Record samples for each class:"
  echo "     presence, anomaly, manual_trigger, idle"
  echo "  Target: 100+ samples × 4 classes, 1s clips, 16kHz mono"
  echo ""
  echo "Starting edge-impulse-daemon..."
  edge-impulse-daemon --api-key "$API_KEY"
}

step_train() {
  echo "── Training ─────────────────────────────────────────────"
  step_get_project_id

  echo "Triggering training job for project $PROJECT_ID..."
  TRAIN=$(ei_post "/$PROJECT_ID/jobs/train-impulse" '{}')
  JOB_ID=$(echo "$TRAIN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('ERROR:', d.get('error','unknown'), file=sys.stderr)
    sys.exit(1)
print(d.get('id', d.get('jobId', '')))
")
  echo "✓ Training job started: $JOB_ID"
  echo ""
  echo "Polling job status (may take 5-15 minutes)..."
  while true; do
    STATUS=$(ei_get "/$PROJECT_ID/jobs/$JOB_ID" | python3 -c "
import json,sys
d=json.load(sys.stdin)
j=d.get('job',{})
print(j.get('finished','false'), j.get('success',''), j.get('status','running'))
")
    FINISHED=$(echo "$STATUS" | awk '{print $1}')
    SUCCESS=$(echo  "$STATUS" | awk '{print $2}')
    STATE=$(echo    "$STATUS" | awk '{print $3}')
    echo "  status: $STATE"
    if [[ "$FINISHED" == "True" || "$FINISHED" == "true" ]]; then
      if [[ "$SUCCESS" == "True" || "$SUCCESS" == "true" ]]; then
        echo "✓ Training complete!"
      else
        echo "✗ Training failed. Check Edge Impulse dashboard for details."
        exit 1
      fi
      break
    fi
    sleep 30
  done
}

step_export() {
  echo "── Export ───────────────────────────────────────────────"
  step_get_project_id

  mkdir -p "$EXPORT_DIR" "$FIRMWARE_DIR"

  echo "Downloading Arduino library ZIP for project $PROJECT_ID..."
  curl -fSL \
    -H "x-api-key: $API_KEY" \
    "$EI_BASE/$PROJECT_ID/deployment/download?type=arduino" \
    -o "$EXPORT_DIR/$ZIP_NAME"

  # Also copy to firmware folder for reference
  cp "$EXPORT_DIR/$ZIP_NAME" "$FIRMWARE_DIR/$ZIP_NAME"

  echo "✓ Saved to $EXPORT_DIR/$ZIP_NAME"
  echo "✓ Copied to $FIRMWARE_DIR/$ZIP_NAME"
  echo ""
  echo "Next steps:"
  echo "  1. In Arduino IDE: Sketch → Include Library → Add .ZIP Library"
  echo "     Select: $EXPORT_DIR/$ZIP_NAME"
  echo "  2. Open app/sketch/sketch.ino — the EI integration is already in place."
  echo "  3. Compile and upload to Arduino UNO Q."
}

# ── Main ──────────────────────────────────────────────────────────────────
case "$STEP" in
  setup)  step_setup ;;
  data)   step_setup; step_data ;;
  train)  step_setup; step_train ;;
  export) step_setup; step_export ;;
  all)    step_setup; step_train; step_export ;;
  *)
    echo "Unknown step: $STEP. Choose: setup|data|train|export|all"
    exit 1
    ;;
esac
