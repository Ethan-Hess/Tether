# ADR 0005: Native arm64 Wine with FEX (ARM64EC), not x86_64 under Rosetta 2

**Status:** Proposed (conditional go from the [feasibility spike](../spikes/arm64-fex.md); becomes Accepted once the open items below are closed)

## Context
The original design (ADR 0004, ROADMAP M1) built Wine as x86_64 and ran it under Rosetta 2. Two things make that a poor foundation:

1. **Rosetta is being phased out.** Apple has said Rosetta 2 tapers after macOS 27 and mostly disappears in macOS 28 (expected 2027), keeping only a limited subset for older games. A 1.0 built on it would ship close to the cutoff.
2. **The x86_64 toolchain is no longer practical.** The official Homebrew installer refuses to create an x86_64 prefix on Apple Silicon, so `build-wine.sh`'s `/usr/local` dependency model cannot be reproduced. We would have to build every x86_64 dependency from source.

Community projects ([Mach9](https://github.com/athei/mach9), formerly `athei/wine-build`, and [MetalSharp-Wine](https://github.com/metalsharp/MetalSharp-Wine)) now ship native arm64 Wine for macOS. Mach9's engine is designed to be embedded in a launcher (see the [distribution spike](../spikes/distribution.md)). Wine runs natively on arm64 and [FEX](https://github.com/FEX-Emu/FEX) translates only the Windows x86 code (64-bit as ARM64EC, 32-bit through WoW64). The spike confirmed on macOS 26.6.2 that such a build initializes a prefix and runs `cmd`, `notepad` and `winecfg`.

FEX needs 4K pages while macOS arm64 uses 16K. The community builds solve this with Apple's `com.apple.developer.cross-architecture-support` entitlement, which gives the Wine process 4K pages and the low 4 GB of address space. It requires macOS 26.4 or later and running from a signed app bundle.

## Decision
- **Target architecture:** native arm64 Wine host, with FEX as the x86 translator (ARM64EC for 64-bit, WoW64 for 32-bit). x86_64-under-Rosetta is dropped as the primary design.
- **Unchanged from ADR 0004:** upstream Wine at a pinned tag plus a thin, provenance-tagged patch queue, upstream by default.
- **Minimum macOS** becomes 26.4 for the runtime (the host app can still target an older minimum, but cannot launch games below it).
- **Runtime source: wrap first, build later.** For M1, `tether runtime install` fetches a pinned community build (starting with `athei/mach9`), verifies its SHA-256 against a value pinned in Tether, and unpacks it unmodified. We do not re-sign or patch it, so its original Developer ID signature and entitlement provisioning profile stay valid and our own entitlement is not on the critical path. Building our own Wine and FEX (and carrying our own patch queue) is deferred until we need changes the community builds will not take, and at that point it requires our own entitlement. Community build scripts are prior art only. Some of their glue is AGPL-3.0, so we do not copy it.
- **Mitigations for depending on a third-party build:** pin by version and hash; keep the previous runtime installed for rollback; record the source and license links (LGPL for Wine, MIT for FEX) in `runtime.json`; keep a second candidate (MetalSharp-Wine) tested as a fallback; contribute fixes upstream rather than forking.
- **Build tools** use the user's arm64 Homebrew. No x86_64 prefix is required.

## Open items before this is Accepted
1. **Licence inventory.** The bundle ships no licence or notice files, and its third-party libraries (gnutls, nettle, GMP, SDL, freetype, Vulkan loader, Mesa/KosmicKrisp and others) need notices and source links before we redistribute it.

**Delivery (decided):** for 1.0 the pinned runtime is embedded in Tether.app, with `wine.app` left untouched, the way Mach9.app does it. Notarization is deferred: the project owner accepts macOS's unnotarized-app warning (Open Anyway) for now rather than pay for an Apple Developer ID. A stand-in app experiment showed that approving the outer app also covers the quarantined runtime nested inside it (one Open Anyway, runtime ran); a real browser download and a full game launch from the translocated app are still untested (see the distribution spike). The bare `wine.app` is Developer ID signed (hardened runtime, secure timestamp) but not notarized, and a copy carrying the quarantine attribute was blocked by Gatekeeper in a test, so download-on-demand is fragile. `tether runtime install` stays for development and rollback testing, and `tether doctor` flags a quarantined runtime. Runtime updates ship with app updates. Details in the [distribution spike](../spikes/distribution.md).

Closed: the D3D11 sample ran through DXMT on the arm64 runtime (see the spike); the wrap-versus-build decision is made above; and the entitlement question is answered for wrapping, because Mach9 documents that an embedding app leaves `wine.app` untouched, so its signature and provisioning profile stay valid. Tether needs its own entitlement only if it builds its own loader.

## Consequences
- No dependence on Rosetta, which removes the existential risk in the roadmap. We now depend on FEX and on the entitlement.
- The macOS floor rises to 26.4 for gameplay, which excludes older systems.
- `WineRuntime`, `Launcher` and the runtime layout docs assume x86_64 (`lib/wine/x86_64-unix`) and must change: the arm64 build uses `aarch64-unix` and keeps the real loader inside a signed `wine.app`.
- Backends (DXMT, DXVK) need ARM64X/ARM64EC builds for best performance; until then their Windows side runs as x86_64 under FEX.
- A wrapped runtime selects DXMT or wined3d per executable with its own compatibility database. Tether models this as the `runtime` backend (runtime feature `managed-graphics`): it installs no DLLs and sets no overrides, and `tether env`/`run` report the backend as runtime-managed. The runtime does let a launcher choose: `WINE_COMPATDB` takes rules such as `exe=*;dxgi=wined3d` or `exe=steam:<appid>;dxgi=dxmt` (an earlier draft said forcing was impossible; that came from a test with values that were not valid rules). Until Tether writes those rules, a bottle's forced backend is reported as ignored.
- `build-wine.sh` must be reworked for arm64 (or replaced by a wrap-and-verify step).
- Anti-cheat policy is unchanged. FEX is a standard translation layer, not process injection, so ADR 0003 still holds. Revisit if any FEX feature needs host-side hooks.
