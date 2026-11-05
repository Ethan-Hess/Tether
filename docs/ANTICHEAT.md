# Anti-cheat policy

Tether's goal for online games such as Overwatch 2 is to be **an ordinary, transparent compatibility layer**. We don't try to make Tether invisible. We make it *uninteresting*: games run unmodified, and nothing is added to their process beyond Wine and standard DirectX translation DLLs. That's the same setup millions of Steam Deck/Proton and CrossOver users run.

## What Tether will never do

These are hard project rules. PRs that add any of them will be closed.

- Inject code into game processes (`DYLD_INSERT_LIBRARIES`, `task_for_pid`, `mach_vm_write`, DLL injection, hook DLLs).
- Read or write game memory.
- Modify, patch, or replace game or anti-cheat files.
- Spoof hardware identifiers, serial numbers, or MAC addresses, or otherwise misrepresent the machine.
- Hide or disguise Wine. Wine's registry keys, exports such as `wine_get_version`, and similar markers stay as upstream ships them.
- Bypass, stub, or disable anti-cheat drivers or services.
- Ship or integrate third-party overlays, FPS unlockers, trainers, or macro tools.

## What Tether does instead

- **Clean prefixes.** We recommend one bottle per game or launcher, with no leftover tools or DLLs from other software.
- **Unmodified installs.** Games are installed and updated by their own launchers (for example Battle.net).
- **Minimal process surface.** The game process contains Wine and the selected graphics backend, and nothing else.
- **Enforced in code.** `OverridePolicy` only allows translation-surface DLL overrides (Direct3D, DXGI, shader compilers, XAudio). `LaunchEnvironment` drops `DYLD_*` and Wine-owned variables from profiles, bottles, and the host shell. Both are covered by tests.
- **Performance overlays are backend-native only:** the Metal Performance HUD (`MTL_HUD_ENABLED`) or `DXVK_HUD`. These are drawn by the translation layer, not injected.

## Honest caveats

- Publishers decide what's allowed on their services. Some explicitly support or tolerate compatibility layers, and some kernel-level anti-cheats (which can't run under Wine at all) block them outright. **Tether can't guarantee that any account is safe.** Check the game's terms and support articles.
- If a game's anti-cheat refuses to run under Wine, the answer is to mark it **Unsupported**, not to work around it.
- Report anti-cheat incidents (kicks, warnings, bans) in an issue using the `anti-cheat` label, with the runtime version, backend, and profile, so we can document them.

## Per-game notes

### Overwatch 2 (Battle.net)

- Use a dedicated bottle created with the `battlenet` profile. Install Battle.net there, then install Overwatch through it. The `overwatch` profile is matched automatically by executable name.
- Default backend order is `dxmt → d3dmetal → dxvk`. Overwatch defaults to D3D11, so DXMT is the shortest path to Metal.
- Status: **untested**. Results will be recorded here.
