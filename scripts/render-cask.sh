#!/usr/bin/env bash
# Prints the Homebrew cask for a release, from Packaging/homebrew/tether.rb.in.
#
#   scripts/render-cask.sh <version> <sha256-of-the-dmg> > Casks/tether.rb
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/render-cask.sh <version> <sha256>}"
SHA256="${2:?usage: scripts/render-cask.sh <version> <sha256>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 64; }
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "sha256 must be 64 lowercase hex characters" >&2; exit 64; }

sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA256/" Packaging/homebrew/tether.rb.in
