# ADR 0004: Upstream Wine with a thin patch queue (not Proton, not a fork)

**Status:** Accepted

## Context
Tether needs a Wine build tuned for macOS. There were three options:

1. **Base on Proton** (Valve's Wine fork).
2. **Hard-fork Wine**, stripping it down to a Mac-only codebase.
3. **Use upstream Wine plus a downstream patch queue.**

**Proton's** main advantages depend on Linux: fsync (Linux `futex_waitv`), EAC and BattlEye support (Linux-native modules), `lsteamclient` (bridges to the Linux Steam client), the Steam Linux Runtime container, and DXVK/vkd3d-proton tuned for Linux Vulkan drivers. Valve doesn't test or maintain Proton's Wine on macOS.

**A hard fork** wouldn't reduce runtime overhead. Wine loads modules on demand, so unused code costs nothing at runtime. On macOS, overhead comes from a few hot paths: wineserver synchronization, transitions between Windows code and the Mac-side code underneath it, the macOS driver (windowing, input, presentation), and Rosetta translation. Meanwhile upstream ships a development release every two weeks and a stable release every year, with a steady stream of game-compatibility fixes. A fork falls behind and gets harder to rebase over time. The likely long-term path off Rosetta (Wine running natively on Apple Silicon, with only Windows x86 code emulated) is being built upstream.

## Decision
- **Base:** pin an upstream Wine **stable** tag. Rebase once per stable release, and nightly CI tracks the development branch to catch breakage early.
- **Mac-only build through configuration, not code deletion:** `--without-x --without-wayland`, Linux audio and video backends disabled, `--disable-tests`, and wow64 (`--enable-archs=i386,x86_64`).
- **Patch queue** in `runtime/patches/wine/`, applied in the order listed in `series`. Every patch has a provenance header (format in `runtime/patches/wine/README.md`) recording:
  - **Origin:** `tether`, `crossover` (from CodeWeavers' published LGPL source), `proton` (from Valve's LGPL Wine fork), or `staging`.
  - **Upstream status:** `upstreamed` (dropped at the next rebase), `submitted` (with merge-request link), or `downstream-only` (with a written reason).
- **Sources for Mac work:** CrossOver's source first (msync, macOS driver, Retina). Proton patches are cherry-picked individually for specific game fixes.
- **Measure, then patch:** performance patches need a `tether bench` result showing the improvement (see ROADMAP M4).
- **Upstream by default:** every `tether`-origin patch should be submitted upstream unless it's inherently downstream.

## Consequences
- We get upstream compatibility fixes and the future Apple Silicon-native work with little effort.
- Rebases stay cheap as long as the queue stays small. The `downstream-only` count is the health metric to watch.
- Proton-exclusive Linux features stay off the table. They wouldn't work on macOS anyway.
- Steam integration has to be solved separately: Windows Steam runs inside a bottle for now, and a bridge to the native macOS Steam client is a research item in the roadmap.
