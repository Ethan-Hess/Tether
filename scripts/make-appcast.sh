#!/usr/bin/env bash
# Writes the signed Sparkle appcast (and binary deltas from earlier versions) for the DMGs in a folder.
#
#   scripts/make-appcast.sh <release-dir> <version>
#
# <release-dir> must hold Tether-<version>.dmg. Earlier DMGs and the previous appcast.xml, if present,
# are used to build deltas and keep older entries. Needs `swift build` (or `swift package resolve`)
# to have fetched Sparkle's tools first.
#
# APPCAST_URL_PREFIX overrides where the DMG and deltas are said to live (for testing against a local server).
#
# The signing key comes from SPARKLE_ED_KEY (the private key text, for example a CI secret). It is
# handed to Sparkle on stdin and never written to disk. Without it the login keychain is used.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="${1:?usage: scripts/make-appcast.sh <release-dir> <version>}"
VERSION="${2:?usage: scripts/make-appcast.sh <release-dir> <version>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 64; }

REPO="${GITHUB_REPOSITORY:-Ethan-Hess/Tether}"
TOOL=.build/artifacts/sparkle/Sparkle/bin/generate_appcast
[[ -x "$TOOL" ]] || { echo "Sparkle's tools are missing; run 'swift package resolve' first" >&2; exit 1; }
[[ -f "$DIR/Tether-$VERSION.dmg" ]] || { echo "$DIR/Tether-$VERSION.dmg not found" >&2; exit 1; }

PREFIX="${APPCAST_URL_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"
ARGS=(--download-url-prefix "$PREFIX")
if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_ED_KEY" | "$TOOL" --ed-key-file - "${ARGS[@]}" "$DIR"
else
  "$TOOL" "${ARGS[@]}" "$DIR"
fi

# A feed without a signature for this release would be rejected by every installed copy.
[[ -s "$DIR/appcast.xml" ]] || { echo "no appcast.xml was written" >&2; exit 1; }
python3 - "$DIR/appcast.xml" "$VERSION" <<'PY'
import sys, xml.etree.ElementTree as ET
path, version = sys.argv[1:]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
for item in ET.parse(path).getroot().iter("item"):
    if item.findtext("sparkle:shortVersionString", namespaces=ns) == version:
        enc = item.find("enclosure")
        sig = enc.get("{%s}edSignature" % ns["sparkle"]) if enc is not None else None
        if not sig:
            sys.exit(f"appcast entry for {version} has no edSignature")
        print(f"appcast ok: {version} is signed")
        break
else:
    sys.exit(f"appcast has no entry for {version}")
PY
