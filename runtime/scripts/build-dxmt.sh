#!/usr/bin/env bash
# Builds DXMT (D3D10/11 -> Metal).
# STEP: clone github.com/3Shain/dxmt at the pinned revision into runtime/src/dxmt
# STEP: build against the Wine tree from build-wine.sh (meson, per DXMT's README)
# STEP: install PE DLLs to runtime/build/backends/dxmt/{x86_64,i386}/
# STEP: install winemetal.so into the Wine x86_64-unix lib dir
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
