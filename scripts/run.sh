#!/usr/bin/env bash
#
# Builds Magnifier.app, restarts the running instance and launches it.
#
#   ./scripts/run.sh              # Debug build
#   ./scripts/run.sh --release    # Release build
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="Debug"
for arg in "$@"; do
  case "$arg" in
    --release) CONFIGURATION="Release" ;;
  esac
done

./scripts/build.sh "$@"

APP="build/Build/Products/$CONFIGURATION/Magnifier.app"
pkill -f "Magnifier.app/Contents/MacOS/Magnifier" >/dev/null 2>&1 || true
sleep 0.5
open "$APP"
echo "Launched: $APP"
