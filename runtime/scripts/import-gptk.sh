#!/usr/bin/env bash
# Imports Apple's D3DMetal from the user's own Game Porting Toolkit download.
# Tether never redistributes D3DMetal; this only copies from a GPTK the user obtained from Apple.
# STEP: take a path to the mounted GPTK .dmg (or the extracted 'redist' folder)
# STEP: locate D3DMetal.framework and the wine x86_64-windows d3d11/d3d12/dxgi builtin DLLs
# STEP: copy into $TETHER_HOME/UserComponents/d3dmetal/ in the layout D3DMetalBackend expects
# STEP: record the GPTK version for `tether doctor`
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
