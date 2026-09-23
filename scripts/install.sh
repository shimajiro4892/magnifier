#!/usr/bin/env bash
#
# Builds the release version, installs it into /Applications and launches it.
#
#   ./scripts/install.sh
#
# Use this instead of run.sh once the app lives in /Applications, otherwise two
# copies would fight over the global shortcut.
#
set -euo pipefail

cd "$(dirname "$0")/.."

DEST="/Applications/Magnifier.app"

./scripts/build.sh --release

SOURCE="build/Build/Products/Release/Magnifier.app"

pkill -f "Magnifier.app/Contents/MacOS/Magnifier" >/dev/null 2>&1 || true
sleep 0.5

rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

open "$DEST"
echo "Installed: $DEST"
