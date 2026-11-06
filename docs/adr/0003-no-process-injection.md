# ADR 0003: No process injection, no concealment

**Status:** Accepted

## Context
Online games run anti-cheat that, reasonably, treats code injection, memory tampering, and environment spoofing as hostile. Injection-based features such as overlays, hooks, and FPS limiters also cost performance and stability.

## Decision
The host interacts with game processes **only** by spawning Wine with a computed environment and by `wineserver -k`. Concretely:

- No `DYLD_INSERT_LIBRARIES` and no inherited `DYLD_*`. The launch environment is built from an allowlist.
- No `task_for_pid`, memory access, or debugger attachment.
- DLL overrides from profiles and bottles are restricted to the translation surface (`OverridePolicy.allowedDLLs`).
- No hiding or spoofing of Wine, hardware, or OS identity.

## Steam, the overlay and compat rules
- **Steam Overlay and Steam Input** are features of the Windows Steam client running inside the bottle. They belong to Steam and its settings; Tether neither provides, injects nor configures them, and does not treat them as a reason to relax any rule above.
- **Games are started by Steam**, not by Tether: `tether steam launch` runs `Steam.exe` with Steam's own `steam://rungameid/<appid>` URL, and Steam starts the game, so Steamworks DRM and Cloud work as on Windows. Tether never attaches to or writes into the game process.
- **Compat rules** (`WINE_COMPATDB_FILE`, see ADR 0005) are written by Tether and may only choose graphics implementations (`dxgi`, `d3d9`) and the Metal HUD. The rules format can also carry arguments, environment variables and DLL overrides, but Tether never writes those through this channel, and `WINE_COMPATDB` and `WINE_COMPATDB_FILE` are protected variables that profiles and bottles cannot set.
- **Launch arguments** (`launchArguments` on profiles and bottles) are plain arguments to the executable, never run through a shell and never used to load code. A profile matched only by Steam app ID contributes none, because the executable being launched is then Steam, not the game.

See [docs/ANTICHEAT.md](../ANTICHEAT.md) for the user-facing policy.

## Consequences
- Some convenience features (custom overlays, FPS limiters, input hooks) are out of scope unless a translation layer provides them natively.
- The policy is enforced and tested in `LaunchEnvironment`/`OverridePolicy`. Changing the allowlist needs a reviewed PR explaining why the DLL is part of the translation surface.
