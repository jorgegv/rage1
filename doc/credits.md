# Credits & Third-Party Attributions

RAGE1 (Retro Adventure Game Engine, release 1) depends on, vendors, or
links against several third-party libraries and tools. This document
records the upstream provenance, authorship, licence, and pinned
version (where applicable) for each one.

If you ship a binary built with RAGE1 you must comply with the
licences of every vendored / linked component listed below. In
particular, LGPL components require that the user be able to relink
your binary against a modified version of the library; the simplest
way to satisfy this is to publish your source tree alongside the
binary.

---

## Engine authorship

RAGE1 is written and maintained by Jorge González Villalonga.
Repository: <https://github.com/jorgegv/rage1>

---

## Vendored third-party libraries (git submodules under `external/`)

### SP1 sprite library

- **Component**: SP1 (Sprite Pack 1) sprite engine for the ZX Spectrum.
- **Provenance**: Bundled with z88dk (`<arch/zx/sp1.h>`); not a
  submodule but a hard dependency of every ZX build.
- **Author(s)**: Alvin Albrecht (original author), z88dk team.
- **Licence**: z88dk Clarified Artistic License (per z88dk LICENCE
  files).
- **URL**: <https://github.com/z88dk/z88dk>

### JSP sprite library

- **Component**: JSP, an alternative sprite engine used by `gfx_jsp.c`.
- **Path in tree**: `external/jsp/` (git submodule).
- **Author(s)**: Jorge González Villalonga.
- **Licence**: see `external/jsp/LICENSE`.
- **URL**: <https://github.com/jorgegv/jsp>

### cpctelera (submodule removed — translated primitives retained)

- **Component**: cpctelera — engine + low-level library for the
  Amstrad CPC family. RAGE1 no longer vendors cpctelera as a submodule.
  A small set of its low-level hardware-I/O primitives was **hand-translated**
  from `sdas` to z88dk `z80asm` and lives permanently in-tree under
  `engine/src/cpc/` (`cpct_video.asm`, `cpct_gfx_m1.asm`, `cpct_strings_m1.asm`,
  `cpct_keyboard.asm`). Those files compile standalone under z88dk with **no
  cpctelera library dependency**; their cpctelera attribution / credit headers
  are kept verbatim.
- **Status**: The `external/cpctelera/` git submodule was **removed in
  Phase 4J R10** (reference-only, never compiled), together with the interim
  `gfx_cpctel` graphics backend and the `cpct_img2tileset` host asset converter.
  RAGE1's CPC graphics engine is now JSP (see
  `doc/multiplatform-plan/cpc-renderer.md`): byte-aligned CPC sprite libraries
  cannot do 1-px horizontal movement, which is why a realtime-shift engine (JSP)
  was chosen instead. Only the translated `engine/src/cpc/` primitives remain.
- **Pinned commit (when vendored)**: `662fc885adc3301205c87d2cd89462d67a64d809`
  (upstream `development` branch; tag base `v1.3.2-1322-g662fc885`) — the commit
  the `engine/src/cpc/` translations were derived from.
- **Author(s)**: Francisco Gallego-Durán (ronaldo / FremosCPM) and
  the cpctelera contributors.
- **Licence**: GNU Lesser General Public License v3.0 (LGPL-3.0). The
  per-file LGPL-3.0 attribution headers in `engine/src/cpc/` carry the
  licence for the retained translated code.
- **URL**: <https://github.com/lronaldo/cpctelera>

### Arkos Tracker 2 / AKG player

- **Component**: AKG (Arkos Tracker 2 generic / "Arkos 2 Keyframed
  Generic") music + SFX player routine, used by RAGE1's ZX and CPC AY
  audio backends.
- **Path in tree**: `engine/banked_code/audio/arkos2_player.asm` — a single
  canonical in-tree copy (translated to z88dk `z80asm`), shared by the ZX
  (`audio_zx_ay`) and CPC (`audio_cpc_ay`) backends via per-hardware wrapper
  `.inc` files. No longer vendored inside the (R10-removed) cpctelera submodule.
- **Author(s)**: Julien Névo (Targhan) — Arkos Tracker 2 team.
- **Licence**: see the AT2 player licence (typically free for non-commercial
  use; check upstream before shipping a commercial title).
- **URL**: <https://www.julien-nevo.com/arkostracker/>
- **Status**: RAGE1 links the AKG player (Phase AU4/AU5): ZX 128K AY music +
  SFX, and CPC AY via the 8255 PPI. The Spectrum branch is byte-for-byte the
  pre-move single-file player.

---

## Toolchain (build-time only — not redistributed in binaries)

- **z88dk**: C cross-compiler and standard library, used as the
  RAGE1 build driver. <https://github.com/z88dk/z88dk>
- **SDCC**: C compiler backend, used by z88dk (`zcc ... -compiler=sdcc`).
  <http://sdcc.sourceforge.net/>
- **z88dk-zx0**: ZX0 compressor for datasets / codesets.
- **Perl 5** + CPAN modules (`Data::Compare`, `List::MoreUtils`, `GD`,
  `YAML`, `Algorithm::FastPermute`, `Digest::SHA1`) for `tools/datagen.pl`,
  `tools/mapgen.pl`, `tools/banktool.pl`, etc.
- **bas2tap**: BASIC loader → TAP conversion.

These tools are invoked at build time only and are not statically
linked into shipped binaries; their respective licences therefore do
not propagate to the game artefacts.

---

## Updating this file

When adding, removing, or bumping a vendored third-party component:

1. Update the corresponding section above (including the pinned
   commit / version).
2. Confirm the upstream licence file is preserved in-tree
   (`external/<component>/LICENSE` or equivalent).
3. Cross-reference the change in the relevant phase doc under
   `doc/multiplatform-plan/`.
