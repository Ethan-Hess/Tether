# Third-party components in the runtime

What the pinned runtime bundle contains and under which licences, as far as could be verified. This is an engineering inventory, **not legal advice**. Its source of truth for the app is [`Sources/TetherKit/Resources/Notices/components.json`](../Sources/TetherKit/Resources/Notices/components.json) with the licence texts beside it; the app's Notices screen and `Contents/Resources/Notices` are generated from that, and a test checks that every entry has its licence text. Each row says how its licence was established; "unverified" means it must be checked before Tether redistributes the bundle.

Runtime `0.2.0` is Mach9 `arm64-11.20-5` (`athei/mach9`, Wine `wine-11.20-33-g10f3ccc905`). Mach9 builds its components from its own forks, pinned by branch in `pins/*-src.ref` of its repository at that tag.

## Engine components (built by Mach9)

| Component | Source | Licence | How established |
|-----------|--------|---------|-----------------|
| Mach9 own code (compat rules library, loader glue) | [athei/mach9](https://github.com/athei/mach9) | Zlib | Read the repository's `LICENSE` |
| Wine (`arm64-patched`) | [athei/wine](https://github.com/athei/wine) | LGPL-2.1-or-later (Wine's standard licence) | `COPYING.LIB` exists in the upstream mirror `wine-mirror/wine`; the fork's own copy was not checked |
| FEX (`macos-patched`) | [athei/FEX](https://github.com/athei/FEX) | MIT | Detected by GitHub on the fork |
| DXMT (`macos-patched`) | [athei/dxmt](https://github.com/athei/dxmt) | LGPL-2.1-or-later | Read `LICENSE` of the upstream `3Shain/dxmt`; the fork's copy was not checked |
| vkd3d-proton (`macos-patched`) | [athei/vkd3d-proton](https://github.com/athei/vkd3d-proton) | LGPL-2.1 | Detected by GitHub on the fork |
| Mesa, including KosmicKrisp, `libgallium` and EGL/Zink (`macos-patched`) | [athei/mesa](https://github.com/athei/mesa) | MIT for the core; individual files can carry other licences | The fork ships Mesa's `licenses/` folder and `docs/license.rst` ("licensed according to the terms of the MIT license"); GitHub's detector found none, which is why this row used to be unverified |

## Libraries in `lib/external`

| Library | Licence | How established |
|---------|---------|-----------------|
| FFmpeg: `libavcodec`, `libavformat`, `libavutil`, `libavfilter`, `libswresample` | LGPL version 2.1 or later | Read from the shipped dylibs (each reports `license: LGPL version 2.1 or later`); Mach9's `build-gstreamer.sh` also states GPL code is disabled |
| GStreamer (`libgst*`, 1.28.x), glib, gobject, gio, gmodule | LGPL-2.1-or-later | Read `COPYING` in the upstream GStreamer and GLib repositories (LGPL 2.1) |
| libffi, libbrotli | MIT | Read `LICENSE` in the upstream repositories |
| libintl (gettext runtime) | **unverified** (LGPL-2.1-or-later expected) | Not established |
| Vulkan loader (`libvulkan`) | Apache-2.0 | Read `LICENSE.txt` in KhronosGroup/Vulkan-Loader |
| FreeType | FTL (or GPL-2.0-or-later; Tether relies on the FTL) | Read `docs/FTL.TXT` upstream; matches Homebrew's metadata |
| gnutls | LGPL-2.1-or-later (the formula also lists GPL-3.0-only, presumably for its command-line tools, not the library) | Read `COPYING.LESSERv2` upstream; Homebrew formula metadata |
| nettle / hogweed | GPL-2.0-or-later OR LGPL-3.0-or-later | Read `COPYING.LESSERv3` upstream; Homebrew formula metadata |
| GMP | LGPL-3.0-or-later OR GPL-2.0-or-later | Homebrew formula metadata |
| libidn2 | multi-licence (GPL-2.0-or-later OR LGPL-3.0-or-later, plus Unicode terms and others) | Homebrew formula metadata |
| p11-kit | BSD-3-Clause | Read `COPYING` upstream |
| libtasn1 | LGPL-2.1-or-later | Homebrew formula metadata |
| libunistring | GPL-2.0-or-later OR LGPL-3.0-or-later | Homebrew formula metadata |
| libpng | libpng-2.0 | Read `LICENSE.md` upstream |
| SDL2 (via sdl2-compat) and SDL3 | Zlib | Read `LICENSE.txt` upstream |

Caveats for the Homebrew rows: Mach9 builds against whatever Homebrew has at build time (`pins/brew-formulae` lists names, not versions), so the versions shipped may differ from the stable versions on a given Mac today. Licences were taken from Homebrew's metadata, not from the library sources. For the dual-licensed libraries (nettle, GMP, libunistring, libidn2) Tether would rely on the LGPL option.

## Status after M6
- Licence texts for every component are shipped with the app and shown in Notices, with a link to the source (the pinned Mach9 release for the runtime build).
- Still unverified, because the licence rests on package metadata and the standard text was not checked against the shipped source: **GMP, libidn2, libintl, libtasn1, libunistring** (all expected to be LGPL; the app marks them with a question mark).
- Still open: exact library versions read from the shipped dylibs (the catalog lists versions only where they are known), and a written source offer if counsel advises one.

## What redistribution will need (to be confirmed)
- Include the licence text and copyright notices for each component in the app (a notices screen), and link to the corresponding source: the pinned Mach9 forks above and the upstream projects for the libraries.
- Keep the LGPL libraries as separately replaceable dynamic libraries, as the bundle ships them today.
- Resolve every "unverified" row above, and record the exact library versions from the dylibs rather than from Homebrew's current formulae.
- Mach9's `licenses/` directory holds only an icon-font licence belonging to its own launcher app, which Tether does not ship.
