# ADR 0005: Native arm64 Wine with FEX (ARM64EC), not x86_64 under Rosetta 2

**Status:** Proposed (conditional go from the [feasibility spike](../spikes/arm64-fex.md); becomes Accepted once the open items below are closed)

## Context
The original design (ADR 0004, ROADMAP M1) built Wine as x86_64 and ran it under Rosetta 2. Two things make that a poor foundation:

1. **Rosetta is being phased out.** Apple has said Rosetta 2 tapers after macOS 27 and mostly disappears in macOS 28 (expected 2027), keeping only a limited subset for older games. A 1.0 built on it would ship close to the cutoff.
2. **The x86_64 toolchain is no longer practical.** The official Homebrew installer refuses to create an x86_64 prefix on Apple Silicon, so `build-wine.sh`'s `/usr/local` dependency model cannot be reproduced. We would have to build every x86_64 dependency from source.

Community projects ([athei/wine-build](https://github.com/athei/wine-build), [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine)) now ship native arm64 Wine for macOS. Wine runs natively on arm64 and [FEX](https://github.com/FEX-Emu/FEX) translates only the Windows x86 code (64-bit as ARM64EC, 32-bit through WoW64). The spike confirmed on macOS 26.6.2 that such a build initializes a prefix and runs `cmd`, `notepad` and `winecfg`.

FEX needs 4K pages while macOS arm64 uses 16K. The community builds solve this with Apple's `com.apple.developer.cross-architecture-support` entitlement, which gives the Wine process 4K pages and the low 4 GB of address space. It requires macOS 26.4 or later and running from a signed app bundle.

## Decision
- **Target architecture:** native arm64 Wine host, with FEX as the x86 translator (ARM64EC for 64-bit, WoW64 for 32-bit). x86_64-under-Rosetta is dropped as the primary design.
- **Unchanged from ADR 0004:** upstream Wine at a pinned tag plus a thin, provenance-tagged patch queue, upstream by default.
- **Minimum macOS** becomes 26.4 for the runtime (the host app can still target an older minimum, but cannot launch games below it).
- **Runtime source** is decided after the remaining spike items: either wrap pinned, hash-verified community builds, or build Wine and FEX ourselves. Community build scripts are prior art only. Some of their glue is AGPL-3.0, so we do not copy it.
- **Build tools** use the user's arm64 Homebrew. No x86_64 prefix is required.

## Open items before this is Accepted
1. Confirm the cross-architecture entitlement is available to Tether's own Developer ID team (self-serve capability or a request to Apple).
2. Run a D3D11 sample through DXMT on the arm64 runtime (not yet done).
3. Decide wrap-versus-build for the runtime.

## Consequences
- No dependence on Rosetta, which removes the existential risk in the roadmap. We now depend on FEX and on the entitlement.
- The macOS floor rises to 26.4 for gameplay, which excludes older systems.
- `WineRuntime`, `Launcher` and the runtime layout docs assume x86_64 (`lib/wine/x86_64-unix`) and must change: the arm64 build uses `aarch64-unix` and keeps the real loader inside a signed `wine.app`.
- Backends (DXMT, DXVK) need ARM64X/ARM64EC builds for best performance; until then their Windows side runs as x86_64 under FEX.
- `build-wine.sh` must be reworked for arm64 (or replaced by a wrap-and-verify step).
- Anti-cheat policy is unchanged. FEX is a standard translation layer, not process injection, so ADR 0003 still holds. Revisit if any FEX feature needs host-side hooks.
