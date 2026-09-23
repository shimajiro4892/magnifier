#!/usr/bin/env bash
#
# Builds Magnifier.app.
#
#   ./scripts/build.sh              # Debug build
#   ./scripts/build.sh --release    # Release build
#
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="Debug"
for arg in "$@"; do
  case "$arg" in
    --release) CONFIGURATION="Release" ;;
    -h|--help)
      echo "usage: $0 [--release]"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

# Sign with an "Apple Development" certificate when one is available so the
# screen recording permission survives rebuilds. Falls back to ad-hoc signing.
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ {print $2; exit}')}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "note: no Apple Development certificate found, using ad-hoc signing" >&2
fi

xcodebuild -quiet \
  -project Magnifier.xcodeproj \
  -scheme Magnifier \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  build

APP="build/Build/Products/$CONFIGURATION/Magnifier.app"
echo "Built: $APP"
