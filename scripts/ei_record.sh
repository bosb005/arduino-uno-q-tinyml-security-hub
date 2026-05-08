#!/usr/bin/env bash
# ei_record.sh — Record one audio sample per class and upload to Edge Impulse.
#
# Records from the MacBook Air built-in microphone (avfoundation device 0).
# Uses ffmpeg to capture 1-second 16kHz mono WAV files, then uploads each
# to the training set via edge-impulse-uploader.
#
# Usage:
#   bash scripts/ei_record.sh
#   (reads API key + project ID from ei.env automatically)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load credentials
if [[ -f "$REPO_ROOT/ei.env" ]]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/ei.env"
fi

API_KEY="${EI_API_KEY:-}"
PROJECT_ID="${EI_PROJECT_ID:-}"

if [[ -z "$API_KEY" ]]; then
  echo "Error: EI_API_KEY not set. Add it to ei.env or export it."
  exit 1
fi

CLASSES=("idle" "presence" "anomaly" "manual_trigger")
SAMPLE_DIR="$REPO_ROOT/03_ai_model/samples"
DURATION=1          # seconds per sample
SAMPLE_RATE=16000   # Hz
MIC_DEVICE=":0"     # avfoundation device 0 = MacBook Air mic

mkdir -p "$SAMPLE_DIR"

echo "──────────────────────────────────────────────"
echo "  Edge Impulse — Record training samples"
echo "  1 second per class | 16 kHz mono | 4 classes"
echo "──────────────────────────────────────────────"
echo ""

for CLASS in "${CLASSES[@]}"; do
  WAV="$SAMPLE_DIR/${CLASS}_001.wav"

  echo "Class: $CLASS"
  case "$CLASS" in
    idle)           echo "  → Sit quietly (room background noise)" ;;
    presence)       echo "  → Walk past mic or speak softly" ;;
    anomaly)        echo "  → Clap once loudly or knock hard on desk" ;;
    manual_trigger) echo "  → Clap exactly 3 times in 1 second" ;;
  esac

  read -r -p "  Press Enter to start recording (Ctrl-C to abort)..."
  echo "  🎤 Recording for ${DURATION}s..."

  ffmpeg -y -loglevel error \
    -f avfoundation -i "$MIC_DEVICE" \
    -t "$DURATION" \
    -ar "$SAMPLE_RATE" -ac 1 -sample_fmt s16 \
    "$WAV"

  echo "  ✓ Saved: $WAV"

  echo "  ↑ Uploading to Edge Impulse (project $PROJECT_ID, label=$CLASS)..."
  edge-impulse-uploader --api-key "$API_KEY" --label "$CLASS" --category training --silent "$WAV"
  echo "  ✓ Uploaded"
  echo ""
done

echo "──────────────────────────────────────────────"
echo "✅  All 4 samples recorded and uploaded."
echo ""
echo "Next: configure impulse + train"
echo "  bash scripts/ei_workflow.sh --step all"
echo "──────────────────────────────────────────────"
