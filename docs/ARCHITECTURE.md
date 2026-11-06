# Architecture

Tether has three layers: a **host** (Swift app and CLI), a **runtime** (Wine plus translation backends, built separately and versioned), and **bottles** (per-game Wine prefixes). The host plans and spawns. The runtime does the actual translation.

```
┌──────────────────────────── host (this repo, Swift) ────────────────────────────┐
│  TetherApp (SwiftUI)          tether (CLI, swift-argument-parser)               │
│        └──────────────┬──────────────┘                                          │
│                  TetherKit                                                      │
│   Bottle/   BottleStore: bottle.json + prefix/ + cache/ + logs/                 │
│   Runtime/  RuntimeStore: installed runtimes, runtime.json manifests            │
│   Profiles/ GameProfile JSON, ProfileLibrary (built-in + user, match by exe)    │
│   Graphics/ GraphicsBackend protocol, DXMT/DXVK/D3DMetal/wined3d,               │
│             DLLOverride + OverridePolicy, BackendInstaller                      │
│   Launch/   LaunchEnvironment (env assembly + policy), Launcher (spawn)         │
│   Diagnostics/ os.Logger categories, SystemCheck                                │
└─────────────────────────────────────┬───────────────────────────────────────────┘
                                      │ posix_spawn(wine, env)   ← only interface
┌─────────────────────────────────────▼──────── runtime (runtime/, built) ────────┐
│  wine (arm64 Mach-O, FEX translates x86) + wineserver       [target: ADR 0005]  │
│  lib/wine/{aarch64-unix, aarch64-windows, x86_64-windows, i386-windows}         │
│  backends/dxmt/{x86_64,i386}/*.dll   backends/dxvk/{x86_64,i386}/*.dll          │
│  (+ MoltenVK dylib, DXMT winemetal.so)                                          │
│  UserComponents/d3dmetal  ← imported by the user from Apple GPTK                │
└─────────────────────────────────────┬───────────────────────────────────────────┘
                                      ▼
                               Metal · CoreAudio · macOS
```

## Process model

- **One `wineserver` per bottle.** Bottles share nothing, so a crash or a stray process in one bottle can't affect another.
- **The host is never in the game's address space.** `Launcher` writes files, builds an environment, and spawns `bin/wine` with the target executable. After that it can only wait for exit or run `wineserver -k`. There is no IPC channel into the game, no `DYLD_INSERT_LIBRARIES`, and no `task_for_pid`. See [ADR 0003](adr/0003-no-process-injection.md).
- **FEX handles x86 → arm64.** Wine runs natively on arm64 and FEX translates only the Windows x86 code (64-bit as ARM64EC, 32-bit through WoW64). FEX needs 4K pages, which macOS provides to a signed app with the cross-architecture entitlement (macOS 26.4+). See [ADR 0005](adr/0005-arm64-wine-with-fex.md) and the [spike](spikes/arm64-fex.md). The code and scripts still reflect the earlier x86_64/Rosetta design until the runtime pipeline is reworked.

## Launch pipeline

```
LaunchRequest(bottle, exe, args)
  → Launcher.plan()                         pure, no side effects; `tether env` prints this
      RuntimeStore.resolve(bottle.runtimeVersion ?? latest)
      ProfileLibrary: request.profileID ?? bottle.profileID ?? match(exe filename)
      GraphicsBackends.resolve: bottle choice → profile preference → default order,
                                first one whose files are present
      LaunchEnvironment(bottle, runtime, backend, profile)
  → Launcher.launch(plan)
      wineboot --init + winecfg -v <ver>    first launch only
      BackendInstaller.install              copy backend DLLs into system32/syswow64
      Process.run()                         stdout/stderr → /dev/null unless --debug
```

### Environment assembly

`LaunchEnvironment` starts from an **empty** environment and inherits only `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `LANG`, `LC_ALL`, and `SHELL`. Layers are then applied in order:

1. **Core:** `PATH` (runtime bin first), `WINEPREFIX`, `WINEDEBUG=-all` (or debug channels with `--debug`), and `WINEDLLPATH` for builtin-style backends.
2. **Backend:** for example `DXVK_STATE_CACHE_PATH=<bottle>/cache/dxvk`, log levels off, and the HUD if enabled.
3. **Sync:** bottle → profile → `msync`. Falls back to `esync` if the runtime manifest lacks the `msync` feature.
4. **`WINEDLLOVERRIDES`:** the backend's overrides, then profile overrides filtered by `OverridePolicy`, then `winemenubuilder.exe=` (disabled).
5. **Profile env, then bottle env.** Protected keys (`WINEPREFIX`, `WINEDLLOVERRIDES`, `WINEDLLPATH`, `WINESERVER`, `WINELOADER`, `PATH`, `DYLD_*`) are dropped and reported.

## Graphics backends

| Backend    | APIs      | Path                             | Ships with runtime | Notes |
|------------|-----------|----------------------------------|--------------------|-------|
| `dxmt`     | D3D10/11  | DXMT → Metal                     | yes                | Default for D3D11. No Vulkan hop. |
| `d3dmetal` | D3D11/12  | D3DMetal → Metal                 | **no**, user import | Best D3D12 path. GPTK license forbids redistribution. Loaded as builtin via `WINEDLLPATH`. |
| `dxvk`     | D3D9–11   | DXVK → Vulkan → MoltenVK → Metal | yes                | Broadest compatibility, but one more translation hop. |
| `wined3d`  | D3D9–11   | wined3d → OpenGL                 | built into Wine    | Fallback only. |

Default order when nothing else is specified: `dxmt → d3dmetal → dxvk → wined3d`. A backend is "available" if its file directory exists. Adding a backend means one `GraphicsBackend` conformance plus a build script in `runtime/scripts/`.

Planned: `vkd3d-proton` (D3D12 → Vulkan) as an open-source D3D12 fallback when D3DMetal isn't imported.

## Performance strategy

| Technique | Where |
|-----------|-------|
| Metal-native backends first (DXMT, D3DMetal) | `GraphicsBackends.defaultOrder` |
| msync: wineserver sync via Mach semaphores instead of server round-trips | `runtime/patches/wine`, `LaunchEnvironment` |
| No logging in release launches (`WINEDEBUG=-all`, backend log levels off, output to `/dev/null`) | `LaunchEnvironment`, `Launcher.makeProcess` |
| Persistent per-bottle shader and pipeline caches | `Bottle.cacheURL`, backend env |
| No overlays, hooks, or helper processes alongside the game | ADR 0003 |
| Minimal, reproducible environment | `LaunchEnvironment.inheritedKeys` |
| *(planned)* Rosetta AOT warm-up of the game binary on install | `Launcher` |
| *(planned)* Shader cache pre-compilation | backend-specific |

## On-disk layout

```
~/Library/Application Support/Tether/          ($TETHER_HOME overrides)
  Bottles/<name>/
    bottle.json      BottleConfig (schemaVersion, runtimeVersion, backend, profileID, windowsVersion, sync, environment, showPerformanceHUD)
    prefix/          WINEPREFIX (drive_c, system.reg, …)
    cache/           shader/pipeline caches
    logs/wine.log    only written with --debug
  Runtimes/<version>/
    runtime.json     RuntimeManifest (version, wineVersion, features, components)
    bin/ lib/ backends/
  UserComponents/d3dmetal/   imported from Apple GPTK
  Profiles/*.json            user game profiles
```

## Testing

`TetherKit` has no UI and no global state, so everything above `Process.run()` is unit-tested against a temporary `TetherPaths` root. See `Tests/TetherKitTests`. Launch planning is deterministic: `tether env` prints exactly what a launch would use.
