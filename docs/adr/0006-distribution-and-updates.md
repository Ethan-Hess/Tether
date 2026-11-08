# ADR 0006: Distribution: embedded runtime, DMG, Sparkle updates

**Status:** Accepted

## Context
Until now Tether ran only through `swift run`, and its Wine runtime was a separate download. ADR 0005 and the [distribution spike](../spikes/distribution.md) decided to embed the pinned runtime in Tether.app. M6 builds that, and the pieces around it: how the app is packaged and signed, how it updates, how a bottle can go back to an older runtime, how its settings survive upgrades, what a user is told about third-party code, and how to remove it all.

## Decisions

**Packaging.** `scripts/package-app.sh` assembles `Tether.app` from the SwiftPM release build, with no Xcode project. SwiftPM's resource bundle can't sit at an app's root (it breaks signing and its accessor falls back to the build machine's folder), so resources are copied into `Contents/Resources` and `TetherResources` looks there first. The runtime is installed through the existing hash-pinned `tether runtime install` into a cache and copied into `Contents/Resources/EmbeddedRuntimes/<version>`. `RuntimeStore` lists embedded and installed runtimes together; for the same version the embedded copy wins because the app's signature seals it.

**Signing.** Ad-hoc by default; `SIGN_IDENTITY` switches to a real identity with the hardened runtime and also signs the runtime's other Mach-O files. The outer app is signed without `--deep` and `wine.app` is never re-signed (it carries its own provisioning profile and the cross-architecture entitlement). `scripts/verify-app.sh` checks that `wine.app` is byte-for-byte what was downloaded. Notarization is scripted (`NOTARY_PROFILE`) but untested: no Developer ID Application certificate exists, and ad-hoc builds need one "Open Anyway" approval, as the spike showed.

**Delivery.** One DMG (LZMA, about 190 MB for the 1.1 GB app) on a GitHub release.

**Updates.** Sparkle 2, added as a SwiftPM dependency of the app only. Updates are accepted only with an EdDSA signature matching the public key in `Info.plist` (`Packaging/sparkle_public_key.txt`); the private key lives in the maintainer's keychain. The feed is the appcast attached to the latest GitHub release. Because the runtime rarely changes, Sparkle's binary deltas keep updates small. Updates are written by Sparkle without the download quarantine, so "Open Anyway" is needed once, not per update. Builds without a key (or run with `swift run`) have updates disabled rather than erroring.

**Rollback.** The runtime ships with the app, so it can't be kept across updates by copying. Instead, a bottle can pin a runtime version (`BottleConfig.runtimeVersion`, a picker in the bottle's settings), and Settings can install any older catalog version (hash-pinned download). A bottle pinned to a missing runtime says so and offers to install it.

**Settings format.** `BottleMigrator` upgrades `bottle.json` one version at a time before decoding, keeps `bottle.json.v<N>.bak`, writes atomically, refuses files from a newer Tether instead of dropping fields, and leaves the original untouched if a step fails. Unreadable bottles are listed as problems rather than hidden. No migrations exist yet because format 1 is the only released one.

**Notices.** The in-app Notices screen and `Contents/Resources/Notices` come from one catalog (`components.json` and licence texts taken from the upstream repositories). Rows whose licence still rests on package metadata are marked unverified, in the app and in `docs/THIRD-PARTY.md`, instead of being presented as checked.

**Uninstall.** Everything lives under `~/Library/Application Support/Tether` plus preferences; Settings → Remove Tether Data deletes chosen categories, only known folders directly inside the root, never following links, and refuses while anything is running. Documented in `docs/UNINSTALL.md`.

## Consequences
- The app is about 1.1 GB on disk. A release build takes minutes, most of it DMG compression.
- Losing the Sparkle private key strands existing installs; backing it up is part of the release checklist.
- With an ad-hoc signature, updates rely on Sparkle's EdDSA check rather than Apple's identity chain. Moving to Developer ID later changes the signing identity between releases, which Sparkle handles with the same EdDSA key.
- Still open: Developer ID signing and notarization, Homebrew cask, reproducible builds and SBOM, a security review, a game launch from a quarantined download of the DMG, and installing an update through Sparkle's dialogs.
