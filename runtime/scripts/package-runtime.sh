#!/usr/bin/env bash
# Assembles runtime/build into a versioned runtime directory and writes runtime.json.
# STEP: lay out bin/, lib/, backends/ per runtime/README.md
# STEP: write runtime.json (version, wineVersion, features, components)
# STEP: ad-hoc codesign Mach-O binaries
# STEP: produce runtime/dist/tether-runtime-<version>.tar.xz + .sha256
# STEP: optionally install into $TETHER_HOME/Runtimes/<version>
set -euo pipefail
source "$(dirname "$0")/_stub.sh"; stub
