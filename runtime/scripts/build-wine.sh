#!/usr/bin/env bash
# Builds Wine for macOS: x86_64 host binaries (run under Rosetta 2), wow64 for 32-bit PE.
#
#   build-wine.sh                 fetch, patch, configure, build, install
#   build-wine.sh --prepare-only  fetch and apply the patch queue only (used to check patches in CI)
#
# Output:
#   runtime/src/wine              upstream checkout with the patch queue applied
#   runtime/build/wine            install tree (bin/wine, lib/wine/...)
#   runtime/build/wine-build.json version, commit, features, and applied patches (read by package-runtime.sh)
#
# Environment overrides:
#   WINE_TAG   upstream tag to build (default below; bump it as part of a rebase, see patches/wine/README.md)
#   WINE_REPO  upstream git URL
#   JOBS       parallel make jobs
#   X86_PREFIX Homebrew prefix for x86_64 dependencies (default /usr/local)
set -euo pipefail

WINE_TAG="${WINE_TAG:-wine-10.0}"
WINE_REPO="${WINE_REPO:-https://gitlab.winehq.org/wine/wine.git}"
X86_PREFIX="${X86_PREFIX:-/usr/local}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

RUNTIME_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$RUNTIME_DIR/src/wine"
BUILD_DIR="$RUNTIME_DIR/build/wine-obj"
OUT_DIR="$RUNTIME_DIR/build/wine"
PATCH_DIR="$RUNTIME_DIR/patches/wine"
BUILD_INFO="$RUNTIME_DIR/build/wine-build.json"

PREPARE_ONLY=0
case "${1:-}" in
  "") ;;
  --prepare-only) PREPARE_ONLY=1 ;;
  *) echo "usage: $(basename "$0") [--prepare-only]" >&2; exit 64 ;;
esac

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Everything native to the build (configure, make, the compiler driver) runs as x86_64 with the
# x86_64 Homebrew prefix first in PATH. Cross compilers for PE targets may be arm64 binaries;
# an x86_64 process can still spawn those.
x86() {
  arch -x86_64 env \
    PATH="$X86_PREFIX/bin:$X86_PREFIX/sbin:$PATH" \
    PKG_CONFIG_PATH="$X86_PREFIX/lib/pkgconfig:$X86_PREFIX/share/pkgconfig" \
    "$@"
}

# --- preflight ---------------------------------------------------------------------------------

preflight() {
  [[ "$(uname -m)" == "arm64" ]] || die "expected an Apple Silicon host"
  command -v git >/dev/null || die "git not found"

  if (( PREPARE_ONLY )); then return; fi

  arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta 2 missing: softwareupdate --install-rosetta --agree-to-license"
  [[ -x "$X86_PREFIX/bin/brew" ]] || die "x86_64 Homebrew not found at $X86_PREFIX. Install it with: arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

  local missing=()
  for tool in bison flex pkg-config; do
    [[ -x "$X86_PREFIX/bin/$tool" ]] || missing+=("$tool")
  done
  for pc in freetype2 gnutls sdl2; do
    x86 pkg-config --exists "$pc" || missing+=("$pc")
  done
  if (( ${#missing[@]} )); then
    die "missing x86_64 dependencies: ${missing[*]}
install with: arch -x86_64 $X86_PREFIX/bin/brew install bison flex pkg-config freetype gnutls sdl2 gstreamer molten-vk"
  fi

  for cc in x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
    command -v "$cc" >/dev/null || [[ -x "$X86_PREFIX/bin/$cc" ]] \
      || die "$cc not found (brew install mingw-w64, or use llvm-mingw)"
  done
}

# --- source ------------------------------------------------------------------------------------

fetch_source() {
  mkdir -p "$(dirname "$SRC_DIR")"
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    log "Cloning $WINE_REPO at $WINE_TAG"
    git clone --quiet --depth 1 --branch "$WINE_TAG" "$WINE_REPO" "$SRC_DIR"
  else
    log "Updating existing checkout to $WINE_TAG"
    git -C "$SRC_DIR" fetch --quiet --depth 1 origin "refs/tags/$WINE_TAG:refs/tags/$WINE_TAG"
  fi
  # Always start from a pristine tree so the result depends only on the tag and the series.
  git -C "$SRC_DIR" checkout --quiet --force "refs/tags/$WINE_TAG"
  git -C "$SRC_DIR" clean --quiet -fdx
  WINE_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
}

# --- patch queue -------------------------------------------------------------------------------

# Prints the patch filenames from `series`, in order, without comments or blank lines.
series_patches() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$PATCH_DIR/series"
}

# Fails unless the patch begins with a valid Tether-* provenance header (see patches/wine/README.md).
validate_header() {
  local patch="$1" name header origin upstream
  name="$(basename "$patch")"
  # The header sits above the format-patch output, so only look before the first diff or mbox line.
  header="$(awk '/^(From |diff --git |--- )/ {exit} {print}' "$patch")"

  origin="$(sed -n 's/^Tether-Origin:[[:space:]]*//p' <<<"$header" | head -1)"
  [[ "$origin" =~ ^(crossover|proton|staging|tether)$ ]] \
    || die "$name: Tether-Origin must be one of crossover, proton, staging, tether (got '${origin:-missing}')"

  grep -q '^Tether-Source:[[:space:]]*[^[:space:]]' <<<"$header" \
    || die "$name: missing Tether-Source"

  upstream="$(sed -n 's/^Tether-Upstream:[[:space:]]*//p' <<<"$header" | head -1)"
  case "$upstream" in
    upstreamed) ;;
    "submitted "http*) ;;
    downstream-only)
      grep -q '^Tether-Reason:[[:space:]]*[^[:space:]]' <<<"$header" \
        || die "$name: downstream-only patches need a Tether-Reason" ;;
    *) die "$name: Tether-Upstream must be 'upstreamed', 'submitted <url>', or 'downstream-only' (got '${upstream:-missing}')" ;;
  esac
}

APPLIED_PATCHES=()   # "filename sha256" pairs, in apply order

apply_patches() {
  [[ -f "$PATCH_DIR/series" ]] || die "missing $PATCH_DIR/series"
  local name patch sha listed
  listed="$(series_patches)"
  for patch in "$PATCH_DIR"/*.patch; do
    [[ -e "$patch" ]] || continue
    grep -qxF "$(basename "$patch")" <<<"$listed" \
      || die "$(basename "$patch") is in patches/wine but not listed in series"
  done
  while IFS= read -r name; do
    patch="$PATCH_DIR/$name"
    [[ -f "$patch" ]] || die "series lists $name but the file does not exist"
    validate_header "$patch"
    log "Applying $name"
    git -C "$SRC_DIR" apply --whitespace=nowarn "$patch" \
      || die "$name does not apply to $WINE_TAG (refresh it; see patches/wine/README.md)"
    sha="$(shasum -a 256 "$patch" | cut -d' ' -f1)"
    APPLIED_PATCHES+=("$name $sha")
  done < <(series_patches)
  log "Applied ${#APPLIED_PATCHES[@]} patch(es)"
}

# --- build -------------------------------------------------------------------------------------

build_wine() {
  rm -rf "$BUILD_DIR" "$OUT_DIR"
  mkdir -p "$BUILD_DIR" "$OUT_DIR"

  log "Configuring (x86_64, wow64)"
  (
    cd "$BUILD_DIR"
    x86 env \
      CFLAGS="-O2 -g -I$X86_PREFIX/include" \
      CROSSCFLAGS="-O2 -g" \
      LDFLAGS="-L$X86_PREFIX/lib -Wl,-rpath,$X86_PREFIX/lib" \
      "$SRC_DIR/configure" \
        --prefix="$OUT_DIR" \
        --enable-archs=i386,x86_64 \
        --disable-tests \
        --without-x \
        --without-wayland \
        --without-alsa \
        --without-oss \
        --without-pulse \
        --without-v4l2 \
        --without-udev
  )

  log "Building with $JOBS jobs"
  x86 make -C "$BUILD_DIR" -j"$JOBS"

  log "Installing to $OUT_DIR"
  x86 make -C "$BUILD_DIR" install

  [[ -x "$OUT_DIR/bin/wine" ]] || die "build finished but $OUT_DIR/bin/wine is missing"
}

# --- build record ------------------------------------------------------------------------------

write_build_info() {
  local features='"wow64"' p
  for p in "${APPLIED_PATCHES[@]:-}"; do
    [[ "$p" == *msync* ]] && { features='"msync", "wow64"'; break; }
  done

  local patches_json="" sep=""
  for p in "${APPLIED_PATCHES[@]:-}"; do
    [[ -n "$p" ]] || continue
    patches_json+="$sep{ \"name\": \"${p%% *}\", \"sha256\": \"${p##* }\" }"
    sep=", "
  done

  mkdir -p "$(dirname "$BUILD_INFO")"
  cat >"$BUILD_INFO" <<EOF
{
  "wineVersion": "${WINE_TAG#wine-}",
  "wineTag": "$WINE_TAG",
  "wineCommit": "$WINE_COMMIT",
  "source": "$WINE_REPO",
  "features": [$features],
  "patches": [$patches_json]
}
EOF
  log "Wrote $BUILD_INFO"
}

preflight
fetch_source
apply_patches
if (( PREPARE_ONLY )); then
  log "Prepared $SRC_DIR (--prepare-only: not building)"
  exit 0
fi
build_wine
write_build_info
log "Done: $OUT_DIR"
