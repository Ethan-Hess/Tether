#!/usr/bin/env bash
# Builds build/Tether.app: a release build of the app, its resources, the Sparkle updater, and
# (unless --no-runtime) the pinned Wine runtime embedded inside it. No Xcode needed.
#
#   scripts/package-app.sh [--no-runtime] [--runtime VERSION] [--version X.Y.Z] [--build N] [--out DIR]
#
# Signing: ad-hoc by default (users approve "Open Anyway" once). To sign with a real identity:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/package-app.sh
# which also signs the runtime's other Mach-O files with the hardened runtime, as notarization
# needs. wine.app is NEVER re-signed: it carries its own provisioning profile and entitlement.
# Notarizing is done by scripts/release.sh (NOTARY_PROFILE).
#
# Environment: SIGN_IDENTITY, TETHER_FEED_URL (default: the GitHub releases appcast),
# SPARKLE_PUBLIC_KEY_FILE (default Packaging/sparkle_public_key.txt; tests use a throwaway key).
set -euo pipefail
cd "$(dirname "$0")/.."

EMBED=1
OUT=build
VERSION="$(tr -d '[:space:]' < VERSION)"
RUNTIME_VERSION=""
BUILD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-runtime) EMBED=0; shift ;;
    --runtime) RUNTIME_VERSION="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
FEED_URL="${TETHER_FEED_URL:-https://github.com/Ethan-Hess/Tether/releases/latest/download/appcast.xml}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="$OUT/Tether.app"

echo "==> Building release binaries"
swift build -c release --product TetherApp
swift build -c release --product tether
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP (version $VERSION, build $BUILD)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/TetherApp" "$APP/Contents/MacOS/Tether"
# The Sparkle framework lives in Contents/Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Tether" 2>/dev/null || true
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM's resource bundle can't sit at the app's root (it breaks signing), so its contents go
# into Contents/Resources, where TetherResources looks first.
for d in Profiles Runtimes Notices; do
  ditto "$BIN/Tether_TetherKit.bundle/$d" "$APP/Contents/Resources/$d"
done

SPARKLE_SRC="$(find .build/artifacts -type d -name Sparkle.framework -path "*macos-arm64*" | head -1)"
[[ -n "$SPARKLE_SRC" ]] || { echo "Sparkle.framework not found; run 'swift build' first" >&2; exit 1; }
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

KEY_FILE="${SPARKLE_PUBLIC_KEY_FILE:-Packaging/sparkle_public_key.txt}"
SPARKLE_KEY=""
if [[ -s "$KEY_FILE" ]]; then
  SPARKLE_KEY="    <key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < "$KEY_FILE")</string>"
else
  echo "warning: $KEY_FILE is missing, so this build can't verify updates (updates are disabled in it)" >&2
fi
python3 - "$VERSION" "$BUILD" "$FEED_URL" "$SPARKLE_KEY" "$APP/Contents/Info.plist" <<'PY'
import sys
version, build, feed, key, out = sys.argv[1:]
text = open("Packaging/Info.plist.template").read()
for k, v in {"@VERSION@": version, "@BUILD@": build, "@FEED_URL@": feed, "@SPARKLE_KEY@": key}.items():
    text = text.replace(k, v)
open(out, "w").write(text)
PY
plutil -lint "$APP/Contents/Info.plist" >/dev/null

if (( EMBED )); then
  if [[ -z "$RUNTIME_VERSION" ]]; then
    RUNTIME_VERSION="$(python3 - <<'PY'
import json
r = json.load(open("Sources/TetherKit/Resources/Runtimes/catalog.json"))["runtimes"]
key = lambda v: [int(p) for p in v.split(".")]
print(max((x["version"] for x in r), key=key))
PY
)"
  fi
  CACHE="$OUT/cache/runtime-$RUNTIME_VERSION"
  if [[ ! -x "$CACHE/Runtimes/$RUNTIME_VERSION/bin/wine" ]]; then
    echo "==> Downloading and verifying runtime $RUNTIME_VERSION (pinned SHA-256)"
    rm -rf "$CACHE"; mkdir -p "$CACHE"
    TETHER_HOME="$CACHE" "$BIN/tether" runtime install "$RUNTIME_VERSION"
  else
    echo "==> Using cached runtime $RUNTIME_VERSION ($CACHE)"
  fi
  echo "==> Embedding runtime"
  mkdir -p "$APP/Contents/Resources/EmbeddedRuntimes"
  ditto "$CACHE/Runtimes/$RUNTIME_VERSION" "$APP/Contents/Resources/EmbeddedRuntimes/$RUNTIME_VERSION"
fi

echo "==> Signing ($([[ "$IDENTITY" == "-" ]] && echo "ad-hoc" || echo "$IDENTITY"))"
if [[ "$IDENTITY" == "-" ]]; then OPTS=(--timestamp=none); else OPTS=(--options runtime --timestamp); fi
sign() { codesign --force --sign "$IDENTITY" "${OPTS[@]}" "$@"; }

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for v in "$SPARKLE"/Versions/*/; do
  [[ -L "${v%/}" ]] && continue
  for x in "$v"XPCServices/*.xpc "$v"Autoupdate "$v"Updater.app; do [[ -e "$x" ]] && sign "$x"; done
done
sign "$SPARKLE"

if [[ "$IDENTITY" != "-" && -d "$APP/Contents/Resources/EmbeddedRuntimes" ]]; then
  echo "    signing the runtime's Mach-O files (not wine.app)"
  while IFS= read -r -d '' f; do
    file -b "$f" | grep -q "Mach-O" && sign "$f"
  done < <(find "$APP/Contents/Resources/EmbeddedRuntimes" -type f ! -path "*/wine.app/*" -print0)
fi

# The outer app last, without --deep, so nested signatures (wine.app especially) stay as shipped.
sign "$APP"

echo "==> Done: $APP ($(du -sh "$APP" | cut -f1))"
echo "    Check it with: scripts/verify-app.sh $APP"
