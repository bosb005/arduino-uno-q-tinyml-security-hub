#!/usr/bin/env bash
# ei_workflow.sh — Automate Edge Impulse project setup, training, and export.
#
# Usage:
#   1. Create account at https://edgeimpulse.com
#   2. Copy your API key: Dashboard → your username (top-right) → API keys
#   3. Run:  bash scripts/ei_workflow.sh --api-key ei_... [--step <STEP>]
#
# Steps (run in order):
#   setup      — verify CLI, validate API key
#   data       — start edge-impulse-daemon for live audio recording (interactive)
#   configure  — create project + set MFCC impulse + NN architecture via REST API
#   train      — generate features, then trigger training job via REST API
#   export     — download Arduino library ZIP via REST API
#   all        — setup → configure → train → export  (run 'data' separately first)

set -euo pipefail

EI_BASE="https://studio.edgeimpulse.com/v1/api"
PROJECT_NAME="security-hub-acoustic"
EXPORT_DIR="03_ai_model"
FIRMWARE_DIR="04_firmware_inference"
ZIP_NAME="security-hub-acoustic_inferencing.zip"

API_KEY=""
STEP="all"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-load ei.env from repo root if present
if [[ -f "$REPO_ROOT/ei.env" ]]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/ei.env"
  [[ -n "${EI_API_KEY:-}" ]] && API_KEY="$EI_API_KEY"
fi

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
  # Use project ID from ei.env if available
  if [[ -n "${EI_PROJECT_ID:-}" ]]; then
    PROJECT_ID="$EI_PROJECT_ID"
    echo "✓ Using project ID from ei.env: $PROJECT_ID"
    export PROJECT_ID
    return
  fi

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

# Configure the impulse design (MFCC + NN blocks) using model_config.json values.
# This replaces all manual impulse setup in the Edge Impulse dashboard.
step_configure() {
  echo "── Configure Impulse ────────────────────────────────────"
  step_get_project_id

  # Set the full impulse: Audio input → MFCC DSP → Classification NN
  # Parameters match 03_ai_model/model_config.json exactly.
  echo "Setting impulse design (MFCC + Dense NN)..."
  IMPULSE_PAYLOAD='{
    "inputBlocks": [{
      "id": 1, "type": "time-series", "name": "Audio input", "title": "Time series",
      "windowSizeMs": 1000, "windowIncreaseMs": 500,
      "frequencyHz": 16000, "padZeros": true
    }],
    "dspBlocks": [{
      "id": 2, "type": "mfcc", "name": "MFCC", "title": "Audio (MFCC)",
      "axes": ["audio"], "input": 1, "implementationVersion": 4
    }],
    "learnBlocks": [{
      "id": 3, "type": "keras", "name": "NN Classifier", "title": "Classification",
      "dsp": [2]
    }],
    "postProcessingBlocks": []
  }'
  RESULT=$(ei_post "/$PROJECT_ID/impulse" "$IMPULSE_PAYLOAD")
  echo "$RESULT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('  WARN: impulse set failed (may need manual setup in dashboard):', d.get('error',''))
else:
    print('✓ Impulse design configured')
"

  # Configure MFCC DSP block parameters
  echo "Configuring MFCC parameters..."
  MFCC_PAYLOAD='{
    "config": {
      "frame_length": 0.025,
      "frame_stride": 0.010,
      "num_cepstral": 13,
      "fft_length": 512,
      "low_frequency": 300,
      "high_frequency": 8000,
      "noise_floor_db": -52,
      "win_size": 101
    }
  }'
  RESULT=$(ei_post "/$PROJECT_ID/dsp/2/config" "$MFCC_PAYLOAD")
  echo "$RESULT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('  WARN: MFCC config failed (may need manual config in dashboard):', d.get('error',''))
else:
    print('✓ MFCC parameters set')
"
  echo ""
  echo "Note: NN architecture (Dense 64→32, dropout 0.25) is set during training."
  echo "If impulse/MFCC config calls failed, configure manually in the EI dashboard"
  echo "using 03_ai_model/EDGE_IMPULSE_SETUP.md as reference."
}

step_train() {
  echo "── Training ─────────────────────────────────────────────"
  step_get_project_id

  # Step 1: generate DSP features (block ID 2)
  echo "Generating DSP features (MFCC)..."
  GEN=$(ei_post "/$PROJECT_ID/jobs/generate-features" '{"dspId":2}')
  GEN_JOB=$(echo "$GEN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('id', ''))
" 2>/dev/null || echo "")

  if [[ -n "$GEN_JOB" ]]; then
    echo "  Waiting for feature generation (job $GEN_JOB)..."
    _wait_for_job "$GEN_JOB"
  fi

  # Step 2: train the keras learn block (ID 3)
  echo "Triggering training job for project $PROJECT_ID..."
  TRAIN=$(curl -fsSL -X POST \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"mode":"visual","trainingCycles":100,"learningRate":0.0005,"batchSize":32,"profileInt8":true}' \
    "$EI_BASE/$PROJECT_ID/jobs/train/keras/3")
  JOB_ID=$(echo "$TRAIN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('ERROR:', d.get('error','unknown'), file=sys.stderr)
    sys.exit(1)
print(d.get('id', ''))
")
  echo "✓ Training job started: $JOB_ID"
  echo ""
  echo "Polling job status (may take 5-15 minutes)..."
  _wait_for_job "$JOB_ID"
  echo "✓ Training complete!"
}

_wait_for_job() {
  local JOB="$1"
  while true; do
    STATUS=$(ei_get "/$PROJECT_ID/jobs/$JOB" | python3 -c "
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
      if [[ "$SUCCESS" != "True" && "$SUCCESS" != "true" ]]; then
        echo "✗ Job $JOB failed. Check Edge Impulse dashboard for details."
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

  # Step 1: trigger build
  echo "Building Arduino library deployment..."
  BUILD=$(curl -fsSL -X POST \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"engine":"tflite-eon"}' \
    "$EI_BASE/$PROJECT_ID/jobs/build-ondevice-model?type=arduino&impulseId=1")
  BUILD_JOB=$(echo "$BUILD" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if not d.get('success'):
    print('ERROR:', d.get('error','unknown'), file=sys.stderr)
    sys.exit(1)
print(d.get('id',''))
")
  DEPLOYMENT_VERSION=$(echo "$BUILD" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('deploymentVersion',''))
")
  if [[ -z "$DEPLOYMENT_VERSION" ]]; then
    echo "✗ Build response did not include deploymentVersion"
    exit 1
  fi
  echo "✓ Build job started: $BUILD_JOB"
  echo "✓ Deployment version: $DEPLOYMENT_VERSION"

  # Step 2: poll until historic deployment download is ready (returns HTTP 200).
  echo "Downloading Arduino library ZIP for project $PROJECT_ID..."
  local download_url="$EI_BASE/$PROJECT_ID/deployment/history/$DEPLOYMENT_VERSION/download"
  local got_zip="no"
  for _ in $(seq 1 30); do
    code=$(curl -s -o "$EXPORT_DIR/$ZIP_NAME" -w '%{http_code}' \
      -H "x-api-key: $API_KEY" "$download_url")
    if [[ "$code" == "200" ]]; then
      got_zip="yes"
      break
    fi
    sleep 10
  done
  if [[ "$got_zip" != "yes" ]]; then
    echo "✗ Deployment artifact not ready from $download_url"
    exit 1
  fi

  # Also copy to firmware folder for reference
  cp "$EXPORT_DIR/$ZIP_NAME" "$FIRMWARE_DIR/$ZIP_NAME"

  # Print actual library name from ZIP
  LIB_NAME=$(unzip -l "$EXPORT_DIR/$ZIP_NAME" 2>/dev/null | grep "/$" | head -1 | awk '{print $NF}' | tr -d '/')
  EI_HEADER=$(unzip -l "$EXPORT_DIR/$ZIP_NAME" 2>/dev/null | awk '{print $NF}' | grep -E '_inferencing\.h$' | head -1 || true)
  if [[ -z "$EI_HEADER" ]]; then
    echo "✗ Exported ZIP does not contain *_inferencing.h (got placeholder package)."
    exit 1
  fi
  echo "✓ Saved to $EXPORT_DIR/$ZIP_NAME"
  echo "✓ Copied to $FIRMWARE_DIR/$ZIP_NAME"
  echo "✓ Inference header: $(basename "$EI_HEADER")"
  echo ""
  echo "Library name inside ZIP: $LIB_NAME"
  echo ""
  echo "Next steps:"
  echo "  1. In Arduino IDE: Sketch → Include Library → Add .ZIP Library"
  echo "     Select: $EXPORT_DIR/$ZIP_NAME"
  echo "  2. Open app/sketch/sketch.ino — the EI integration is already in place."
  echo "  3. Compile and upload to Arduino UNO Q."
}

# ── Main ──────────────────────────────────────────────────────────────────
case "$STEP" in
  setup)     step_setup ;;
  data)      step_setup; step_data ;;
  configure) step_setup; step_configure ;;
  train)     step_setup; step_train ;;
  export)    step_setup; step_export ;;
  all)       step_setup; step_configure; step_train; step_export ;;
  *)
    echo "Unknown step: $STEP. Choose: setup|data|configure|train|export|all"
    exit 1
    ;;
esac
