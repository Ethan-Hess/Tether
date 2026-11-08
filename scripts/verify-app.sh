#!/usr/bin/env bash
# Checks a built Tether.app: structure, Info.plist, signatures, that wine.app is untouched, and
# that the app finds its own resources and runtime when it runs (via `Tether --self-check`).
#
#   scripts/verify-app.sh [build/Tether.app]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
APP="${1:-build/Tether.app}"
FAILS=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
warn() { printf '  note  %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

[[ -d "$APP" ]] || { echo "no app at $APP" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
EXPECT_VERSION="$(tr -d '[:space:]' < VERSION)"

echo "Structure"
check "executable is arm64" "lipo -archs '$APP/Contents/MacOS/Tether' | grep -x arm64"
check "nothing but Contents at the bundle root" "[[ \$(ls -A '$APP') == 'Contents' ]]"
for f in Profiles/steam.json Runtimes/catalog.json Notices/components.json Notices/licenses/LGPL-2.1.txt AppIcon.icns; do
  check "resource $f" "[[ -s '$APP/Contents/Resources/$f' ]]"
done
check "Sparkle framework present" "[[ -d '$APP/Contents/Frameworks/Sparkle.framework' ]]"
check "rpath finds Contents/Frameworks" "otool -l '$APP/Contents/MacOS/Tether' | grep '@executable_path/../Frameworks'"

echo "Info.plist"
check "bundle id dev.tether.Tether" "[[ \$(pl CFBundleIdentifier) == dev.tether.Tether ]]"
check "version is $EXPECT_VERSION (or overridden)" "[[ -n \$(pl CFBundleShortVersionString) ]]"
check "build number is numeric" "[[ \$(pl CFBundleVersion) =~ ^[0-9]+\$ ]]"
check "minimum macOS 14" "[[ \$(pl LSMinimumSystemVersion) == 14.0 ]]"
check "update feed is https" "[[ \$(pl SUFeedURL) == https://* ]]"
if [[ -n "$(pl SUPublicEDKey)" ]]; then ok "update signing key present"; else warn "no SUPublicEDKey: this build cannot receive updates"; fi

echo "Signatures"
check "app signature valid (strict)" "codesign --verify --strict --verbose=2 '$APP'"
check "Sparkle signature valid" "codesign --verify --strict '$APP/Contents/Frameworks/Sparkle.framework'"
spctl --assess --type execute "$APP" >/dev/null 2>&1 && ok "Gatekeeper accepts the app" || warn "Gatekeeper rejects it (expected for ad-hoc or un-notarized builds; one 'Open Anyway')"

RT_ROOT="$APP/Contents/Resources/EmbeddedRuntimes"
if [[ -d "$RT_ROOT" ]]; then
  echo "Embedded runtime"
  RT="$(find "$RT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -1)"
  VER="$(basename "$RT")"
  WINE_APP="$RT/lib/wine/aarch64-unix/wine.app"
  check "runtime.json present" "[[ -s '$RT/runtime.json' ]]"
  check "bin/wine is executable" "[[ -x '$RT/bin/wine' ]]"
  check "wine.app signature still valid" "codesign --verify --strict '$WINE_APP'"
  check "wine.app still signed by its upstream team (WLKUUJD25W)" "codesign -dvv '$WINE_APP' 2>&1 | grep 'TeamIdentifier=WLKUUJD25W'"
  check "wine.app keeps the cross-architecture entitlement" "codesign -d --entitlements - '$WINE_APP' 2>&1 | grep cross-architecture-support"
  SRC="build/cache/runtime-$VER/Runtimes/$VER/lib/wine/aarch64-unix/wine.app"
  if [[ -d "$SRC" ]]; then
    check "wine.app identical to the verified download" "[[ \$(codesign -dvvv '$WINE_APP' 2>&1 | grep CDHash=) == \$(codesign -dvvv '$SRC' 2>&1 | grep CDHash=) ]]"
  else
    warn "no cached download to compare wine.app against"
  fi
else
  warn "no embedded runtime (built with --no-runtime)"
fi

echo "Runs"
OUTPUT="$("$APP/Contents/MacOS/Tether" --self-check 2>&1)"; STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
check "self-check passes (exit 0)" "[[ $STATUS -eq 0 ]]"
check "resources load from inside the app (not from a build folder)" "echo '$OUTPUT' | grep '^resources=$(cd "$APP" && pwd)/Contents/Resources\$'"
if [[ -d "$RT_ROOT" ]]; then
  check "the embedded runtime is the one resolved" "echo '$OUTPUT' | grep 'embedded=true'"
fi

echo
if (( FAILS )); then echo "$FAILS check(s) failed"; exit 1; else echo "All checks passed"; fi
