# Building

## Host (app + CLI)

Requirements: macOS 14+, Apple Silicon, and Swift 6 (Xcode 16+ or the Command Line Tools).

```sh
./scripts/bootstrap.sh
swift build                 # TetherKit, tether, TetherApp
./scripts/test.sh           # swift test, with the extra framework paths the CLT needs
swift run tether doctor
swift run TetherApp
```

`scripts/test.sh` exists because with only the Command Line Tools installed (no Xcode), SwiftPM doesn't add the CLT `Testing.framework` search path. With Xcode, plain `swift test` works.

## Tether.app and the DMG

`swift run TetherApp` is for development. To build the real app (no Xcode needed, scripts only):

```sh
scripts/package-app.sh              # build/Tether.app with the pinned runtime embedded (~1 GB)
scripts/package-app.sh --no-runtime # same, without the runtime: quick, for UI and update testing
scripts/verify-app.sh               # structure, signatures, wine.app untouched, and a --self-check run
scripts/make-dmg.sh                 # build/Tether-<version>.dmg (LZMA compressed)
```

What the app script does, and why:

- It builds the release binaries, then lays out `Contents/{MacOS,Resources,Frameworks}`. SwiftPM's own resource bundle can't sit at an app's root (it breaks signing and points at the build folder), so its contents go into `Contents/Resources`, where `TetherResources` looks first.
- The runtime is installed with the normal `tether runtime install` path (download, pinned SHA-256, safe unpack) into `build/cache`, then copied to `Contents/Resources/EmbeddedRuntimes/<version>`. It is reused on later builds.
- It signs ad-hoc by default. The outer app is signed **without `--deep`** and `wine.app` is never re-signed: it carries its own provisioning profile and the cross-architecture entitlement ([distribution spike](spikes/distribution.md)).
- `SIGN_IDENTITY="Developer ID Application: …"` signs with a real identity and the hardened runtime, and signs the runtime's other Mach-O files too (not `wine.app`), as notarization needs. That path is wired but has not been run: no Developer ID certificate exists yet.
- `Tether --self-check` (used by `verify-app.sh`) prints where the app found its resources and runtime, so a copy that quietly falls back to a build folder is caught.
- The version comes from the `VERSION` file; the build number is the commit count.

CI runs the same scripts on GitHub's runners (`.github/workflows/ci.yml`: tests on macOS 15 and 26, a `--no-runtime` bundle build checked by `verify-app.sh`, lint). Releasing (tag, draft, publish, Homebrew) is in [RELEASING.md](RELEASING.md); removing Tether is in [UNINSTALL.md](UNINSTALL.md).

## Runtime (Wine + backends)

The runtime is built separately from the host and versioned independently. See [runtime/README.md](../runtime/README.md). In short:

```sh
runtime/scripts/build-wine.sh      # Wine x86_64 + wow64, with patches from runtime/patches/wine
runtime/scripts/build-dxmt.sh      # DXMT (D3D11 → Metal)
runtime/scripts/build-dxvk.sh      # DXVK PE DLLs (cross-compiled with mingw)
runtime/scripts/fetch-moltenvk.sh  # MoltenVK release dylib
runtime/scripts/package-runtime.sh # assemble Runtimes/<version>/ + runtime.json
runtime/scripts/import-gptk.sh     # optional: import D3DMetal from your own GPTK download
```

> **Note:** the runtime is moving to native arm64 Wine + FEX ([ADR 0005](adr/0005-arm64-wine-with-fex.md)). The official Homebrew installer no longer supports an x86_64 prefix, so the x86_64 instructions below cannot be followed on a fresh machine. `build-wine.sh` will be reworked for arm64.

`build-wine.sh` is implemented (for the earlier x86_64 design) and needs x86_64 Homebrew in `/usr/local` (`arch -x86_64 /usr/local/bin/brew install bison flex pkg-config freetype gnutls sdl2 gstreamer molten-vk mingw-w64`). The other runtime scripts are still **stubs** that document their steps and exit. Making them real is the top roadmap item.
