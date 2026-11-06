# Spike: native arm64 Wine + FEX (ARM64EC) on macOS

Date: 2026-11-05. Host: macOS 26.6.2, Apple Silicon, 16K host page size.

## Question
Can Tether target native arm64 Wine with FEX translating x86 (instead of x86_64 Wine under Rosetta 2), and is the required entitlement obtainable?

## What was tested
Community build: `athei/wine-build` release `arm64-11.19-1` (`wine-arm64-11.19-1-macos-arm64.tar.xz`, 109,787,992 bytes, SHA-256 `b9c5e88b…ad1ba4`, verified against the release digest). Wine reported `wine-11.19-17-ge2e42653b41`. Run only against a throwaway prefix in the session scratchpad.

| Check | Result |
|-------|--------|
| `bin/wine`, `bin/wineserver` | Mach-O arm64 (native, no Rosetta) |
| `wineboot --init` on a fresh prefix | Succeeded; prefix created |
| `wine cmd /c echo` | Succeeded |
| `notepad`, `winecfg` | Both launched and stayed running (GUI not inspected visually) |
| D3D11 sample through DXMT | **Not run**: no D3D11 sample binary is available yet |
| Page size inside Wine / FEX paths | Not measured |

## Entitlement and signing
The loader `lib/wine/aarch64-unix/wine.app` is Developer ID signed (hardened runtime) and carries `com.apple.developer.cross-architecture-support`, plus `allow-jit`, `disable-executable-page-protection` and `disable-library-validation`. The entitlement is granted through an embedded provisioning profile (`ProvisionsAllDevices`, expires 2044) issued to an **individual** developer team, not a company. That suggests it can be obtained with a normal Developer ID team, but **this is unconfirmed**: whether it is a self-serve capability or needs a request to Apple must be checked in the developer portal before we commit to shipping.

## Findings for Tether
- **Runtime layout differs.** The build uses `lib/wine/{aarch64-unix,aarch64-windows,x86_64-windows,i386-windows}` and the real loader is inside `wine.app`. `Sources/TetherKit/Runtime/WineRuntime.swift` documents and assumes `x86_64-unix`; `Launcher.swift` comments say "x86_64, translated by Rosetta 2". Both need updating, and `bin/wine` must resolve to the signed app.
- **Bundled libraries** (freetype, gnutls, SDL) ship inside `lib/external`, so no host Homebrew dependencies are needed at runtime.
- **Compat database:** the runtime applies per-game settings itself (dll overrides, `FEX_X87REDUCEDPRECISION`, etc.). Tether profiles will need to coexist with it.
- **Environment leakage:** running `wine` directly from a shell passes the whole shell environment, including secret-looking variables, to Windows processes. Tether's launch path builds its environment from an allowlist (`LaunchEnvironment.swift`) and must keep doing so.
- Upstream limitations from the release notes: macOS 26.4+, no D3D12 yet, DXMT's Windows side still x86_64 under FEX until ARM64X builds land.

## Recommendation
**Conditional go.** The arm64 + FEX path works for basic Wine on this machine, and the entitlement looks obtainable. Before Phase B/C:
1. Confirm entitlement availability for our own team.
2. Build or obtain a D3D11 sample and verify the DXMT path.
3. Decide between wrapping community builds and building our own runtime.
