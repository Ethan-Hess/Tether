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

Packaging a signed and notarized `Tether.app` is on the roadmap. It will be an Xcode or `xcodebuild` wrapper around the same SwiftPM targets.

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

The build scripts are currently **stubs** that document their steps and exit. Making them real is the top roadmap item.
