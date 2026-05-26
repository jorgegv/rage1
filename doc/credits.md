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

### cpctelera

- **Component**: cpctelera — engine + low-level library for the
  Amstrad CPC family, used by RAGE1's CPC renderer backend
  (Phase R / Phase 3 of the cross-platform plan).
- **Path in tree**: `external/cpctelera/` (git submodule).
- **Pinned commit**: `662fc885adc3301205c87d2cd89462d67a64d809`
  (on upstream `development` branch; tag base `v1.3.2-1322-g662fc885`).
- **Author(s)**: Francisco Gallego-Durán (ronaldo / FremosCPM) and
  the cpctelera contributors.
- **Licence**: GNU Lesser General Public License v3.0 (LGPL-3.0). See
  `external/cpctelera/LICENSE` for the full text.
- **URL**: <https://github.com/lronaldo/cpctelera>

### Arkos Tracker 2 / AKG player

- **Component**: AKG (Arkos Tracker 2 generic / "Arkos 2 Keyframed
  Generic") music + SFX player routines, used indirectly via
  cpctelera's AT2 wrapper for CPC audio playback.
- **Path in tree**: vendored inside `external/cpctelera/` (see
  cpctelera's own attribution and licence headers for the exact
  source files).
- **Author(s)**: Julien Névo (Targhan) — Arkos Tracker 2 team.
- **Licence**: see the headers of the AT2 source files distributed
  by cpctelera (typically free for non-commercial use; check upstream
  before shipping a commercial title).
- **URL**: <https://www.julien-nevo.com/arkostracker/>
- **Status**: **Placeholder attribution.** RAGE1 does not yet link
  the AKG player; this entry is recorded here per the Phase R1 plan
  (see `doc/multiplatform-plan/cpc-renderer.md` § R1-3) and **must be
  verified and tightened in Phase AU5** (audio.md) when the audio
  backend actually integrates cpctelera's AT2 wrapper.

---

## Toolchain (build-time only — not redistributed in binaries)

- **z88dk**: C cross-compiler and standard library, used as the
  RAGE1 build driver. <https://github.com/z88dk/z88dk>
- **SDCC**: C compiler backend, used by z88dk and also bundled inside
  cpctelera for prebuilding its `.lib`. <http://sdcc.sourceforge.net/>
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
