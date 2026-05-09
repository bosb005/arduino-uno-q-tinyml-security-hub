#!/usr/bin/env bash
# cycle.sh — simple app-centric deploy/test entrypoint
#
# Runs the full change -> deploy -> test loop by delegating to deploy.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

exec "$PROJECT_ROOT/deploy.sh" cycle
