# Wine patch queue

Tether builds upstream Wine (pinned stable tag) plus the patches in this directory, applied in the order listed in [`series`](series). Background and rules are in [ADR 0004](../../../docs/adr/0004-upstream-wine-with-patch-queue.md).

## Layout

```
runtime/patches/wine/
  series                          # one patch filename per line, in apply order; '#' comments allowed
  README.md
  0001-msync-....patch
  0002-macdrv-....patch
```

Number patches in apply order. Group related patches (e.g. the msync series) under consecutive numbers.

## Required header

Every patch starts with this header, above the `git format-patch` output:

```
Tether-Origin: crossover | proton | staging | tether
Tether-Source: <URL or source tarball + path the patch came from>
Tether-Upstream: upstreamed | submitted <merge-request URL> | downstream-only
Tether-Reason: <required if downstream-only: why this can't go upstream>
Tether-Bench: <optional: tether bench result showing the effect, required for performance patches>
```

## Checking the queue

Run `runtime/scripts/build-wine.sh --prepare-only` before committing a patch. It validates headers, rejects patch files missing from `series`, and applies the whole queue to the pinned tag.

## Rebase procedure (once per Wine stable release)

1. Bump the pinned tag in `runtime/scripts/build-wine.sh`.
2. Drop every patch marked `upstreamed` that is in the new tag.
3. Re-apply the rest. Refresh any that conflict and note the refresh in the commit message.
4. Run the smoke tests and the benchmark set. Compare against the previous runtime.

## Reusing third-party code

### Licenses
- **CrossOver** (CodeWeavers' published source tarballs) and **Proton's Wine fork** are LGPL-2.1, so they're compatible with Tether. Check the license header of each file you take, because not everything in a tarball is necessarily LGPL. Keep all copyright notices.
- **Never take:** the CrossOver app, its bottle tooling, or CrossTie installer recipes (proprietary); CrossOver branding (trademark); or D3DMetal (Apple's, and not redistributable).
- **Whisky** is GPL-3.0 (verify in its repo). Copying its code into Tether would make the combined work GPL-3.0, so use it as a reference only.
- **Source availability:** every runtime release must ship with, or link to, the exact Wine source it was built from (the upstream tag plus this patch queue).

### Extracting a CrossOver patch
1. **Check upstream first.** CodeWeavers sends much of its work upstream, so the fix may already be in the pinned tag.
2. Find the upstream Wine tag the CrossOver release is based on, and diff the tarball's `wine/` tree against that tag.
3. Extract **one feature per patch** (e.g. msync, a `winemac.drv` fix), never the whole diff.
4. Add the header with `Tether-Origin: crossover` and `Tether-Source: crossover-sources-<version>.tar.gz:<path>`.
5. Performance patches need a `Tether-Bench` result before merge.

### Priorities
1. **msync** (synchronization overhead)
2. **`winemac.drv` fixes:** Retina, fullscreen, cursor capture, and raw mouse input
3. **D3DMetal loading glue** (the Wine side is LGPL even though D3DMetal isn't). This resolves the TODO in `D3DMetalBackend`.
4. **Game-specific fixes**, only when a tested game needs one.

Skip the old 32-bit-on-64 approach ("wine32on64"). Tether uses upstream wow64.

## Rules

- Compatibility, performance, and macOS-integration fixes only. Never anything that hides Wine or changes what games can observe about the system ([docs/ANTICHEAT.md](../../../docs/ANTICHEAT.md)).
- Prefer configure flags over patches for disabling features.
- Keep the `downstream-only` count low. It's the health metric for this queue.
