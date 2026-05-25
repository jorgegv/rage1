# Toolchain & build matrix: ZX + CPC

This document specifies how the RAGE1 build system evolves to produce binaries
for both ZX Spectrum (48K, 128K) **and** Amstrad CPC (464, 664, 6128) from the
same source tree. It is **toolchain-only**: how compilers, assemblers, linkers,
loaders and packagers are invoked and wired together. The graphics, audio,
input and CPC-renderer subsystems live in their own subsystem docs
(`gfx.md`, `audio.md`, `input.md`, `cpc-renderer.md`); banking/SUB strategy
lives in `banking.md`; asset/data pipeline lives in `assets.md`.

The plan respects the architectural anchors set in the task spec:

- Existing ZX games keep building (best-effort, green at each phase exit).
- CPC backend wraps a vendored CPC graphics library (selected in
  `cpc-renderer.md`); toolchain.md must accommodate whichever library is chosen
  but does not itself choose it.
- `PLATFORM` replaces the ad-hoc `ZX_TARGET` dispatch as the **primary
  axis** of the build matrix. The secondary axis, `GFX_BACKEND` (renamed
  from `SPRITE_ENGINE`), selects the sprite/graphics library *within* a
  platform — today `sp1`/`jsp` on ZX and `cpctel` (cpctelera) on CPC,
  with room for alternate CPC libs (e.g. `cpcrs` for cpcrslib) added
  later under the same axis.

---

## 1. Current state audit

### 1.1 z88dk + SDCC: how RAGE1 currently uses it

RAGE1 is built end-to-end with **z88dk**, locked to tag `v2.3` in the CI image
(`docker/Dockerfile:9`). Every compile, assemble and packaging step goes
through the `zcc` driver and `z88dk-appmake`. Key configuration:

- **Target**: `+zx` (hard-coded as `ZCC_TARGET = +zx` at
  `Makefile.common:121`, and reused via `z88dk-appmake +zx` for every TAP
  produced).
- **Compiler backend**: SDCC, selected with `-compiler=sdcc`.
- **C library**: `sdcc_iy` (IY-as-frame-pointer SDCC clib variant), selected
  with `-clib=sdcc_iy`.
- **Optimisation/code-gen flags**:
  `-SO3 --opt-code-size --max-allocs-per-node200000` (`Makefile.common:136`).
- **CRT/pragma configuration** comes from per-target include files passed via
  `-pragma-include`:
  - `zpragma-48.inc` — SP1, 48K: `CRT_ORG_CODE=0x5f00`, `REGISTER_SP=0xd1d1`,
    `__MMAP=-1` (custom memory map in `mmap.inc`).
  - `zpragma-48-jsp.inc` — JSP, 48K: same org, stack at `0xe1e1` (JSP moves IV
    table to `0xE000`).
  - `zpragma-128.inc` — 128K (engine-agnostic): org/stack supplied at command
    line via `CFLAGS += -pragma-define:CRT_ORG_CODE=$(BASE_CODE_ADDRESS_128)`
    and `REGISTER_SP=$(ISR_VECTOR_ADDRESS_128)` (`Makefile-128:21-22`), values
    read from `etc/rage1-config.yml`.
- **Memory map**: custom user MMAP at `mmap.inc`, enforced by
  `tools/check_mmap_sections.sh` (`make section-check`).
- **Auxiliary z88dk tools** used: `z88dk-zx0` (ZX0 compression of datasets and
  optionally SUBs), `z88dk-z80nm` (symbol extraction in
  `Makefile-128:51-57`), `z88dk-appmake +zx` (every binary→TAP step).
- **Three distinct compile contexts** all reuse the same `CFLAGS` plus tweaks:
  1. **Main binary**: `-startup=31 -o main.bin` (`Makefile-48:94`,
     `Makefile-128:191`).
  2. **Datasets**: `--no-crt`, source from `build/generated/datasets/dataset_N.src/`
     (`Makefile-128:73-81`), then `z88dk-zx0` compression.
  3. **Codesets** and **banked code**: `--no-crt` org'ed at `0xC000`
     (`Makefile-128:94-99,131-140`).
- **SUBs (Single Use Binaries)** are built by per-SUB nested Makefiles under
  each game's `game_src/sub_*/Makefile`. Every one of those calls
  `zcc +zx ... --no-crt` then `z88dk-appmake +zx -b sub.bin --org $(ORG)`.
  See e.g. `games/sub_bufs_128/game_src/sub_dsbuf_error/Makefile:14,25`.

**Baked-in ZX assumptions in the build system** (audit summary; each is a
later refactor target):

| Location                                                                               | Assumption                                                                           |
|----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| `Makefile.common:121`                                                                  | `ZCC_TARGET = +zx`                                                                   |
| `Makefile.common:214`                                                                  | screen.tap built with `z88dk-appmake +zx --org 16384`                                |
| `Makefile-48:61,81,90`                                                                 | every appmake call uses `+zx`, plus 48K orgs `0x5E00`/`0x5F00`                       |
| `Makefile-128:121,123,173,178,183`                                                     | every appmake call uses `+zx`, plus orgs `0xC000`, `0x8000`, `BASE_CODE_ADDRESS_128` |
| `engine/loader48/loader.bas`, `engine/loader128/loader.bas`                            | Sinclair BASIC (`CLEAR`, `LOAD ""`, `RANDOMIZE USR`)                                 |
| every `game_src/sub_*/Makefile`                                                        | `zcc +zx`, `z88dk-appmake +zx`                                                       |
| `tools/datagen.pl` (search `getopts "b:d:ct:s:"` ≈line 4363; validation ≈line 768-772) | `-t` option restricted to `48`/`128` only                                            |
| `tools/loadertool.pl:33-34`                                                            | hard-coded `loader_org_48 = 0x5E00`, `loader_org_128 = 0x8000`                       |
| `Makefile-128:51`                                                                      | `memory_switch_bank` named as a ZX-specific lowmem symbol                            |
| `Makefile.common:206-214`                                                              | loading-SCREEN$ pipeline uses ZX SCR format (6912 bytes) via `tools/png2scr.pl`      |
| `Makefile-128:13`                                                                      | hard-coded `MYMAKE -j8` (cosmetic; not portable issue)                               |
| `Makefile.common:233-247`                                                              | run targets use `fuse` (ZX) and `jnext` (ZXN) only                                   |

The `+zx` and Sinclair-loader hard-coding is consistent and pervasive but
**isolated to the toolchain layer** (Makefiles plus a small number of Perl
tools that emit org addresses and loader BASIC). No engine C source assumes
the appmake target.

### 1.2 Perl tool family — invocation map

| Tool | Where invoked | What it does | Platform coupling |
| --- | --- | --- | --- |
| `tools/datagen.pl` | `Makefile.common:185` (`make data`) | Parses `.gdata` → C/ASM source + `features.h`. | Validates `ZX_TARGET ∈ {48,128}` around `datagen.pl:768-772`; emits `BUILD_FEATURE_ZX_TARGET_48`/`_128`. ZX-only enums and screen/cell assumptions live in generated code, not in toolchain. |
| `tools/mapgen.pl` | `Makefile:103-108` (only `build-mapgen`) | Generates `.gdata` map/screen files from PNG. | Embeds ZX cell/attribute model in PNG-decoding; toolchain just calls it. (Owned by `assets.md`.) |
| `tools/btilegen.pl` | `Makefile:102` (only `build-mapgen`) | Generates btile `.gdata` from PNG tilesets. | Same — assets.md problem. |
| `tools/banktool.pl` | `Makefile-128:148` (`make banks`) | Bin-packs datasets+codesets into 16 KB banks; emits dataset/codeset info ASM. | Hard-coded `dataset_valid_banks = (1,3,7,6,4)`, `codeset_valid_banks = (6,1,3,7)` (ZX128 page numbers). Toolchain consumer; banking.md owns the policy. |
| `tools/loadertool.pl` | `Makefile-48:70`, `Makefile-128:156` | Generates `asmloader.asm` and patches `loader.bas`. | Hard-codes ZX loader orgs `0x5E00` (48), `0x8000` (128). Sinclair-BASIC-aware. |
| `tools/generate_banked_function_defs.pl` | `Makefile.common:186` | Emits `banked_function_defs.h` from `etc/rage1-config.yml`. | Toolchain-neutral. |
| `tools/check_banked_code_definitions.pl` | `Makefile-128:132` | Sanity-checks banked-function declarations. | Toolchain-neutral. |
| `tools/check_mmap_sections.sh` | `Makefile-48:40`, `Makefile-128:40` (`section-check`) | Verifies main.map sections vs `mmap.inc`. | Toolchain-neutral, but `mmap.inc` is ZX-shaped. |
| `tools/lowmemsym.pl` | `Makefile-128:64` | Verifies engine symbols are linked low in main binary. | ZX-128-specific check. |
| `tools/png2scr.pl` | `Makefile.common:212` | PNG → ZX `.scr` (6912 bytes) for loading screen. | ZX-only by definition. |
| `tools/mem-summary-{sp1,jsp}-{48,128}.sh` | `Makefile.common:315` | Memory-usage reports. | Already platform-matrixed by file name; the convention extends naturally. |
| `tools/r1size.sh`, `tools/memmap.pl`, `tools/r1sym.pl` | `Makefile.common:300-308`, `Makefile.common:240` | Reporting/symbol tools. | Toolchain-neutral. |

Generic finding: the Perl family is mostly toolchain-neutral *consumers*. Two
tools — `loadertool.pl` and `png2scr.pl` — and one option in `datagen.pl`
(`-t 48|128`) embed ZX-specific format knowledge and are the natural mutation
points for a CPC build. `mapgen.pl`/`btilegen.pl` embed ZX *asset* model
knowledge and are owned by `assets.md`.

### 1.3 Makefile family structure

```
Makefile                — top-level orchestration: clean, config, build,
                          build48, build128, all test-game targets
Makefile.common         — shared vars, paths, generic rules (%.o, %.c.asm,
                          %.tap-from-.bas), data generation, run/mem/tests
Makefile-48             — 48K-specific: org, no-bank, simple TAPs
Makefile-128            — 128K-specific: datasets, codesets, banked code,
                          banks, lowmemcheck
Makefile.game           — Used by external games as a thin wrapper that
                          checks out RAGE1 and invokes its build
```

The split is along an **address-map / banking** axis (48 = single binary,
128 = main + banks + datasets + codesets). It is *not* organised along a
"platform" axis. Adding CPC requires introducing that second axis. The
natural shape is `Makefile-<platform>` with a per-platform memory-model
selector for "with banking" vs "without".

Current dispatch logic — the `build` target at `Makefile:60-65` —
`grep`s `ZX_TARGET` out of the game's `game_data/game_config/*.gdata`
and dispatches to `Makefile-$(ZX_TARGET)`. The same `.gdata` field also
controls `make data` (via `-t $(ZX_TARGET)` in `Makefile.common:185`).
`ZX_TARGET` is therefore a single source of truth, but its name and its
value space (`48`/`128`) are ZX-only.

A second toolchain-relevant configuration variable, `BUILD_SPRITE_ENGINE` /
`SPRITE_ENGINE`, is detected at `Makefile.common:35-38` and currently selects
between SP1 (default) and JSP (vendored at `external/jsp`). It alters
`zpragma-48*.inc` selection and adds JSP source files to the build. Both
SP1 and JSP are ZX-only sprite engines; on CPC the equivalent slot will be
the cpctelera-or-similar graphics backend. Conceptually `SPRITE_ENGINE` is
already a graphics-backend selector, and post-gfx.md HAL work that semantic
becomes explicit.

### 1.4 Output packaging: bas2tap, .tap concatenation, asm loader

The ZX packaging pipeline today is a four-stage chain:

1. **BASIC loader** — Sinclair BASIC source in
   `engine/loader{48,128}/loader.bas` (3 lines each); copied to
   `build/generated/loader.bas` by `Makefile-48:33` / `Makefile-128:36`,
   converted with `bas2tap -sLOADER -a10 -q` (`Makefile.common:198-199`).
   `bas2tap` is built into the CI image from the `speccyorg/bas2tap` GitHub
   repo (`docker/Dockerfile:28-32`).
2. **ASM loader** — generated by `tools/loadertool.pl` from the bank/SUB/
   dataset/codeset binary inventory, then assembled with `zcc +zx ... --no-crt`
   and wrapped with `z88dk-appmake +zx --noloader --org $LOADER_ORG -b`
   (`Makefile-48:80-81`, `Makefile-128:181-183`).
3. **Per-section TAPs** — `bank_N.tap`, `sub_*.tap`, `main.tap`, optional
   `screen.tap`. Each is produced with `z88dk-appmake +zx --noloader
   --noheader --org <addr> -b <bin>`. The combinatorics of "which TAPs" is
   carried by the `TAPS` variable defined per-Makefile-N (`Makefile-48:17`,
   `Makefile-128:17`).
4. **Final TAP** — `cat $(TAPS) > game.tap` (`Makefile.common:201-204`).

Two observations matter for CPC:

- The final-stage `cat` of pre-orged blocks is **format-agnostic at the
  shell level** — it presumes only that each block is a self-contained TAP
  chunk with headers. The CPC analogues (CDT for tape, DSK for disk) are
  *not* concatenable the same way: CDT is a structured tape image with
  block timing, and DSK is a sectored disk image. The "cat the parts"
  abstraction has to become "pass the parts to a per-platform packager".
- The BASIC loader format and the ASM loader's role (set up memory paging,
  load each block, RANDOMIZE USR into code) are both Sinclair-specific.
  CPC's loader has the same *logical* job — set up banking on CPC6128,
  load each block, JP into code — but is written in Locomotive BASIC (or
  pure machine code launched from AMSDOS) and uses different firmware
  calls. The loader stack therefore has **two parallel implementations**,
  not a parameterised one.

### 1.5 Docker CI image (`zxjogv/rage1-z88dk`)

The image (`docker/Dockerfile`) is Fedora-based and contains exactly:

- A from-source build of z88dk at tag `v2.3` with `BUILD_SDCC=1
  BUILD_SDCC_HTTP=1` — i.e. SDCC is the SDCC version that z88dk bundles
  at that tag, **not** a system SDCC.
- `bas2tap` from `speccyorg/bas2tap`, copied into z88dk's bin.
- Perl + every CPAN module RAGE1 needs.
- Standard build-essentials (m4, bison, flex, make, …).

The image is built and pushed by `.github/workflows/build-z88dk-docker.yaml`
on changes to `docker/Dockerfile`. CI test-game builds (`build-test-games.yaml`)
pull `zxjogv/rage1-z88dk:latest` and run `make all-test-builds`.

The image does **not** currently contain: cpctelera, the `2cdt` tool (needed
for z88dk CDT output), any CPC emulator, any external CPC asset converter.

---

## 2. CPC toolchain evaluation

### 2.1 z88dk `+cpc` target — does it work, what is its maturity?

Findings (verified against z88dk wiki, CPCWiki Z88DK page, and
z88dk-appmake source):

- z88dk has had a `+cpc` target for years and explicitly supports CPC464,
  CPC664 and CPC6128 with the same code base. The standard compile command
  is e.g. `zcc +cpc -clib=sdcc_iy -lndos test.c -create-app -o test`.
- **`-clib=sdcc_iy` is the default** for `+cpc` exactly as for `+zx`; the
  IY-frame-pointer SDCC variant is the same one RAGE1 already depends on.
  This is the single most important compatibility fact: **the C ABI and
  calling convention RAGE1 is built against carry over to CPC unchanged.**
- Default `CRT_ORG_CODE` is `0x1200`; overrideable with `-zorg=` or
  `-pragma-define:CRT_ORG_CODE=...` — identical mechanism to the ZX 128K
  build (`Makefile-128:21`).
- Banking on CPC6128 is supported via z88dk's `#pragma bank NN` (`NN`
  0..7), with banked applications emittable in both CAS and DSK formats
  per the z88dk wiki. z88dk exposes the same `#pragma bank` family for
  ZX128 (different numbers). **However, RAGE1 does not currently use
  z88dk's `#pragma bank` mechanism** — it has its own banking
  implementation: custom dataset/codeset/SUB emission, `banktool.pl`
  page-policy lists, and a hand-rolled asmloader (emitted by
  `loadertool.pl`) that does the bank switching directly. Whether to
  keep RAGE1's own banking model and extend it to CPC, or migrate both
  sides to z88dk's `#pragma bank`, is a decision owed by `banking.md`
  (tracked here as OQ-T11). From the toolchain side either path is
  feasible; this doc accommodates whichever banking.md picks.

- Output packaging: `z88dk-appmake +cpc` produces:
  - **AMSDOS-headed `.cpc` binary** (default `-create-app`),
  - **`.dsk` disk image** (subtype `disk`),
  - **`.wav` audio file** of cassette tones (subtype `audio`/`wav`).
  - **No native CDT output** — CDT generation requires an external tool,
    the canonical one being `2cdt` (from cpcdos toolchain). This is a small
    Makefile dependency added in §5.
- File-I/O variants are selectable via `-lndos` (stub) or `-lcpcfs` (real
  AMSDOS calls). RAGE1 doesn't do user-visible file I/O so `-lndos`
  suffices.

Conclusion: **z88dk `+cpc` is production-ready** at the same C-toolchain
maturity level as `+zx`. There is no shortfall in the compiler/linker layer
that would force a switch off z88dk for CPC.

### 2.2 Alternative: SDCC standalone with cpctelera's own toolchain

cpctelera ships its own SDCC build (3.6.8 at the time of writing per its
`setup.sh` history) plus its own Makefile, its own ASZ80 assembler invocation
and its own CDT/DSK packagers and asset converters
(`cpct_img2tileset`, `cpct_bin2c`, `cpct_sp2tiles`, `cpct_tmx2csv`, …).
This is the same SDCC family RAGE1 already uses via z88dk, but:

- cpctelera's build system expects to drive the whole compile — its
  `cpct_mkproject` scaffolds a project around itself. Using cpctelera as a
  pure library linked from a foreign build is non-standard.
- The cpctelera SDCC version is pinned independently of z88dk's bundled SDCC
  version. Two SDCC versions in one CI image is feasible but adds friction.
- The asset tools (`cpct_*`) are useful regardless of which compiler drives
  the final link — they produce header/source files that any SDCC build
  can ingest. (This is the integration handle that lets us pick the
  z88dk path without losing access to cpctelera's tooling — see §2.3.)

The pure-SDCC path would mean either: (a) maintain two completely separate
build chains, ZX via z88dk and CPC via cpctelera-SDCC, which roughly
doubles toolchain surface; or (b) migrate ZX off z88dk too, which is a
major undertaking with no upside (z88dk's ZX support is more mature than
SDCC's via-cpctelera ZX story).

### 2.3 Decision and rationale

**Decision: z88dk-only for the C/ASM compile, link and packaging layer
across all four Phase-1 platform identities (ZX48, ZX128, CPC464,
CPC6128 — CPC664 is supported as a runtime target of the CPC464
build).** Use
cpctelera (or whichever CPC graphics library is selected in
`cpc-renderer.md`) **as a vendored library only** — vendored via git
submodule at `external/<libname>/` mirroring the existing `external/jsp/`
pattern — and consume only its public headers, .lib/.asm sources and
asset-conversion command-line tools. Do not import its build system.

Rationale:

- **C ABI continuity**: same `sdcc_iy` clib on both sides means RAGE1's
  engine C compiles identically, with no second calling-convention
  surface.
- **Minimal toolchain surface in the CI image**: one z88dk install
  serves all four platforms. cpctelera asset tools are small native
  binaries with no SDCC dependency at runtime.
- **Pragma/CRT mechanism is uniform**: `zpragma-<platform>.inc` works
  the same way for `+zx` and `+cpc`; the existing `-pragma-define`
  injection in `Makefile-128:21` carries over to a per-platform
  `Makefile-cpc-flat` / `Makefile-cpc-banked` with no new mechanism.
- **Banking mechanism is platform-side uniform** at the z88dk level:
  z88dk exposes `#pragma bank NN` on both `+zx` and `+cpc` if we
  ever want it. **RAGE1 does NOT use z88dk's `#pragma bank`** today
  (see §2.1 and OQ-T11 / banking.md OQ-B11): the engine has its own
  banking pipeline that's extended to CPC. The shared linker
  feature is mentioned here only to note the toolchain accommodates
  either mechanism.
- **Library vendoring precedent**: JSP already lives at `external/jsp/`
  as a submodule. Same approach for cpctelera (`external/cpctelera/`)
  gives the user identical mental model and CI behaviour.
- **Risk of mismatch with cpctelera's expectations**: cpctelera library
  sources are written against its own SDCC version, but as long as we
  use cpctelera's `.asm` and `.h` files (not its prebuilt binaries) and
  feed them to the z88dk-driven SDCC of equivalent vintage, calling
  conventions match. This is a known-good pattern (cpctelera itself
  builds its lib with the same compiler family). Validated empirically
  by a small spike in Phase T0; see Risks.

The chosen architecture is therefore:

```
                  zcc +zx                            zcc +cpc
                  -clib=sdcc_iy                      -clib=sdcc_iy
                       │                                  │
   engine/src  ────────┤                                  ├──── engine/src
    gfx_sp1 ───────────┤    one shared C corpus           │
    gfx_jsp ───────────┤    + per-platform backends ──────┤───── gfx_cpctel
    external/jsp/lib ──┘                                  └──── external/cpctelera/lib

      ↓ link                                                  ↓ link
      ↓                                                       ↓
   main.bin (+ bank N TAPs, sub TAPs, dataset/codeset)    main.bin (+ banks)
      ↓ z88dk-appmake +zx                                     ↓ z88dk-appmake +cpc
   game.tap                                                .cpc / .dsk / .cdt
                                                              (CDT via 2cdt)
```

---

## 3. Build-matrix design

### 3.1 The `PLATFORM` variable

Introduce a single new top-level variable, **`PLATFORM`**, with these
allowed values:

| `PLATFORM` value | Meaning                               | z88dk target | Memory model                      |
|------------------|---------------------------------------|--------------|-----------------------------------|
| `zx48`           | ZX Spectrum 48K                       | `+zx`        | flat 48K, no banking              |
| `zx128`          | ZX Spectrum 128K                      | `+zx`        | banked (datasets, codesets, SUBs) |
| `cpc464`         | Amstrad CPC 464 (also runs on CPC664) | `+cpc`       | flat 64K, no banking              |
| `cpc6128`        | Amstrad CPC 6128                      | `+cpc`       | banked (CPC ext-RAM model)        |

**CPC664 is not a separate `PLATFORM` value.** CPC464 and CPC664 share
the same 64K memory model and the same screen hardware; they differ
only in firmware (BASIC version; CPC664 has AMSDOS, CPC464 does not).
A CPC464-targeted binary loads on CPC664 unchanged via tape; the
`.dsk` artifact produced by the cpc-flat build also loads on CPC664
because CPC664 has AMSDOS. CPC664 is therefore supported as a
*runtime target* with no separate build identity. CPC6128 gets its
own `Makefile-cpc-banked` and `zpragma-cpc-banked.inc`.

**Interaction with existing `ZX_TARGET`**:

- `ZX_TARGET` remains a *.gdata* field name (backwards-compatible) but
  is reinterpreted as one component of the platform tuple, mapped:

  | game_config field  | PLATFORM derivation                                      |
  |--------------------|----------------------------------------------------------|
  | `ZX_TARGET 48`     | `PLATFORM=zx48`                                          |
  | `ZX_TARGET 128`    | `PLATFORM=zx128`                                         |
  | `PLATFORM cpc464`  | `PLATFORM=cpc464` (new direct field; also covers CPC664) |
  | `PLATFORM cpc6128` | `PLATFORM=cpc6128` (new direct field)                    |

  **Two-axis spelling.** Phase 1 has 4 build-time platform identities
  (`zx48 | zx128 | cpc464 | cpc6128`), all on the *machine-identity
  axis*. The memory-model axis used by [banking.md §4.4](banking.md)
  uses 4 corresponding values (`zx48 | zx128 | cpc-flat | cpc-banked`).
  Mapping is **bijective in Phase 1**: `zx48→zx48`, `zx128→zx128`,
  `cpc464→cpc-flat`, `cpc6128→cpc-banked`. Both macro families are
  emitted: `BUILD_FEATURE_PLATFORM_CPC6128` (machine identity) *and*
  `BUILD_FEATURE_PLATFORM_CPC_BANKED` (memory model). Engine
  `#ifdef`s pick whichever is semantically right — banking-aware
  code tests `CPC_BANKED`; firmware-specific code tests `CPC6128`.
  The two axes are kept conceptually distinct so a future platform
  (e.g. MSX with a 64K and a 128K variant) can sit at one identity
  but two memory models, or vice versa.

- A new game_config field `PLATFORM <value>` takes precedence when present.
  When absent, the legacy `ZX_TARGET` field maps to `zx48`/`zx128` as
  above. This guarantees every existing test game and every existing
  user game keeps building with no change.

- The build top-level (`make build`) replaces its
  `grep -E 'ZX_TARGET.+(48|128)$$'` dispatch
  (`Makefile:61-65`) with a single helper script
  `tools/detect-platform.sh` that:
  1. Looks for `PLATFORM <value>` in `game_config/*.gdata` first;
  2. Falls back to `ZX_TARGET 48|128` → `zx48|zx128`;
  3. Falls back to `zx48` with a warning;
  4. Validates the result against the allowed set;
  5. Prints the value (stdout) for `$(shell …)` capture.

- The `data` step continues to receive a target-equivalent value;
  `datagen.pl` learns a new `-p <platform>` option (`-t` deprecated but
  still accepted with mapping). `datagen.pl` emits the matching
  `BUILD_FEATURE_PLATFORM_*` macro (e.g. `BUILD_FEATURE_PLATFORM_CPC6128`)
  in addition to keeping `BUILD_FEATURE_ZX_TARGET_*` for compatibility.
  Detail in `assets.md`.

**Interaction with existing `SPRITE_ENGINE`**:

Rename `SPRITE_ENGINE` → **`GFX_BACKEND`** at the Makefile/.gdata level
(see also `gfx.md`). Default still `sp1`. Allowed values per platform:

| PLATFORM  | Default `GFX_BACKEND` | Allowed                                   |
|-----------|-----------------------|-------------------------------------------|
| `zx48`    | `sp1`                 | `sp1`, `jsp`                              |
| `zx128`   | `sp1`                 | `sp1`, `jsp`                              |
| `cpc464`  | `cpctel`              | `cpctel` (future: `cpcrs`, other CPC libs)|
| `cpc6128` | `cpctel`              | `cpctel` (future: `cpcrs`, other CPC libs)|

**Backend naming rule**: a `GFX_BACKEND` value is the **short name of
the underlying library**, never a generic platform tag. ZX backends
follow this today (`sp1`, `jsp`); CPC backends do the same — `cpctel`
for cpctelera, `cpcrs` reserved for cpcrslib, `cpc<lib>` for any other
CPC graphics library added later. Engine code gates with
`#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL` (and parallel macros for
future entrants), matching `gfx.md`'s usage.

`SPRITE_ENGINE` (old name) remains accepted at the `.gdata` level
**indefinitely** as a silent alias for `GFX_BACKEND` (per README
§5.6). The Makefile-side variable name changes outright; only one
user (gfx.md) needs to know both names at any time.

### 3.2 Makefile restructure

The current per-memory-model file shape is the right shape; widen its
axis from "48 vs 128" to "platform-and-memory-model". Target layout:

```
Makefile                — top-level: clean, config, dispatch on PLATFORM
Makefile.common         — shared rules (mostly unchanged), but ZCC_TARGET
                          becomes a variable set by the per-PLATFORM file
Makefile-zx48           — was: Makefile-48 (renamed; alias kept)
Makefile-zx128          — was: Makefile-128 (renamed; alias kept)
Makefile-cpc-flat       — new: cpc464 (CPC664 also runs the cpc464 binary)
Makefile-cpc-banked     — new: covers cpc6128
Makefile.game           — unchanged
```

For the renamed files, keep one-line forwarding stubs `Makefile-48`
and `Makefile-128` that `-include Makefile-zx48` / `Makefile-zx128`,
so any external games that call `make -f Makefile-48` continue to
work. Per README §5.6, the forwarding stubs are **permanent and
silent** (no deprecation banner).

The top-level dispatch becomes:

```
build:
    $(MYMAKE) clean
    $(MYMAKE) PLATFORM=$$($(DETECT_PLATFORM)) config
    $(MYMAKE) PLATFORM=$$($(DETECT_PLATFORM)) data
    $(MYMAKE) -f Makefile-$$($(DETECT_PLATFORM)) build
```

… where `DETECT_PLATFORM = tools/detect-platform.sh` returns
`zx48|zx128|cpc-flat|cpc-banked` (the memory-model axis) — mapping
`cpc464 → cpc-flat`, `cpc6128 → cpc-banked` — and additionally
exporting the `CPC_MACHINE` variable so the
loader knows which firmware to call).

Per-platform Makefile responsibilities:

| File | Sets | Emits |
| --- | --- | --- |
| `Makefile-zx48` | `ZCC_TARGET=+zx`, `ZPRAGMA_INC=zpragma-zx48[-jsp].inc`, `LOADER_ORG=0x5E00`, `MAIN_ORG=0x5F00`, packagers use `+zx` | `game.tap` |
| `Makefile-zx128` | `ZCC_TARGET=+zx`, `ZPRAGMA_INC=zpragma-zx128.inc`, `BASE_CODE_ADDRESS=$(BASE_CODE_ADDRESS_128)`, `LOADER_ORG=0x8000`, packagers use `+zx` | `game.tap` |
| `Makefile-cpc-flat` | `ZCC_TARGET=+cpc`, `ZPRAGMA_INC=zpragma-cpc-flat.inc`, `MAIN_ORG=0x1200` (default) or game-specified, packagers use `+cpc` | `game.cpc`, `game.dsk` (`appmake +cpc` native), `game.cdt` (via `2cdt`) |
| `Makefile-cpc-banked` | `ZCC_TARGET=+cpc`, `ZPRAGMA_INC=zpragma-cpc-banked.inc`, dataset/codeset orgs as defined by `banking.md`, packagers use `+cpc` | `game.cpc`, `game.dsk` (`appmake +cpc` native), `game.cdt` (via `2cdt`) |

The generic rule that compiles `%.c → %.o` in `Makefile.common:145-147`
becomes `ZCC_TARGET`-parameterised — already is, structurally, since
`ZCC_TARGET` is already a variable; the value just stops being a global
constant and starts being set by the per-PLATFORM file *before*
`-include Makefile.common`.

### 3.3 Per-platform pragma + CRT

Five pragma files, one per platform/sprite-engine combination
(matching today's two-for-ZX48 pattern):

- `zpragma-zx48.inc` — was `zpragma-48.inc` (renamed)
- `zpragma-zx48-jsp.inc` — was `zpragma-48-jsp.inc`
- `zpragma-zx128.inc` — was `zpragma-128.inc`
- `zpragma-cpc-flat.inc` — new (CPC464/664; `CRT_ORG_CODE=0x1200` or
  override, `CRT_STACK_SIZE=...`, `CRT_ENABLE_EIDI=1`, `__MMAP=-1`
  pointing to a new `mmap-cpc-flat.inc`)
- `zpragma-cpc-banked.inc` — new (CPC6128 with banks; per
  `banking.md`'s decisions on org and stack)

A `zpragma-cpc-flat-cpctelera.inc` variant **only** appears if cpctelera's
runtime requires specific pragma deltas (firmware-disable, special
interrupt setup); decision deferred to `cpc-renderer.md`.

Keep `zpragma-48.inc` and `zpragma-128.inc` as one-line forwarding
includes **indefinitely** per README §5.6, silently (no `#warning`).

### 3.4 New build targets

**Platform-selection rule** (canonical statement in
[README.md §5.3](README.md) and [assets.md §2.1](assets.md);
mirrored here because the build targets enforce it):

- `make build` (no suffix) uses the `PLATFORM` declared in
  `Game.gdata` and builds from the shared `game_data/` directly.
  No overlay tree is required for the declared default.
- `make build-<platform>` (or `PLATFORM=<platform> make build`)
  overrides the `.gdata`'s declared platform. The override
  **requires** an opt-in overlay tree at `<platform>/game_data/`
  in the game directory. If the overlay tree is absent, the build
  is **rejected** with a clear error (e.g. *"game `foo` does not
  declare an overlay for platform `cpc6128` — add
  `cpc6128/game_data/` to opt in"*). There is **no fallback to
  the declared default**.

The detection logic lives in `tools/detect-platform.sh` (introduced
in Phase T1-1) — it returns the resolved platform identity given
CLI args + `Game.gdata` contents, and emits the rejection error
when the rule triggers.

**New top-level targets**:

```
make build                 # auto-dispatch per PLATFORM in .gdata
make build-zx48            # force ZX 48 (requires zx48/game_data/ overlay if not default)
make build-zx128           # force ZX 128 (requires zx128/game_data/ overlay if not default)
make build-cpc464          # force CPC 464  → Makefile-cpc-flat (also runs on CPC664)
make build-cpc6128         # force CPC 6128 → Makefile-cpc-banked
make build-cpc             # alias for build-cpc6128 (most-capable CPC)
```

**Legacy aliases** (kept **indefinitely** per README §5.6, silent):

```
make build48   # → build-zx48   (silent forwarding alias)
make build128  # → build-zx128  (silent forwarding alias)
```

**Per-test-game targets** in `Makefile:91-135` need no change; they all
go through `make build target_game=...` which auto-detects PLATFORM.
New CPC test games (added in Phase T3+ as `games/cpc-default/`,
`games/cpc-minimal/`) get parallel entries.

**`make all-test-builds`** continues to iterate over `ls games/`; each
game's `.gdata` declares its own PLATFORM, so the matrix expands
naturally. A new convenience target `make all-test-builds-zx` /
`make all-test-builds-cpc` filters by directory-name prefix for
focused regression runs.

---

## 4. Output packaging per platform

### 4.1 ZX Spectrum

Unchanged in shape, just renamed. Pipeline:

```
loader.bas ─┐
            ├─ bas2tap ─→ loader.tap ─┐
asmloader.asm ─ zcc → asmloader.bin ─→ +zx appmake → asmloader.tap ─┤
main.bin   ─ +zx appmake (--org MAIN_ORG) ─-> main.tap              ├─ cat → game.tap
bank_N.bin ─ +zx appmake (--org 0xC000)   ─-> bank_N.tap            │
sub_N.bin  ─ +zx appmake (--org 0x0000)   ─-> sub_N.tap             ┘
```

### 4.2 Amstrad CPC

Pipeline (logical equivalent):

```
loader.bas ─ Locomotive BASIC source in engine/loader-cpc/
           ─ converted with `tools/bas2cpc.pl` (new, small) ────┐
                                                                ├─ z88dk-appmake +cpc ─→ game.cpc
asmloader.asm ─ zcc +cpc -> asmloader.bin                       │   (AMSDOS file)
main.bin      ─ zcc +cpc (--no-crt) -> main.bin                 │
bank_N.bin    ─ zcc +cpc (--no-crt, --org as per banking.md)    ┘
                                                                ├─ z88dk-appmake +cpc -subtype=disk ─→ game.dsk
                                                                │
                                                                └─ 2cdt ─→ game.cdt
```

Three deltas from the ZX pipeline:

1. **BASIC loader is Locomotive BASIC**, not Sinclair BASIC. `bas2tap`
   does not apply. A small new tool `tools/bas2cpc.pl` converts a
   tokenised-equivalent Locomotive listing or, more pragmatically, the
   loader is provided **pre-assembled as a small Z80 stub** entered via
   AMSDOS — that is the simpler path and the one cpctelera itself uses.
   The chosen path is recorded in `cpc-renderer.md` once cpctelera's
   approach is confirmed; toolchain.md expects either to be feasible.
2. **The final blob is not a `cat` of TAP chunks.** For CPC:
   - **AMSDOS single-file (.cpc)**: only feasible for cpc-flat — one
     binary loaded by `RUN"FILE.CPC"`. Datasets/codesets/banks have to be
     embedded in the same file or live as siblings on a disk image.
   - **Disk (.dsk)**: native `z88dk-appmake +cpc -subtype=disk` packs an
     arbitrary set of binaries into a 178 KB or 720 KB DSK image. This is
     the natural output for CPC6128 with banks.
   - **Tape (.cdt)**: each section becomes a tape block; `2cdt` assembles
     them in order. `2cdt` is a single small C binary, easy to add to the
     CI image.
3. **Loader semantics**: the asmloader's job (load each block into the
   right bank, JP into code) requires different firmware calls on CPC.
   `tools/loadertool.pl` is refactored in Phase T1 (see T1-11) into a
   uniform **template-driven** engine: each platform owns an
   `asmloader.asm.in` template under
   `engine/loader-<platform>/`, and the tool loads the template,
   substitutes placeholders, and writes `asmloader.asm`. CPC bring-up
   then **adds two more templates** rather than introducing a new
   mechanism. The four templates that exist after Phase T3 are:
   `engine/loader-zx48/asmloader.asm.in`,
   `engine/loader-zx128/asmloader.asm.in`,
   `engine/loader-cpc-flat/asmloader.asm.in` and
   `engine/loader-cpc-banked/asmloader.asm.in`. `loadertool.pl` carries
   no platform-specific inline loader text. The CPC template bodies
   themselves are designed in `cpc-renderer.md` / `banking.md`.


### 4.3 Loader stack

| Platform             | BASIC loader source                                                                                                                 | Tokenisation                | Boot mechanism         |
|----------------------|-------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|------------------------|
| zx48 / zx128         | `engine/loader-zx{48,128}/loader.bas` (Sinclair)                                                                                    | `bas2tap`                   | `RANDOMIZE USR <addr>` |
| cpc464 (also CPC664) | none (boot via AMSDOS-headed `.cpc` — CPC464 via tape, CPC664 via either) — or trivial Locomotive `MEMORY` + `LOAD` + `CALL` script | (none) or pre-assembled asm | AMSDOS `RUN"FILE.CPC"` |
| cpc6128              | small Locomotive script that sets up memory and `CALL`s asmloader, or pure asmloader entry                                          | same                        | AMSDOS `RUN"FILE.CPC"` |

The directory rename `engine/loader{48,128}/` → `engine/loader-zx{48,128}/`
happens as part of Phase T1 (introducing PLATFORM symmetry); new dirs
`engine/loader-cpc-flat/` and `engine/loader-cpc-banked/` appear in Phase
T2/T3 with CPC bring-up.

---

## 5. CI image evolution

`docker/Dockerfile` needs three additions and one possible change:

1. **z88dk version bump** — verify the pinned `Z88DK_TAG="v2.3"` includes
   working `+cpc` for our use cases. v2.3 is from 2023; `+cpc` has been
   stable since well before. If a newer pinned tag (e.g. v2.4) is needed
   for any CPC fix or for cpctelera ABI parity, bump it in Phase T0.
2. **`2cdt` install** — small `dnf install -y` or a 30-line
   `git clone && make` for CDT output generation. Mandatory for CPC tape
   distribution (optional for disk-only distribution).
3. **CPC graphics library** — vendored as a git submodule under
   `external/<libname>/` (the JSP-precedent pattern). No image change
   needed for vendored sources; if cpctelera's `cpct_*` asset tools are
   used at build time, the CI image needs them. Two options:
   a. Build the `cpct_*` tools from the vendored submodule inside the
      image (cpctelera's tools have a `make tools` style target).
   b. Install precompiled cpctelera tool binaries from a release.
   Decision recorded in `cpc-renderer.md`. From the CI-image perspective
   the difference is one `RUN` block of Dockerfile.
4. **Emulators (for `tests/00regression/` extension)** — out of
   toolchain.md scope, owned by `testing.md`. The image probably gains
   Caprice32 or RVM headless support.

The `build-z88dk-docker.yaml` workflow is content-addressed on
`docker/Dockerfile`, so any change auto-rebuilds and pushes the image.
The image tag `zxjogv/rage1-z88dk:latest` is the right name to keep
(it's not "z88dk-only" any more, but renaming the image is a Docker Hub
operation, not a code change, and `:latest` plus a soft `:cpc-ready`
tag during Phase T2 is sufficient).

CI matrix change in `.github/workflows/build-test-games.yaml`:
`make all-test-builds` already iterates all games; once CPC test games
exist in `games/cpc-*/`, they build automatically. A second job
`build-cpc-only` (just `make all-test-builds-cpc`) makes failures
attributable in PR checks.

---

## 6. Phased work plan

Phases are sized so each is independently testable and lands the tree
green per the project's "phase-exit green" rule. Each task lists what to
change, what to test, and what "done" looks like.

### Phase T0 — Spike: prove z88dk `+cpc` + sdcc_iy with vendored CPC lib

Establish the chosen toolchain stack works end-to-end with a "hello
sprite" CPC program before any RAGE1 plumbing changes. No RAGE1 code is
modified.

- **T0-1** Add `external/cpctelera/` as a git submodule, mirroring
  the JSP precedent (`Makefile.common:127-134`, commit `cc8e942`).
  This is the **canonical** submodule-add step for the CPC renderer
  library; cpc-renderer.md Phase R1 only verifies, pins, and records
  licence/attribution after the fact (no second `git submodule add`).
  Also recurse-update the CI checkout (`.github/workflows/build-test-games.yaml`
  already does this from JSP work).
  *Test*: `git submodule update --init external/cpctelera` clones
  cleanly; `external/cpctelera/cpctelera/src/cpctelera.h` exists.
  *Done*: `external/cpctelera/` populated; submodule pointer in the
  index.
- **T0-2** Add a throwaway smoke-test at `misc/cpc-spike/`: a single
  `.c` file that includes the CPC library's main header and calls a
  trivial draw primitive. *Test*: compile with
  `zcc +cpc -clib=sdcc_iy -I external/<lib>/include
  external/<lib>/src/*.{c,asm} misc/cpc-spike/hello.c -create-app
  -o hello.cpc`. *Done*: AMSDOS `.cpc` file produced; loads under
  Caprice32 and draws something visible.
- **T0-3** Repeat T0-2 with `-subtype=disk` to confirm DSK generation.
  *Done*: `.dsk` boots under Caprice32 and runs the spike.
- **T0-4** Confirm `#pragma bank 4` produces a banked binary that loads
  correctly on CPC6128. *Done*: a two-banked spike (one function in
  bank 4, called from main) runs without crashing.
- **T0-5** Update `docker/Dockerfile` with z88dk tag bump (if needed),
  `2cdt` install, and cpctelera tools install. Push image. *Done*: CI
  workflow `build-z88dk-docker` succeeds and the new image can run the
  T0-2 compile inside `docker run`.
- **Phase-exit criteria**:
  - T0-2/T0-3/T0-4 spike artifacts exist on a branch and run on a real
    or emulated CPC.
  - The updated CI image is published.
  - `make all-test-builds` on master still green (we touched only
    `external/` and the Dockerfile).
  - **Spike code is deleted** before Phase T1 — it has served its
    purpose.

### Phase T1 — Introduce `PLATFORM` axis without touching CPC

Rename and re-factor the build matrix so adding a CPC Makefile in Phase
T2 is a pure-addition step. ZX is the only platform alive during this
phase; correctness is verified by all-green ZX tests at phase exit.

- **T1-1** Add `tools/detect-platform.sh` returning
  `zx48|zx128`. Hook it into `Makefile:60-65` `build` target to replace
  the existing `grep -E 'ZX_TARGET.+(48|128)'` chain. Honours new
  `PLATFORM <value>` `.gdata` field if present; falls back to
  `ZX_TARGET`. *Test*: `make build target_game=games/default`,
  `make build target_game=games/default_jsp`,
  `make build target_game=games/sub_bufs_128` — all build green.
  *Done*: dispatch script in place, behaviour identical.
- **T1-2** Rename `Makefile-48` → `Makefile-zx48`, `Makefile-128` →
  `Makefile-zx128`. Add one-line forwarding stubs at the old names,
  **silent** (no deprecation echo, per README §5.6). *Test*:
  `make build48`, `make build128`, `make -f Makefile-48 build` all
  still work. *Done*: rename complete; legacy entry points succeed
  silently as permanent aliases.
- **T1-3** Rename `zpragma-48.inc` → `zpragma-zx48.inc`,
  `zpragma-48-jsp.inc` → `zpragma-zx48-jsp.inc`,
  `zpragma-128.inc` → `zpragma-zx128.inc`. Update internal references
  in the Makefiles. Keep silent forwarding stubs at old names (no
  `#warning`, per README §5.6). *Test*: `make all-test-builds`.
  *Done*: all green.
- **T1-4** Rename `engine/loader48/` → `engine/loader-zx48/`,
  `engine/loader128/` → `engine/loader-zx128/`. Update internal refs.
  *Test*: `make all-test-builds`. *Done*: all green.
- **T1-5** Add new top-level targets `build-zx48`, `build-zx128`.
  Make `build48`, `build128` silent permanent aliases (no
  deprecation echo, per README §5.6). *Test*: both old and new
  names work. *Done*: documented in Makefile `help`.
- **T1-6** Generalise `ZCC_TARGET` so it is *set per
  `Makefile-<platform>` file before* `-include Makefile.common` rather
  than being a literal constant in `Makefile.common:121`. *Test*:
  `make all-test-builds`. *Done*: `Makefile.common` no longer mentions
  `+zx`; only the per-platform Makefiles do.
- **T1-7** Generalise `z88dk-appmake +zx` invocations: introduce
  `APPMAKE = z88dk-appmake $(ZCC_TARGET)` in `Makefile.common`, replace
  each literal `z88dk-appmake +zx` in `Makefile.common`,
  `Makefile-zx48`, `Makefile-zx128`, and per-SUB game Makefiles with
  `$(APPMAKE)`. *Test*: `make all-test-builds`. *Done*: literal `+zx`
  in build files reduced to `ZCC_TARGET=+zx` lines in
  `Makefile-zx{48,128}` only.
- **T1-8** Teach `datagen.pl` a new `-p <platform>` option that accepts
  `zx48|zx128` (CPC values stub to "not yet implemented") and emits
  `BUILD_FEATURE_PLATFORM_ZX48`/`_ZX128` alongside the existing
  `BUILD_FEATURE_ZX_TARGET_*`. Keep `-t` working. *Test*:
  `make all-test-builds`; grep generated `features.h` for both old and
  new macros. *Done*: both macros present.
- **T1-9** Rename `SPRITE_ENGINE` variable to `GFX_BACKEND` at the
  Makefile level. Keep `.gdata` field name `SPRITE_ENGINE` as a
  **permanent silent alias** for `GFX_BACKEND` (README §5.6).
  *Test*: `make build-default`, `make build-default_jsp`,
  `make build-minimal_jsp`. *Done*: variable rename complete; both
  engines build; `.gdata` alias keeps working indefinitely.
- **T1-10** Update `tools/loadertool.pl` to take a `--platform` option;
  for `zx48`/`zx128` the behaviour is identical to today (default
  values match). *Test*: `make all-test-builds`. *Done*: option in
  place, default unchanged.
- **T1-11** Refactor `tools/loadertool.pl` into a uniform
  **template-driven** engine: the tool loads
  `engine/loader-<platform>/asmloader.asm.in`, substitutes
  placeholders, and writes `asmloader.asm`. Extract the current inline
  ZX48 and ZX128 loader bodies into
  `engine/loader-zx48/asmloader.asm.in` and
  `engine/loader-zx128/asmloader.asm.in` respectively. The tool must
  carry no platform-specific inline loader text — all loader bodies
  live in the templates. *Test*: `make all-test-builds` green;
  `tests/00regression/` screenshot tests green for ZX games; emitted
  `asmloader.asm` is byte-identical (or functionally equivalent) to
  the pre-refactor output. *Done*: ZX loaders driven by templates, no
  inline loader text remains in `loadertool.pl`, CPC bring-up in T2/T3
  becomes "add new template" rather than "introduce new mechanism".
- **Phase-exit criteria**:
  - `make all-test-builds` green.
  - `tests/00regression/` screenshot tests green for ZX games.
  - No literal `+zx` outside the per-platform Makefile files.
  - `Makefile.common` references `ZCC_TARGET` only, never `+zx`.
  - `loadertool.pl` contains no platform-specific inline loader text;
    all loader bodies live in `engine/loader-<platform>/asmloader.asm.in`.

### Phase T2 — CPC464/664 bring-up (cpc-flat, no banking)

Add the CPC toolchain in flat (CPC464/664) memory model. Produces a
**minimal** CPC binary from a CPC-specific test game; full RAGE1 feature
parity comes in later phases owned by gfx/audio/input subsystems.

- **T2-1** Add `Makefile-cpc-flat` modeled on `Makefile-zx48` with:
  `ZCC_TARGET=+cpc`, `ZPRAGMA_INC=zpragma-cpc-flat.inc`, packagers
  using `+cpc`. Initially supports only `make build` of a hello-world
  C program (no engine integration). *Test*: `make -f Makefile-cpc-flat
  build target_game=games/cpc-hello`. *Done*: a `.cpc` file is
  produced.
- **T2-2** Add `zpragma-cpc-flat.inc` (`CRT_ORG_CODE=0x1200`,
  `CRT_STACK_SIZE`, `CRT_ENABLE_EIDI=1`, `__MMAP=-1`,
  `mmap-cpc-flat.inc`). *Test*: T2-1 still builds; produced binary's
  org matches. *Done*: pragma file checked in.
- **T2-3** Add `mmap-cpc-flat.inc` modeled on `mmap.inc` but with CPC
  memory layout (placeholders for screen, firmware reserve, code).
  Detail validated against `cpc-renderer.md` decisions and
  `banking.md`. *Test*: T2-1 build's `.map` file places sections
  inside the expected regions. *Done*: section-check passes.
- **T2-4** Add `engine/loader-cpc-flat/` with either a trivial
  Locomotive BASIC stub or an AMSDOS-loaded asm entry (decision per
  `cpc-renderer.md`). *Test*: a `games/cpc-hello/` game builds a
  `game.cpc` that runs in Caprice32. *Done*: hello-world CPC game
  runs in CI emulator (link to `testing.md` regression infra).
- **T2-5** Teach `tools/loadertool.pl` `--platform=cpc-flat` to emit
  the CPC loader template. *Test*: `make build-cpc464
  target_game=games/cpc-hello`. *Done*: asmloader for CPC emitted.
- **T2-6** Teach `datagen.pl` `-p cpc464`; emit
  `BUILD_FEATURE_PLATFORM_CPC464` and `BUILD_FEATURE_PLATFORM_CPC_FLAT`.
  *Test*: `make build-cpc464 target_game=games/cpc-hello`. *Done*:
  macros visible in `features.h`.
- **T2-7** Add top-level `build-cpc464` target to `Makefile`.
  *Test*: works; `make build target_game=...` picks cpc-flat when
  `.gdata` declares `PLATFORM cpc464`. *Done*: dispatch is symmetric
  with ZX. (CPC664 is supported as a *runtime target* of the
  cpc464 build; no separate `build-cpc664` target.)
- **T2-8** Add `2cdt` packaging path to `Makefile-cpc-flat`. *Test*:
  `games/cpc-hello` produces `game.cpc`, `game.dsk` and `game.cdt`.
  *Done*: three artifacts produced; at least `.cpc` and `.dsk` boot
  under emulator.
- **T2-9** Update `docker/Dockerfile` to install `2cdt`. *Test*:
  `build-z88dk-docker.yaml` rebuilds image; CI `build-test-games`
  succeeds. *Done*: image published.
- **T2-10** Add `games/cpc-hello/` test game (mirroring `games/minimal`
  shape but with `PLATFORM cpc464` and a minimal `.gdata` set
  consumable by the current `datagen.pl`). At this phase, gfx and
  input HALs may be stubbed — the goal is that the toolchain emits a
  binary that boots. *Test*: `make build-cpc464
  target_game=games/cpc-hello` produces a runnable artifact.
  *Done*: artifact runs in Caprice32 with a static screen.
- **Phase-exit criteria**:
  - `make all-test-builds-zx` (ZX subset) green.
  - `make build-cpc464 target_game=games/cpc-hello` produces a
    runnable artifact end-to-end with no manual intervention.
  - CI image has `2cdt` and any required cpctelera tools.
  - `Makefile-cpc-flat` and `zpragma-cpc-flat.inc` checked in.

### Phase T3 — CPC6128 bring-up (cpc-banked)

Add the banked CPC memory model. Most of the *banking strategy* itself
lives in `banking.md`; this phase is the toolchain plumbing that lets a
banked CPC build produce a working DSK.

- **T3-1** Add `Makefile-cpc-banked` modeled on `Makefile-zx128` with
  CPC equivalents: `ZCC_TARGET=+cpc`, banked compile of datasets and
  codesets via `--no-crt`, `#pragma bank` driven splits per
  `banking.md`. *Test*: builds a hello-banked CPC test game.
  *Done*: produces `game.dsk` with main + at least one bank file.
- **T3-2** Add `zpragma-cpc-banked.inc` with CPC6128 org and stack
  per `banking.md`. *Test*: T3-1 build's `.map` shows sections in
  the right CPC banks. *Done*: pragma file checked in.
- **T3-3** Add `mmap-cpc-banked.inc`. *Test*: section-check passes.
  *Done*: file checked in.
- **T3-4** Add `engine/loader-cpc-banked/` with a CPC6128-aware loader
  (firmware bank-switching). *Test*: `games/cpc-hello-banked/` builds
  and at least main+1 bank load and run. *Done*: artifact loads on
  emulator.
- **T3-5** Teach `tools/banktool.pl` a `--platform` flag and a
  CPC6128 bank-number policy (replacing the ZX `1,3,7,6,4` lists
  with CPC equivalents per `banking.md`). *Test*: a multi-dataset
  CPC build produces correctly-numbered bank files. *Done*: tool
  emits correct mapping; bank-info ASM matches.
- **T3-6** Teach `tools/loadertool.pl` `--platform=cpc-banked`.
  *Test*: `make build-cpc6128 target_game=games/cpc-hello-banked`.
  *Done*: emitted loader bank-switches correctly.
- **T3-7** Teach `datagen.pl` `-p cpc6128`; emit
  `BUILD_FEATURE_PLATFORM_CPC6128`. *Test*: build works. *Done*:
  macro in `features.h`.
- **T3-8** Add top-level `build-cpc6128` target. *Test*: end-to-end
  banked CPC build works. *Done*: dispatch is symmetric.
- **T3-9** Add `games/cpc-hello-banked/` test game. *Test*: CI runs
  it. *Done*: artifact runs in Caprice32 with at least one
  dataset-equivalent swap visible.
- **Phase-exit criteria**:
  - `make all-test-builds-zx` (ZX subset) green.
  - `make build-cpc6128 target_game=games/cpc-hello-banked` produces
    a working banked CPC artifact.
  - `tools/banktool.pl` and `tools/loadertool.pl` carry no
    platform-specific behaviour in switch-anchored common code paths.

### Phase T4 — `make all-test-builds` matrix completion

By the time T3 closes, the toolchain is functionally complete and the
remaining work is convergence with the other subsystem plans (gfx,
audio, input, banking, assets). T4's job is to expand the test-build
matrix so CI catches regressions on both platforms.

- **T4-1** Add CPC equivalents of every ZX test game that has a
  semantic CPC equivalent (`games/cpc-minimal/`, `games/cpc-blobs/`,
  `games/cpc-mapgen/`, …). Some ZX games (e.g. JSP-specific ones) have
  no CPC counterpart; those are simply absent. *Test*:
  `make all-test-builds-cpc` builds them all green. *Done*: matrix
  expanded.
- **T4-2** Add `.github/workflows/build-test-games.yaml` matrix
  strategy: jobs for `zx` and `cpc` flavours. *Test*: PR CI runs both
  jobs. *Done*: separately attributable in PR check status.
- **T4-3** *(originally "remove legacy aliases" — DROPPED per
  README §5.6 backwards-compat-indefinite.)* Documentation-only
  pass: confirm every forwarding stub from T1 (`Makefile-48`,
  `Makefile-128`, `zpragma-48*.inc`, `engine/loader48/`,
  `engine/loader128/`, `build48`, `build128`, `SPRITE_ENGINE`
  alias) is in place and silent (no deprecation banners), and that
  `CHANGELOG.md` records the rename as "old name remains accepted
  indefinitely". *Test*: `make all-test-builds`. *Done*: CHANGELOG
  note added; no removal happens.
- **T4-4** Update `doc/USAGE-OVERVIEW.md`, `doc/TOOLS.md`,
  `doc/MEMORY-MAP.md`, and `CLAUDE.md` to reflect the multi-platform
  reality. *Test*: docs review. *Done*: docs landed.
- **Phase-exit criteria**:
  - `make all-test-builds` builds both ZX and CPC test games green.
  - CI runs the matrix.
  - Every legacy alias from T1 still works (silently) — verified
    by `make build48`, `make build128`, `make -f Makefile-48 build`,
    and an external-game smoke build using `SPRITE_ENGINE` in
    `.gdata`.
  - Documentation matches reality.

### Sketch only: MSX (Z80)

MSX is z80 + VDP — the toolchain layer would reuse the entire
decision matrix above with `+msx` as a fifth platform and an
`msx-gfx` / `msx-audio` HAL. No deep work needed in Task 1; the
`PLATFORM` / `GFX_BACKEND` axis is extensible.

(C64 is **out of scope** for this project entirely — see
[README §5.7](README.md). The toolchain architecture deliberately
does not leave hooks for a 6502 sibling; a future C64 port would
be a separate project.)

---

## 7. Risks

- **R-T1 — cpctelera library expects its own SDCC version.** cpctelera
  pins SDCC 3.5.5 / 3.6.8 (per its setup). z88dk v2.3 ships a newer SDCC.
  If cpctelera's `.asm`/`.c` source uses SDCC-internal idioms that
  changed between versions, the z88dk-driven build of those sources may
  fail or, worse, mis-codegen. Phase T0's spike directly verifies this.
  Mitigation if it fails: pick a leaner CPC library (per `cpc-renderer.md`)
  or maintain a minimal locally-patched fork of cpctelera in
  `external/`.
- **R-T2 — z88dk-appmake CDT output is missing.** Confirmed: CDT
  generation requires the external `2cdt` tool. This adds one CI image
  dependency but is otherwise trivial. Risk only materialises if
  `2cdt` becomes unmaintained; a fallback is generating WAV (which
  z88dk-appmake +cpc supports natively) and converting offline.
- **R-T3 — Locomotive BASIC tokeniser availability.** No widely-used
  Python/Perl Locomotive BASIC tokeniser equivalent of `bas2tap` exists.
  We sidestep this by using AMSDOS-headed `.cpc` files entered via
  `RUN"FILE.CPC"` (BASIC line is one user-typed command, not a tokenised
  loader file). If a tokenised loader is needed for tape distribution,
  hand-assembled raw tokens are the fallback.
- **R-T4 — `+cpc` clib gaps vs `+zx` clib.** z88dk's `+cpc` `sdcc_iy`
  clib is well-supported but receives less testing than `+zx`. Specific
  features RAGE1 relies on (e.g. specific `string.h`/`stdint.h`/inline
  asm patterns) might surface latent issues. Mitigated by Phase T0
  spike covering the engine's core C idioms.
- **R-T5 — Per-SUB game Makefiles need migration.** Every game's
  `game_src/sub_*/Makefile` currently has its own `zcc +zx` /
  `z88dk-appmake +zx` invocation. Phase T1-7 fixes the engine and test-
  game-level Makefiles; user games (external repos) inherit the change
  via `Makefile.game`, but the per-SUB Makefiles in user trees would
  need re-running `make new-game` (or a migration recipe). Mitigation:
  publish a one-page migration note in `CHANGELOG.md` when T1 lands.
- **R-T6 — `tools/banktool.pl` is structurally ZX-specific.** Its bank
  number lists and 0xC000-window assumptions are baked-in. Phase T3-5
  parameterises this; if the rework is bigger than expected, consider
  spawning `tools/banktool-cpc.pl` and a small dispatcher rather than
  one tool with a `--platform` flag. Owned by `banking.md`.
- **R-T7 — `make -j` interactions.** `Makefile-zx128` hard-codes `-j8`;
  if the CPC Makefiles follow suit, the dependency graph changes
  (different per-bank steps) and parallel-build correctness must be
  re-verified per platform.
- **R-T8 — CI image size.** Adding cpctelera + tools + 2cdt + a CPC
  emulator (for `testing.md`) could push the image from ~1 GB to several
  GB. Mitigation: split into `:zx` and `:cpc` tagged variants and let
  the workflow pick.
- **R-T9 — CPC664 runtime divergence from CPC464.** Phase 1 treats
  CPC664 as a runtime target of the CPC464 build (memory-identical).
  If firmware divergence proves problematic (e.g. AMSDOS-required
  routines in the loader path that CPC464's BASIC ROM can't reach),
  CPC664 would need its own `PLATFORM` value and a tiny separate
  loader path. Mitigation: defer; the tape boot path is the safe
  common subset.

## 8. Open Questions

- **OQ-T1** — Is the `PLATFORM` variable name right, or should it be
  `RAGE1_PLATFORM` to avoid collisions with user-level Makefiles? The
  current name reads cleanest; the prefix is defensive. User input
  required before Phase T1.
- **OQ-T2** ✅ — Legacy `Makefile-48` / `Makefile-128` alias lifetime.
  **Resolved (2026-05-25): indefinite** per README §5.6
  (backwards-compat indefinite). The forwarding stubs are
  permanent and silent; T4-3 is no longer a removal task. Same
  policy applies to every other user-visible alias touched by
  this refactor (`build48` / `build128`, `zpragma-48*.inc`,
  `engine/loader48/`, `SPRITE_ENGINE`, `ZX_TARGET`,
  `BUILD_FEATURE_SPRITE_ENGINE_*`, `datagen.pl -t`).
- **OQ-T3** — Is z88dk v2.3 the right pinned version, or should T0
  bump to a more recent z88dk tag (v2.4+) to get the latest `+cpc`
  fixes? Trade-off: newer z88dk may also bring SDCC version changes that
  affect ZX code-gen. Verify with a clean `make all-test-builds` on a
  v2.4 spike branch.
- **OQ-T4** — Which CPC graphics library is vendored? toolchain.md
  assumes cpctelera (or equivalent) but the decision lives in
  `cpc-renderer.md`. A non-cpctelera choice (e.g. CPCRSlib, or a
  minimal hand-rolled `gfx_<libname>` library) changes Phase T0's spike
  target and Phase T2's CRT pragma but not the build-matrix design.
- **OQ-T5** — How are CPC test-game artifacts validated in CI? The
  current ZX path uses FUSE for `make run` and JNEXT for screenshots
  (`tests/00regression/`). The CPC path will need Caprice32 or RVM
  headless — owned by `testing.md`, but its choice affects which
  emulator binary the CI image must contain.
- **OQ-T6** — Should the CPC banking model use `#pragma bank` numbers
  literally identical to the ZX 128K convention (i.e. share the same
  bank-id space conceptually) or stay independent? Affects whether
  `banktool.pl` becomes one tool or two. Decision owed by `banking.md`.
- **OQ-T7** — For CPC tape distribution, do we need CDT at all, or is
  AMSDOS DSK + a CDT generated only on-demand sufficient? CDT
  generation is small but adds CI dependency; punting it to "on
  demand" simplifies the standard build to `.cpc` + `.dsk` only.
- **OQ-T8** — Does the cpctelera (or chosen library) submodule require
  any of cpctelera's build-system invariants to be honoured (e.g.
  specific `M4`/`#pragma` setup that its lib sources expect)? Phase T0
  must surface these so we can either honour them in our Makefile or
  patch them out.
- **OQ-T9** — Does the `--no-crt` compile of CPC datasets/codesets
  need different firmware-disable pragmas than the main binary?
  z88dk has `CRT_ENABLE_RST_xx` family; verify in Phase T0 spike.
- **OQ-T10** — For external games using `Makefile.game`, do we want a
  game-side `make build-cpc6128` shortcut, or do they always go
  through `make build` with `.gdata`-declared `PLATFORM`? Plan
  currently assumes the latter (less surface). Confirm before T2.
- **OQ-T11** ✅ — Banking mechanism. **RESOLVED (2026-05-26)** by
  [banking.md OQ-B11](banking.md): **extend RAGE1's existing
  custom banking** to CPC (Option A). z88dk's `#pragma bank` is
  not used on either platform. Migration to z88dk's mechanism is
  deferred to a future dedicated task (captured as banking.md
  Risk R13). Toolchain side: T3-5 (banktool.pl `--platform`) and
  T1-11 (loadertool.pl template-driven) cover the work; no
  toolchain.md rewrites needed beyond softening the §2.1
  `#pragma bank` discussion to make explicit that RAGE1 doesn't
  use it.
