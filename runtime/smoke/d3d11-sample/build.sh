#!/usr/bin/env bash
# Cross-compiles the D3D11 smoke test to an x86_64 Windows PE with mingw-w64.
# Requires: brew install mingw-w64
# Usage: build.sh [output-dir]   (default: runtime/build/smoke)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/../../build/smoke}"
cc="${CC:-x86_64-w64-mingw32-gcc}"
command -v "$cc" >/dev/null || { echo "error: $cc not found (brew install mingw-w64)" >&2; exit 1; }

mkdir -p "$out"
"$cc" -O2 -Wall -o "$out/d3d11-sample.exe" "$here/main.c" -ld3d11 -ldxgi -luuid -lgdi32 -luser32
echo "built $out/d3d11-sample.exe"
