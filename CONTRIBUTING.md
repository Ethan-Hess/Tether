# Contributing to Tether

Thanks for helping. Please read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/ANTICHEAT.md](docs/ANTICHEAT.md) first. The anti-cheat rules are non-negotiable.

## Setup

```sh
./scripts/bootstrap.sh
swift build
./scripts/test.sh
```

Use `TETHER_HOME=$(mktemp -d)` when experimenting so you don't touch your real bottles.

## Where things go

| Change | Location |
|--------|----------|
| Bottle/runtime/launch logic | `Sources/TetherKit` (no UI imports) |
| CLI commands | `Sources/tether/main.swift` |
| UI | `Sources/TetherApp` (keep logic in TetherKit) |
| Game profile | `Sources/TetherKit/Resources/Profiles/<id>.json` |
| New graphics backend | `Sources/TetherKit/Graphics/Backends.swift` + `runtime/scripts/build-<id>.sh` + add to `GraphicsBackends.all` |
| Wine patches | `runtime/patches/wine/NNNN-description.patch` + entry in `series` (header format: `runtime/patches/wine/README.md`) |
| Design decisions | `docs/adr/NNNN-title.md` |

## Adding a game profile

1. Find a working config with `tether bottle set <name> --backend … --env KEY=VALUE`.
2. Confirm with `tether env <bottle> <exe>` that nothing gets blocked by policy.
3. Add a JSON profile containing only what's needed. Use `notes` for known issues and tested runtime versions.
4. Update the status table in the README.

## Continuous integration

Every pull request runs `.github/workflows/ci.yml`: the test suite on macOS 15 and 26, a release build of every product, a `Tether.app` build checked by `scripts/verify-app.sh`, and linting of the shell scripts, JSON files and workflows. Run the same things locally before pushing:

```sh
./scripts/test.sh
./scripts/package-app.sh --no-runtime && ./scripts/verify-app.sh build/Tether.app
```

Releases are built by `.github/workflows/release.yml` (see [docs/RELEASING.md](docs/RELEASING.md)); you don't need to touch it to contribute.

## Pull requests

- Add or update tests in `Tests/TetherKitTests` for any TetherKit change.
- Keep `LaunchEnvironment` and `OverridePolicy` changes small and well-justified. They're the security boundary.
- Never commit Wine, backend, or GPTK binaries.
- By contributing you agree your work is licensed under LGPL-2.1.
