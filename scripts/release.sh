#!/usr/bin/env bash
# Builds everything for a release in build/release/: the signed app, a DMG, and the Sparkle appcast
# (EdDSA-signed, with binary deltas from earlier versions kept in that folder). It NEVER publishes:
# it prints the `gh release create` command for you to run.
#
#   scripts/release.sh 0.2.0
#
# Environment:
#   SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)". Unset = ad-hoc (users do one "Open Anyway").
#   NOTARY_PROFILE  a `xcrun notarytool store-credentials` profile; with SIGN_IDENTITY, the app and DMG
#                   are notarized and stapled.
# The same pieces run in CI (.github/workflows/release.yml); this script is the local way to do it.
# One-time: Packaging/sparkle_public_key.txt must hold the public key of the update signing key
# in your keychain (see docs/RELEASING.md). Keep old DMGs in build/release/ so deltas can be made.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh X.Y.Z}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 64; }
[[ -s Packaging/sparkle_public_key.txt ]] || { echo "Packaging/sparkle_public_key.txt is missing; see docs/RELEASING.md" >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then echo "warning: the working tree has uncommitted changes" >&2; fi

REL=build/release
mkdir -p "$REL"
DMG="$REL/Tether-$VERSION.dmg"

echo "==> Building and signing Tether.app $VERSION"
scripts/package-app.sh --version "$VERSION"
scripts/verify-app.sh build/Tether.app

notarize() { # path
  [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]] || return 0
  echo "==> Notarizing $1"
  local target="$1"
  if [[ -d "$1" ]]; then target="build/notarize.zip"; ditto -c -k --keepParent "$1" "$target"; fi
  xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$1"
  [[ -d "$1" ]] && rm -f "$target"
  return 0
}
notarize build/Tether.app

echo "==> Making the disk image"
scripts/make-dmg.sh build/Tether.app "$DMG"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"; fi
notarize "$DMG"

echo "==> Writing the appcast"
scripts/make-appcast.sh "$REL" "$VERSION"

cat <<MSG

Built in $REL:
$(find "$REL" -maxdepth 1 -type f -exec basename {} \; | sort | sed 's/^/  /')

Check the DMG on a clean Mac account if you can. When you are happy, publish with:

  gh release create v$VERSION \\
    "$DMG" "$REL/appcast.xml" $(ls "$REL"/*.delta 2>/dev/null | sed 's/^/"/;s/$/"/' | tr '\n' ' ')\\
    --title "Tether $VERSION" --notes-file RELEASE_NOTES.md

(Upload the delta files too, if any. The app looks for updates at the appcast of the latest release.)
MSG
