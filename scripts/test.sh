#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools (no Xcode), SwiftPM doesn't add
# the CLT's Testing.framework to the search paths, so we pass them explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  F="$DEV_DIR/Library/Developer/Frameworks"
  L="$DEV_DIR/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F -Xswiftc "$F" \
    -Xlinker -F -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$L" "$@"
else
  exec swift test "$@"
fi
