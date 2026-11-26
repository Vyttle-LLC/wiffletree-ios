#!/usr/bin/env bash
#
# Blessed XcodeGen wrapper. Always regenerate Wiffletree.xcodeproj through this
# so the committed project stays in sync with project.yml.
#
# Gotcha it guards: on Nix-symlinked installs, invoking xcodegen via the PATH
# symlink makes it miss its bundled SettingPresets and silently strip build
# settings from the generated project. Resolving the real binary path avoids
# that. On CI (the pinned 2.44.1 release zip) the resolve is a no-op.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found on PATH. Install XcodeGen 2.44.1 (see README.md)." >&2
    exit 1
fi

xcodegen_bin="$(command -v xcodegen)"
resolved="$(readlink -f "$xcodegen_bin" 2>/dev/null || echo "$xcodegen_bin")"

echo "Generating Wiffletree.xcodeproj with $resolved"
"$resolved" generate "$@"
