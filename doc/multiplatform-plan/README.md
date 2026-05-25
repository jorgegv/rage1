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
   multi-platform graphics HAL. SP1, JSP, and a new CPC backend all
   sit behind the same surface. No second abstraction layer above
   `gfx_*`. See [gfx.md](gfx.md).
3. **`audio_*` HAL**: same shape — shared API surface, per-platform
   backends (ZX beeper, ZX AY, CPC AY). Music + SFX in scope. See
   [audio.md](audio.md).
4. **`input_*` HAL**: same shape — gameplay-level events
   (up/down/fire/action keys) routed through a per-platform
   keyboard/joystick driver. See [input.md](input.md).
5. **CPC graphics backend**: vendor **cpctelera** as a git submodule
   under `external/cpctelera`, mirroring the JSP precedent. Not a
   new owned library. See [cpc-renderer.md](cpc-renderer.md).
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
| [cpc-renderer.md](cpc-renderer.md) | cpctelera library evaluation, vendoring, licence audit (LGPL-3.0 → GPL-3 conveyance), `cpct_img2tileset` subprocess wiring                                    | **R1–R5**   |
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
- `R1` — cpctelera submodule add (vendored but not yet compiled)

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

This ordering is intentionally serialised across subsystems because
many phases depend on others (e.g. `G7` needs `R1`; `A5` needs `R3`;
`G8` needs `R4`; `TS3` needs `R4` and `G8`). The per-subsystem docs
contain the authoritative dependency notes for each phase.

## 5. Cross-doc decisions reconciled here

Architectural decisions that span more than one doc. Recorded here as
the canonical resolution; the per-subsystem docs reflect them.
Decisions are dated; resolved-during-review decisions land in
chronological order.

### 5.1 CPC asset conversion: cpctelera subprocess, not Perl-side encoders

**Decision**: for CPC builds, RAGE1's asset pipeline shells out to
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

**Decision (2026-05-24)**: a `GFX_BACKEND` value is the **short name
of the underlying library**, never a generic platform tag. ZX
backends today: `sp1`, `jsp`. CPC backend today: `cpctel`
(cpctelera). Reserved future CPC entrant: `cpcrs` (cpcrslib). Any
other CPC graphics library added later follows the same pattern
(`cpc<lib>`).

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
  cpctelera ships SDCC 3.6.8 internally; z88dk ships SDCC 4.3.x.
  The `__z88dk_callee` / `__z88dk_fastcall` annotations should make
  them interchangeable, but it is not proven until phase `R2`'s
  hello-world PoC. Most CPC work is gated on `R2` succeeding.
  Mitigation: `R2` is explicitly a gating phase; fall-back paths
  include patching individual cpctelera asm files or, worst case,
  switching to CPCRSlib (the `cpc-renderer.md` survey identifies
  fallbacks).
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
