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
> (2 waves of 4), independently reviewed (8 reviews), and reworked
> against the review findings. **User review in progress** — completed
> per-doc review-1 passes are recorded in the commit history. As of
> 2026-05-25: `assets.md`, `toolchain.md`, `gfx.md`, and this README
> have a first user-review commit; `cpc-renderer.md`, `audio.md`,
> `input.md`, `banking.md`, `testing.md` still in initial-draft state.

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

## 4. Cross-cutting phase sequence

Each subsystem's phases are numbered with its own prefix (G/A/T/R/
AU/IN/B/TS). The high-level sequence across all subsystems:

**Phase α — Foundation (no CPC code; pure preparation).**

- `TS1` — backfill ZX regression baselines (≥80 % of test games)
- `T0` — toolchain spike: prove z88dk `+cpc` + sdcc_iy + a tiny
  cpctelera build outside RAGE1
- `B1` — banking-config externalisation into
  `etc/rage1-config.yml` (ZX byte-identical)
- `G1` — `gfx_*` audit completion & baseline pin

**Phase β — HAL & asset-pipeline scaffolding (ZX-only, additive).**

- `G2` — `SPRITE_ENGINE` → `GFX_BACKEND` mechanical rename
- `A1` — introduce `PLATFORM` directive (`zx48`, `zx128` only)
- `A2` — sibling-tree overlay copy in `make config`
  (mechanism only; no overlay files yet)
- `T1` — `PLATFORM` axis throughout the Makefile family; ZX-only
- `B2` — per-platform ISR / codeset YAML split
- `IN1`, `IN2` — input audit + HAL skeleton (alias-only, ZX-only)
- `AU1`, `AU2` — audio audit + HAL aliases
- `R1` — cpctelera submodule add (vendored but not yet compiled)

**Phase γ — HAL generalisation (ZX byte-identical).**

- `G3–G6` — attribute / pixel coords / geometry / tile-ID abstraction
- `A3–A4` — per-platform dispatch seam in `datagen.pl`; overlay
  precedence proven end-to-end on ZX
- `B3` — parameterise lowmem threshold checks
- `IN3–IN4` — engine ↔ HAL migration; per-game `kbd.c` consolidation
- `AU3` — migrate to `audio_*` names; remove aliases

**Phase δ — CPC bring-up (cpc-flat first, then cpc-banked).**

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

**Phase ε — Hardening + CI matrix expansion.**

- `R5` — cpctelera hardening, upstream feedback
- `G9` — CPC backend across 3+ games (blobs / crumbs / mapgen)
- `IN7` — optional `CONTROLLER` `.gdata` directive
- `AU6` — `SOUND_MAP` directive for cross-platform `SOUND` events
- `B8` — SUBs on CPC
- `TS4–TS5` — TAP-byte invariant mode; CI matrix expansion

**Phase ζ — Cleanup.**

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
  (ZX: interleaved mask+graphic UDG bytes; CPC: mode-1 packed pixel
  bytes).

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
  50 Hz frame semantics survive but every ISR-using subsystem
  (audio, input, banking) must coordinate to the 300 Hz tick.
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
| (assets) **Q8** ✅ | CPC `SOUND` mapping | [assets.md](assets.md), [audio.md](audio.md) | **Resolved (2026-05-23)**: per-platform `SOUND_<PLATFORM>` directive (e.g. `SOUND_CPC`) in `Game.gdata`; general `SOUND_MAP` (audio.md AU6) deferred |
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
| (toolchain) **OQ-T11** | CPC banking model: extend RAGE1's own vs migrate both sides to z88dk `#pragma bank` | [toolchain.md](toolchain.md), [banking.md](banking.md) | Owed by `banking.md`; toolchain accommodates either |
| (cpc-renderer) **OQ-1** | Default CPC mode | [cpc-renderer.md](cpc-renderer.md) | **Mode 1** |
| (cpc-renderer) **OQ-2** | Pin cpctelera commit on `development` or `master` | [cpc-renderer.md](cpc-renderer.md) | Specific commit on `development` |
| (cpc-renderer) **OQ-5** | CDT/DSK via `appmake` or cpctelera's `iDSK`/`2cdt` | [cpc-renderer.md](cpc-renderer.md), [toolchain.md](toolchain.md) | `appmake` |
| (audio) **Q4** | ZX128 SFX routing: beeper-only vs beeper + AY both active | [audio.md](audio.md) | Both active by default; per-game opt-out |
| (audio) **Q8** | Shared `.aks` as recommended authoring convention | [audio.md](audio.md) | Yes |
| (input) **Q3** | CPC pause-key default | [input.md](input.md) | `Key_H` |
| (input) **Q4** | `cpct_scanKeyboard_if` vs `_f` (DI/EI ownership) | [input.md](input.md) | `_if` with explicit engine-side DI/EI |
| (banking) **OQ-B1** | Dataset destination buffer in page C vs page A | [banking.md](banking.md) | Page C |
| (banking) **OQ-B4** | CPC mode 0 support in Phase 1 | [banking.md](banking.md) | **No** — mode 1 only |
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
- [ ] User review and approval of the **initial** plan — in progress:
  - [x] `assets.md` review-1 (2026-05-23)
  - [x] `toolchain.md` review-1 (2026-05-24)
  - [x] `gfx.md` review-1 (2026-05-25)
  - [x] `README.md` cross-doc decisions absorbed (2026-05-25)
  - [ ] `cpc-renderer.md` review-1
  - [ ] `audio.md` review-1
  - [ ] `input.md` review-1
  - [ ] `banking.md` review-1
  - [ ] `testing.md` review-1
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
