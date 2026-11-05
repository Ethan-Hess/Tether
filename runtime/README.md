# Tether runtime

The runtime is everything that runs *inside* a bottle: Wine plus the DirectX translation backends. It's built here, versioned independently of the app, and installed to:

```
~/Library/Application Support/Tether/Runtimes/<version>/
  runtime.json            manifest read by RuntimeStore (see below)
  bin/wine, bin/wineserver
  lib/wine/{x86_64-unix,x86_64-windows,i386-windows}/
  lib/libMoltenVK.dylib
  backends/dxmt/{x86_64,i386}/{d3d11,dxgi,d3d10core,winemetal}.dll
  backends/dxvk/{x86_64,i386}/{d3d9,d3d10core,d3d11,dxgi}.dll
```

## Components

| Component | Source | Build | Notes |
|-----------|--------|-------|-------|
| Wine | upstream `wine` stable + `patches/wine/` | `scripts/build-wine.sh` | x86_64 Mach-O, `--enable-archs=i386,x86_64` (wow64), macOS driver |
| msync | downstream patch set | applied by `build-wine.sh` | Mach-semaphore sync. Advertised as feature `msync` in `runtime.json` |
| DXMT | github.com/3Shain/dxmt | `scripts/build-dxmt.sh` | D3D10/11 → Metal. Needs the Wine build tree for `winemetal` |
| DXVK | github.com/doitsujin/dxvk | `scripts/build-dxvk.sh` | mingw cross-compile, PE DLLs only |
| MoltenVK | github.com/KhronosGroup/MoltenVK | `scripts/fetch-moltenvk.sh` | Release dylib, used by Wine's winevulkan |
| D3DMetal | Apple Game Porting Toolkit | `scripts/import-gptk.sh` | **Not redistributable.** User-imported into `UserComponents/d3dmetal` |

## `runtime.json`

```json
{
  "version": "0.1.0",
  "wineVersion": "10.0",
  "features": ["msync", "wow64"],
  "components": [
    { "name": "wine", "version": "10.0", "source": "https://gitlab.winehq.org/wine/wine/-/tags/wine-10.0" },
    { "name": "dxmt", "version": "0.x", "source": "https://github.com/3Shain/dxmt" },
    { "name": "dxvk", "version": "2.x", "source": "https://github.com/doitsujin/dxvk" },
    { "name": "moltenvk", "version": "1.x", "source": "https://github.com/KhronosGroup/MoltenVK" }
  ]
}
```

## Status

The scripts in `scripts/` are **stubs**: each documents its intended steps and exits non-zero. Turning them into a reproducible build (ideally in CI, published to GitHub Releases with checksums) is the top roadmap item. Contributions welcome.

## Rules

- Never commit built binaries. `runtime/build`, `runtime/src`, and `runtime/dist` are gitignored.
- Patches in `patches/wine/` must be upstreamable in spirit: compatibility and performance fixes only, never anything that hides Wine or alters what games can observe about the system (see `docs/ANTICHEAT.md`).
