#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(dirname "$HERE")"
python3 "$HERE/check_patch_anchors.py"
python3 "$HERE/static_verify.py"
BIN="$(mktemp -d)/hud_auto_policy"
swiftc -parse-as-library "$PKG/ios/HUDController/App/HUDMapModeAutoRejoinPolicy.swift" "$HERE/check_policy.swift" -o "$BIN"
"$BIN"
echo "All available source package checks passed. iOS xcodebuild still required on macOS."
