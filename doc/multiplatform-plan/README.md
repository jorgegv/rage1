# RAGE1 cross-platform plan (ZX + CPC)

This directory is the **plan deliverable** for [Task 1 of
`.prompts/2026-05-23.md`](../../.prompts/2026-05-23.md): turn RAGE1
from a ZX-only engine into a cross-platform engine that builds the
same game (mostly shared `.gdata` plus minimal per-platform overlays)
for both **ZX Spectrum** (48 / 128) and **Amstrad CPC** (464 / 664 /
6128).

Task 1 produces documentation only — no engine refactor or code
change happens under it. Execution is a separate future task. The
plan is a **living document during execution**: subsequent execution
tasks may revise phases, add or split steps, fold in risks discovered
during work, or correct architectural choices that don't survive
contact with reality.

> **Status**: initial draft assembled by 8 parallel subsystem agents
> (2 waves of 4), independently reviewed (8 reviews), reworked
> against the review findings, and **user review-1 complete across
> all 9 documents** as of 2026-05-26 (per-doc commits recorded in
> the §8 progress checklist). Awaiting final user approval of the
> initial plan before execution begins.

---

## Table of contents

- [Table of contents](#table-of-contents)
- [1. Phase 1 platforms](#1-phase-1-platforms)
- [2. Architectural anchors (decided before drafting; the plan reflects, does not re-analyse)](#2-architectural-anchors-decided-before-drafting-the-plan-reflects-does-not-re-analyse)
- [3. Subsystem documents](#3-subsystem-documents)
- [4. Cross-cutting phase sequence](#4-cross-cutting-phase-sequence)
- [5. Cross-doc decisions reconciled here](#5-cross-doc-decisions-reconciled-here)
  - [5.1 CPC asset conversion: cpctelera subprocess, not Perl-side encoders](#51-cpc-asset-conversion-cpctelera-subprocess-not-perl-side-encoders)
  - [5.2 Per-platform overlay tree: sibling, not sub-tree](#52-per-platform-overlay-tree-sibling-not-sub-tree)
  - [5.3 Platform-selection rule: CLI \> Game.gdata; no fallback](#53-platform-selection-rule-cli--gamegdata-no-fallback)
  - [5.4 GFX\_BACKEND naming rule: value = library short-name](#54-gfx_backend-naming-rule-value--library-short-name)
  - [5.5 Two-layer colour model: bitmap universal, attribute ZX-only](#55-two-layer-colour-model-bitmap-universal-attribute-zx-only)
  - [5.6 Backwards compatibility is INDEFINITE](#56-backwards-compatibility-is-indefinite)
  - [5.7 C64 is OUT OF SCOPE](#57-c64-is-out-of-scope)
  - [5.8 BTile cell data flavour discriminator](#58-btile-cell-data-flavour-discriminator)
  - [5.9 CPC mono game mode reuses the existing mono path with 1bpp BTile cells](#59-cpc-mono-game-mode-reuses-the-existing-mono-path-with-1bpp-btile-cells)
  - [5.10 Generic FG/BG colour token vocabulary](#510-generic-fgbg-colour-token-vocabulary)
  - [5.11 Generalised PATCH directives across .gdata sections](#511-generalised-patch-directives-across-gdata-sections)
- [6. Consolidated Risks index](#6-consolidated-risks-index)
- [7. Consolidated Open Questions index](#7-consolidated-open-questions-index)
- [8. Progress tracking](#8-progress-tracking)
- [9. How to read and revise this plan](#9-how-to-read-and-revise-this-plan)

---

## 1. Phase 1 platforms

In scope (the plan covers these in depth):

- **ZX Spectrum**: ZX48 and ZX128
- **Amstrad CPC**: CPC464 and CPC6128 (CPC664 is a *runtime target* of
  the CPC464 build — memory-identical to CPC464, so the same binary
  runs on it; it is not a separate build identity)

Sketched only (long-horizon future direction; no detailed analysis):

- **MSX** — Z80-family, similar enough that nothing in this plan
  should block a later MSX port. Kept as an explicitly open option:
  every HAL choice in the plan stays MSX-friendly.

**Out of scope:**

- **Commodore 64** — 6502 architecture and sprite+bitmap graphics
  model would require a separate porting project, not a backend
  within this design. Not addressed by any subsystem doc in this
  plan. See §5.7.

> **Note on the two PLATFORM-axis spellings.** Two spellings of the
> platform axis appear in the plan and are *both intentional*:
> [toolchain.md](toolchain.md) uses the **machine-identity axis**
> (`zx48 | zx128 | cpc464 | cpc6128`); [banking.md](banking.md) uses
> the **memory-model axis** (`zx48 | zx128 | cpc-flat | cpc-banked`).
> The two axes are **bijective in Phase 1**: `zx48→zx48`,
> `zx128→zx128`, `cpc464→cpc-flat`, `cpc6128→cpc-banked`. Both macro
> families are emitted in `features.h` (e.g.
> `BUILD_FEATURE_PLATFORM_CPC6128` + `BUILD_FEATURE_PLATFORM_CPC_BANKED`);
> engine `#ifdef`s pick whichever is semantically right (machine-
> identity for firmware specifics, memory-model for banking-aware
> code). Kept conceptually distinct so a future platform with two
> memory models per machine (e.g. an MSX 64K/128K split) can sit
> at one identity with two memory-models, or vice versa.

## 2. Architectural anchors (decided before drafting; the plan reflects, does not re-analyse)

1. **Asset model**: shared-core `.gdata` + per-platform overlays in
   a parallel *sibling tree* `<platform>/game_data/` at the same
   level as `game_data/`. File-level shadow at `make config` copy
   time. The existing `patches/` mechanism is preserved unchanged.
   See [assets.md](assets.md).
2. **HAL position**: the existing `gfx_*` API (introduced for the
   SP1↔JSP split, stable post-JSP closure) **subsumes** into the
   multi-platform graphics HAL. SP1 and JSP both sit behind the same
   surface. No second abstraction layer above `gfx_*`. See
   [gfx.md](gfx.md). **Updated 2026-06-05 (§5.13):** the CPC graphics
   backend is **JSP in CPC mode**, not a separate "new CPC backend" —
   JSP is the single cross-platform backend (ZX + CPC); SP1 stays
   ZX-only.
3. **`audio_*` HAL**: same shape — shared API surface, per-platform
   backends (ZX beeper, ZX AY, CPC AY). Music + SFX in scope. See
   [audio.md](audio.md).
4. **`input_*` HAL**: same shape — gameplay-level events
   (up/down/fire/action keys) routed through a per-platform
   keyboard/joystick driver. See [input.md](input.md).
5. **CPC graphics backend**: ~~vendor **cpctelera** as a git submodule
   under `external/cpctelera`, mirroring the JSP precedent.~~
   **REVOKED 2026-06-05 (§5.13).** The CPC graphics backend is **JSP**
   (already vendored at `external/jsp`, already a RAGE1 backend on ZX,
   now with CPC support). cpctelera is fully dropped; the
   `external/cpctelera` submodule is removed. See
   [cpc-renderer.md](cpc-renderer.md).
6. **ZX back-compat**: best-effort, **green at phase boundaries**.
   Each phase must end with `make all-test-builds` green and
   `tests/00regression/` ZX screenshot tests green. Mid-phase
   regressions are acceptable if they unblock the architecture,
   provided the phase-exit criterion restores green.

## 3. Subsystem documents

Each subsystem has its own phased plan with numbered phases,
numbered tasks, phase-exit criteria, Risks, and Open Questions.

| Doc                                | Owns                                                                                                                                                          | Phases      |
|------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------|
| [gfx.md](gfx.md)                   | Graphics HAL audit; `gfx_*` API generalisation; `gfx_cpctel.c` interface; ZX-derived assumption removal                                                       | **G1–G9**   |
| [assets.md](assets.md)             | Shared-core `.gdata` + sibling-tree overlays; `datagen.pl` / `mapgen.pl` / `btilegen.pl` changes; per-platform asset converters; tracker file / music overlay | **A1–A7**   |
| [toolchain.md](toolchain.md)       | z88dk-only across all 4 platforms; `PLATFORM` axis; per-platform Makefile structure; CDT/DSK packaging; CI Docker image evolution                             | **T0–T4**   |
| [cpc-renderer.md](cpc-renderer.md) | **CPC graphics engine = JSP bring-up** (build integration, `gfx_jsp` CPC sections, asset pipeline, retire `gfx_cpctel`, remove cpctelera) — see §5.13. R1–R5 (cpctelera vendor/licence/translate) retained as history. | **R6–R10** (R1–R5 superseded) |
| [audio.md](audio.md)               | `audio_*` HAL design; ZX (beeper + AY/Vortex/Arkos2) and CPC (AT2 AKG generic player) backends; music/SFX asset overlay; `SOUND_MAP` directive                | **AU1–AU7** |
| [input.md](input.md)               | `input_*` HAL design; ZX (keyboard/Kempston/Sinclair) and CPC (cpctelera `cpct_scanKeyboard_if`) backends; per-game key-mapping config                        | **IN1–IN8** |
| [banking.md](banking.md)           | ZX 128 paging vs CPC Gate Array banking; datasets/codesets/SUBs per platform; per-platform memory maps; `banktool.pl` / `loadertool.pl` parametrisation       | **B1–B9**   |
| [testing.md](testing.md)           | Per-platform emulator strategy (FUSE/JNEXT for ZX; **Caprice32 + Xvfb** for CPC); `tests/00regression/` extension; per-platform baselines; CI matrix          | **TS1–TS6** |

Read order suggestion: start with this README; then `gfx.md` (anchors
the HAL pattern that other subsystems follow); then `assets.md`,
`toolchain.md`, `cpc-renderer.md` together (they jointly own the
build-side concerns); then `banking.md` (memory maps that everyone
plugs into); then `audio.md`, `input.md` in either order; then
`testing.md` last (it tests everything else).

Execution-tracking artefacts live under
[management/](management/):

- [management/00tasklist.md](management/00tasklist.md) — flat
  checkbox view of the 56 phases (the file to tick as work
  completes).
- [management/gantt.md](management/gantt.md) — graphical view of
  phase dependencies (master Gantt + per-phase Gantts + cross-
  subsystem DAG + critical path).

## 4. Cross-cutting phase sequence

Each subsystem's phases are numbered with its own prefix (G/A/T/R/
AU/IN/B/TS). The high-level sequence across all subsystems:

> **Updated 2026-06-05 (§5.13):** every `R`-prefixed cpctelera phase
> below (R1 submodule add, R2 cpctelera PoC, R3 `cpct_img2tileset`
> wiring, R5 cpctelera hardening) is **superseded** by the switch to
> JSP. They were executed and produced the *interim* `gfx_cpctel`
> backend; the CPC graphics engine is now JSP (new `R6–R10`, `G10`,
> `A8`). The sequence text below is preserved for history — read it
> together with §5.13's per-doc ripple table and the rewritten
> [cpc-renderer.md](cpc-renderer.md).

**Phase 1 — Foundation (no CPC code; pure preparation).**

- `TS1` — backfill ZX regression baselines (≥80 % of test games)
- `T0` — toolchain spike: prove z88dk `+cpc` + sdcc_iy + a tiny
  cpctelera build outside RAGE1
- `B1` — banking-config externalisation into
  `etc/rage1-config.yml` (ZX byte-identical)
- `G1` — `gfx_*` audit completion & baseline pin

**Phase 2 — HAL & asset-pipeline scaffolding (ZX-only, additive).**

- `G2` — `SPRITE_ENGINE` → `GFX_BACKEND` mechanical rename
- `A1` — introduce `PLATFORM` directive (`zx48`, `zx128` only)
- `A2` — sibling-tree overlay copy in `make config`
  (mechanism only; no overlay files yet)
- `T1` — `PLATFORM` axis throughout the Makefile family; ZX-only
- `B2` — per-platform ISR / codeset YAML split
- `IN1`, `IN2` — input audit + HAL skeleton (alias-only, ZX-only)
- `AU1`, `AU2` — audio audit + HAL aliases
- `R1` — cpctelera submodule add (vendored as reference; never compiled — Option (b) translation, see cpc-renderer.md §4.2/§6)

**Phase 3 — HAL generalisation (ZX byte-identical).**

- `G3–G6` — attribute / pixel coords / geometry / tile-ID abstraction
- `A3–A4` — per-platform dispatch seam in `datagen.pl`; overlay
  precedence proven end-to-end on ZX
- `B3` — parameterise lowmem threshold checks
- `IN3–IN4` — engine ↔ HAL migration; per-game `kbd.c` consolidation
- `AU3` — migrate engine + games to `audio_*` names (legacy
  `beeper_*` / `tracker_*` / `BUILD_FEATURE_TRACKER_*` spellings
  stay as permanent silent aliases per §5.6)

**Phase 4 — CPC bring-up (cpc-flat first, then cpc-banked).**

- `R2` — cpctelera + z88dk hello-world PoC (gating test)
- `R3` — `cpct_img2tileset` asset-converter wiring
- `T2` — cpc-flat Makefile; first `.cpc`/`.cdt` build
- `B4–B5` — CPC banking config seam (cpc-flat = no banking)
- `G7` — `gfx_cpctel.c` stub skeleton
- `IN5` — input CPC skeleton (stub)
- `AU4` — audio CPC skeleton + AT2 player relocation
- `A5` — `datagen.pl` invokes `cpct_img2tileset` for CPC assets
- `TS2` — Caprice32 + Xvfb in dev env + Docker
- `R4` — real `gfx_cpctel.c` + `games/minimal_cpc/`
- `G8` — real CPC backend wiring
- `IN6` — real CPC input via cpctelera keyboard scan
- `AU5` — real CPC audio via AT2 AKG generic player
- `TS3` — first CPC regression baseline
- `B6–B7` — cpc-banked banking infrastructure + tooling
- `T3` — cpc-banked Makefile; first banked `.dsk` build

**Phase 5 — Hardening + CI matrix expansion.**

- `R5` — cpctelera hardening, upstream feedback
- `G9` — CPC backend across 3+ games (blobs / crumbs / mapgen)
- `IN7` — optional `CONTROLLER` `.gdata` directive
- `AU6` — `SOUND_MAP` directive for cross-platform `SOUND` events
- `B8` — SUBs on CPC
- `TS4–TS5` — TAP-byte invariant mode; CI matrix expansion

**Phase 6 — Cleanup.**

- `A6–A7` — platform-scoped patches
- `T4` — matrix completion (legacy aliases like `ZX_TARGET`,
  `Makefile-48`, `SPRITE_ENGINE`, etc. are kept indefinitely per §5.6
  — no removal scheduled)
- `AU7` — audio cleanup (no removal of legacy `MUSIC` / `SOUND`
  spellings; they stay as aliases)
- `IN8` — input hardening, MSX sketch
- `B9` — banking cleanup (legacy macros stay as aliases)
- `TS6` — retire CPC-only stub games once shared games cover them

**Phase 7 — CPC video modes (Mode 0 / Mode 2 + MONO/FAST) + palette.**

- `CM1–CM8` — per-game `CPC_MODE`, palette, multi-pen colour, runtime
  palette changes, demos + baselines, docs. Plan APPROVED 2026-06-07 —
  see [cpc-modes.md](cpc-modes.md).

**Phase 8 — Engine performance optimization (first AI pass).**

- `PO1–PO7` — speed-measurement harness + baselines (PO1, gating
  prerequisite); loop-invariant/redundant-deref micro-opts (PO2);
  measured local→static (PO3); compiler flag/pragma tuning (PO4);
  targeted C→asm kernels for the hottest loops (PO5); hot-path
  hand-asm (PO6); docs + optimization log (PO7). Gate is *behavioral*
  (regression suite) + *measured* deltas, **not** byte-identity (this
  phase changes output by design). Plan PROPOSED 2026-06-08 — see
  [performance.md](performance.md).

This ordering is intentionally serialised across subsystems because
many phases depend on others (e.g. `G7` needs `R1`; `A5` needs `R3`;
`G8` needs `R4`; `TS3` needs `R4` and `G8`). The per-subsystem docs
contain the authoritative dependency notes for each phase.

## 5. Cross-doc decisions reconciled here

Architectural decisions that span more than one doc. Recorded here as
the canonical resolution; the per-subsystem docs reflect them.
Decisions are dated; resolved-during-review decisions land in
chronological order.

### 5.1 CPC asset conversion: in-datagen asset backend (REVERSED — was subprocess)

> **REVERSED 2026-06-06 (Task 5):** the *subprocess* decision is dropped.
> CPC asset conversion is an **in-process datagen asset backend** — datagen
> already holds the pixel grid (from `PIXELS`/`MASK` or PNG via GD), so it
> packs CPC mode-1 bytes directly (no PNG round-trip, no subprocess) and
> emits them inline in the same C structs as the ZX path. The packing is
> **copied/adapted from `external/jsp/tools/cpcgfx.pl`** (`cell_bytes`/
> `emit_cell`) into a RAGE1 module (`lib/RAGE/`); cpcgfx.pl itself stays in
> the JSP submodule, untouched. datagen's copy MAY diverge as long as the
> emitted **bytes stay JSP-compatible** — guarded by a byte-compat regression
> test (datagen output == cpcgfx.pl output for reference art). The original
> §5.1 rationale ("no foreign CPC encoder in Perl") no longer applies: the
> encoder is now JSP's own Perl, copied with a verified format contract.
> Implemented under **Task 5** (datagen asset-backend refactor) + assets.md A8.
> The 2026-06-05 subprocess note below is superseded.

> **Superseded 2026-06-05 (§5.13):** the *subprocess* decision stands, but
> the tool is **JSP's vendored converters** — `external/jsp/tools/cpcgfx.pl
> --mode 1` (4-pen colour) and `external/jsp/tools/gfxgen.pl` (1bpp /
> Mode 2 / MONO) — **not** cpctelera's `cpct_img2tileset`. They emit Z80
> **ASM** (`PUBLIC` + `db`), not C arrays, so the build links ASM rather
> than compiling generated C. `CPCT_PATH` / Img2CPC install steps are
> gone. The original cpctelera-worded decision below is retained for
> history; see §5.13 and assets.md A8.

**Decision (superseded)**: for CPC builds, RAGE1's asset pipeline shells out to
cpctelera's `cpct_img2tileset` (and the equivalent of its
`IMG2SPRITES` Makefile macro) to convert PNG → CPC C arrays. The
ZX path stays Perl-internal (`RAGE::PNGFileUtils`). No CPC
pixel/palette logic is added to `PNGFileUtils.pm`.

**Why**: cpctelera owns the canonical bug-for-bug pixel encoding
for the CPC runtime that will consume those bytes. Re-implementing
mode-0/1/2 packing in Perl would duplicate the work and risk
divergence over time.

**Where it lives**: `datagen.pl` gets a per-platform dispatcher
(Phase `A3`); the CPC branch invokes `tools/cpc_asset_convert.pl`
(Phase `A5`), a thin wrapper that gives `cpct_img2tileset` a fixed
invocation surface decoupled from cpctelera's `CPCT_PATH`-env
assumptions. The wrapper contract is documented as part of `A5-4`.

### 5.2 Per-platform overlay tree: sibling, not sub-tree

**Decision**: per-platform overrides live in a **sibling tree** at
`<platform>/game_data/...` (e.g. `cpc6128/game_data/btiles/`),
parallel to the shared `game_data/`. Not a sub-tree under
`game_data/cpc/`.

**Why**: cleaner symmetry, easier to reason about file-level shadow
semantics, easier to add another platform later. The asset pipeline
copy step in `make config` is one extra `cp -r` per platform.

**Where it lives**: defined in [assets.md §2.1](assets.md); used by
all docs that reference per-platform asset paths.

### 5.3 Platform-selection rule: CLI > Game.gdata; no fallback

**Decision (2026-05-23)**: the platform a build targets is resolved
as `CLI override > Game.gdata's PLATFORM directive`. Concretely:

- `Game.gdata` declares the **default platform** via the
  `PLATFORM` directive (mandatory after Phase A1's migration).
- `make build` with no platform suffix builds the declared default
  from the shared `game_data/` tree directly.
- `make build-<platform>` (or `PLATFORM=<platform> make build`)
  overrides the default. The build **requires** an overlay tree
  at `<platform>/game_data/`; if none exists, the build is
  **rejected** with a clear error. **No silent fallback to the
  declared default.**
- The shared `game_data/` IS the data for the declared default
  platform — no `<default>/game_data/` overlay is needed for it.
- Per-platform `game_src/<platform>/` overlays follow the same
  rule (independent axis).

**Why**: single-platform games stay maximally simple
(`PLATFORM zx128` + `game_data/`, no overlay tree needed). Cross-
platform games make their support explicit by adding the relevant
`<platform>/game_data/` directory (which can be empty if the
shared core is sufficient — the directory's existence is the
opt-in signal). The rejection-instead-of-fallback rule prevents
accidentally producing a build for a platform the game wasn't
authored for.

**Where it lives**: defined in [assets.md §2.1](assets.md) (rule)
and [assets.md Phase A1](assets.md) (implementation, task A1-6);
mirrored in [toolchain.md §3.4](toolchain.md) (build-target
semantics).

### 5.4 GFX_BACKEND naming rule: value = library short-name

**Decision (2026-05-24; updated 2026-06-05 §5.13)**: a `GFX_BACKEND`
value is the **short name of the underlying library**, never a generic
platform tag. Backends today: `sp1` (ZX-only), `jsp` (**cross-platform —
ZX and CPC**). The CPC graphics engine is `jsp`, selected by the
`PLATFORM` axis, not by a distinct backend value — the library is JSP on
both platforms, so by this very rule the value is `jsp`. `cpctel`
(cpctelera) and `cpcrs` (cpcrslib) remain **reserved names only** for any
future CPC library added as a first-class alternative; the `cpctel`
backend that Phase 4 built is the interim renderer being retired (§5.13).

**Why**: a generic `cpc` backend value would prevent multiple CPC
sprite libraries from coexisting as first-class backends. Naming by
library makes future CPC alternatives drop-in equivalents alongside
the existing ZX sp1/jsp pattern.

**Mechanical consequences**: `gfx_cpctel.{h,c}` (not `gfx_cpc.*`),
backend symbol prefix `gfx_cpctel_*`, feature macro
`BUILD_FEATURE_GFX_BACKEND_CPCTEL`. The platform-family identifier
`cpc` is retained for build targets (`make build-cpc`, etc.) and
Makefile filenames (`Makefile-cpc-flat`, `Makefile-cpc-banked`) —
those are platform tags, not backend names.

**Scope: gfx-only by design.** The library-short-name rule applies
to `GFX_BACKEND` only. The `input_*` and `audio_*` HALs use
platform/hardware tags in their backend filenames and feature
macros (`input_cpc.{h,c}` + `BUILD_FEATURE_INPUT_BACKEND_CPC`;
`audio_cpc_ay.{h,c}` + `BUILD_FEATURE_AUDIO_*_BACKEND_CPC_AY`)
because there is no competing CPC library to disambiguate against
on those axes today: input goes straight through cpctelera's
keyboard scan, and audio goes straight through the AY chip via
AT2's AKG generic player. If a second CPC input or audio library
ever appears as a first-class alternative, those HALs adopt the
same library-short-name pattern at that point. Until then, the
asymmetry is intentional.

**Where it lives**: rule defined in [toolchain.md §3.1](toolchain.md);
applied in [gfx.md §2.8 + §3.1–§3.3](gfx.md); ripples into
[cpc-renderer.md](cpc-renderer.md), [assets.md](assets.md).

### 5.5 Two-layer colour model: bitmap universal, attribute ZX-only

**Decision (2026-05-25)**: RAGE1's graphics surface is decomposed
into two layers, with explicit per-platform consumption rules.

- **Bitmap layer (universal)**: every backend consumes opaque pixel
  bytes. ZX backends consume 1bpp mono UDG bytes (and 16-bit
  pointers to address-specified UDG patterns). CPC backend consumes
  either pre-baked colour-in-pixel bytes for multi-colour BTiles
  (asset pipeline emits CPC-native bytes), or mono UDG bytes
  converted at register-time to a mode-1 block using a fixed
  default pen pair (for text glyphs).
- **Attribute layer (OPTIONAL / ZX-only)**: the `uint8_t attr`
  parameter on `gfx_init`, `gfx_tile_put`, `gfx_clear_rect`,
  `GFX_PRINT_CTX_INIT`, `gfx_sprite_set_color` is **consumed by
  SP1/JSP exactly as today and silently ignored on CPC**. The CPC
  backend accepts `attr` on the API for source-compatibility but
  discards it (`(void) attr;`). Colour on CPC comes from the bitmap
  layer plus a fixed/per-game pen palette owned by
  [cpc-renderer.md](cpc-renderer.md).

**Single exception**: `gfx_set_border( gfx_attr_t color )` — the
border has to land somewhere on CPC, so the value IS consumed there,
interpreted as a pen index in the current palette.

**Why**: projecting ZX attribute semantics onto CPC was rejected
(CPC pens vs Spectrum INK/PAPER/BRIGHT/FLASH have no clean mapping;
per-pixel colour on CPC bakes the colour into the bitmap data
anyway). The two-layer model also keeps the design open to multi-mode
CPC (mode 0/2) without API change.

**Trade-off acknowledged**: per-call colour change (e.g. flashing
tints) is transparent on ZX via `attr`, but not on CPC. CPC games
that need per-tile colour variation either register multiple tile
variants or use a CPC-specific palette-cycle effect.

**Where it lives**: defined in [gfx.md §1.2 obs 4 + §2.1](gfx.md);
ripples into [cpc-renderer.md](cpc-renderer.md) (pen palette,
default text pens), [assets.md](assets.md) (mono UDG kept on every
platform; only multi-colour assets are pre-converted to CPC bytes).

### 5.6 Backwards compatibility is INDEFINITE

**Decision (2026-05-25)**: every user-visible RAGE1 surface that
gets renamed by this multiplatform refactor — `.gdata` keywords,
Makefile targets, pragma-include filenames, loader directory names,
CLI option flags, generated feature macros — keeps its old spelling
accepted **indefinitely**, mapped transparently to the new one. No
removal is scheduled.

Concrete examples:

- `SPRITE_ENGINE` (`.gdata` keyword) stays an alias for `GFX_BACKEND`
  forever; `datagen.pl` maps it silently.
- `ZX_TARGET` (`.gdata` field) stays accepted forever; mapped to
  `PLATFORM` (`zx48`/`zx128`).
- `Makefile-48` / `Makefile-128` (forwarding stubs) stay forever as
  silent-acceptance forwarders to `Makefile-zx48` / `Makefile-zx128`.
- `build48` / `build128` (Makefile targets) stay forever as
  aliases for `build-zx48` / `build-zx128`.
- `zpragma-48*.inc`, `engine/loader48/`, `engine/loader128/` —
  forwarding stubs stay forever.
- `BUILD_FEATURE_SPRITE_ENGINE_*` macros stay emitted alongside the
  new `BUILD_FEATURE_GFX_BACKEND_*` so external games that `#ifdef`
  on them keep building.
- `datagen.pl -t` option stays accepted forever alongside the new
  `-p`.

**Why**: there are real games already built on top of RAGE1
(external to this repo). The project does not require their
migration. Any "deprecated; removed in N releases" plan creates
migration work on those games and is explicitly rejected.

**Consequence for the per-doc plans**:
- toolchain.md OQ-T2 (legacy Makefile alias lifetime) → **resolved:
  indefinite**.
- toolchain.md T4-3 ("move legacy aliases to removed") → **dropped**.
- toolchain.md T1-2 / T1-3 / T1-4 / T1-5 forwarding stubs are
  permanent, not "one release cycle"; their deprecation banners
  become silent acceptance.
- gfx.md Q3 (SPRITE_ENGINE alias lifetime) → **resolved: indefinite**.
- Any per-doc "deprecation removal" phase becomes a no-op (or is
  re-scoped to documentation / changelog work only).

**Where it lives**: project-wide policy; reflected in every doc's
rename phases.

### 5.7 C64 is OUT OF SCOPE

**Decision (2026-05-25)**: C64 is dropped from this multiplatform
project entirely. Its 6502 architecture and sprite+bitmap graphics
model would require a separate porting project, not a backend
within this design. No subsystem doc should leave "C64 sketch"
placeholders, hedging hooks (e.g. `make build-c64`), or design
considerations for cc65 / `Makefile-c64`.

**MSX** stays as an open future option — its Z80 + VDP architecture
fits the engine's 8×8-cell model, so every HAL choice in the plan
must stay MSX-friendly. Phase 1 does not add MSX.

**Where it lives**: defined in [gfx.md Q8](gfx.md); ripples into
[toolchain.md "Sketch only"](toolchain.md) (drop the C64/cc65
paragraph) and any other doc with C64 hedging.

### 5.8 BTile cell data flavour discriminator

**Decision (2026-05-25)**: the `tile` argument to `gfx_tile_put` has
two flavours, **unambiguously distinguished by value range** (no
separate registration entrypoint, no out-of-band flag):

- `0..255` → registered mono glyph slot. The `graphic` argument to
  `gfx_tile_register(idx, graphic)` is **ALWAYS 8 bytes of
  1-bit-per-pixel mono UDG pattern**, on every backend. ZX
  backends store as-is; CPC backend bit-expands to a 16-byte mode-1
  block at register-time using the backend's default pen pair.
- `≥256` → 16-bit pointer to pre-converted, platform-native bitmap
  bytes emitted by the asset pipeline. **BTile cells are ALWAYS
  16-bit pointers**, never small IDs. Layout is platform-specific
  (ZX: 8 bytes mono UDG per cell, no mask — BTiles are opaque and
  carry no mask data, in contrast to sprites; per-BTile `attrs` are
  held separately under `BUILD_FEATURE_GAMEAREA_COLOR_FULL`. CPC
  full-colour: mode-1 packed pixel bytes, 16 bytes/cell. CPC mono:
  8 bytes mono UDG per cell, same as ZX — see §5.9).

**Why**: makes the API agnostic at the source level (callers don't
need to know which flavour they're using); makes the CPC backend's
dispatch trivial (one branch on `tile < 256`); makes the asset
pipeline's job clean (small IDs are mono / engine-side, pointers
are pre-converted / asset-side).

**Where it lives**: defined in [gfx.md §2.3 + Q1](gfx.md); ripples
into [assets.md](assets.md) (asset pipeline emits platform-native
bytes only for the pointer flavour) and
[cpc-renderer.md](cpc-renderer.md) (1bpp → 2bpp conversion routine,
default pen pair configuration).

### 5.9 CPC mono game mode reuses the existing mono path with 1bpp BTile cells

> **Updated 2026-06-05 (§5.13a):** every `cpct_img2tileset` reference below
> is replaced by JSP's tools (`cpcgfx.pl --mode 1` for 2bpp sprites,
> `gfxgen.pl` for 1bpp). The whole mono optimisation is **re-evaluated
> under A8**: JSP's blitter can expand 1bpp `gfxgen.pl` output at blit
> time, so the bespoke 512-byte LUT below may be unnecessary. The
> 1bpp-BTile / 2bpp-sprite *intent* stands; the tool and the LUT detail
> may change.

**Decision (2026-05-26)**: when a game is in mono mode (existing
`BUILD_FEATURE_GAMEAREA_COLOR_MONO` build feature, emitted by
`datagen.pl` from the absence of per-BTile colour data — see
[tools/datagen.pl:2741-2743](../../tools/datagen.pl#L2741-L2743)),
the CPC backend keeps BTile cell graphic data as **1bpp UDG bytes
(8 bytes/cell, byte-identical to the ZX version)** and expands each
cell to a 16-byte mode-1 block **at blit time** via a 512-byte
lookup table built once at game init from the game's resolved CPC
pen pair (§5.10).

Concrete shape on CPC:

- **BTile cell data layout** under mono mode: 8 bytes/cell, same UDG
  bytes the ZX build uses. Pre-baked 2bpp mode-1 data is **not**
  emitted by the asset pipeline for mono CPC games — `cpct_img2tileset`
  is skipped for BTiles in mono mode; the shared UDG bytes flow
  straight to both platforms.
- **LUT**: 256 entries × 2 bytes = 512 bytes, indexed by the 1bpp
  input byte, yielding the two mode-1 output bytes that encode the
  same 8 pixels. Built at game init from the resolved mono pen pair;
  cached in always-resident memory. One LUT per game (single global
  pen pair → single LUT).
- **`gfx_tile_put` on CPC mono**: one LUT lookup per row × 8 rows
  per cell (~320 cycles/cell). Full-screen redraw at screen-enter
  ≈ 4–8 frames at 50 Hz — acceptable for the existing transition
  pause; no per-frame cost during gameplay.
- **Sprites stay 2bpp pre-baked** under mono CPC. The asset pipeline
  bakes sprite cells using the resolved mono pen pair, so sprite
  blits remain memcpy-fast (no per-frame conversion).
- **Full-colour CPC games** (`BUILD_FEATURE_GAMEAREA_COLOR_FULL`):
  BTile cell data stays 2bpp pre-baked via `cpct_img2tileset` as
  today's plan; the LUT path is mono-only.
- **BTile struct shape on CPC** under mono mode is identical to ZX
  mono: the `#ifdef BUILD_FEATURE_GAMEAREA_COLOR_FULL`-gated `attrs`
  field stays compiled out
  ([engine/include/rage1/btile.h:42-44](../../engine/include/rage1/btile.h#L42-L44));
  no per-BTile colour metadata on either platform.

**Why**: CPC mode-1 doubles BTile graphic bytes vs ZX (16 vs 8); on
cpc-banked, dataset capacity is the dominant constraint. Reusing the
existing mono path on CPC reclaims ~50 % of BTile graphic bytes for
mono games (the typical retro-adventure content shape) at the cost
of a tiny blit-time conversion absorbed in the screen-enter pause.
The mechanism reuses an already-tested engine code path with the
same build-feature surface — no new author-facing decision.

**Where it lives**: defined here; implemented in
[cpc-renderer.md](cpc-renderer.md) (LUT routine + screen-enter
budget); referenced by [gfx.md §2.3](gfx.md) (the §5.8 cell-layout
note for CPC mono); referenced by [assets.md](assets.md) (mono CPC
games skip the `cpct_img2tileset` BTile pass).

### 5.10 Generic FG/BG colour token vocabulary

**Decision (2026-05-26)**: colour-bearing directives in shared
`.gdata` use platform-neutral tokens (`FG_*` / `BG_*` + `BRIGHT` /
`FLASH` modifiers). `datagen.pl` resolves the per-platform emission
from a canonical token-to-encoding table. The existing ZX-spelled
tokens (`INK_*`, `PAPER_*`) stay accepted forever as silent aliases
for the new spelling per §5.6.

**Phase 1 scope**: applies to the **global mono-mode directives
only** — `gamearea_attr` (the `BUILD_FEATURE_GAMEAREA_COLOR_MONO`
reference attr, see
[tools/datagen.pl:3425](../../tools/datagen.pl#L3425)) and
`DEFAULT_BG_ATTR` ([tools/datagen.pl:782-783, :3309](../../tools/datagen.pl#L782-L783)).
Per-BTile attrs (full-colour ZX mode) and per-sprite attrs are not
unified — full-colour CPC bakes colour into the bitmap layer (§5.5),
and synthesised per-BTile colour tokens are out of scope on CPC
(assets.md Q2). The vocabulary may be extended in later phases if
needed.

**Canonical token → platform mapping** (one row per `FG_*` / `BG_*`
token; the `FG_` and `BG_` prefixes pick role, not colour, so the
table indexes on the colour name alone):

| Colour token | ZX encoding | CPC firmware colour |
|---|---|---|
| `BLACK` | INK/PAPER 0 | 0 (Black) |
| `BLUE` | INK/PAPER 1 | 1 (Blue) |
| `RED` | INK/PAPER 2 | 3 (Red) |
| `MAGENTA` | INK/PAPER 3 | 4 (Magenta) |
| `GREEN` | INK/PAPER 4 | 9 (Green) |
| `CYAN` | INK/PAPER 5 | 10 (Cyan) |
| `YELLOW` | INK/PAPER 6 | 12 (Yellow) |
| `WHITE` | INK/PAPER 7 | 13 (White / 50 % grey) |
| `BLACK` + `BRIGHT` | INK/PAPER 0 + BRIGHT | 0 (no brighter black) |
| `BLUE` + `BRIGHT` | INK/PAPER 1 + BRIGHT | 2 (Bright Blue) |
| `RED` + `BRIGHT` | INK/PAPER 2 + BRIGHT | 6 (Bright Red) |
| `MAGENTA` + `BRIGHT` | INK/PAPER 3 + BRIGHT | 8 (Bright Magenta) |
| `GREEN` + `BRIGHT` | INK/PAPER 4 + BRIGHT | 18 (Bright Green) |
| `CYAN` + `BRIGHT` | INK/PAPER 5 + BRIGHT | 20 (Bright Cyan) |
| `YELLOW` + `BRIGHT` | INK/PAPER 6 + BRIGHT | 24 (Bright Yellow) |
| `WHITE` + `BRIGHT` | INK/PAPER 7 + BRIGHT | 26 (Bright White) |

CPC firmware colour numbers are the values accepted by the firmware
`SET INK` / `SCR SET INK` calls (also the values cpctelera's pen-
setup helpers consume). The mapping picks the CPC firmware colour
whose nominal RGB best matches the ZX colour's nominal RGB
(`0xC0` per "on" channel non-bright; `0xFF` bright).

**`FLASH` on CPC**: silently dropped (no hardware FLASH in mode 1;
emulation via palette cycling is out of Phase 1 scope). Authors who
need a flashing effect on CPC implement it explicitly via a per-
platform overlay.

**Per-game palette override** — `CPC_COLOR_MAP` directive in the
game's CPC overlay (`cpc6128/game_data/game_config/` or via
`PATCH_GAME_CONFIG`, §5.11):

```
BEGIN_CPC_COLOR_MAP
    YELLOW            FW=15    # render as Orange instead of canonical 12
    BRIGHT_BLUE       FW=11    # render as Sky Blue instead of canonical 2
END_CPC_COLOR_MAP
```

Each entry maps one colour token (with or without `BRIGHT`) to an
explicit CPC firmware colour number. Unspecified tokens fall back
to the canonical table. The override is platform-overlay-scoped —
ZX builds ignore it.

**CPC palette construction from tokens**: in mono mode, the CPC
backend's 4-pen mode-1 palette is auto-derived: pen 0 = `gamearea_attr`'s
BG colour, pen 1 = `gamearea_attr`'s FG colour, pens 2-3 = black
(unused). Games that need a richer mono palette can add a more
explicit `CPC_PALETTE` directive (assets.md Q5) to override the
auto-derived palette. For `BUILD_FEATURE_GAMEAREA_COLOR_FULL` games
on CPC, `CPC_PALETTE` is the authoritative palette source and the
FG/BG token vocabulary is irrelevant to asset bytes (colour is
baked into bitmap bytes by `cpct_img2tileset`).

**Why**: single source of truth for colour intent in shared
`.gdata`; eliminates the "are the ZX and CPC values visually
equivalent?" risk that an explicit-per-platform value-pair approach
would carry; preserves explicit-override escape hatches
(`CPC_COLOR_MAP`, `CPC_PALETTE`, full per-platform `gamearea_attr`
override via `PATCH_GAME_CONFIG`) for games that need non-canonical
mappings.

**Where it lives**: defined here; implemented in
[assets.md](assets.md) (token parser + canonical table + the
`CPC_COLOR_MAP` directive in `datagen.pl`); cross-referenced by §5.9
(the mono LUT's pen pair is the resolved CPC pen pair from this
table) and assets.md Q5 (`CPC_PALETTE` stays as the explicit-palette
authority for full-colour games).

### 5.11 Generalised PATCH directives across .gdata sections

**Decision (2026-05-26)**: extend the existing `PATCH_SCREEN`
machinery in `datagen.pl` to cover every named `.gdata` section
that could plausibly be partially overridden by either a same-
platform `patches/` file or a per-platform overlay's `patches/`.

Today the patch mechanism is **screen-only**
([tools/datagen.pl:250-258](../../tools/datagen.pl#L250-L258),
[assets.md §1.4](assets.md)). Phase 1 of the multiplatform refactor
adds at minimum:

- `PATCH_GAME_CONFIG` — surgical override of individual `GAME_CONFIG`
  fields without rewriting the whole config.
- `PATCH_BTILE NAME=…` — replace or augment a BTile's frames, attrs,
  or cells.
- `PATCH_SPRITE NAME=…` — same for sprites.
- `PATCH_HERO NAME=…` — same for heroes.

`PATCH_RULE` is **not** added in Phase 1 — flow rules already append
by default through their normal `BEGIN_RULE` blocks (no rule has a
stable identity beyond its `(screen, when)` bucket; see
[assets.md §1.4](assets.md)), so adding new rules via overlay or
patch files works today without explicit `PATCH_RULE` machinery.
Adding it would require giving rules stable IDs — a deeper change
out of scope here.

**Semantics** (mirroring `PATCH_SCREEN`):

- The named entity must already exist when the `PATCH_*` directive
  is encountered. Load order is the existing Makefile contract —
  regular files first, patches last
  ([Makefile.common GDATA_FILES / GDATA_PATCHES](../../Makefile.common)).
- `PATCH_*` puts the parser into the matching section's state with
  `$cur_*` pointing at the already-loaded struct (no copy), and
  sets a `*_patching` flag that suppresses the normal "push new
  struct" path at the matching `END_*`.
- Per-section semantics decide which directives **replace by key**
  vs **append to list**. For `GAME_CONFIG`, every directive is
  replace-by-key (idempotent on shared base + overlay). For
  `BTILE` / `SPRITE` / `HERO`, frame-list directives append, attr
  scalars and cell-data directives replace by row/col.

**Why**: the per-platform overlay model (§5.2) does file-level
shadowing today — a `cpc6128/game_data/game_config/game_config.gdata`
overlay has to restate the entire shared config to change one field
(e.g. just to add a `CPC_COLOR_MAP` block per §5.10). That's
brittle: any later edit to the shared file silently diverges from
the overlay. `PATCH_*` directives turn overlays into **surgical
merges**: the overlay file restates only what changes, and the rest
stays inherited.

This is the natural landing site for §5.10's `CPC_COLOR_MAP` and
any other per-platform tweak that touches only a small subset of a
section's fields.

**Implementation**: small parser extension in `datagen.pl`. The
state-machine already dispatches on `BEGIN_*` directives; the new
`PATCH_*` variants look up the named entity in the already-
populated index and reuse the existing state-handler code paths
with the `*_patching` flag. The Makefile's `GDATA_PATCHES` glob
extends to include `patches/game_config/*.gdata`,
`patches/btiles/*.gdata`, `patches/sprites/*.gdata`,
`patches/heroes/*.gdata` (and the per-platform overlay's `patches/`
subdirs follow the same shape).

**Removal semantics out of scope (Phase 1)**: matching the existing
`PATCH_SCREEN` precedent, all `PATCH_*` directives in Phase 1 are
**additive / replace-by-key**, with no syntax for removing list
elements. If a future need arises (e.g. "remove this BTile from
this screen on CPC"), a separate `UNPATCH_*` or `REMOVE_*` family
can be added — not Phase 1.

**Where it lives**: defined here; implemented in
[assets.md](assets.md) §1.4 (current mechanism description gains an
"and the Phase 1 generalisation" sub-section) and in a new Phase A
task (folded into A1 or split as a new A-task, TBD when assets.md
is amended). Cross-referenced by §5.10 (overlay ergonomics depend
on this) and §5.2 (sibling-tree overlays gain surgical-merge
semantics).

### 5.12 CPC Phase-4 execution scope: cpc-flat (cpc464) first; cpc6128 overlays + 16-bit coords tracked

**Decision (2026-05-31, execution-time)**: Phase 4 CPC bring-up is
executed on **cpc-flat (cpc464)** first, against a dedicated
`games/minimal_cpc` stub. Several Phase-4 tasks (G7, R4, G8, IN6,
AU5, TS3) carry literal `PLATFORM cpc6128` text in their per-doc
specs, but cpc6128 **is** cpc-banked, whose toolchain lands **last**
(toolchain.md T3). So each of those tasks was retargeted to
`cpc464` + `games/minimal_cpc` during execution; the cpc6128 build
of any real game is unavailable until T3.

**Tracked deferrals to Phase 5 / G9 (gated on T3 building cpc6128)** —
these are *not dropped*, only resequenced:

- The cpc6128 **per-game overlays** of `games/minimal` and
  `games/default` — `IN6-4`, `IN6-5`, `IN6-6` (CPC controller-select
  menus + their regression) and `AU5-2`/`AU5-3` for `games/default`
  (CPC music/SFX in a real game) — land in **Phase 5** (alongside
  `G9` "CPC across 3+ games"). Phase-4 `IN6`/`AU5` are scoped to
  `games/minimal_cpc` on cpc464.
- `TS3`'s first CPC regression baseline is **cpc464** (`minimal_cpc`);
  the cpc6128 baseline follows T3.

**AU5 execution note (2026-05-31)**: Phase AU5 (real CPC Arkos2 AY audio)
was executed on **cpc464 / cpc-flat** with a dedicated audio test game
**`games/minimal_audio_cpc`** (= `minimal_cpc` + a `TRACKER arkos2` song +
SFX table + a `TRACKER_PLAY_FX` flow rule). It links the AT2 AKG player for
`+cpc`, runs the music tick in the 50 Hz ISR, and boots + runs stably in
Caprice32 (the shadow-reg ISR fix makes the tracker-in-ISR safe). The
`games/default` CPC music/SFX build remains deferred to **Phase 5** per the
scope above. AU5's ZX output is byte-identical (the shared AT2 player's ZX
PSG-output + R7-mixer paths are guarded `IF PLY_AKG_HARDWARE_SPECTRUM`;
`default` + `vortex2` `main.map`/`banked_code.map` show zero address drift).

**New tracked task — `G8a` (no-debt; genuinely engine-wide, so
scheduled not crammed)**: **CPC 16-bit sprite/position coordinates +
`gfx_cpctel` screen-bounds clamp.** `G4` widened the *gfx pixel*
coordinate type to `uint16_t` on CPC, but the engine's sprite/enemy
**fixed-point position** integer part is still `uint8_t`, so a sprite
cannot be positioned at x>255 on CPC mode-1's 320 px (40-col) screen;
and `blit_mono_cell` lacks a screen-bounds clamp (an edge-placed
sprite could write past the 16 KB screen). Both are harmless for
`minimal_cpc` (enemy stays <255, on-screen) but **must** land before
any non-stub CPC game (`G9`). Scheduled at the cpc-flat hardening
boundary (end of Phase 4 / start of Phase 5). Surfaced by the G8
review.

**Where it lives**: defined here; `G8a` mirrored into
[management/gantt.md](management/gantt.md) and
[management/00tasklist.md](management/00tasklist.md). The cpc6128
deferrals already exist as sub-tasks in input.md / audio.md / testing.md;
this note records the resequencing.

### 5.13 CPC graphics engine switched from cpctelera to JSP; cpctelera fully revoked

**Decision (2026-06-05, execution-time — supersedes architectural anchor #2's
"new CPC backend" framing and anchor #5 entirely, and reverses §5.1, the
cpctelera half of §5.4, and the cpctelera dependency in §5.5/§5.8/§5.9):** the
CPC graphics engine is **JSP** (Jorge's Sprite Library), not cpctelera.
**cpctelera is fully revoked** as a RAGE1 dependency.

#### Why the pivot

The original plan chose cpctelera as a *new* CPC graphics backend
(`GFX_BACKEND=cpctel`, backend file `gfx_cpctel.c`). Phase 4 executed that
choice and produced a working — but **cell-granular** — CPC renderer: cpctelera
(and every other reusable CPC sprite library: CPCRSLib, cpcsprite, AMSprite) is
byte-aligned horizontally (Mode 1 = 4 px), so sprites only move in whole-cell
(8 px) jumps. Pixel-smooth horizontal movement is a hard requirement for a
RAGE1 game and was never achievable on a byte-aligned library without
pre-shifting (rejected: too memory-heavy) or realtime bit-shifting (which no
off-the-shelf CPC library offers). See
[../CPC-SPRITE-ENGINE-ANALYSIS.md](../CPC-SPRITE-ENGINE-ANALYSIS.md) and the
parked task in `.prompts/2026-06-05.md`.

JSP solves this natively. JSP is the SP1-derived sprite engine **already vendored
and already a first-class RAGE1 graphics backend** (`GFX_BACKEND=jsp`, in
production on ZX today via `engine/src/gfx_jsp.c` / `gfx_jsp.h`). JSP has since
gained full CPC support — `CPC_MODE1` with **1-pixel horizontal positioning via
runtime rotation tables (no pre-shifting)**, masked compositing, deferred
recompositing, and its own vendored PNG→asset converters — and builds natively
with `zcc +cpc -compiler=sdcc`. JSP is vendored at `external/jsp` (git submodule;
pin advanced to include CPC support on 2026-06-05).

#### What this changes architecturally

1. **JSP is the single cross-platform graphics backend.** SP1 stays ZX-only.
   JSP serves **both** ZX and CPC under one `GFX_BACKEND=jsp` value. Per §5.4
   (a backend value is the library short-name), no new backend value is created:
   the **`PLATFORM` axis** (cpc-flat / cpc-banked) selects the CPC build, and
   `engine/src/gfx_jsp.{c,h}` gain `#ifdef BUILD_FEATURE_PLATFORM_CPC_*` sections
   for the CPC-specific divergences (16-bit X coordinate — already widened by
   `G4`; mode + palette programming inside `gfx_init`; `attr`/colour API inert
   per §5.5). Whether those CPC sections live as inline `#ifdef`s in
   `gfx_jsp.{c,h}` or in a sibling `gfx_jsp_cpc.{c,h}` included under the CPC
   guard is an execution-time implementation choice (cpc-renderer.md), not a
   plan-level decision. Initial CPC mode is **`CPC_MODE1` (regular, NOT mono)**
   per §5.13a below; other JSP CPC modes (Mode 0/2, MONO, FAST) are deferred.

2. **The `cpctel` backend is retired.** `engine/src/gfx_cpctel.c` /
   `gfx_cpctel.h` and the `BUILD_FEATURE_GFX_BACKEND_CPCTEL` macro are removed
   once JSP-CPC reaches functional parity with the interim backend (its
   `mono_lut` / `glyph_cache` / `blit_*` machinery is entirely subsumed by JSP's
   internal engine). Until then `gfx_cpctel` remains as the **interim** CPC
   backend (it is what Phase 4 built and what `games/minimal_cpc` runs today).

3. **The `external/cpctelera` submodule is removed** (`git rm`, drop the
   `.gitmodules` entry). It was vendored as reference-only and never compiled;
   nothing in the JSP path needs it.

4. **CPC asset conversion uses JSP's vendored tools**, not `cpct_img2tileset`:
   `external/jsp/tools/cpcgfx.pl --mode 1` (4-pen colour, incl. `--multicolor`
   + `--palette-symbol`) and `external/jsp/tools/gfxgen.pl` (1bpp, for Mode 2 /
   MONO). These emit **Z80 ASM** (`PUBLIC` + `db`), not C arrays — the build
   wiring links ASM instead of compiling generated C. `tools/cpc_asset_convert.pl`
   is re-pointed to wrap these; `CPCT_PATH` / Img2CPC install steps disappear.

5. **The cpctelera↔z88dk SDCC-fork compatibility risk evaporates.** It was the
   single largest cross-doc risk (§6) and the entire reason for the Phase T0
   spike and the Phase R1 "Option (b) file-by-file sdas→z80asm translation"
   workflow. JSP is z88dk-native; none of that applies.

#### What is explicitly **kept** (not part of "revoke")

A handful of **CPC hardware-I/O primitives** already hand-translated into
`engine/src/cpc/` are *cpctelera-derived by lineage* but compile standalone
under z88dk z80asm with **zero** cpctelera library/toolchain dependency. They
implement raw CPC hardware operations JSP deliberately leaves to the caller, so
they stay. **Their cpctelera attribution / credit comments are kept** — the code
genuinely comes from cpctelera and credit is given where it is due; we are
dropping the *library and submodule dependency*, not the acknowledgement. (Each
file keeps its "hand-translated from cpctelera <commit>, © ronaldo / cpctelera,
LGPL-3.0" header.) Kept files:

- `cpct_video.asm` — set video mode + program palette (`gfx_init` needs this
  before the first `jsp_redraw`; JSP leaves mode/palette to the caller's `main`,
  per [external/jsp/doc/CPC-USAGE.md §5](../../external/jsp/doc/CPC-USAGE.md)).
- `cpct_keyboard.asm` — PPI keyboard-matrix scan + status buffer (JSP provides
  no input; this is RAGE1's only CPC keyboard source — input.md IN6 already
  depends on it, not on the cpctelera library).
- `cpct_gfx_m1.asm` — keep `cpct_getScreenPtr` + `cpct_setBorder` (hardware
  address arithmetic / border write); drop `cpct_drawSprite` (superseded by JSP).
- `cpct_strings_m1.asm` — conditional: keep only if a production CPC code path
  still draws firmware-font text; otherwise drop (JSP renders its own glyphs).
- `asmdata_cpc.c` — already RAGE1-original (no cpctelera content); unaffected.

#### Subsystems with **no** material change

- **Audio (AU1–AU7):** zero cpctelera dependency — confirmed. CPC audio is the
  Arkos Tracker 2 AKG generic player (`PLY_AKG_HARDWARE_CPC`), never cpctelera's
  audio module. Untouched.
- **Input (IN1–IN8):** the CPC backend already calls the standalone
  `engine/src/cpc/cpct_keyboard.asm` (kept per above), not the cpctelera
  library. Only doc language changes ("cpctelera keyboard scan" →
  "hand-translated CPC keyboard scan in `engine/src/cpc/`").
- **Banking memory maps (B-series):** addresses are CPC hardware facts,
  unchanged. Only the *implementation* of the bank-switch / firmware-disable
  primitives changes: `cpct_pageMemory()` / `cpct_disableFirmware()` → ~6-byte
  direct Gate-Array port writes (already the preferred answer in banking.md
  OQ-B2). Re-check the cpc-flat stack-budget estimate (was sized off cpctelera's
  ~60 B deepest frame) against JSP's actual call depth.

#### Per-doc ripple (authoritative index of follow-on edits)

| Doc | What changes |
|---|---|
| [README.md](README.md) | Anchor #2 (CPC backend = JSP, not "new backend"); anchor #5 (vendor JSP not cpctelera) — **revoked**; §4 phase sequence (R-series re-pointed); §5.1 (asset tool = cpcgfx.pl/gfxgen.pl); §5.4 (CPC backend = `jsp`, platform-discriminated; `cpctel`/`cpcrs` remain reserved names only); §6 (drop the SDCC-fork compat risk); §7 OQ table (cpctelera OQs → resolved/moot) |
| [cpc-renderer.md](cpc-renderer.md) | **Rewritten** as the JSP-CPC integration plan. R1–R5 (cpctelera vendor/licence/translate/asset-wire) marked **superseded**; new JSP-CPC bring-up phases **R6–R10** added (JSP `+cpc` build integration; `gfx_jsp` CPC sections; migrate `games/minimal_cpc` to `GFX_BACKEND=jsp` with pixel-smooth movement; retire `gfx_cpctel`; remove `external/cpctelera` submodule). Surviving concerns retained: mode/palette setup, `appmake` CDT/DSK packaging, loading screen, asset byte format. |
| [gfx.md](gfx.md) | G7/G8/G8a re-annotated as the **interim** cpctel backend (built, now superseded). New **G10** "JSP CPC backend" (thin `gfx_*→jsp_*` HAL + mode/palette in `gfx_init`; pixel-smooth — closes the parked movement task). G9 (CPC across 3+ games) re-targets `GFX_BACKEND=jsp`; CI lane `cpctel-cpc*` → `jsp-cpc*`. |
| [assets.md](assets.md) | A5 (CPC via `cpct_img2tileset`) re-annotated **superseded**. New **A8** "JSP CPC asset pipeline" (`cpc_asset_convert.pl` wraps `cpcgfx.pl`/`gfxgen.pl`; ASM output; §5.9 mono path may collapse to a single 1bpp `gfxgen.pl` output expanded by JSP's blitter). OQ-A9 (firmware-colour table) can be verified against `cpcgfx.pl`'s vendored palette now. |
| [toolchain.md](toolchain.md) | T0 outcome annotated: cpctelera spike / SDCC-dialect findings **moot** (JSP is z88dk-native). Drop the SDCC-standalone-with-cpctelera alternative, the `zpragma-cpc-flat-cpctelera.inc` variant, and the cpctelera CI-tool install. Keep `+cpc` `sdcc_iy`-vs-default-clib finding (applies to JSP too), `2cdt`, DSK packaging. OQ-T4 resolved (JSP). Architecture diagram: `external/cpctelera/lib` → `external/jsp/lib`. |
| [banking.md](banking.md) | §2.3 / B6-1 / loadertool bswitch stub: `cpct_pageMemory()` → direct MMR write; firmware-disable → direct Gate-Array write. Re-measure cpc-flat stack budget vs JSP. Memory-map addresses unchanged. |
| [input.md](input.md) | Doc language in §3.2 / §4.3 / IN6: "cpctelera keyboard scan" → "hand-translated CPC keyboard scan in `engine/src/cpc/cpct_keyboard.asm` (standalone, no cpctelera library dependency)". No task spec change. |
| [audio.md](audio.md) | No change (already cpctelera-independent). AU7-5 wording stays valid. |
| [testing.md](testing.md) | TS3 CPC regression baseline is rebaselined when `minimal_cpc` moves to `GFX_BACKEND=jsp` (pixel-smooth output differs from the cell-granular cpctel baseline). Caprice32 harness unchanged. |
| [management/00tasklist.md](management/00tasklist.md), [management/gantt.md](management/gantt.md) | Mirror: annotate the cpctelera-built Phase-4 tasks as interim/superseded; add R6–R10, G10, A8. |

#### Migration sequencing (no regression to the playable cpc-flat game)

The interim `gfx_cpctel` backend stays green throughout. JSP-CPC is brought up
alongside it (new `R6–R10` / `G10` / `A8`), `games/minimal_cpc` is migrated to
`GFX_BACKEND=jsp` and re-baselined, and only **then** are `gfx_cpctel` and the
`external/cpctelera` submodule removed. Every phase still ends green per the
§9 phase-exit invariant.

### 5.13a CPC mode: JSP `CPC_MODE1` (regular, non-mono) is the Phase-1 target

**Decision (2026-06-05):** the initial RAGE1 CPC build uses JSP's **`CPC_MODE1`**
(4 pens, 320 px, per-pixel colour, 1 px X positioning) — **not** `CPC_MODE1_MONO`
and not the `*_FAST` byte-aligned variants. This supersedes the cpctelera-era
"Mode 1" resolutions (assets Q3, gfx Q7, banking OQ-B4, cpc-renderer OQ-1) by
making them concrete against JSP's mode matrix. Mode 0 (16 pens) and Mode 2
(640 px mono) and the MONO/FAST variants remain deferred; the two-layer colour
model (§5.5) and JSP's compile-time mode guard accommodate them without API
change. The §5.9 mono-mode BTile optimisation is re-evaluated under A8 (JSP's
1bpp `gfxgen.pl` output can be expanded by the blitter, potentially simplifying
the LUT path).

### 5.13b CPC test games converge on the ZX test games; assets reused via a text-mode → PNG bridge

**Decision (2026-06-05):** the CPC test games should be **rewritten to be as
close to the ZX test games as possible** — same shared `game_data/` core +
a thin `cpc*/game_data/` overlay (per §5.2/§5.3), reusing the **same authored
assets**, rather than the bespoke divergent stubs that Phase 4 created
(`games/minimal_cpc`, `games/minimal_audio_cpc`, `games/cpc-hello`,
`games/00cpc-compile-test`, `games/cpc-a5-png-test`). The end state is that
building `games/minimal` (and later `default`, `blobs`, …) for a CPC `PLATFORM`
"just works" off the shared core, and the CPC-only stubs are retired (testing.md
TS6). This is the existing direction (TS6 + README §5.12 cpc6128 overlays) made
an explicit goal of the JSP switch.

**The asset-reuse wrinkle (the reason this is a §5 decision):** the ZX test
games author their graphics **in text mode inside `.gdata`** — `PIXELS` / `MASK`
ASCII-art blocks (e.g.
[games/minimal/game_data/sprites/Hero.gdata](../../games/minimal/game_data/sprites/Hero.gdata),
[games/minimal/game_data/btiles/Live.gdata](../../games/minimal/game_data/btiles/Live.gdata)),
**not** PNG files. But JSP's CPC asset converters (`cpcgfx.pl`, `gfxgen.pl`,
A8) consume **PNG** input. To reuse the very same authored assets on CPC, the
asset pipeline therefore needs a **text-mode → PNG bridge**: synthesise a PNG
from the `PIXELS`/`MASK` definition (one transparent/fg/bg colour per pixel
class), then feed that PNG to the JSP converter to emit CPC-format bytes.

**Why a PNG bridge rather than a direct `PIXELS`→CPC-bytes encoder in datagen:**
it keeps **one** canonical CPC pixel-encoding authority (the JSP tools), exactly
as §5.1 keeps CPC encoding out of Perl. A parallel hand-rolled `PIXELS`→Mode-1
encoder in `datagen.pl` would re-introduce the divergence risk §5.1 rejected.
The PNG bridge is a thin, testable shim; the encoding stays in JSP's tools.

**Mono assets:** note that JSP's mono converter `gfxgen.pl` **also takes PNG**,
so the mono path normally goes through the **same bridge** (→ `gfxgen.pl`), not
through a PNG-free route. A truly PNG-free path — datagen reusing its existing
ZX 1bpp `PIXELS`→bytes output directly, with JSP's blitter expanding 1bpp at
draw time — is available **only if A8-5 proves** RAGE1's ZX 1bpp byte layout is
bit-identical to what JSP's CPC blitter consumes; if so it is adopted as a
*documented §5.1 exception* (datagen becomes the mono CPC encoder for that one
layout). Until A8-5 measures this, treat it as undecided: the bridge→`gfxgen.pl`
route is the default for mono too. A8 decides per asset class which path applies.

**Where it lives:** implemented under **assets.md A8** (new tasks: the
text-mode→PNG bridge + reuse of shared `.gdata` assets on CPC) and
**cpc-renderer.md R9** (rewrite `games/minimal_cpc` to mirror `games/minimal`,
reusing its assets); retirement of the CPC-only stubs stays **testing.md TS6**.

## 6. Consolidated Risks index

The per-subsystem docs each carry their own detailed Risks section.
The following cross-cutting risks span multiple docs and are worth
holding in mind:

- **Cross-doc — ZX byte-identical invariant.** Many phases assert
  "ZX byte-identical to pre-phase output". This invariant is
  testable only if `tests/00regression/` covers enough games. See
  `TS1` (backfill is the prerequisite for safe execution of every
  later refactor).
- **Cross-doc — cpctelera + z88dk SDCC fork compatibility.**
  **RESOLVED / MOOT 2026-06-05 (§5.13):** cpctelera is revoked; the CPC
  graphics engine is JSP, which is z88dk-native (`zcc +cpc
  -compiler=sdcc`). This risk — the largest in the plan, the reason for
  Phase T0 and the R1 sdas→z80asm translation workflow — no longer
  applies. The text below is retained for history.
  cpctelera ships SDCC 3.6.8 internally; z88dk ships SDCC 4.3.x.
  The `__z88dk_callee` / `__z88dk_fastcall` annotations should make
  them interchangeable, but it is not proven until phase `R2`'s
  hello-world PoC. Most CPC work is gated on `R2` succeeding.
  Mitigation: `R2` is explicitly a gating phase; fall-back paths
  include patching individual cpctelera asm files or, worst case,
  switching to CPCRSlib (the `cpc-renderer.md` survey identifies
  fallbacks).
  *Updated 2026-05-25*: T0 spike confirmed the SDCC ABI compatibility
  but surfaced two adjacent issues (no `sdcc_iy` on `+cpc`,
  asm-dialect incompatibility) — see toolchain.md §2.1 + Phase T0
  outcomes and cpc-renderer.md R1 amendment.
  *Updated 2026-05-30*: Phase R1 decision flipped from Option (a)
  prebuilt `.lib` to Option (b) LLM-assisted file-by-file translation.
  Two findings drove the flip: (1) z88dk patches SDCC to emit z80asm
  syntax (not sdas), so there is no z88dk path for sdas source;
  (2) cpctelera's sdld-produced `.lib` is almost certainly not
  z88dk-link-format compatible, so Option (a) would still require
  translated source to link. CPCRSlib remains the documented fall-back
  if per-file translation hits a wall on a specific primitive. See
  cpc-renderer.md Phase R1 / R1-5 for the rewritten workflow and
  toolchain.md Phase T0 outcomes Finding 2 follow-up for the
  z88dk-patches-SDCC clarification.
- **Cross-doc — cpctelera upstream dormancy.** Both `master` and
  `development` branches are largely dormant (last meaningful
  commits May 2026 and Nov 2025 respectively). The pin policy
  (`R5-3`) is conservative; the LGPL-3.0 licence means we can fork
  if upstream stops responding.
- **Cross-doc — CPC mode 1 asset bytes are 2× ZX bytes; mode 0 is
  4×.** Dataset capacity effectively halves on CPC for the same
  content. Mitigation: **mode 1 only in Phase 1** (`cpc-renderer.md`
  OQ-1, `banking.md` OQ-B4).
- **Cross-doc — CPC raster IRQ is hardware-fixed at 300 Hz.** Only
  the divide-by-six to 50 Hz is software-tunable. RAGE1's existing
  50 Hz frame semantics survive, but every ISR-using subsystem
  (audio, input, banking) must coordinate to the 300 Hz tick.
  Specifically on **cpc-banked**: the 300 Hz ISR fires up to six
  times more often than ZX128's 50 Hz tick, so any work that runs
  inside a swapped-in codeset (audio mixer tick, music player tick,
  flow-rule eval) competes with the banked-function dispatcher's
  DI/EI window around bank switch. The two interactions worth
  budgeting at Phase B6 / Phase AU5: (a) worst-case dispatcher
  latency × 300 Hz must leave headroom for the music player's
  per-tick CPU budget, and (b) ISR-driven audio tick (if hosted in
  a codeset) needs the dispatcher to be re-entrancy-safe or the
  audio code must live in always-resident memory (Page A or
  always-mapped low RAM). Default plan: AT2 AKG player lives in
  always-resident memory; flow-rule eval stays banked. Phase B6 /
  AU5 verifies the budget on real hardware.
- **Cross-doc — cpc-banked Page A engine-code budget is TBD until
  Phase B4-1's z88dk +cpc CRT walk.** The cpc-banked memory shape
  assumes the engine fits below 0x4000 (Page A) with comfortable
  headroom after the +cpc clib's CRT support routines. If the CRT
  footprint turns out larger than estimated (banking.md §3.1.4 / R9),
  the engine still has **Page C** (0xC000–0xFFFF, minus the dataset
  swap area at the top) as a fallback for engine code, with the
  banked-function dispatcher relocated accordingly. Either shape is
  viable; the choice between Shape A (engine in Page A) and Shape B
  (engine in Page C) is finalised by B4-1's measurement, not now.
  No architectural change is required either way.
- **Cross-doc — Per-game `kbd.c` duplication (narrow).** Only
  `games/default` and `games/default_jsp` carry the inline-asm
  `kbd.c`/`kbd.h` raw-scan helper today. `input.md` Phase IN4
  consolidates these two.
- **Cross-doc — Per-game controller-selection menu drift (wider).**
  Several games (`blobs`, `crumbs`, `damage_mode`, `get_weapon`,
  `monochrome`, `vortex2`, plus `default` and `default_jsp`) carry
  bespoke `game_functions.c` controller-selection menus. After the
  sibling-tree overlay lands, these may need per-platform versions.
  See `input.md` Risk R7.

## 7. Consolidated Open Questions index

The per-subsystem docs each carry their own Open Questions with
recommendations. The following are the cross-cutting decisions the
user should be ready to make at the relevant phase boundary:

| ID | Topic | Doc | Recommendation |
|---|---|---|---|
| (assets) **Q1** ✅ | Screen dimensions | [assets.md](assets.md) | **Resolved (2026-05-23)**: per-platform `GAME_AREA_<PLATFORM>` directive |
| (assets) **Q2** ✅ | Synthesised per-BTile colour token on CPC | [assets.md](assets.md) | **Resolved (2026-05-23)**: skip on CPC; parameterise the engine to not require one |
| (assets) **Q3** ✅ | Default CPC colour mode | [assets.md](assets.md), [cpc-renderer.md](cpc-renderer.md) | **Resolved (2026-05-23)**: Mode 1 |
| (assets) **Q4** ✅ | `game_src/<platform>/` overlay scope | [assets.md](assets.md) | **Resolved (2026-05-23)**: supported via same `cp -r` mechanism (Phase A2) |
| (assets) **Q5** ✅ | Palette table strategy | [assets.md](assets.md) | **Resolved (2026-05-23)**: extend tooling — new `CPC_PALETTE` directive forwarded to `cpct_img2tileset --palette` |
| (assets) **Q6** ✅ | `patches/flow/` policy | [assets.md](assets.md) | **Resolved (2026-05-23)**: keep existing `patches/{map,flow}/` mechanism as-is; extend to `<platform>/game_data/patches/{map,flow}/` |
| (assets) **Q7** ✅ | PNG path resolution under overlays | [assets.md](assets.md) | **Resolved (2026-05-23)**: invoke `datagen.pl` with `cwd = build/` so overlay-copied PNGs are resolved |
| (assets) **Q8** ✅ | CPC `SOUND` mapping | [assets.md](assets.md), [audio.md](audio.md) | **Re-resolved (2026-05-26, supersedes 2026-05-23)**: **Option C** — backend-agnostic event IDs in shared `Game.gdata` (e.g. `SOUND ENEMY_KILLED=SFX_HIT`) + per-platform `SOUND_MAP` overlay at `<platform>/game_data/game_config/sound_map.gdata` (audio.md §3.3). Old plan (per-platform `SOUND_<PLATFORM>` directive) rejected — would proliferate suffixes across 4 platforms |
| (assets) **OQ-A9** | Canonical FG/BG token → CPC firmware-colour mapping table (§5.10) | [assets.md](assets.md) | **Open (2026-05-26)** — verify each row of the proposed 16-entry table against a definitive CPC firmware-palette reference before merging A1-7. Override mechanism (`CPC_COLOR_MAP`, §5.10) lets per-game disagreements be fixed without rebuilding the table. Resolution gate: A1-7 implementation |
| (gfx) **Q1** ✅ | Single `gfx_tile_register` vs split | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: single entrypoint; BTile cells are ALWAYS 16-bit pointers (§5.8) |
| (gfx) **Q2** ✅ | `gfx_attr_t` storage width | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: `uint8_t` on every platform (inert on CPC per §5.5) |
| (gfx) **Q3** ✅ | Backwards-compat window for `SPRITE_ENGINE` | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: indefinite (§5.6) |
| (gfx) **Q4** ✅ | BTile geometry generalisation ownership | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: per-platform overlays (per §5.3); no auto-extension |
| (gfx) **Q5** ✅ | Off-screen sprite parking strategy | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: `gfx_sprite_park(s)` as first-class HAL API; backend-internal parking row |
| (gfx) **Q6** ✅ | Border colour API shape | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: `gfx_set_border(gfx_attr_t)` is the single exception consuming `attr` on CPC (pen index); per §5.5 |
| (gfx) **Q7** ✅ | Multi-mode CPC in Phase 1 | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: mode 1 only in Phase 1; modes 0/2 deferred (two-layer model accommodates them without API change) |
| (gfx) **Q8** ✅ | MSX / C64 placeholder | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: MSX kept as open option; C64 OUT OF SCOPE (§5.7) |
| (gfx) **Q9** ✅ | Pixel-coord widening default | [gfx.md](gfx.md) | **Resolved (2026-05-25)**: per-platform typedef (`uint8_t` on ZX, `uint16_t` on CPC and future ZX Next) |
| (toolchain) **OQ-T1** | `PLATFORM` variable name (`PLATFORM` vs `RAGE1_PLATFORM`) | [toolchain.md](toolchain.md) | `PLATFORM` |
| (toolchain) **OQ-T2** ✅ | Legacy `Makefile-48`/`Makefile-128` alias lifetime | [toolchain.md](toolchain.md) | **Resolved (2026-05-25)**: indefinite (§5.6) |
| (toolchain) **OQ-T3** | z88dk pinned version bump | [toolchain.md](toolchain.md) | Bump to current stable (v2.3 → v2.4) |
| (toolchain) **OQ-T11** ✅ | CPC banking model: extend RAGE1's own vs migrate both sides to z88dk `#pragma bank` | [toolchain.md](toolchain.md), [banking.md](banking.md) | **Resolved (2026-05-26)** by [banking.md OQ-B11](banking.md): extend RAGE1's custom banking (Option A). z88dk `#pragma bank` migration deferred to a future task (banking.md R13) |
| (banking) **OQ-B1** ✅ | Dataset destination buffer placement on cpc-banked | [banking.md](banking.md) | **Resolved (2026-05-26)**: top of Page C (0x8000-0x9FFF, 8 KB). Page A alternative recorded as fallback |
| (banking) **OQ-B4** ✅ | CPC mode 0 support in Phase 1 | [banking.md](banking.md) | **Resolved (2026-05-26)**: mode 1 only — see also gfx.md Q7, cpc-renderer.md OQ-1 |
| (banking) **OQ-B11** ✅ | Banking mechanism: custom vs z88dk #pragma bank | [banking.md](banking.md), [toolchain.md](toolchain.md) | **Resolved (2026-05-26)**: extend RAGE1's custom banking (Option A); migration to z88dk deferred as future task. Cross-link: OQ-T11 |
| (cpc-renderer) **OQ-1** ✅ | Default CPC mode | [cpc-renderer.md](cpc-renderer.md) | **Resolved (2026-05-25)**: Mode 1 — cross-link gfx.md Q7, banking.md OQ-B4 |
| (cpc-renderer) **OQ-2** ✅ | Pin cpctelera commit on `development` or `master` | [cpc-renderer.md](cpc-renderer.md) | **Resolved (2026-05-25)**: pin a specific commit on `development` |
| (cpc-renderer) **OQ-5** ✅ | CDT/DSK via `appmake` or cpctelera's `iDSK`/`2cdt` | [cpc-renderer.md](cpc-renderer.md), [toolchain.md](toolchain.md) | **Resolved (2026-05-25)**: `appmake` |
| (audio) **Q4** ✅ | ZX128 SFX routing: beeper-only vs beeper + AY both active | [audio.md](audio.md) | **Resolved** (audio.md §3.1.1 / §3.2): both active by default; per-game opt-out |
| (audio) **Q8** ✅ | Shared `.aks` as recommended authoring convention | [audio.md](audio.md) | **Resolved**: yes — shared `.aks` is the recommended authoring convention |
| (audio) **Q10** ✅ | MSX placeholder (C64 OOS) | [audio.md](audio.md) | **Resolved (2026-05-26)**: MSX stays sketch-only and `audio_*` generalises cleanly via `PLY_AKG_HARDWARE_MSX`; C64 out of scope per §5.7 |
| (input) **Q3** | CPC pause-key default | [input.md](input.md) | `Key_H` |
| (input) **Q4** | `cpct_scanKeyboard_if` vs `_f` (DI/EI ownership) | [input.md](input.md) | `_if` with explicit engine-side DI/EI |
| (banking) **OQ-B6** | CPC cold-boot loader path | [banking.md](banking.md), [toolchain.md](toolchain.md) | AMSDOS one-shot `.cpc` (cpc-flat) / disk per-block load (cpc-banked) |
| (testing) **OQ-TS1** | Caprice32 autocmd token spelling verification | [testing.md](testing.md) | Confirm in TS2 against pinned version |
| (testing) **OQ-TS9** | Whether CPC664 needs explicit emulator smoke testing in CI (it runs the CPC464 build as a runtime target) | [testing.md](testing.md) | No (Phase 1) |

Per-subsystem docs contain additional Open Questions that don't
surface here; the table above is the cross-cutting subset.

## 8. Progress tracking

Initial draft complete. Per-subsystem phase progress lives inside
each subsystem doc (each carries its own phase / task list). When
execution begins, each per-doc phase is the unit of progress.

- [x] Initial draft assembled (8 subsystem docs + this README)
- [x] Independent review of each subsystem doc (8 reviews)
- [x] Rework against review findings (all 8 docs)
- [x] User review-1 of the **initial** plan — complete:
  - [x] `assets.md` review-1 (2026-05-23)
  - [x] `toolchain.md` review-1 (2026-05-24)
  - [x] `gfx.md` review-1 (2026-05-25)
  - [x] `README.md` cross-doc decisions absorbed (2026-05-25)
  - [x] `cpc-renderer.md` review-1 (2026-05-25)
  - [x] `banking.md` review-1 (2026-05-26)
  - [x] `audio.md` review-1 (2026-05-26)
  - [x] `input.md` review-1 (2026-05-26)
  - [x] `testing.md` review-1 (2026-05-26)
- [ ] Final user approval of the initial plan
- [ ] Execution begins — phases run per the cross-cutting sequence
      in §4

## 9. How to read and revise this plan

- **Living document.** Subsequent execution tasks may revise
  phases, add or split steps, fold in risks discovered during work,
  or correct architectural choices that don't survive contact with
  reality. The plan is not a frozen contract.
- **Per-subsystem ownership.** Each subsystem doc owns its own
  Phases, Tasks, Risks, and Open Questions. The README is the
  cross-cutting index; do not duplicate per-subsystem content here.
- **Cross-doc decisions.** When a decision genuinely spans multiple
  docs, record it in §5 (Cross-doc decisions reconciled here) and
  cross-link from the affected docs.
- **Line numbers may drift.** All source-code citations in the
  per-subsystem docs reference the repo HEAD as of the audit. When
  executing later, re-grep before relying on a specific line range.
- **Phase-exit invariant.** Every phase, in every subsystem, must
  end with `make all-test-builds` green and `tests/00regression/`
  ZX screenshot tests green. Mid-phase regressions are acceptable.
  This is the load-bearing rule that makes the plan executable
  without freezing ZX work.
