#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/magnifier-lifecycle.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

# A single compilation unit permits test-only extensions to access private
# state, without changing visibility in the app or requesting screen recording.
cat Magnifier/Overlay/*.swift \
    Magnifier/Capture/ScreenCaptureEngine.swift \
    Magnifier/Input/*.swift \
    Magnifier/Support/*.swift \
    Magnifier/Settings/SettingsStore.swift \
    Magnifier/Permissions/PermissionMonitor.swift \
    Tools/verify-lifecycle.swift > "$TEST_DIR/Lifecycle.swift"
swiftc -parse-as-library -module-cache-path "$TEST_DIR/ModuleCache" \
    "$TEST_DIR/Lifecycle.swift" -o "$TEST_DIR/verify-lifecycle"
"$TEST_DIR/verify-lifecycle"
