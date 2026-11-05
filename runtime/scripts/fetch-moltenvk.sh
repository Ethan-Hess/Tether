#!/usr/bin/env bash
# Fetches a pinned MoltenVK release.
# STEP: download the pinned MoltenVK release archive from GitHub
# STEP: verify its SHA-256 against the pinned checksum in this script
# STEP: copy the macOS libMoltenVK.dylib (x86_64 slice) to runtime/build/lib/
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
