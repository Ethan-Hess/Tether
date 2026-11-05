# Tether

**Run Windows games on Apple Silicon Macs. Open source, low overhead, and no tricks.**

Tether is an open-source alternative to CrossOver for macOS. It pairs a native Swift/SwiftUI app with a curated [Wine](https://www.winehq.org/) runtime and Metal-native DirectX translation, so you can run Windows games and launchers like Battle.net in isolated "bottles."

> [!WARNING]
> **Pre-alpha.** The app, CLI, bottle management, and launch pipeline are scaffolded and tested, but there is no prebuilt Wine runtime yet, so it can't run games out of the box. See [Roadmap](#roadmap).

## Goals

1. **Minimal translation overhead.** Use the shortest path from DirectX to Metal (DXMT or D3DMetal, with no Vulkan hop where possible), Mach-semaphore sync (msync), persistent shader caches, and no logging in release launches.
2. **Behave like a plain compatibility layer.** Tether never injects into, hooks, or patches a game process, and never spoofs or hides anything. Online games see exactly what every Proton or CrossOver user runs: Wine plus standard translation DLLs. This is a deliberate design constraint, enforced in code. See [docs/ANTICHEAT.md](docs/ANTICHEAT.md).
3. **Native and boring.** A small Swift app with no Electron, no background daemons, and no telemetry.

## How it works

```
 Tether.app / tether CLI          (Swift: bottles, profiles, launch planning)
          │  posix_spawn + environment only. Never in the game's address space.
          ▼
 Wine (x86_64, translated by Rosetta 2; wow64 for 32-bit)
          │
          ▼
 Graphics backend (pluggable, chosen per game)
   ├─ DXMT        D3D10/11 → Metal                 (default for D3D11)
   ├─ D3DMetal    D3D11/12 → Metal                 (Apple GPTK, user-supplied)
   ├─ DXVK        D3D9–11 → Vulkan → MoltenVK → Metal
   └─ wined3d     → OpenGL                         (last resort)
          │
          ▼
 Metal / macOS
```

The full design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Apple Silicon Mac (M1 or newer)
- macOS 14 Sonoma or newer
- Rosetta 2 (`softwareupdate --install-rosetta`)
- Xcode 16+ or the Swift 6 command line tools, to build

## Quick start (developers)

```sh
git clone https://github.com/Ethan-Hess/Tether.git
cd Tether
./scripts/bootstrap.sh        # checks toolchain, Rosetta, build deps
swift build
./scripts/test.sh             # runs the test suite (works with the CLT or Xcode)

swift run tether doctor       # check this Mac
swift run tether bottle create Battle.net --profile battlenet
swift run tether bottle list
swift run TetherApp           # SwiftUI app
```

Once a runtime is installed (see [runtime/README.md](runtime/README.md)):

```sh
swift run tether run Battle.net ~/Downloads/Battle.net-Setup.exe
swift run tether env Battle.net 'C:\Program Files (x86)\Overwatch\_retail_\Overwatch.exe'   # inspect the exact launch env
```

Set `TETHER_HOME=/some/dir` to keep bottles and runtimes somewhere other than `~/Library/Application Support/Tether`.

## Game profiles

Profiles are small JSON files that choose a backend order, sync mode, Windows version, and safe tweaks for a game. Built-in profiles live in [Sources/TetherKit/Resources/Profiles](Sources/TetherKit/Resources/Profiles). User profiles in `~/Library/Application Support/Tether/Profiles` override them by `id`.

```json
{
  "id": "overwatch",
  "name": "Overwatch 2",
  "executables": ["Overwatch.exe"],
  "backendPreference": ["dxmt", "d3dmetal", "dxvk"],
  "sync": "msync",
  "windowsVersion": "win10"
}
```

Profiles can't override arbitrary DLLs or set injection-capable variables (`DYLD_*`, `WINEDLLOVERRIDES`, and others). The launcher drops those and warns about them.

| Game / app  | Profile     | Status      |
|-------------|-------------|-------------|
| Battle.net  | `battlenet` | Untested    |
| Overwatch 2 | `overwatch` | Untested    |

## Anti-cheat

Short version: Tether makes no attempt to evade anti-cheat, and its architecture makes evasion impossible to add by accident. It runs games unmodified in a clean prefix, with nothing injected. Whether a publisher allows play through a compatibility layer is their call, so check their policy. Details are in [docs/ANTICHEAT.md](docs/ANTICHEAT.md).

## Roadmap

- [x] Bottle management, game profiles, launch-environment planning (TetherKit)
- [x] `tether` CLI and SwiftUI app skeleton
- [x] Override and environment policy enforcement, with tests
- [ ] Reproducible runtime build: Wine + msync patches, DXMT, DXVK, MoltenVK ([runtime/](runtime/))
- [ ] Runtime download and update from GitHub Releases, with signature verification
- [ ] App: run executable, installers, shortcuts, per-game launch buttons
- [ ] GPTK import flow in the app
- [ ] Shader cache pre-warming, Rosetta AOT warm-up
- [ ] Signed and notarized `.app` builds

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Design decisions are recorded in [docs/adr](docs/adr).

## Credits

Tether is glue. The hard work is done by:
[Wine](https://gitlab.winehq.org/wine/wine) (including CodeWeavers' extensive upstream contributions),
[DXMT](https://github.com/3Shain/dxmt),
[DXVK](https://github.com/doitsujin/dxvk),
[MoltenVK](https://github.com/KhronosGroup/MoltenVK),
[vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton),
Apple's [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/),
and prior art from [Whisky](https://github.com/Whisky-App/Whisky).

## License

[LGPL-2.1](LICENSE), the same license as Wine. Bundled components keep their own licenses. Apple's D3DMetal is **not** redistributed: you import it from your own Game Porting Toolkit download.

Tether is not affiliated with CodeWeavers, Apple, Blizzard, or any game publisher. CrossOver is a trademark of CodeWeavers, Inc.
