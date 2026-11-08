#!/usr/bin/env bash
# Packs Tether.app into a compressed disk image with an Applications shortcut.
#
#   scripts/make-dmg.sh [build/Tether.app] [build/Tether-X.Y.Z.dmg]
#
# LZMA compression (ULMO) matters here: the embedded runtime shrinks about 8x.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Tether.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="${2:-build/Tether-$VERSION.dmg}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tether-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Tether.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Tether $VERSION" -srcfolder "$STAGE" -format ULMO -fs APFS -ov "$DMG" >/dev/null
echo "Wrote $DMG ($(du -sh "$DMG" | cut -f1))"
