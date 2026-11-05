#!/usr/bin/env bash
# Builds DXVK PE DLLs (D3D9-11 -> Vulkan; MoltenVK provides Vulkan on Metal).
# STEP: clone github.com/doitsujin/dxvk at the pinned tag (or a macOS-compatible fork)
# STEP: meson cross-compile with build-win64.txt and build-win32.txt (mingw-w64)
# STEP: install d3d9/d3d10core/d3d11/dxgi.dll to runtime/build/backends/dxvk/{x86_64,i386}/
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
