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

## Options for delivery
| Option | Notes |
|--------|-------|
| **A. Embed the pinned runtime in a notarized Tether.app** (recommended for 1.0) | Matches Mach9.app. Notarization covers the nested loader and the app signs the other Mach-O files. Runtime updates ship with app updates. Cost: a larger app (about 1 GB unpacked), and notarization tooling work in M6. |
| B. Download on demand, unquarantined (current) | Works today and keeps the app small. Runs unnotarized third-party code outside notarization, breaks if anything quarantines it, and depends on Gatekeeper's current behaviour for non-quarantined files. |
| C. Download, then strip quarantine after hash verification | Technically possible, but it means Tether overriding a Gatekeeper check on unnotarized code. Not recommended without an explicit decision. |

## Recommendation
Plan M6 around option A and keep `tether runtime install` for development and for runtime rollback testing. Until then, document that the runtime must not be quarantined. Add a check to `tether doctor` that flags a quarantine attribute on an installed runtime, since the failure is otherwise a confusing dialog.

## Open items
- Delivery decision (above), for the user.
- Licence and version inventory for the bundle.
- Whether a Tether.app that embeds the bundle notarizes cleanly (needs a test with a real signing identity, which we don't have in this environment).
