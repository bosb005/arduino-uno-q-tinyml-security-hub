#!/usr/bin/env bash
# bridge-test.sh — isolate the MCU ↔ app bridge with the audio-test pair
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

exec "$PROJECT_ROOT/deploy.sh" bridge-test
