#!/usr/bin/env bash
# Builds Wine for macOS (x86_64 host binaries under Rosetta, wow64 for 32-bit PE).
# STEP: clone upstream wine at the pinned tag into runtime/src/wine
# STEP: apply patches listed in runtime/patches/wine/series, in order; fail if any lacks a Tether-Origin header
# STEP: configure under `arch -x86_64` with --enable-archs=i386,x86_64 --without-x --without-wayland --disable-tests (Linux audio/video backends off)
# STEP: make -j && make install DESTDIR=runtime/build/wine
# STEP: record version + applied patches for runtime.json
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
