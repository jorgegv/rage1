# CPC renderer library: vendoring + integration

This document is the **library-selection and vendoring plan** for the Amstrad
CPC graphics backend of cross-platform RAGE1. It picks the library, audits
its licence, defines the submodule layout and how its runtime gets built
into RAGE1, covers the library-specific asset converters, and proposes a
phased integration plan.

It sits inside the wider multi-platform plan:

- The HAL surface that this backend implements (`gfx_*` API, including any
  audit changes to remove ZX assumptions) is owned by `gfx.md`. This
  document only assumes such a surface exists and that the CPC backend
  file is `gfx_cpc.c` (paralleling the existing `engine/src/gfx_sp1.c` and
  `engine/src/gfx_jsp.c`).
- The general asset pipeline (shared `.gdata` core, per-platform overlays,
  `datagen.pl` / `mapgen.pl` / `btilegen.pl` changes) is owned by
  `assets.md`. Here we cover only the **library-specific** asset
  converters (`cpct_img2tileset`, `cpct_img2sprites`).
- The platform/build matrix, per-platform `Makefile-cpc-flat` /
  `Makefile-cpc-banked`, BASIC loader,
  and CDT/DSK packaging are owned by `toolchain.md`. This document
  covers only the **library-specific** toolchain bits (SDCC version,
  build-system collision avoidance, link-time integration).
- Banking, audio and input are owned by `banking.md`, `audio.md` and
  `input.md` respectively. We note in passing what cpctelera covers in
  those areas (it is a full framework, not just a renderer), but defer
  real design there.

### JSP precedent

The repo already establishes the "vendor an external Z80 graphics library
as a git submodule under `external/<libname>` and wire it into the build
via `Makefile.common`" pattern via JSP. Concretely:

- `.gitmodules` declares `external/jsp` pointing at
  `https://github.com/jorgegv/jsp.git`, branch `main`.
- `Makefile.common:127-134` sets `JSP_DIR = external/jsp` and, when the
  feature flag is on, pulls `external/jsp/lib/*.c` into `CSRC`,
  `external/jsp/lib/*.asm` into `ASMSRC`, and adds `external/jsp/include`
  to the include path. The library is compiled inline by the host
  toolchain (`zcc +zx`) with no subbuild.
- Vendoring commit `cc8e942` ("jsp: vendor JSP sprite library as git
  submodule at external/jsp") changed exactly four files: `.gitmodules`,
  `Makefile.common`, the submodule pointer, and `.github/workflows/`
  (`--recurse-submodules` checkout in CI).
- The HAL-side mapping lives in `engine/src/gfx_jsp.c` + matching header
  `engine/include/rage1/gfx_jsp.h`. The generic `gfx.c`/`gfx.h` dispatch
  to either `gfx_sp1.c` or `gfx_jsp.c` at build time via
  `BUILD_FEATURE_SPRITE_ENGINE_*` macros.

This document proposes following exactly that pattern, with the
adjustments forced by cpctelera being a much larger and more opinionated
library than JSP.

---

## 1. Library survey

Three serious candidates plus one quick disqualification.

### 1.1 cpctelera

- **What**: "Astonishingly fast Amstrad CPC game engine for C developers"
  — a full low-level framework, not just a sprite library.
- **Source / docs**:
  - Repo: `https://github.com/lronaldo/cpctelera`
  - Reference manual: `http://lronaldo.github.io/cpctelera/`
- **Scope**: organised into discrete modules under `cpctelera/src/`:
  - `sprites/` — masked / unmasked / blended sprite blits, flipped
    variants for modes 0/1/2, tile-aligned fast paths (e.g.
    `cpct_drawSprite`, `cpct_drawSpriteMasked`, `cpct_drawSpriteBlended`,
    `cpct_drawTileAligned2x8`)
  - `easytilemaps/` — tilemap rendering for 2x4-byte tiles
    (`cpct_etm_drawTilemap2x4_f`, `cpct_etm_drawTileBox2x4`,
    `cpct_etm_drawTileRow2x4`)
  - `video/` — modes 0/1/2 setup, palette (HW + firmware), VSYNC,
    double-buffering, scrolling
  - `audio/` — Arkos Tracker player (`cpct_akp_musicPlay`,
    `cpct_akp_musicInit`, `cpct_akp_SFXPlay`, fade)
  - `keyboard/` — fast scan + state query (`cpct_scanKeyboard`,
    `cpct_isKeyPressed`)
  - `firmware/` — disable/re-enable firmware, ROM enable/disable,
    interrupt handler hooks
  - `memutils/` — `cpct_memcpy`, `cpct_memset`, `cpct_pageMemory`, banking
    macros
  - `strings/` — ROM-charset string/character draw without firmware
  - `bitarray/` — 1/2/4-bit packed array helpers
  - `random/`, `macros/` — misc utilities
- **Implementation language**: ~86% C, with hot paths (sprite blits,
  tilemap row writers, keyboard scan) in Z80 assembly. Calling
  conventions are SDCC-native, with explicit `__z88dk_callee` /
  `__z88dk_fastcall` annotations on many functions — relevant later.
- **Compiler**: built around **SDCC**, with a private bundled SDCC tree
  (`cpctelera/tools/sdcc-3.6.8-r9946/`) used by default. The
  `__z88dk_callee` and `__z88dk_fastcall` annotations mean the same C
  sources can be compiled by z88dk's patched SDCC (currently 4.3.x as
  of z88dk v2.3/v2.4).
- **Toolchain**: ships a complete build system:
  - `cpct_mkproject` scaffolds a new project tree with a fixed
    `cfg/build_config.mk` + `Makefile` template
  - bundled tools: SDCC 3.6.8, iDSK 0.13, Hex2Bin 2.0, 2cdt, Arkos
    Tracker, an emulator launcher
  - asset converters: `cpct_img2tileset` and `cpct_bin2c` as Bash
    scripts in `cpctelera/tools/scripts/`; **sprite-sheet conversion**
    is provided by the `IMG2SPRITES` Makefile macro in
    `cpctelera/cfg/global_functions.mk`, which wraps `cpct_img2tileset`
    with sprite-oriented flags (it is **not** a separate script). Plus
    `cpct_pack` (RLE/aPLib packer wrapper) and the underlying Img2CPC
    binary by Augusto Ruiz.
  - host OS support: Linux, OSX, Windows-via-Cygwin
- **Licence**: GNU LGPL v3.0 (verified: `LICENSE` file on master is the
  verbatim LGPL-3.0 text from 29 June 2007; the bundled `cpctelera/src/`
  header notes "low-level library, examples and scripts are distributed
  under GNU Lesser General Public License v3"; bundled third-party
  tools under `cpctelera/tools/` carry their own licences).
- **Latest tagged version**: v1.4.2 (16 July 2017).
- **Maintenance**:
  - master HEAD as of late May 2026 is a commit dated **6 May 2026**
    ("Bugfix: fix misaligned `dc_mode1_ct` carry computation closes
    #193") — i.e. master is alive but rarely touched.
  - Between that and the previous master commit (Feb 2023) the project
    was effectively dormant on master for 3 years.
  - The `development` branch carries 2200+ commits and the in-tree
    `v1.5/dev` version marker, but its most recent commit is dated
    **12 November 2025** — i.e. ~6 months stale at review time. There
    is no announced "in-flight v1.5 release"; the marker is a long-
    running internal label, not an active release line.
  - Issues from 2024 and 2025 are open; triage activity is sporadic.
  - Community: ~250 GitHub stars, ~60 forks; active references on
    CPCWiki and cpcrulez.
- **Verdict**: by far the most complete and well-documented option;
  fits the "vendor an external library" mandate; comes with the
  awkwardness of being a framework rather than a plain library.

### 1.2 Alternatives (brief)

#### 1.2.1 CPCRSlib

- **What**: a sprite + tilemap + sound library for Amstrad CPC.
- **Source**: `https://github.com/cpcitor/cpcrslib` (Git mirror of the
  original SourceForge project, cleaned history).
- **Author**: Artaburu (Raúl Simarro), repo imported by cpcitor.
- **Language**: ~93% Z80 assembly, ~6% C — almost entirely asm.
- **Compiler**: targets both z88dk and SDCC.
- **Scope**: sprites, tile maps, sound (AY) and keyboard — narrower than
  cpctelera, comparable to SP1+beepfx scope on Spectrum.
- **Licence**: MIT.
- **Maintenance**: no GitHub releases, very low recent activity, small
  community presence. Historically used in some published games and
  referenced by CPCtelera v1.4 release notes as a third-party option.
- **Verdict**: licence is friendlier (MIT < LGPL < GPL) and the surface
  is closer to what RAGE1 needs, but the asm-heavy implementation, lack
  of asset-conversion tooling, lack of audio beyond a small AY player,
  and weak documentation make the integration cost similar to or worse
  than cpctelera while delivering fewer features. Realistically a
  fallback, not a contender.

#### 1.2.2 z88dk built-in CPC support (`+cpc` target)

- **What**: z88dk's own platform target for the Amstrad CPC, paralleling
  `+zx`.
- **Scope**: native math + floating point, file I/O via the CAS_
  interface, `appmake` for `.dsk` / `.cdt` / `.sna`, a generic graphics
  library, and conio/console drivers. It does **not** ship an SP1-
  equivalent sprite library; the z88dk wiki explicitly points users at
  cpcrslib or Crocolib for sprites/tilemaps.
- **Implementation language**: mix of C and asm, integrated with the
  rest of z88dk's runtime.
- **Licence**: Clarified BSD / public-domain mosaic (z88dk's standard
  per-file licensing).
- **Verdict**: useful as the **toolchain** for the CPC backend (since
  RAGE1 already lives in z88dk's `zcc` world for ZX), but does not on
  its own provide the sprite/tilemap layer the engine needs.

#### 1.2.3 Crocolib

- **What**: a z88dk-based CPC framework with hardware-level features
  (video, scrolling, sound).
- **Source**: development-thread on the z88dk forum, plus documentation
  at cpcrulez.fr; no canonical GitHub repository surfaced in this
  survey.
- **Language**: C on z88dk, with low-level support routines.
- **Licence**: not clearly stated in publicly indexed material.
- **Maintenance**: niche; one-person project; documentation in French
  on cpcrulez; not widely adopted.
- **Verdict**: not a serious contender — too small, licence unclear,
  unhostable without forking. Worth re-checking later as a source of
  ideas, not as a vendored dependency.

#### 1.2.4 ugBASIC runtime (quick disqualification)

- **What**: a BASIC-dialect compiler targeting ~26 8-bit systems
  including CPC664.
- **Why disqualified**: ugBASIC's CPC runtime is part of a BASIC
  compiler's emitted output; it is not packaged as a library to be
  linked from external C/asm code. Extracting just the runtime would
  be a fork.

### 1.3 Comparison summary

| Property | cpctelera | CPCRSlib | z88dk +cpc | Crocolib |
|---|---|---|---|---|
| Sprite blits (masked / unmasked / blended) | yes, multiple variants | yes (asm) | basic only | yes |
| Easy tilemaps | yes (`cpct_etm_*`) | yes | no | yes |
| AY music + SFX (Arkos) | yes | partial | no | yes |
| Keyboard scan | yes (fast) | yes | yes | yes |
| Asset converters (PNG → tileset/sprite) | yes (`cpct_img2*`) | no | no | partial |
| CDT / DSK packaging | yes (bundled iDSK + 2cdt) | no | yes (`appmake`) | via z88dk |
| C / asm split | 86% / 14% | 6% / 93% | mixed | C-heavy |
| Implementation language fit (C-leaning) | best | worst | good | good |
| Licence | LGPL-3.0 | MIT | BSD-ish | unclear |
| Latest activity (as of 2026-05) | May 2026 master fix; active `development` | low | very active | very low |
| Community size | moderate (250+ stars) | small | large (z88dk) | tiny |
| Documentation | extensive reference manual | sparse | moderate (wiki) | sparse, French |
| Build-system collision risk | high (own Makefile template) | low | low (we already use it) | medium |

---

## 2. Recommendation

**Vendor cpctelera as the CPC graphics + audio + keyboard backend.**
Specifically:

1. Add `external/cpctelera` as a git submodule (JSP precedent). The
   submodule add is owned by toolchain.md Phase T0 (so the toolchain
   spike can prove the build end-to-end before R-phase work starts);
   R1 then verifies, pins, and records the licence.
2. Use cpctelera as a **source-level library**, bypassing its
   `cpct_mkproject` build system: compile the relevant subset of
   `cpctelera/cpctelera/src/**/*.{c,s,asm,c.s}` with z88dk's `zcc +cpc`,
   the same way `Makefile.common:127-134` already does for JSP.
3. Map RAGE1's `gfx_*` HAL to cpctelera primitives via a new file
   `engine/src/gfx_cpc.c` + header `engine/include/rage1/gfx_cpc.h`.
4. Drive cpctelera's asset converters (`cpct_img2tileset`,
   `cpct_img2sprites`) as subprocesses from RAGE1's CPC-side asset
   pipeline.

### Justification

- **Functional coverage**. cpctelera is the only candidate that covers
  sprite blits, easy tilemaps, AY music/SFX (Arkos), keyboard scan and
  asset conversion in one tree. The other candidates would force
  stitching together two or three sub-libraries, multiplying the
  vendoring + integration cost. Even though audio and input belong to
  `audio.md` / `input.md`, having one upstream that supplies clean APIs
  for all three reduces the surface area we have to design.
- **Fit with `gfx_*` HAL**. The cpctelera primitives map naturally onto
  the kind of operations the JSP/SP1 HAL exposes (init video, draw
  sprite, undraw sprite via saved background, draw tilemap row, etc.).
  We will write a thin C adapter, exactly as `gfx_jsp.c` does for JSP.
  No part of `gfx_*` HAL is so ZX-specific that cpctelera cannot back
  it once the gfx.md audit removes the obvious ZX assumptions
  (attribute cell, BAT, 32×24 screen dimension).
- **Language fit**. cpctelera is overwhelmingly C — that is exactly the
  language RAGE1 is written in. The hot-path asm is well-isolated under
  `cpctelera/src/sprites/` and `cpctelera/src/keyboard/` and uses SDCC
  `__z88dk_*` calling conventions that z88dk's own SDCC fork
  understands. Compare to CPCRSlib, where ~93% of the code is hand-
  written asm against a custom calling convention — porting/integration
  cost there would be much higher.
- **Toolchain fit**. RAGE1 already lives in z88dk (`zcc +zx`). The same
  `zcc` driver supports `+cpc`, with a patched SDCC that honours the
  `__z88dk_callee` / `__z88dk_fastcall` markers cpctelera's headers
  use. We do **not** need cpctelera's bundled SDCC 3.6.8.
- **Licence compatibility**. LGPL-3.0 is compatible with RAGE1's
  GPL-3-or-later: LGPL grants explicit permission to relicense under
  GPL-3+ for combined works (LGPLv3 §3); the resulting binary is
  legitimately distributable as GPL-3+. See section 3.
- **Maturity and traction**. cpctelera is the canonical CPC C engine in
  practice: it is cited in CPCWiki and used in publicly released games.
  Releases are infrequent: master had a real bug-fix commit in May 2026
  after a 3-year dormancy, and the `development` branch (carrying
  2200+ commits and the `v1.5/dev` marker) was last touched in
  November 2025. Upstream is alive but slow — see risk R-7.
- **Asset converters**. cpctelera's `cpct_img2tileset` /
  `cpct_img2sprites` know how to encode pixels in each CPC video mode
  including the awkward two-pixels-per-byte mode-0 layout. Reimple-
  menting that in `mapgen.pl` / `btilegen.pl` is a non-trivial slice of
  work we get for free by shelling out.

### Expected trade-offs

- **No more "self-contained build"**. We now depend on cpctelera's
  source-tree layout staying stable enough for us to glob it. JSP is
  Jorge's own repo and trivially stable; cpctelera is an external
  project. We pin to a specific commit on a specific branch.
- **Branch choice**. master is conservative and stale; `development`
  carries the bulk of the work and the v1.5/dev marker but is also
  ~6 months stale. We pin to a **specific commit** on the
  `development` branch (rather than tracking the branch head),
  re-evaluated per phase. If upstream stays dormant we may need to
  fork — LGPL-3.0 permits this cleanly (see §3).
- **We will not use cpctelera's build system**, even though it is
  battle-tested. That is the real integration cost — see section 4.3.
- **Memory layout assumptions** (e.g. screen base at 0xC000 on CPC,
  vs. 0x4000 on ZX) sit inside cpctelera and inside our wider banking
  story. Banking effects on dataset/codeset swapping land in
  `banking.md`; here we just confirm cpctelera supports
  `cpct_pageMemory` and explicit RAM-bank macros that should let us
  build a CPC dataset/codeset model analogous to ZX 128's.

---

## 3. Licence audit

cpctelera is **LGPL-3.0**. The repo root `LICENSE` file is the verbatim
GNU LGPL v3 (29 June 2007) text, and `cpctelera/src/readme.txt` states:

> "CPCtelera low-level library, examples and scripts are distributed
> under GNU Lesser General Public License v3"

Bundled third-party tools under `cpctelera/tools/` (SDCC, iDSK, Hex2Bin,
2cdt, Arkos Tracker player) have their **own** licences. We do not
intend to vendor those — see section 4.1 for the subset we actually pull
in.

### LGPL-3.0 + RAGE1 (GPL-3)

RAGE1's top-level `LICENSE` file is the verbatim GNU GPL v3 text
(29 June 2007). Whether the project intends "GPL-3-only" or
"GPL-3-or-later" is not explicit in the LICENSE filename and is to be
confirmed in R1-3 (see phase R1 below). The conclusion below holds in
**either** case: LGPL-3.0 combines cleanly with GPL-3 (and with
GPL-3-or-later) under LGPLv3 §3 / §4.

The relevant clause of LGPLv3 is §3 ("Object Code Incorporating
Material from Library Header Files") and §4 ("Combined Works"), plus
LGPLv3 §0 ("As used herein, ‘this License' refers to version 3 of the
GNU Lesser General Public License…"), and the LGPLv3 preamble's
explicit statement that:

> "You may convey a covered work under sections 3 and 4 of this License
> without being bound by section 3 of the GNU GPL."

And, decisively, LGPLv3 §3 permits relicensing under GPL-3+:

> "You may convey a covered work under the terms of sections 3 and 4 of
> this License. … as an alternative … you may convey it under the terms
> of the GNU General Public License, version 3 or later, applicable to
> the modified version."

(Wording paraphrased — the binding text is the LICENSE file itself; see
section 7 ("Combined Libraries") for the explicit GPL-conveyance
permission.)

**In practice**, for our distribution scenario:

- We ship combined source that includes a subset of cpctelera's
  `cpctelera/src/**` (LGPL-3.0) plus RAGE1 engine + game (GPL-3+).
- The combined work is distributed under **GPL-3+**, with cpctelera's
  origin and licence preserved (LICENSE file kept in `external/
  cpctelera/`, headers' copyright notices preserved as required by
  LGPLv3 §4).
- We must make the cpctelera **source** available alongside binaries —
  trivial since we ship as source anyway and pin a submodule commit.
- The user retains the right to relink RAGE1 against a modified
  cpctelera (the "LGPL relinking" requirement). Since the entire engine
  is shipped as source, this is satisfied automatically.

### Caveats

1. **Bundled SDCC**. cpctelera's `cpctelera/tools/sdcc-3.6.8-r9946/`
   includes a full SDCC source tree, GPL-licensed in its own right. We
   do **not** vendor `cpctelera/tools/` — see section 4.1 — so this
   does not enter our distribution. Documenting that omission is part
   of the integration plan.
2. **Bundled Arkos player**. Arkos Tracker's player code (under
   `cpctelera/src/audio/`) is LGPL-3.0 along with the rest of the
   cpctelera src tree, but has additional attribution requirements
   ("Music done with Arkos Tracker by Targhan/Arkos"). To be confirmed
   during phase R1: we read the in-tree licence headers and add the
   required notice in `doc/credits.md` (or equivalent). This is owned
   by `audio.md` overall.
3. **Asset-converter executables** (`cpct_img2tileset` etc. and the
   underlying Img2CPC binary): if we ship pre-built binaries we must
   ship their LICENSE files too. Simpler: require the developer/CI to
   install or build them from source. The asset pipeline does not need
   to bundle them into the distributable `.cdt` / `.dsk` output, only
   into the build environment.
4. **No static-linking-without-relinkability problem**. LGPLv3 §4(d)
   normally requires either dynamic linking or shipping the object code
   for relinking. We are an all-source distribution: §4(d)(0) is
   satisfied because users have full source of the combined work.

### Conclusion

LGPL-3.0 (library) + GPL-3+ (engine + game) is a clean, well-trodden
combination. The combined RAGE1+cpctelera+game binary is distributable
as GPL-3+. No licence-blocking issues for vendoring.

---

## 4. Integration approach

### 4.1 Submodule layout (`external/cpctelera`) — JSP precedent

Submodule add:

```
git submodule add -b development \
  https://github.com/lronaldo/cpctelera.git external/cpctelera
git -C external/cpctelera checkout <pinned-commit>
```

We pin to a specific commit (initially the latest stable point on
`development`, re-evaluated at the start of each subsequent integration
phase). `master` is too stale; `development` is where v1.5 lives.

The submodule entry in `.gitmodules` mirrors the JSP entry:

```
[submodule "external/cpctelera"]
    path = external/cpctelera
    url = https://github.com/lronaldo/cpctelera.git
    branch = development
```

We use cpctelera **as-is from upstream**, without forking, vendoring a
subset, or copying files in. The selection of which paths inside
`external/cpctelera` we actually compile is done at Makefile level by
explicit globs — exactly how `Makefile.common:130-133` does for JSP.

The cpctelera tree we **do** consume:

- `external/cpctelera/cpctelera/src/` — the runtime library (all sub-
  directories listed in 1.1 except possibly `buildsys/` which is the
  build template and not runtime code)
- `external/cpctelera/cpctelera/cfg/` — configuration headers we may
  need (e.g. fixed memory addresses); to be confirmed in R2
- `external/cpctelera/cpctelera/tools/scripts/` — only the asset
  converters we need: `cpct_img2tileset`, `cpct_img2sprites`,
  `cpct_bin2c` (driven as subprocesses; see section 5). The Img2CPC
  binary they call is built from `cpctelera/tools/img2cpc/`.

The cpctelera tree we **do not** consume:

- `external/cpctelera/cpctelera/tools/sdcc-3.6.8-r9946/` — bundled
  SDCC; we use z88dk's SDCC.
- `external/cpctelera/cpctelera/tools/iDSK*` and bundled emulator —
  toolchain.md will decide whether to use these or system-provided
  alternatives.
- `external/cpctelera/examples/`, `cpctelera/docs/` — examples and
  docs; not built into RAGE1.

There is no fork; if we discover upstream bugs during integration we
file PRs / issues against `lronaldo/cpctelera` and pin past them in the
meantime by bumping the submodule SHA, exactly as we would handle a JSP
bug.

### 4.2 Build-time integration (link, runtime extraction, subbuild)

Three strategies were considered:

| Strategy | Description | Verdict |
|---|---|---|
| **A. Source-glob inline compile** | Add cpctelera C/asm sources to `CSRC` / `ASMSRC` in `Makefile-cpc-flat` (and `Makefile-cpc-banked` for cpc6128) and let `zcc +cpc` compile them alongside engine code, exactly like JSP today. | **Chosen.** |
| **B. Pre-built library** | Run cpctelera's own Makefile once to produce a `.lib`, then link RAGE1 against the result. | Rejected — requires installing cpctelera's full toolchain (bundled SDCC, scripts), defeats the "z88dk-only" simplification, makes the link more brittle. |
| **C. Driven subbuild** | Have RAGE1's Makefile shell out to cpctelera's own Makefile per build. | Rejected — same brittleness as B plus the worst of both worlds: dependency on cpctelera's build system without the benefit of caching. |

Strategy A is the same model as JSP and the same model RAGE1 already
uses for **all** its own code. The cost is that we encode in
`Makefile-cpc-flat` / `Makefile-cpc-banked` (both owned by
`toolchain.md`) the list of source paths under
`external/cpctelera/cpctelera/src/`. Concretely:

```make
# in Makefile-cpc-flat / Makefile-cpc-banked (sketched; final form in toolchain.md)
CPCTELERA_DIR   = external/cpctelera/cpctelera
CPCTELERA_SRC   = $(CPCTELERA_DIR)/src
CSRC          += $(shell find $(CPCTELERA_SRC) -name '*.c' -not -path '*/audio/akm/*' )
ASMSRC        += $(shell find $(CPCTELERA_SRC) -name '*.s' -o -name '*.asm')
INC           += -I$(CPCTELERA_SRC) -I$(CPCTELERA_DIR)/cfg
```

The exact globs (and any exclusions for files that don't compile under
z88dk's SDCC fork) are determined in phase R2 by a hello-world build.

#### Compile flags

cpctelera headers declare callee/fastcall via `__z88dk_callee` and
`__z88dk_fastcall`, which z88dk's SDCC fork supports natively. No
porting layer should be required.

The `.s` (SDCC asm) vs `.asm` (z88dk asm) split needs verification:
cpctelera's hand-written hot-path files use a mix of `.s` and `.asm`
extensions and target SDCC's `sdasz80` assembler syntax. Inside
`zcc`, `.asm` is normally routed through z88dk's `z80asm`, while `.s`
files are routed through `sdasz80` when SDCC mode is active — the two
paths are not equivalent and may need explicit per-file extension
choices or `zcc` flags to route every cpctelera asm file through
`sdasz80`. R2's hello-world PoC must establish which routing is
required for cpctelera's asm tree to assemble. This is the single
biggest unknown: see section 7 risk R-1.

#### What about cpctelera's audio backend?

The Arkos player in `src/audio/` is C+asm and needs an Arkos-format
music file to play. Music format and audio HAL are owned by `audio.md`.
At the build level we expect to glob `src/audio/*.c` and `.asm` into
the build same as the rest — they should compile fine standalone — but
**whether we wire them into the runtime** is `audio.md`'s call.

### 4.3 Toolchain marriage (SDCC version, build-system collision avoidance)

This is the single non-trivial novelty vs JSP.

#### Bundled vs host SDCC

- cpctelera ships SDCC 3.6.8 (`cpctelera/tools/sdcc-3.6.8-r9946/`).
- z88dk currently ships its own patched SDCC fork (4.3.x as of z88dk
  v2.3/v2.4, 2025–2026).
- The two SDCCs differ on minor codegen and on which fixes are
  backported, but the **language**, **calling conventions**, and **asm
  syntax** that cpctelera relies on are unchanged between 3.6.8 and
  4.3.x.
- cpctelera's `__z88dk_callee` / `__z88dk_fastcall` annotations are
  exactly what z88dk's SDCC understands — there is no "translation"
  needed.

Conclusion: we **use z88dk's bundled SDCC, not cpctelera's**. We do not
install cpctelera's bundled SDCC tree.

Validation: the R2 hello-world PoC must demonstrate a full
build-and-run of a trivial cpctelera example using only `zcc +cpc`.

#### Avoiding build-system collisions

cpctelera projects expect a `cfg/build_config.mk` and a generated
`Makefile` that pulls in `cpctelera/buildsys/cmd/*.mk`. We do not run
`cpct_mkproject`. We do not include cpctelera's `Makefile` fragments.
We do not source `cpctelera/scripts/cpct-env.sh`.

What we **do** keep visible to our `Makefile-cpc-flat` / `-banked`:

- The header tree under `cpctelera/cpctelera/src/` — for `-I`.
- The C/asm sources themselves — globbed into `CSRC` / `ASMSRC`.
- The asset-converter scripts under `cpctelera/cpctelera/tools/
  scripts/` — invoked as subprocesses.

What we **do not** want:

- `CPCT_PATH` environment variable shenanigans
- cpctelera's `cfg/build_config.mk`
- cpctelera's emulator launcher

This is symmetric with how we use JSP today: we pull source files into
our build, ignore JSP's own `Makefile`, and the rest is transparent.

#### CDT/DSK output

cpctelera's bundled `iDSK` / `2cdt` produce `.dsk` / `.cdt`. RAGE1's
current ZX output is `.tap` via z88dk's `bas2tap` + `appmake`. For CPC
output we have two paths:

1. Use z88dk's `appmake` `+cpc` and `+amstradcpc` modes (`appmake +cpc
   -b game.bin --org 0x1000 -o game --disk`, sketched), which can emit
   `.dsk` and `.cdt`. This is consistent with the rest of RAGE1's
   z88dk-driven build.
2. Drive cpctelera's bundled `iDSK` / `2cdt` as subprocesses.

Both are viable; the decision belongs to `toolchain.md`. The library-
specific recommendation here is: **prefer option 1** unless `appmake`
turns out to lack a feature we need. `iDSK` and `2cdt` are simple tools
that `appmake` largely already covers.

---

## 5. Asset pipeline integration

cpctelera's bundled converters:

- `cpct_img2tileset` — PNG / image → C-array tileset + matching `.h`.
  Handles split-into-tiles, masks, and Mode-0/1/2 pixel encoding.
  Implemented as a Bash script in
  `cpctelera/tools/scripts/cpct_img2tileset.sh` that wraps the
  `Img2CPC` binary (under `cpctelera/tools/img2cpc/`, written by
  Augusto Ruiz, separate sub-licence to confirm).
- `IMG2SPRITES` — sprite-sheet conversion is **not a separate
  script** but a Makefile macro defined in
  `cpctelera/cfg/global_functions.mk`. It invokes the same
  `cpct_img2tileset` script under the hood with sprite-oriented
  flags (per-sprite width/height, mask handling, output formatting).
  From RAGE1's perspective we either replicate the macro's flag set
  in our own wrapper script, or call `cpct_img2tileset` directly
  with the equivalent flags.
- `cpct_bin2c` — binary → C-array helper (script).
- `cpct_pack` — RLE/aPLib packer wrapper.

Three options were considered:

| Option | Description | Verdict |
|---|---|---|
| **A. Drive cpctelera converters as subprocesses** | RAGE1's CPC asset pipeline shells out to `cpct_img2tileset` / `cpct_img2sprites` to generate C arrays, then `datagen.pl` / `btilegen.pl` consume those. | **Chosen.** |
| **B. Replicate the conversion in Perl** | Add Mode-0/1/2 encoders to `btilegen.pl` / sprite generation. | Rejected for phase R1 — encoding mode 0 (two pixels packed into a byte with interleaved bit layout) is correct-by-construction in cpctelera but error-prone to re-implement. Could be revisited later if subprocess invocation proves brittle. |
| **C. Skip cpctelera converters; write fresh** | Same as B but starting from scratch (no reference). | Rejected outright. |

#### How option A wires in

`assets.md` defines the shared-core `.gdata` + per-platform overlay
model and picks a **sibling-tree** layout: per-platform overrides live
at `<platform>/game_data/...` (e.g. `cpc6128/game_data/btiles/`,
`cpc6128/game_data/sprites/`) at the same level as the shared
`game_data/`, and shadow shared files at copy time into `build/`. The
CPC backend uses that layout — there is **no** `game_data/cpc/`
sub-tree.

The CPC asset pipeline step (owned by `assets.md` for architecture,
owned by us for the cpctelera-specific bit):

1. For each sprite/tile PNG in the resolved CPC asset set, run
   `cpct_img2tileset` (or `cpct_img2sprites`) with the appropriate
   tile dimensions and Mode (declared in `.gdata`) to emit a generated
   `.c` + `.h` under `build/generated/cpc/`.
2. The emitted C arrays are pulled into the CPC build same as today's
   ZX generated sprite/tile data.
3. `datagen.pl` is extended (per `assets.md`) to know how to emit
   metadata (animation frames, sequencing, mask vs no-mask) referring
   to cpctelera's array layout.

#### Caveats

- **Img2CPC is a C++ binary** built from cpctelera's own
  `cpctelera/tools/img2cpc/` tree. Installing this binary on CI is a
  one-off `make` step inside the submodule. The CI Docker image
  (`rage1-z88dk` — see `toolchain.md`) needs to gain Img2CPC.
- **`cpct_*` scripts are Bash.** They are mildly opinionated about
  environment (some expect `CPCT_PATH`). We work around this either
  with a wrapper script in `tools/` that fakes the minimum
  environment, or by invoking the underlying Img2CPC binary directly
  with the same flags. To be settled in R3.
- **Generated-file naming**. cpctelera converters emit C variable names
  derived from the PNG filename; we'll need to either rename the
  outputs or follow that convention in RAGE1's generated includes.

---

## 6. Phased work plan

Five phases. Each phase is independently testable; phase exit requires
both `make all-test-builds` green on the ZX side **and** an explicit
exit-criterion test on the CPC side. Phase exit criteria match the
top-level "best-effort ZX back-compat at phase boundaries" rule from
`2026-05-23.md`.

These phases sit **after** the gfx.md HAL audit phases (phase G* in
gfx.md) and the toolchain.md `+cpc` plumbing phases (phase T*); they
assume those have landed. Concretely, the prerequisites are:

- ZX gfx_* HAL has been audited and abstracted (so its surface is
  platform-neutral as a contract, even if implementation is still ZX-
  only).
- A minimal `Makefile-cpc-flat` exists that can compile + link an
  empty RAGE1-shaped binary with `zcc +cpc`. (Owned by toolchain.md;
  the `Makefile-cpc-banked` variant lands in toolchain.md T3, after
  cpc-flat is proven.)

### Phase R1 — Submodule verification + licence wiring

The cpctelera submodule was added (and CI updated to recurse
submodules) in toolchain.md Phase T0 — that's the canonical
submodule-add step. R1 confirms the result, pins the commit, and
records the licence/attribution work that T0 does not own.

- **R1-1** Verify that the cpctelera submodule landed correctly in
  T0 and is pinned to a specific commit on the `development`
  branch (the commit chosen during T0; R1 may bump it if a more
  recent fix is needed).
  - *What to test*: `git submodule status external/cpctelera`
    shows the expected commit; `external/cpctelera/cpctelera/src/cpctelera.h`
    exists; CI checks out submodules recursively per the JSP
    workflow precedent.
  - *Expected outcome*: submodule present and pinned; no engine
    code change.
- **R1-2** Update CI to recursively check out submodules for CPC
  builds. (JSP precedent: `.github/workflows/build-test-games.yaml`
  already does this — verify cpctelera is also picked up.)
  - *What to change*: confirm `submodules: recursive` is already in
    place; add no new flags if it is.
- **R1-3** Record licence files and attributions.
  - *What to change*: new section in `doc/credits.md` (or top-level
    README) crediting cpctelera (Francisco Gallego-Durán et al.),
    LGPL-3.0, with the Arkos Tracker attribution placeholder.
  - *What to test*: `find external/cpctelera -name LICENSE*` confirms
    the LICENSE is preserved in-tree.
- **R1-4** Add `.gitignore` entries for any cpctelera build artefacts
  if/when present in the submodule tree.
- **Phase-exit criteria**:
  - `make all-test-builds` (ZX) green — submodule add must not regress
    ZX builds.
  - `git submodule status` clean; submodule pinned commit recorded
    in-repo.
  - Licence text and credit added to project docs.

### Phase R2 — Hello-world PoC: cpctelera + z88dk `+cpc`

This phase deliberately bypasses RAGE1 entirely. The point is to
prove that cpctelera's source tree compiles under z88dk's SDCC fork
and runs on a CPC emulator. If this fails, the whole plan changes.

- **R2-1** Write a standalone PoC under `tools/cpc-poc/` that
  `#include`s `cpctelera.h` from `external/cpctelera`, calls
  `cpct_setVideoMode(1)` + a sprite blit, and produces a `.cdt`.
  - *What to change*: new directory `tools/cpc-poc/` with a single-file
    `main.c` + small `Makefile` (or inline rules in
    `Makefile.cpc-poc`).
  - *What to test*: `make -C tools/cpc-poc` produces `poc.cdt`.
  - *Expected outcome*: a `.cdt` file. Failure here means the
    SDCC-version assumption (1.4.3 §4.3) is wrong; fall back plan is
    to add `__z88dk_*` shims or pin to specific cpctelera files.
- **R2-2** Identify the subset of `external/cpctelera/cpctelera/src/`
  that compiles cleanly under z88dk's SDCC. Catalogue any files that
  fail with reasons.
  - *What to test*: a `--dry-run` build that touches every source file
    under `cpctelera/src/`; collect errors.
  - *Expected outcome*: a known-failing list of files, ideally empty
    or limited to the audio backend (which we may exclude per
    `audio.md`).
- **R2-3** Run the PoC `.cdt` in a CPC emulator (Caprice32 / ACE /
  RVM — emulator choice owned by `testing.md`); confirm sprite appears.
  - *What to test*: take a screenshot, eyeball-verify against a known
    good output. (Pixel-perfect regression baseline is a `testing.md`
    deliverable, not blocking here.)
- **Phase-exit criteria**:
  - PoC `.cdt` builds with `zcc +cpc` only (no cpctelera-bundled
    SDCC).
  - PoC runs in chosen CPC emulator and renders the sprite.
  - Catalogue of cpctelera files that need exclusion is written into
    this document (section 4.2 globs).
  - ZX builds still green.

### Phase R3 — Asset converter wiring

- **R3-1** Build cpctelera's `Img2CPC` binary as part of CI image
  setup, and install the `cpct_img2tileset` Bash script onto PATH
  (note: there is only **one** cpctelera converter script —
  `cpct_img2tileset`. Sprite-sheet conversion is the `IMG2SPRITES`
  Makefile macro and reduces to a flag-tuned invocation of
  `cpct_img2tileset`, which we either replicate in our wrapper or
  call directly.)
  - *What to change*: `Dockerfile` for `rage1-z88dk` (owned by
    `toolchain.md`, depends on us); `tools/install-cpctelera-
    converters.sh` helper.
  - *What to test*: in CI, `cpct_img2tileset --help` runs without
    error.
- **R3-2** Wrap `cpct_img2tileset` (with two invocation modes: tileset
  and sprite-sheet, the latter replicating cpctelera's `IMG2SPRITES`
  macro flag set) in a small `tools/cpc_asset_convert.pl` (or `.sh`)
  that gives a fixed invocation surface decoupled from cpctelera's
  `CPCT_PATH`-environment assumptions.
- **R3-3** Demonstrate end-to-end conversion: a hand-authored PNG
  under `tools/cpc-poc/assets/test.png` → generated `.c`/`.h` via
  the wrapper → linked into the R2 PoC to render a real sprite (not a
  hard-coded array).
  - *What to test*: PoC `.cdt` renders the PNG content.
- **Phase-exit criteria**:
  - Asset converter is available on the CI image and reachable from a
    fixed-shape command.
  - PoC has been re-built using PNG-derived data, not hard-coded
    arrays.
  - ZX builds still green.

### Phase R4 — gfx_cpc.c skeleton + minimal CPC test game

- **R4-1** Create `engine/include/rage1/gfx_cpc.h` and
  `engine/src/gfx_cpc.c`, mapping the audited `gfx_*` HAL onto
  cpctelera primitives.
  - *What to change*: two new files; `Makefile-cpc-flat` /
    `Makefile-cpc-banked` select them instead of `gfx_sp1.c` /
    `gfx_jsp.c`.
  - *What to test*: file compiles, no link errors.
- **R4-2** Add a `BUILD_FEATURE_GFX_BACKEND_CPC` (or whatever the
  `gfx.md` audit decides on) macro family so the right backend is
  selected per platform target.
- **R4-3** Create a `games/minimal_cpc/` (or `tests/minimal_cpc/`)
  test game with the smallest possible `.gdata` set that exercises
  init, a sprite, a tile, and `gfx_*` HAL flush — enough to confirm
  the HAL-to-cpctelera mapping is correct.
  - *What to test*: emulator screenshot matches expected.
- **R4-4** Wire this game into `make all-test-builds` under the new
  CPC target (mechanism owned by `toolchain.md`).
- **Phase-exit criteria**:
  - `games/minimal_cpc/` builds and renders correctly under emulator.
  - `make all-test-builds` (now covering both ZX and CPC) green.
  - First entries in `tests/00regression/` exist for CPC (initial
    screenshot baseline — full regression flow is `testing.md`'s job).

### Phase R5 — Hardening + upstream feedback

- **R5-1** Add a `tests/00regression/` baseline screenshot for
  `games/minimal_cpc/`; ensure the regression workflow runs both ZX
  and CPC tests.
- **R5-2** File any upstream bugs encountered in R2/R4 against
  `lronaldo/cpctelera`. Track our pinned commit so we can bump past
  fixes.
- **R5-3** Document the cpctelera pin policy: when to bump (security/
  bug-fix only mid-phase; broader updates at phase boundaries).
- **R5-4** Decide on inclusion (or not) of cpctelera's audio backend
  in RAGE1, in conjunction with `audio.md`. If yes, write a
  `audio_cpc.c` HAL backend skeleton.
- **R5-5** Decide on inclusion (or not) of cpctelera's keyboard scan
  in RAGE1, in conjunction with `input.md`. If yes, write an
  `input_cpc.c` HAL backend skeleton.
- **Phase-exit criteria**:
  - CPC regression baseline checked in.
  - cpctelera-vs-RAGE1 integration is documented (this file, plus
    cross-refs from `audio.md` and `input.md`).
  - Pin policy documented.

---

## 7. Risks

- **R-1 (high) — z88dk's SDCC fork rejects parts of cpctelera's asm**.
  cpctelera's hand-written `.asm` files target sdasz80 syntax bundled
  with SDCC 3.6.8. z88dk's SDCC 4.2.x ships a newer sdasz80; subtle
  syntax/macro differences may emerge. *Mitigation*: phase R2 is
  explicitly the gating test for this. If a small number of files
  fail, we patch them (filing PRs upstream); if many fail, we fall
  back to vendoring cpctelera's bundled sdasz80, or worst case to
  CPCRSlib.
- **R-2 (medium) — cpctelera upstream stays dormant**. Both master
  and `development` had only sporadic activity in 2025–2026 (master:
  one commit in 3 years, then a fix in May 2026; development: last
  commit Nov 2025, ~6 months stale at review). A stale pin is the
  control, but we may have to apply patches locally for bugs that
  upstream is slow to merge. *Mitigation*: pin a specific commit
  (documented in R5-3); be willing to carry small local patches in
  the submodule pin notes; if dormancy becomes terminal, fork — the
  LGPL-3.0 licence makes this clean.
- **R-3 (medium) — Img2CPC build on CI is fragile**. It's C++,
  requires a working compiler in the CI image. *Mitigation*: pre-
  build the binary in the `rage1-z88dk` Docker image, never rebuild
  during a normal `make`.
- **R-4 (medium) — Memory-layout assumptions clash with RAGE1's
  banking model**. cpctelera assumes specific screen base addresses
  (0xC000 by default), RAM banking via Gate Array port — different
  from ZX 128 paging. RAGE1's dataset/codeset infrastructure is built
  around ZX 0xC000-bank semantics. *Mitigation*: `banking.md` owns
  the redesign; here, we note that cpctelera does expose
  `cpct_pageMemory` and explicit bank macros, which appears sufficient
  to implement an equivalent paging-driven dataset/codeset model.
- **R-5 (low) — Arkos audio licence attribution requirement**.
  *Mitigation*: small action item in R1-3 to add the standard
  attribution; otherwise non-blocking.
- **R-6 (low) — Img2CPC sub-licence**. Img2CPC by Augusto Ruiz is
  bundled inside cpctelera/tools/ with its own header; needs an
  explicit read in R1-3 to confirm it is also LGPL or otherwise
  GPL-compatible. *Mitigation*: read the file; if incompatible (very
  unlikely), drive only `cpct_img2tileset` outputs without invoking
  Img2CPC inside RAGE1's build, i.e. require it as a host tool, not
  vendored.
- **R-7 (informational) — long-term dormancy**. Covered as the
  worst case of R-2; left here as an explicit reminder that the fork
  option is on the table if upstream stops responding entirely.

---

## 8. Open Questions

- **OQ-1**. Which CPC pixel mode is RAGE1's default — Mode 0 (160×200,
  16 colours, 4 bpp) or Mode 1 (320×200, 4 colours, 2 bpp)? This
  affects sprite encoding choices, asset converter flags, and tile
  cell size in `gfx.md`'s HAL audit. Recommend: **Mode 1** as default
  because its 320×200 pixel grid maps reasonably onto ZX's 256×192
  and its 4-colour palette is the most useful CPC default for tile-
  based action games. Mode 0 deferred to a per-game opt-in.
- **OQ-2**. Do we pin a commit on cpctelera's `development` branch
  or on `master`? Both branches are dormant in absolute terms
  (master: 3-year gap then one commit; development: last touched
  Nov 2025). Recommend: a **specific commit on `development`**,
  because that branch carries the bulk of post-1.4.2 work and the
  `v1.5/dev` marker. Branch choice matters less than commit choice
  since we pin a SHA either way; the open decision is which SHA.
- **OQ-3**. Do we want cpctelera's Arkos audio in RAGE1, or do we
  pick a different AY player? Decision belongs to `audio.md`. If
  yes, the audio submodule is "free" via cpctelera; if no, we
  exclude `external/cpctelera/cpctelera/src/audio/` from the source
  glob.
- **OQ-4**. Do we want cpctelera's keyboard scan, or stick to
  `appmake`'s/our own? Decision belongs to `input.md`. cpctelera's
  scan is fast and well-tested; default expectation is yes.
- **OQ-5**. Do we use cpctelera's `iDSK` + `2cdt` or z88dk's
  `appmake`? Decision belongs to `toolchain.md`. Recommendation
  here: **`appmake`** for consistency, unless it lacks a feature we
  need.
- **OQ-6**. Confirm cpctelera's expected `--org` address (CPC
  default user-code area is typically **0x4000** after the BASIC
  HIMEM-managed region; **0xC000** is screen RAM and therefore not
  a code-org candidate) and how it interacts with RAGE1's memory
  map and banking model (see `banking.md`). To be answered in R2:
  build the PoC with the default ORG and inspect; cross-check
  against the chosen RAGE1 CPC memory map.
- **OQ-7**. Is there value in maintaining a thin compatibility shim
  so a future contributor can swap cpctelera for CPCRSlib (or vice
  versa) at the HAL-backend level? Tentative answer: **no** — the
  HAL is already that shim. Backend swap is "fork `gfx_cpc.c` to
  `gfx_cpc_rslib.c`", not a runtime concern.

---

## References

- cpctelera repo: https://github.com/lronaldo/cpctelera
- cpctelera reference manual: http://lronaldo.github.io/cpctelera/
- cpctelera v1.4.2 release notes:
  https://github.com/lronaldo/cpctelera/releases/tag/v1.4.2
- CPCRSlib mirror: https://github.com/cpcitor/cpcrslib
- CPCWiki: CPCtelera
  https://www.cpcwiki.eu/index.php/CPCtelera
- z88dk CPC platform page:
  https://www.z88dk.org/wiki/doku.php?id=platform:amstradcpc
- JSP vendoring commit: `cc8e942` ("jsp: vendor JSP sprite library as
  git submodule at external/jsp")
- JSP build wiring: `Makefile.common:127-134`
- Existing HAL split: `engine/src/gfx.c`, `engine/src/gfx_sp1.c`,
  `engine/src/gfx_jsp.c`, `engine/include/rage1/gfx.h`,
  `engine/include/rage1/gfx_sp1.h`, `engine/include/rage1/gfx_jsp.h`
