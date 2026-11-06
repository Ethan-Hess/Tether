# Roadmap

This is the path from today's scaffolding to a production-ready 1.0. Milestones run in order, because each one depends on the previous. Cross-cutting tracks run alongside them.

## Definition of "production-ready" (1.0 exit criteria)

Tether is 1.0 when **all** of these are true:

| Area | Bar |
|------|-----|
| **Install** | Downloadable `.app`, ad-hoc signed. Without an Apple Developer ID the first launch needs macOS's "Open Anyway" approval in System Settings (accepted for now; Developer ID signing and notarization are deferred, see M6). Developers can also build from source. First run to first game takes under 10 minutes with no Terminal. |
| **Launchers** | Steam installs, logs in, updates, and launches games reliably. Epic and Battle.net launchers are not planned. |
| **Compatibility** | ≥ 50 titles in the compatibility database rated *Gold* or better, including ≥ 10 of Steam's top 100 non-kernel-anti-cheat games. |
| **Performance** | Within 5% of CrossOver's average FPS on the benchmark set for the same backend, with p99 frame time no worse. Shader stutter only on first encounter of a shader, never after a cache hit. |
| **Overhead** | Tether's own processes use ~0% CPU while a game runs. No helper daemons. The app can be quit while games keep running. |
| **Updates** | App (Sparkle) and runtime auto-update with signature verification and one-click rollback. |
| **Reliability** | No data loss across updates. Bottles survive runtime upgrades or are migrated automatically. Crashes leave readable logs. |
| **Policy** | Every item in [docs/ANTICHEAT.md](docs/ANTICHEAT.md) is enforced and tested. Its behavior is documented per game. |

---

## M0: Foundations ✅

- [x] TetherKit: bottles, runtimes, profiles, backend resolution, launch planning
- [x] Launch policy: environment allowlist, DLL override allowlist, protected keys (tested)
- [x] `tether` CLI, SwiftUI app skeleton, architecture docs, ADRs 0001–0003

## M1: First light (a reproducible runtime)

**Goal:** `tether run` starts a real D3D11 program and renders through DXMT.

- [ ] **Wine build** (`runtime/scripts/build-wine.sh`)
  - **Direction changed ([ADR 0005](docs/adr/0005-arm64-wine-with-fex.md), proposed):** native arm64 Wine with FEX (ARM64EC and WoW64) instead of x86_64 under Rosetta. The spike ran a D3D11 sample through DXMT on a community arm64 build, and the decision is to wrap a pinned, hash-verified community runtime first and build our own later. Open items: confirm the cross-architecture entitlement for our team (needed only once we ship our own loader) and confirm the community build's notarization and redistribution terms. The bullets below this one still describe the earlier x86_64 plan and will be rewritten once those are settled.
  - Pin an upstream Wine stable tag. Build x86_64 under Rosetta with `--enable-archs=i386,x86_64` (wow64, so there are no 32-bit host binaries).
  - x86_64 Homebrew deps in `/usr/local` (freetype, gnutls, sdl2, gstreamer, molten-vk). See prior art: Gcenx's macOS Wine builds and Whisky's Wine.
  - Upstream Wine plus a patch queue, not a fork ([ADR 0004](docs/adr/0004-upstream-wine-with-patch-queue.md)). Disable unneeded features with configure flags (`--without-x --without-wayland --disable-tests`).
  - First patches: **msync**, macOS driver fixes, and Retina mode, extracted from CodeWeavers' published CrossOver source (LGPL) by diffing against the matching upstream tag. Each patch carries an origin and upstream-status header ([runtime/patches/wine/README.md](runtime/patches/wine/README.md)).
  - `build-wine.sh --prepare-only` checks that every patch in `series` applies cleanly, has a valid header, and that no patch file is missing from `series`. Run it locally before committing a patch (automated CI is deferred).
  - Nightly build against Wine's development branch to spot rebase conflicts early.
- [ ] **DXMT build** (`build-dxmt.sh`): PE DLLs plus `winemetal.so` built against our Wine tree.
- [ ] **DXVK build** (`build-dxvk.sh`): pin a DXVK version whose Vulkan feature requirements MoltenVK satisfies, and document the choice in an ADR.
- [ ] **MoltenVK** (`fetch-moltenvk.sh`): pinned release with a checksum.
- [ ] **Packaging** (`package-runtime.sh`): `runtime.json`, ad-hoc signing, a `.tar.xz` with SHA-256.
- [ ] **CI** *(deferred: builds and checks run locally for now)*: GitHub Actions on Apple Silicon macOS runners builds the runtime on tag. Release artifacts include checksums and a minisign signature.
- [x] `tether runtime install [version]`: download, verify the pinned hash, unpack into `Runtimes/`. Catalog: `0.1.0` is Mach9 `arm64-11.19-1` (no compat rules, loader not notarized); `0.2.0` is `arm64-11.20-5` (compat rules, notarized loader) and is the default. For development and rollback testing; 1.0 embeds the runtime in the app (M6). The installed runtime must not be quarantined (`tether doctor` checks).
- [ ] **Smoke test set:** `notepad`, `winecfg`, and a redistributable D3D11 sample (built from Microsoft's open-source DirectX samples), run headless in CI where Metal is available.

**Exit:** a fresh Mac runs `tether runtime install && tether bottle create t && tether run t d3d11-sample.exe`, and the sample renders through DXMT. `tether env` shows `WINEMSYNC=1`.

## M2: Launchers (Steam)

**Goal:** install a launcher, log in, install a game, play.

### Steam
- [x] `steam` profile: Steam client in its own bottle, running the Windows `SteamSetup.exe` (`/S` silent install works; installing it from the app is still an M5 item).
- [x] `steamwebhelper` (CEF) works: rendering, GPU and sandbox flags, and login. Track known CrossOver and Proton fixes and upstream what we can. Manual test on the wrapped arm64 runtime (wine 11.19): login and page switching work with `-cef-disable-gpu` (now in the `steam` profile's `launchArguments`); without it the window went blank after switching pages. Not yet tested: long sessions, installing or launching a game, Steam Guard, and whether sandbox flags matter.
- [x] **Library import:** parse `steamapps/libraryfolders.vdf` and `appmanifest_<appid>.acf` to list installed games with app IDs (`tether steam list <bottle>`). Tested on synthetic manifests only; still to be checked against a real Steam install.
- [x] **Launch by app ID:** `tether steam launch <bottle> <appid>` runs Steam.exe with `steam://rungameid/<appid>`, so Steamworks DRM, Cloud saves, and achievements work normally. Checked on one game (There Are No Orcs, Unity, D3D11) from a cold start on the wrapped arm64 runtime: Steam started and the game ran and looked fine in a manual check. The game's own backend rule applies through its app ID; its other profile settings don't (see Launch-parameter passthrough). `-silent`, Cloud saves and achievements were not tested.
- [x] Per-game profile matching by Steam app ID (`steamAppIDs` on `GameProfile`; `LaunchRequest.steamAppID` beats exe-name matching).
- [ ] **Overwatch 2** (Steam app 2357570) tested on DXMT, installed and launched through Steam. Untested so far; also check whether the Steam version needs the Battle.net app or only an account login. Fill in the per-game notes in `docs/ANTICHEAT.md`.
- [x] Steam Overlay: the overlay is Steam's own in-guest feature, not Tether injection, and is left to the user's Steam settings. Documented in [ADR 0003](docs/adr/0003-no-process-injection.md).
- [ ] Controller pass-through: Steam Input and SDL inside Wine.
- [ ] *Research:* a bridge from Windows games to the **native macOS Steam client** (similar in spirit to Proton's `lsteamclient`, which targets Linux), so games don't need Windows Steam running inside every bottle. Saves memory and CPU, but it's a large project. Decide go or no-go after M2.

Battle.net as a launcher is out of scope (decided); games from Blizzard, such as Overwatch 2, are handled through Steam.

### Shared
- [ ] Profile matching by launcher-provided IDs, not only exe names.
- [x] Launch-parameter passthrough: `launchArguments` on profiles and, per bottle, `tether bottle set <b> --arg=<value>` (applied to every executable run in the bottle, in the order profile, bottle, command line). Under Steam a game's own profile contributes its backend rule (through its app ID in `compat.rules`) but not its environment, sync or arguments, which apply only to direct runs: a game started by an already-running Steam inherits Steam's environment, so they would work only on cold starts.

**Exit:** Steam passes a scripted checklist (install → login → install game → launch → quit → relaunch) on a supported macOS version.

Steam checklist: `scripts/steam-checklist.sh --app <id> --game-process <regex>` (login and game install are done by a person; it verifies the result and writes a report). Runs so far on macOS 26.6.2: an existing bottle on runtime 0.1.0 (9 passed, 0 failed, 2 skipped); then a **from-scratch run on runtime 0.2.0** (new bottle, Steam installed, login and game install by hand): 10 passed, 1 failed, the cold relaunch (game process didn't appear within 180 s; Steam's log for that session stopped about two seconds after startup, cause not identified). The same bottle then passed a non-interactive rerun (9 passed, 0 failed, 2 skipped), and five further cold relaunches by hand worked (about 15 s each), so the failure is unexplained and not reproduced. The script now runs launches with debug logging and prints diagnostics on failure. A second clean from-scratch run is still wanted for the exit. The checklist checks that processes start and stop, not that the picture is correct.

## M3: Graphics coverage

**Goal:** every common Windows graphics API has a working path.

- [ ] **D3D12 via D3DMetal:** finish `import-gptk.sh`, verify the `WINEDLLPATH` layout, and add a guided import in the app.
- [ ] **D3D12 open fallback:** vkd3d-proton → MoltenVK backend for users without GPTK. Document its limits.
- [ ] **Vulkan-native games:** winevulkan → MoltenVK, tested.
- [ ] **D3D9 and older:** DXVK d3d9, plus wined3d for D3D8/DirectDraw.
- [ ] **OpenGL games:** wined3d/opengl32 on macOS GL 4.1. Document the ceiling.
- [ ] **Auto-detect API:** read the PE import table of the target exe (d3d9/d3d11/d3d12/vulkan-1) to pick a backend when no profile matches.
- [ ] **Per-backend regression tests:** a frame-capture comparison on a fixed test scene.

**Exit:** a test scene renders correctly on D3D9, D3D11, D3D12, and Vulkan through at least one backend each.

## M4: Performance

**Goal:** match or beat CrossOver, and make that measurable.

### Measurement first
- [ ] `tether bench <bottle> <exe>`: runs a game's built-in benchmark or a scripted scene, collects frame times from backend-native stats (Metal Performance HUD logging or DXVK HUD), and outputs avg FPS, p1/p99 frame time, stutter count, CPU%, memory, and launch time.
- [ ] **Benchmark set:** 5–8 titles with built-in benchmarks, covering D3D11, D3D12, and Vulkan.
- [ ] **CI performance tracking:** run on a dedicated self-hosted Apple Silicon machine, store results, and flag regressions over 3%.

### Optimizations
- [ ] **msync** validated under load. Compare against esync and plain wineserver.
- [ ] **QoS:** spawn game processes at `userInteractive` so they land on P-cores. Keep wineserver responsive.
- [ ] **macOS Game Mode** activates for fullscreen games (verify the activation conditions for Wine windows).
- [ ] **Shader caching:** persistent caches per bottle and per backend. Investigate Metal binary archives in DXMT. Cache survives runtime updates when compatible.
- [ ] **Rosetta warm-up:** pre-translate the game binary and its DLLs once after install, so the first launch doesn't pay the AOT cost.
- [ ] **Instant bottles:** keep a pre-initialized template prefix per runtime and create bottles with APFS `clonefile` (copy-on-write) instead of `wineboot --init`. Backend DLL installs use clones too.
- [ ] **Input latency:** raw mouse input in the Wine macOS driver (critical for FPS games), high-polling-rate mice, cursor capture.
- [ ] **Display:** Retina/HiDPI modes, ProMotion and high refresh rates, VSync control, exclusive-fullscreen emulation without mode switching.
- [ ] **Audio:** CoreAudio buffer sizing for low latency without crackle.
- [ ] Raise file-descriptor limits automatically when esync is in use.

**Exit:** the benchmark set meets the 1.0 performance bar, and the results are published in the repo.

## M5: Product UX

**Goal:** a non-technical user never needs Terminal.

- [ ] **First run:** system check (Rosetta install prompt), runtime download, optional GPTK import.
- [ ] **Library view:** games across bottles, with artwork (Steam app ID lookup), play buttons, and last-played times.
- [ ] Run an executable or installer from the app (NSOpenPanel and drag-and-drop onto the window or Dock icon).
- [ ] **One-click launcher setup:** "Install Steam" creates the bottle, downloads the official installer, and runs it.
- [ ] **Shortcuts:** generate small `.app` launchers in `~/Applications/Tether Games` for Dock, Spotlight, and Launchpad.
- [ ] **Bottle tools:** open C: drive in Finder, kill all processes, winecfg, registry editor, reset prefix, duplicate bottle, export and import.
- [ ] **Logs:** a per-launch log viewer, a "Run with debug logging" toggle, and "Copy diagnostics for a bug report."
- [ ] **Settings:** default backend, HUD, storage location, runtime channel (stable or beta).
- [ ] Menu-bar status while games run (optional, zero overhead when off).
- [ ] Accessibility (VoiceOver labels, keyboard navigation) and localization scaffolding.

**Exit:** usability test where 5 people with no Wine experience install Steam and launch a game unassisted.

## M6: Distribution and trust

- [ ] **Embed the pinned runtime in Tether.app** (notarized only if a paid Developer ID is later obtained; until then ad-hoc signed. A stand-in app test showed one Open Anyway approval covers the nested runtime; still to test: a real browser download and a full game launch from the translocated app, see the distribution spike) ([ADR 0005](docs/adr/0005-arm64-wine-with-fex.md), [distribution spike](docs/spikes/distribution.md)). Leave `lib/wine/aarch64-unix/wine.app` untouched (re-signing it loses its provisioning profile); sign the app's other Mach-O files with the hardened runtime. Verify that notarization accepts the nested loader with a real signing identity.
- [ ] **Developer ID signing and notarization** *(deferred: needs a paid Apple Developer Program membership; decided to ship with the Gatekeeper warning for now)* for the app and any binaries Tether adds. Use the hardened runtime with only the entitlements needed, documented in an ADR.
- [ ] **Licence notices:** a first inventory is in [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) (several rows still unverified); add a notices screen and source links.
- [ ] **App updates** via Sparkle 2 (EdDSA-signed appcast). Runtime updates ship with app updates (the embedded runtime is pinned by version and hash); a separate runtime download channel is not planned.
- [ ] **Rollback:** keep the previous runtime and let bottles pin a version.
- [ ] **Bottle schema migrations** (`schemaVersion` exists; add migrators and tests).
- [ ] **Homebrew cask.**
- [ ] **Reproducible builds:** pinned toolchains and documented build hashes.
- [ ] **License compliance:** an SBOM per runtime release, LGPL source links for Wine and its patches, and a third-party notices screen in the app.
- [ ] **Security review** of the launch-policy boundary and the update pipeline.
- [ ] **Uninstall:** a documented, clean removal of all Tether data.

## M7: 1.0

- [ ] **Compatibility database:** a per-title rating (Platinum, Gold, Silver, Bronze, Borked) with runtime, backend, and macOS version, accepting structured community reports (in the style of ProtonDB). Ratings feed back into profiles.
- [ ] ≥ 50 Gold+ titles (see the exit criteria above).
- [ ] Docs site: user guide, troubleshooting, and the profile-authoring guide.
- [ ] Governance: maintainers, release process, issue triage labels (`anti-cheat`, `backend:*`, `game:*`).
- [ ] 1.0 release.

---

## Cross-cutting tracks

### Testing
- Unit tests for every TetherKit change (in place now).
- Integration tests that run real Wine in CI: prefix init, backend install, launch a sample, clean shutdown.
- A compatibility regression suite of free and redistributable titles, re-run on every runtime release.
- Nightly runtime builds against Wine's development branch to catch breakage early.

### Upstreaming and the patch queue
- Send Wine, DXMT, DXVK, and MoltenVK fixes upstream by default.
- Rebase the patch queue once per Wine stable release, and drop patches that have been upstreamed.
- Health metric: the number of `downstream-only` patches. It should trend down.
- When CodeWeavers releases a new CrossOver source tarball, diff it against the previous one and look for new macOS fixes worth taking.

### Anti-cheat (policy, not workarounds)
- Keep [docs/ANTICHEAT.md](docs/ANTICHEAT.md) current per title.
- **Realistic expectations:** Easy Anti-Cheat and BattlEye support Wine through Linux-native Proton modules, and as far as we know have no macOS equivalent. Games that use them will likely refuse to run, and kernel-level anti-cheats (Vanguard, Ricochet, etc.) won't run under Wine at all. Those titles get marked *Unsupported*. Tether won't work around them.
- Ask publishers about official tolerance for compatibility layers where that's realistic.

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Rosetta 2 phase-out.** Apple has said full Rosetta will be available through macOS 27, with only a subset kept for older games after that. | Existential for the x86_64-Wine design | Mitigated by moving to **native arm64 Wine + FEX (ARM64EC)** ([ADR 0005](docs/adr/0005-arm64-wine-with-fex.md), [spike](docs/spikes/arm64-fex.md)). New risks: dependence on FEX and on Apple's cross-architecture entitlement (availability for our team unconfirmed), macOS 26.4+ floor. |
| D3DMetal license or availability changes | Weaker D3D12 support | Keep vkd3d-proton → MoltenVK viable. Contribute to DXMT D3D12 efforts if they emerge. |
| MoltenVK feature gaps (geometry shaders, transform feedback, etc.) | DXVK and vkd3d-proton titles break | Prefer Metal-native backends. Report gaps upstream. |
| Steam client (CEF) breakage after Steam updates | Steam unusable until fixed | Nightly Steam smoke test. Fast runtime patch releases. |
| Anti-cheat policy changes by publishers | Titles become unplayable | Never work around them. Document and mark *Unsupported*. |
| Maintainer bandwidth | Slow progress | Prioritize M1–M2 ruthlessly. Keep the Swift host small. |
