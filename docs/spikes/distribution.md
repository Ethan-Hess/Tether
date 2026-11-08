# Spike: distributing the wrapped runtime

Date: 2026-11-05. Host: macOS 26.6.2. Runtime under test: Mach9 `arm64-11.19-1` (`athei/mach9`, formerly `athei/wine-build`). Sources: Mach9's README, `docs/internals.md`, `docs/maintenance.md`, `compatdb/core` rustdoc, local `codesign`/`spctl` checks, and one Gatekeeper experiment. Not legal advice.

## Questions
1. Can Tether ship this runtime without its own Apple entitlement?
2. Is it notarized, and what happens if macOS quarantines it?
3. Can a launcher choose the graphics backend, which would resolve the "forced backend ignored" limitation?
4. What licence work is needed before redistributing?

## Findings

### 1. Entitlement: not needed to embed
Mach9 says its engine is "made to be embedded in a launcher". The loader (`lib/wine/aarch64-unix/wine.app`) needs `com.apple.developer.cross-architecture-support`, which macOS honours only through an embedded provisioning profile and a signature from that profile's team. Its docs state: "An app that embeds the bundle leaves `wine.app` as it is: re-signing it or editing its `Info.plist` loses the profile or breaks the signature." The embedding app signs the other Mach-O files with the hardened runtime for notarization. So wrapping needs no entitlement of ours. Building our own loader would.

### 2. Notarization and quarantine
- `codesign --verify --deep --strict` on the installed `wine.app` passes; it has the hardened runtime flag and a secure timestamp, which notarization requires.
- `spctl -a -vvv -t exec` reports **rejected: Unnotarized Developer ID**, and `stapler validate` finds no ticket. Mach9's README says the Mach9.app that embeds it is notarized, i.e. notarization is at the app level.
- **Experiment:** I copied the runtime, set `com.apple.quarantine` on the copy (as a browser download or Archive Utility would) and ran `bin/wine --version`. macOS showed "Apple could not verify 'wine.app' is free of malware" (Move to Trash / Done) and the command hung behind the dialog. The installed copy, which has no quarantine attribute because `URLSession` does not set one, runs normally.
- **Consequence:** download-on-demand works only while nothing quarantines the files. Anything that does (a browser download of the tarball, an unzip tool, AirDrop, an app that opts in to quarantine) turns it into a blocked app with a confusing dialog. Embedding the runtime in a notarized Tether.app avoids that.

### 3. Backend choice: possible through `WINE_COMPATDB`
The runtime loads `compatdb.so` into every Wine process. It reads rules from `WINE_COMPATDB` (and `WINE_COMPATDB_FILE`), one line per rule, `key=value` fields joined by `;`:

```
exe=*;dxgi=wined3d
exe=steam:2357570;dxgi=dxmt
exe=Game.exe;d3d9=wined3d;metal_hud=true
```

- `dxgi` takes `dxmt` or `wined3d`; `d3d9` takes `mtld3d` or `wined3d`. `gptk` is a retired value (a warning).
- `exe` matches the image name, `*`, or `steam:<appid>`, which matches any process whose `SteamAppId` environment value is that app, whatever its name.
- A game started by an already-running program (Steam) inherits that program's `WINE_COMPATDB`. Rules that must change while Steam runs go in a file named by `WINE_COMPATDB_FILE`, set in the environment the root process starts with and replaced atomically (write a temp file, rename over it).
- Rules can also carry `arguments`, `env`, `dll_overrides` and more. Tether should emit only the backend keys and `metal_hud`, to keep ADR 0003's boundary.
- The upstream advice is to write rules with its Rust crate's `Display` rather than by hand. Tether is Swift, so it needs a small emitter covered by tests against the documented examples.
- My earlier "can't force a backend" conclusion was wrong. I had tried `WINE_COMPATDB` values (`off`, `0`, a bogus path) that are not valid rules, and a lenient parser ignores them.

### 4. Licences
- Mach9's own code: Zlib (`LICENSE`). Its `licenses/` directory holds only an icon-font licence.
- The installed bundle contains **no licence or notice files**.
- Bundled third-party libraries seen in `lib/external`: SDL2/SDL3, freetype, GMP, gnutls, nettle (`libhogweed`), libidn2, libintl, p11-kit, libpng, libtasn1, libunistring, the Vulkan loader and KosmicKrisp (Mesa). Wine is LGPL and FEX is MIT (the latter per MetalSharp's notes, not checked at the source); DXMT's licence has not been checked. Several of these libraries are LGPL, which needs notices and a source offer.
- Open: collect the exact versions and licence texts from the release (or Mach9's pins), and decide how the app shows them (a notices screen, plus source links).

## Update: Mach9 `arm64-11.20-5` (2026-11-05)
Everything above was measured on the first pinned release, `arm64-11.19-1`. The newer `arm64-11.20-5` (catalog runtime `0.2.0`) differs in two ways that matter here.

- **Its loader is notarized.** `codesign --verify --strict` passes, the hardened runtime flag, a secure timestamp (2026-10-30) and the cross-architecture entitlement are present, and `spctl -a -vvv -t exec` reports **Notarized Developer ID** (the old release said Unnotarized). I did not check whether a ticket is stapled.
- **A quarantined copy is not blocked.** I copied the runtime, set `com.apple.quarantine` on every file and ran `bin/wine --version`: no dialog, correct output (`wine-11.20-33-g10f3ccc905`). The first launch took 27 seconds, which I take to be macOS's online notarization check; a second launch took under a second. The quarantine attribute was unchanged afterwards.
- **It supports compat rules.** `WINE_COMPATDB_FILE` and `steam:<appid>` rules appear in its docs and release notes and worked in testing (see ADR 0005). `arm64-11.19-1` has neither, and the docs at the `11.19-3` and `11.20-1` tags don't mention the file variable; I did not check `11.19-2`, `11.20-2`, `-3` or `-4`.
- **Effect on the findings above:** the "blocked by Gatekeeper" result and the stand-in app experiment describe `11.19-1`. With `11.20-5`, download-on-demand also looks viable, since a quarantined loader runs. The delivery decision (embed in Tether.app) is unchanged for now and can be revisited; `tether doctor` no longer reports quarantine as a problem for a runtime with a notarized loader.
- **Not tested:** the first launch with no network (the notarization check needs Apple's servers), and the stand-in app flow with this release.

## Options for delivery
| Option | Notes |
|--------|-------|
| **A. Embed the pinned runtime in a notarized Tether.app** (recommended for 1.0) | Matches Mach9.app. Notarization covers the nested loader and the app signs the other Mach-O files. Runtime updates ship with app updates. Cost: a larger app (about 1 GB unpacked), and notarization tooling work in M6. |
| B. Download on demand, unquarantined (current) | Works today and keeps the app small. Runs unnotarized third-party code outside notarization, breaks if anything quarantines it, and depends on Gatekeeper's current behaviour for non-quarantined files. |
| C. Download, then strip quarantine after hash verification | Technically possible, but it means Tether overriding a Gatekeeper check on unnotarized code. Not recommended without an explicit decision. |

## Decision
Option A, confirmed by the project owner: embed the pinned runtime in Tether.app for 1.0. Notarization is deferred: there is no paid Apple Developer ID, and the owner accepts the Gatekeeper warning (Open Anyway) for now. An ad-hoc signed app needs no Apple account.

**Risk of shipping unnotarized, now tested:** the runtime nested inside the app carries its own quarantine attribute, and an unapproved quarantined `wine.app` is blocked. The stand-in app experiment below shows that approving the outer app also covers the nested runtime.

### Stand-in app experiment (2026-11-05, macOS 26.6.2)
- **Setup:** an ad-hoc signed `Standin.app` embedding a copy of the runtime under `Contents/Resources/runtime`. I signed the outer app only (no `--deep`), and checked that the nested `wine.app` kept its upstream Developer ID signature. I set `com.apple.quarantine` (`0081`) on every file in the tree, as an extracted download would have. The app spawns the embedded `bin/wine --version` and records the outcome.
- **Steps:** double-click, which showed "Apple could not verify 'Standin.app' is free of malware"; then System Settings, Privacy & Security, Open Anyway.
- **Result:** wine ran (`wine-11.19-17-ge2e42653b41`, exit 0) with no second prompt. The app ran from an App Translocation path (`/private/var/folders/…/AppTranslocation/…/Standin.app`). Afterwards both the outer app and the nested `wine.app` still had the quarantine attribute, with its flags changed from `0081` to `00c1`, i.e. the user-approved bit was set on the nested runtime too.
- **Conclusion:** shipping an unnotarized, ad-hoc signed Tether.app with the runtime embedded works with one "Open Anyway" approval, and no workaround for the nested runtime is needed.
- **Not tested:** a real browser-downloaded zip or dmg (I set the attribute by hand on every file), moving the app to /Applications, running a game rather than `wine --version` from the translocated read-only location, and other macOS versions or Macs. Keep `tether runtime install` for development and for runtime rollback testing, and have `tether doctor` flag a quarantine attribute on an installed runtime, since the failure is otherwise a confusing dialog.

## Open items
- ~~Licence and version inventory for the bundle.~~ Done for licences (see [THIRD-PARTY.md](../THIRD-PARTY.md); five rows still unverified, versions only where known). Built in M6 ([ADR 0006](../adr/0006-distribution-and-updates.md)).
- Whether a Tether.app that embeds the bundle notarizes cleanly (needs a test with a real signing identity, which we don't have in this environment). `scripts/package-app.sh` and `release.sh` are written for it (`SIGN_IDENTITY`, `NOTARY_PROFILE`) but have not been run.
- Done in M6 for the ad-hoc case: `scripts/package-app.sh` embeds the runtime, signs the outer app without `--deep`, and `scripts/verify-app.sh` shows `wine.app` is byte-identical to the verified download and the app resolves it. The embedded `wine --version` runs from inside the app. Still untested: a game launched from a quarantined, browser-downloaded DMG.
