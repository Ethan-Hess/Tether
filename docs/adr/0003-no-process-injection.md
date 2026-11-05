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

See [docs/ANTICHEAT.md](../ANTICHEAT.md) for the user-facing policy.

## Consequences
- Some convenience features (custom overlays, FPS limiters, input hooks) are out of scope unless a translation layer provides them natively.
- The policy is enforced and tested in `LaunchEnvironment`/`OverridePolicy`. Changing the allowlist needs a reviewed PR explaining why the DLL is part of the translation surface.
