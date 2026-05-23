# Assets pipeline: shared-core `.gdata` + per-platform overlays

This document covers the **asset pipeline** subsystem of the RAGE1 cross-platform
plan. It describes how `.gdata` files, PNG sources, music files and other game
assets flow through the build today; what is implicitly ZX-Spectrum-coupled in
that pipeline; and a phased plan to extend it so that a single shared-core
project, with thin per-platform overlays, can produce assets for both ZX
(Spectrum 48/128) and Amstrad CPC (464/664/6128) targets.

Architectural anchors that this document assumes (decided elsewhere in the
plan, not re-litigated here):

- Asset model: **shared-core `.gdata` + per-platform overlay tree**. The
  existing `patches/` mechanism is the natural precedent.
- A `gfx_*` HAL exists already (SP1/JSP unification) and will be extended to
  cover CPC via cpctelera. Engine consumption of asset bytes is out of scope
  here — see `gfx.md`.
- Music / SFX format choice (Arkos 2 vs Vortex etc.) — see `audio.md`.
- Build matrix mechanics (`PLATFORM=zx48|zx128|cpc464|cpc6128`) — see
  `toolchain.md`.

Out of scope for this document: engine APIs, Makefile/build-matrix mechanics,
audio format specifics, banking/memory-layout impact, cpctelera-specific
asset converters (we sketch the boundary, the deep mechanics live in
`cpc-renderer.md`).

---

## 1. Current state audit

### 1.1 The `.gdata` format (file kinds and what is per-asset)

`.gdata` is a single text-line-oriented DSL parsed by `tools/datagen.pl`
(`engine/.../tools/datagen.pl`). Top-level constructs are:

| Construct                          | Subtree under `game_data/`   | Purpose                                          |
|------------------------------------|------------------------------|--------------------------------------------------|
| `BEGIN_BTILE … END_BTILE`          | `btiles/*.gdata`             | static multi-cell graphic (8×8 cells + ZX attrs) |
| `BEGIN_SPRITE … END_SPRITE`        | `sprites/*.gdata`            | animated movable graphic with mask               |
| `BEGIN_SCREEN … END_SCREEN`        | `map/*.gdata`                | a map screen (layout, enemies, hotzones, items)  |
| `PATCH_SCREEN NAME=… … END_SCREEN` | `patches/map/*.gdata`        | additive overrides to an already-defined screen  |
| `BEGIN_HERO … END_HERO`            | `heroes/*.gdata`             | hero definition (1 per game)                     |
| `BEGIN_GAME_CONFIG … END_GAME_CONFIG` | `game_config/*.gdata`     | global config (target, areas, sounds, …)         |
| `BEGIN_RULE … END_RULE`            | `flow/*.gdata`               | flow-rule (WHEN/CHECK/DO scripted logic)         |

Common syntax rules — see `read_input_data()` at
`tools/datagen.pl:185-285`:

- One construct per `BEGIN_*` / `END_*` block; the parser is a small state
  machine (`state ∈ { NONE, BTILE, SPRITE, SCREEN, HERO, GAME_CONFIG, RULE }`).
- Line-end backslash continuation (`tools/datagen.pl:229`).
- `//` comments and blank lines are stripped (`tools/datagen.pl:217-219`).
- The list of files to process is given on the command line by the Makefile
  (no recursion, no glob inside `.gdata`). Files are processed
  **in CLI order**, which is fixed by `Makefile.common:176-185`:
  `game_config`, `btiles`, `sprites`, `map`, `heroes`, `flow`, then
  `patches/map`, `patches/flow`. This ordering is load-bearing because
  `PATCH_SCREEN` requires the named `SCREEN` to already exist
  (`tools/datagen.pl:252-254`).

The `.gdata` text format is **platform-neutral as a syntactic carrier** —
it is a small key/value/section DSL — but its **values** are heavily
ZX-coupled today: `INK_*` / `PAPER_* | BRIGHT` attribute expressions,
pixel encoding tuned to 8×8 cells, etc. The format can host CPC-coloured
content without grammar changes, provided we let attribute strings be
opaque tokens at parse time and interpret them per platform downstream.

### 1.2 `tools/datagen.pl` — what it does, and what is ZX-specific

`datagen.pl` is a 4400-line Perl tool. Logical pipeline:

1. **Parse** all `.gdata` files into in-memory data structures
   (`@all_btiles`, `@all_sprites`, `@all_screens`, `@all_rules`,
   `$game_config`, etc. — declared `tools/datagen.pl:50-82`).
2. **Compile** pixel/mask strings to byte arrays
   (`validate_and_compile_btile()` at `tools/datagen.pl:1188`;
   `validate_and_compile_sprite()` at `:1244`).
3. **Generate** C / ASM source code into the `generated/` tree
   (`generate_sprite()`, `generate_screen()`, `generate_hero()`, etc.).
4. **Emit** auto-detected feature macros into `features.h`.

ZX-specific assumptions baked into datagen today:

| Concern                | Where                                                  | ZX-coupling                                                                                                |
|------------------------|--------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| Pixel byte packing     | `pixels_to_byte()` `:2593-2598`                        | 16 chars (`##`/`..`) → 8-bit byte, MSB-first. Maps directly to a ZX/CPC 1-bpp linear byte; **platform-portable as a bit primitive**. |
| Per-cell ATTR byte     | `validate_and_compile_btile()` `:1206-1213`            | One attribute per 8×8 cell, expressed as `INK_x \| PAPER_y \| BRIGHT`. **ZX attribute model** — has no native CPC equivalent. |
| PNG → pixels+attrs     | `RAGE::PNGFileUtils::png_to_pixels_and_attrs()`        | Auto-derives ZX attribute strings via `extract_attr_from_cell` (`lib/RAGE/PNGFileUtils.pm:190-197`).        |
| ZX palette table       | `%zx_colors` at `lib/RAGE/PNGFileUtils.pm:23-39`       | Hard-coded 15 RGB tuples → ZX colour names. **ZX-only** today.                                              |
| Per-2-colours-per-cell | `extract_colors_from_cell()` `:148-186`                | ZX "two colours per 8×8 cell" rule, warns on >2. CPC mode-0 is 4bpp / mode-1 is 2bpp, **no attribute clash**. |
| Sprite column layout   | `generate_sprite()` `:1330` (header comment)           | SP1/JSP column-oriented mask+pixel byte stream. CPC will need a different layout (cpctelera-native).        |
| Loading screen SCR     | `tools/png2scr.pl`                                     | Hard-coded ZX screen line order, 6912 bytes (`png2scr.pl:17-26, 64-65`).                                    |
| Custom charset         | `CUSTOM_CHARSET FILE=… RANGE=…` in GAME_CONFIG         | Format is the ZX/z88dk 8×8 1-bpp `.ch8` (768 bytes for 96 chars). CPC mode-1 char is also 8×8 1-bpp → directly portable; CPC mode-0 charset would be different. |
| `ZX_TARGET`            | Game.gdata `ZX_TARGET 48\|128`                         | Named `ZX_TARGET`; chosen via `-t` in `Makefile.common:185`. Will become `PLATFORM` per `toolchain.md`.     |
| `DEFAULT_BG_ATTR`      | GAME_CONFIG                                            | ZX attribute byte expression. Per-platform equivalent will differ.                                          |
| Sound ID names         | `BEEPFX_*` constants in `SOUND <event>=BEEPFX_*`       | Beeper FX library identifiers; ZX-only. CPC needs an AY-equivalent set (see `audio.md`).                    |
| Tracker `.aks` / `.asm` | `TRACKER_SONG FILE=…`                                  | Arkos 2 source format. Note: Arkos2 supports CPC and ZX-AY natively — format itself is portable; the per-platform output binary differs. |

Everything else parsed by datagen (screen layout `OBSTACLE`/`DECORATION`/
`HOTZONE`/`ENEMY`/`ITEM`/`CRUMB`, hero logic, flow rules, BTile→screen
references, dataset assignments, codeset assignments) is **purely logical /
gameplay structure** and has no ZX coupling at the data level.

### 1.3 `mapgen.pl` + `btilegen.pl` + PNG converters

**`btilegen.pl`** (`tools/btilegen.pl`, 37 lines) is the thinnest of the
three. It scans a PNG file plus its sidecar `.tiledef` and emits one
`BEGIN_BTILE` block per tiledef line, with a `PNG_DATA` directive that
points back at the same PNG with coordinates. It does **no pixel
extraction itself** — it just emits `.gdata`. `btilegen.pl` is therefore
**already platform-neutral**: the platform-specific pixel/attr extraction
happens later when datagen processes the `PNG_DATA` directive.

**`mapgen.pl`** (`tools/mapgen.pl`, 2200 lines) is much heavier. It reads
a PNG "map image" plus one or more "tileset PNGs", auto-discovers BTile
rectangles, and writes:

- `game_data/btiles/auto_<name>.gdata` (one per detected BTile,
  `tools/mapgen.pl:1985`).
- `game_data/map/<screen>.gdata` (one per detected screen,
  `tools/mapgen.pl:1847`).
- Auto-generated `HOTZONE` definitions, optional check-map PNGs.

mapgen is **mostly platform-neutral**: it deals with cell-grid topology,
8-cell hotzone defaults, screen tiling. The actual pixel data goes via
`PNG_DATA` references — same indirection as btilegen. ZX-coupling in
mapgen is limited to the implicit assumption that 1 cell = 8×8 pixels
(true for both ZX and CPC), and that screens are an integer number of
cells wide and tall (also true for both platforms; CPC mode-1 is 40×25
cells, ZX is 32×24).

**`lib/RAGE/PNGFileUtils.pm`** is where the ZX coupling concentrates:

- `%zx_colors` (`:23-39`): RGB → ZX name table; the only colour
  vocabulary today.
- `map_png_colors_to_zx_colors()` (`:306`): snaps PNG colours to the
  nearest ZX RGB.
- `extract_attr_from_cell()` (`:190-197`): emits a string of the form
  `INK_<fg> | PAPER_<bg> [| BRIGHT]`.
- `png_to_pixels_and_attrs()` (`:241`): joint extraction for BTiles.
- `pick_pixel_data_by_color_from_png()` / `pick_pixel_data_by_background_from_png()`
  (`:103, :125`): mask-by-colour and pixels-by-background extraction
  for sprites. These two are **colour-vocabulary-agnostic** below the
  surface — they take a hex colour string and emit `##`/`..` — so they
  are easy to re-use from a CPC code path.

A clean refactor target therefore exists: `PNGFileUtils.pm` is the natural
seam between "PNG geometry + bit extraction" (portable) and "ZX palette +
attribute byte" (platform-specific).

### 1.4 The existing `patches/` mechanism (precise)

Today the patches mechanism is **screen-only** and works like this:

1. The Makefile passes both regular `.gdata` files and patch files to
   datagen on the command line, **regular files first, patches last**
   (`Makefile.common:176-185`):
   ```
   GDATA_FILES   = game_config/*.gdata btiles/*.gdata sprites/*.gdata \
                   map/*.gdata heroes/*.gdata flow/*.gdata
   GDATA_PATCHES = patches/map/*.gdata patches/flow/*.gdata
   ```
2. Datagen recognises a new top-level directive **`PATCH_SCREEN NAME=…`**
   (`tools/datagen.pl:250-258`). It looks up the named screen in the
   already-populated `%screen_name_to_index`; if it doesn't exist, it
   `die`s. If it does exist, it puts the parser into the `SCREEN` state
   with `$cur_screen` pointing at the **existing** screen struct (no
   copy) and sets `$screen_patching = 1`.
3. While in the `SCREEN` state, any directive that pushes onto a list
   (`OBSTACLE`, `DECORATION`, `HARMFUL`, `HOTZONE`, `ENEMY`, `ITEM`,
   `CRUMB`, `BACKGROUND`, etc.) **appends** to the already-loaded screen.
4. At `END_SCREEN`, the parser skips the normal `compile_screen()` +
   `push @all_screens` (`tools/datagen.pl:657-668`) when patching — the
   existing entry stays in place, now augmented.

Key properties of the current mechanism:

- It is **strictly additive** — there is no syntax for *removing* or
  *replacing* an existing element on a screen, only for adding new ones.
- It is **screen-scope only** — there is no `PATCH_BTILE`, `PATCH_SPRITE`,
  `PATCH_HERO`, `PATCH_GAME_CONFIG`, or `PATCH_RULE`. The "flow patches"
  directory glob in the Makefile is mostly redundant: flow rules are
  always *appended* to the global rule table by their normal `BEGIN_RULE`
  blocks (no rule has a stable identity beyond its `(screen, when)`
  bucket), so adding files under `patches/flow/` works **because of
  rule append-by-default**, not because of any `PATCH_RULE` machinery.
- It works because of **CLI-argument ordering** in the Makefile — the
  Makefile sequence (regular GDATA before patches) is the entire
  contract. Datagen itself does not know about the `patches/` directory.

This is good news for the multiplatform plan: the precedent is
clean and small, the load order is a Makefile concern (so it can be
generalised under `toolchain.md`), and the only new datagen knowledge
needed is "process files in this order".

### 1.5 Inventory of asset kinds — shared vs per-platform

Going through every `.gdata` directive, what is inherently shared vs
inherently platform-coupled:

**Inherently shared (gameplay/topology)**:

- Screen names, dataset assignments, screen titles (`SCREEN.NAME`,
  `SCREEN.DATASET`, `SCREEN.TITLE`).
- Screen layout / topology: `OBSTACLE`, `DECORATION`, `HARMFUL`,
  `BACKGROUND` placements as `(ROW, COL)` cell coordinates.
- `HOTZONE` definitions (both cell and pixel coordinates — pixel is
  a derived value, the cell grid is platform-neutral because both
  targets are 8×8 cell-based).
- `ENEMY` movement: `XMIN/YMIN/XMAX/YMAX`, `INITX/INITY`, `DX/DY`,
  delays, sequence A/B logic.
- `HERO`: animation sequences, steady frames, step sizes, damage mode,
  bullet config (the **logic**, not the bullet sprite pixels).
- `ITEM`, `CRUMB` placements and `ITEM_ID`.
- All flow rules (`BEGIN_RULE … END_RULE`): WHEN/CHECK/DO logic refers
  to game state (lives, items, hotzones, flags, screens) — none of it
  is platform-coupled.
- `GAME_AREA`, `LIVES_AREA`, `INVENTORY_AREA`, `DEBUG_AREA`,
  `TITLE_AREA` cell rectangles. `GAME_AREA` is per-platform (per
  OQ1 resolution — see §2.3's per-platform directive table); the
  other area rectangles remain shared unless similar suffixed
  variants are added later as needed.
- `SOUND <event>=<symbol>` mapping (the *event* is shared; the
  *symbol* is per-platform — see below).
- `SCREEN INITIAL=…`.
- `SCREEN_DATA` digraph map and `DEFINE GRAPH=…` directives.

**Inherently per-platform (graphic / audible bytes)**:

- BTile / sprite **pixel bytes** that have already been compiled to a
  specific bpp / column order. The author-level `PIXELS`/`MASK` `##`/`..`
  strings are platform-neutral as a *source representation*, but the
  CPC pixel byte layout (especially in mode 0) is not 1-bpp linear.
- BTile / sprite **attribute / palette** information. ZX uses an
  attribute byte per 8×8 cell. CPC uses per-mode palette indexes and
  has no attribute clash.
- The `INK_x | PAPER_y` attribute *expressions* — they are ZX vocabulary.
- Loading screen format (`.scr` is ZX-only; CPC has `.scr` files of its
  own but the byte format is different; both are 6912 vs 16384 bytes
  and have entirely different geometries).
- Sound effect IDs (`BEEPFX_*` are beeper-only; AY has different IDs).
- `DEFAULT_BG_ATTR`.
- `CUSTOM_CHARSET` file format — `.ch8` (768-byte 1-bpp 8×8) is the
  ZX/z88dk convention. CPC mode-1 charset is the same shape; mode-0
  charset is different.
- `BINARY_DATA` blocks (semantically shared, but the *binary content*
  is by nature per-platform if it represents graphics or sound).

**Mostly shared, with a per-platform "tint" line**:

- `GAME_CONFIG` — most directives are shared; only `ZX_TARGET` (will
  become `PLATFORM`), `DEFAULT_BG_ATTR`, the `SOUND` event symbols,
  `LOADING_SCREEN`, `CUSTOM_CHARSET`, and tracker file references are
  platform-coupled.
- `SCREEN.BACKGROUND` references a BTile and inherits the platform
  divergence from that BTile.
- `SPRITE.COLOR` (an `INK_*` constant) — ZX-coupled.

This inventory motivates the design: by far the majority (gameplay
logic, topology, flow) is shared. Per-platform overlays should cover
**the platform-coupled minority**: pixel data, attribute / palette,
loading screen, sound IDs, and the `GAME_CONFIG` platform tint.

---

## 2. Shared-core + overlay design

### 2.1 Tree layout — sibling tree vs extended `patches/`

Two options were considered. They differ on where platform-specific
overrides live relative to the shared core.

**Option A — sibling tree `game_data/<platform>/`**

```
game_data/                  # shared core (the union of common content)
  game_config/Game.gdata
  btiles/*.gdata
  sprites/*.gdata
  map/*.gdata
  heroes/*.gdata
  flow/*.gdata
  png/*.png
  patches/                  # existing additive screen patches (cross-platform)
zx48/game_data/             # per-platform overlay
  game_config/Game.gdata    # zx48-specific tint
  btiles/SomeTile.gdata     # full override for SomeTile
  png/loading_screen.png    # zx48 loading screen
zx128/game_data/
  game_config/Game.gdata
cpc6128/game_data/
  ...
```

**Option B — extend `patches/` to be platform-aware**

```
game_data/
  game_config/Game.gdata
  btiles/*.gdata
  ...
  patches/                  # existing patches/map remain platform-neutral
    map/Screen01.gdata
    zx48/                   # platform-conditional overrides
      game_config/Game.gdata
      btiles/SomeTile.gdata
    cpc6128/
      ...
```

**Trade-offs**:

| Concern                                | A (sibling tree)                                          | B (under `patches/`)                                       |
|----------------------------------------|-----------------------------------------------------------|------------------------------------------------------------|
| Discoverability                        | Excellent — platform overlays sit at the top              | Mediocre — buried under `patches/`                         |
| Continuity with current `patches/`     | None — `patches/` stays exactly as it is today            | High — extends an existing concept                         |
| Conflict with cross-platform screen patches | None — overlays and patches are orthogonal           | Risk — same directory hosts platform-neutral and platform-specific patches; CLI ordering becomes subtler |
| External-game model                    | Each external game has top-level `<platform>/game_data/`  | Each external game has `game_data/patches/<platform>/`     |
| Visual cue at filesystem level         | Strong — `ls game_data/` shows core; `ls zx48/` shows override | Weak — same level of nesting as today                  |
| Symmetry with `game_src/`              | Will need a matching `<platform>/game_src/` story; sibling tree extends cleanly | Less obvious how `game_src` overlays would work       |

**Recommendation: Option A (sibling tree).**

Rationale: the proposal is a clean conceptual extension. The existing
`patches/` mechanism stays exactly as it is — an *additive*,
*screen-only*, *platform-neutral* extension point — and the new
*per-platform* overlay tree is a separate concept with file-level
*shadow* semantics (see §2.2). Keeping the two mechanisms distinct
avoids overloading `patches/` with two different merge rules. The
sibling tree also generalises straightforwardly to `game_src/<platform>/`
for the (rarer) cases where custom C code itself diverges per platform.

The Makefile build pipeline (`make config`, `Makefile:44-57`) already
does the work that this needs: it copies `game_data` and `game_src`
into `build/`. The cross-platform version of `make config` will copy
the shared core first, then **overlay** the selected platform's tree
on top (with file-level shadowing — see §2.2). Detailed Makefile
shape is `toolchain.md`'s problem.

#### Platform-selection rule

The platform a build targets is chosen by exactly one of the
following sources, in this precedence order:

1. **CLI override**: `make build-<platform>` (e.g. `build-cpc6128`),
   or equivalently `PLATFORM=<platform> make build`.
2. **`Game.gdata` declaration**: `PLATFORM <name>` directive in
   `BEGIN_GAME_CONFIG` (mandatory after Phase A1's migration; see
   §2.3 below).

Concretely:

- The shared `game_data/` tree IS the data for the **declared
  default platform** (the value in `Game.gdata`). No
  `<default>/game_data/` overlay is required for the default; the
  shared tree fulfils that role.
- Any **other** supported platform must opt in by providing an
  explicit `<platform>/game_data/` directory (which may be empty —
  the directory's existence is the opt-in signal).
- `make build` (no suffix) builds the declared default platform
  from the shared `game_data/` directly.
- `make build-<platform>` (or `PLATFORM=<platform> make build`)
  **requires** an overlay tree at `<platform>/game_data/`. If the
  overlay tree does not exist, the build is **rejected** with a
  clear error message. **No silent fallback to the declared
  default.**
- The same overlay-presence rule applies to `<platform>/game_src/`
  (per OQ4: per-platform `game_src/` is supported). The two
  overlay axes (`game_data/` and `game_src/`) are independent:
  either one or both may exist for a given platform.

The asymmetry between "declared default uses shared tree" and
"other platforms need an explicit overlay" is deliberate: it keeps
single-platform games maximally simple (`PLATFORM zx128` + a
shared `game_data/` and you are done) while making
cross-platform support an explicit author choice. There is no way
to "accidentally" produce a CPC build of a ZX-only game.

### 2.2 Precedence / merging rules

The fundamental rule is **file-level full shadow**:

> When a file at relative path `P` exists in **both** `game_data/` (shared
> core) **and** `<platform>/game_data/` (overlay), the **overlay file
> completely replaces** the shared file for that build. The shared file
> is not parsed at all.

This is implemented at the **build/copy stage**, not inside datagen.
Concretely, in the platform-aware `make config` step:

```
cp -r game_data/.            build/game_data/
cp -r <platform>/game_data/. build/game_data/    # overlay, overwrites shadowed files
```

This gives **deterministic, easy-to-reason-about** semantics:

- The author owns "all of `btiles/SomeTile.gdata`" or none of it for
  a given platform.
- No mental model of partial merging is required — `diff` between the
  shared and overlay file is the whole story.
- The `make config` overlay is a pure filesystem operation; downstream
  tools (datagen, mapgen, etc.) see exactly one `build/game_data/`
  tree and don't need to know whether anything was overlaid.

**Key-level merging is explicitly rejected** as the default for the
following reasons:

- It would require datagen to understand "the same BTile defined
  twice" semantics — currently a hard error
  (uniqueness checks are implicit in the
  `%btile_name_to_index` / `%sprite_name_to_index` / etc. tables).
- It would introduce a "which key wins" rule per directive, multiplied
  across the entire `.gdata` vocabulary. The complexity is large and
  the benefit is small (a BTile is small enough to copy entirely).
- File-level shadow plus the existing additive `patches/` cover both
  "I want to replace one BTile per platform" (overlay) and "I want to
  add an enemy that only exists on platform X" (could be done via a
  `patches/<platform>/map/Screen01.gdata` file once we extend patches
  with a platform dimension — see §2.3).

For the **`patches/` mechanism**, the extension is small: we keep
*platform-neutral* patches at their current location
(`game_data/patches/map/*.gdata`) and additionally allow
**platform-scoped patches** under `<platform>/game_data/patches/map/*.gdata`.
Both are passed to datagen on the command line, neutral patches
**before** platform patches, both **after** all regular `.gdata` files —
so additive override flow is well-defined.

**Special case — generated assets (mapgen output)**:

mapgen writes into `game_data/btiles/auto_*.gdata` and
`game_data/map/<screen>.gdata`. These are platform-neutral by
design (pixel data is in PNG, see §1.3). If a per-platform override
of a mapgen-generated screen is needed, the **overlay file in
`<platform>/game_data/map/<screen>.gdata` shadows it whole**, which
is the cleanest semantics. For surgical per-platform tweaks to a
mapgen-generated screen, `<platform>/game_data/patches/map/<screen>.gdata`
remains the appropriate tool (the additive `PATCH_SCREEN` syntax).

**Concrete example**:

```
# Shared core
game_data/btiles/Rock01.gdata
game_data/sprites/Jorge.gdata
game_data/map/Screen01.gdata
game_data/game_config/Game.gdata        # contains shared sound mappings,
                                         #   GAME_AREA, etc.
game_data/patches/map/Screen01.gdata    # cross-platform additive patch
                                         #   (existing precedent — keep using)

# ZX 128K overlay
zx128/game_data/game_config/Game.gdata  # adds ZX_TARGET=128, BEEPFX_* SOUND
                                         #   IDs, DEFAULT_BG_ATTR, …
zx128/game_data/btiles/Rock01.gdata     # ZX-coloured Rock01 (shadows shared)
zx128/game_data/sprites/Jorge.gdata     # ZX colour + ZX pixel layout

# CPC 6128 overlay
cpc6128/game_data/game_config/Game.gdata
cpc6128/game_data/btiles/Rock01.gdata   # CPC-palette Rock01 (mode 0/1)
cpc6128/game_data/sprites/Jorge.gdata
cpc6128/game_data/patches/map/Screen01.gdata  # add a CPC-only enemy
```

### 2.3 `.gdata` syntax extensions

The fundamental design choice is: **prefer file-level overlays over
in-file platform-conditional syntax**. Reasons:

- Conditional syntax has no precedent in `.gdata` (no `#ifdef`-style
  blocks); introducing them in the parser is invasive.
- Tools that emit `.gdata` (mapgen, btilegen) would need to learn to
  emit and round-trip conditional blocks.
- The author cost of a small minority of duplicated lines is acceptable;
  the readability benefit of "this file is what this platform sees" is
  high.

**Minimal extension proposed for Phase A1**:

1. **`PLATFORM <name>`** directive inside `BEGIN_GAME_CONFIG`. Replaces
   the role of `ZX_TARGET` (`tools/datagen.pl:780-something` — search
   `ZX_TARGET`). Values: `zx48`, `zx128`, `cpc464`, `cpc6128` (4
   build-time identities; CPC664 runs the `cpc464` binary as a
   runtime target — see README.md §1).
   - `ZX_TARGET 48` becomes `PLATFORM zx48`, `ZX_TARGET 128` becomes
     `PLATFORM zx128`. The two are accepted in parallel during the
     transition (deprecation pass — see Phase B2).
   - Implies a corresponding `BUILD_FEATURE_PLATFORM_*` macro for
     conditional engine code.
2. **Renaming `ZX_TARGET`** to `PLATFORM` is also propagated to
   `Makefile.common`'s `ZX_TARGET` shell-grep
   (`Makefile.common:106`) — toolchain.md tracks this.

**Per-platform directives in `BEGIN_GAME_CONFIG`** (Phase A1):

Per OQ1, OQ5 and OQ8 resolutions, a small set of `BEGIN_GAME_CONFIG`
fields admit a platform-suffixed variant. The base form remains as
today (and is the implicit value on platforms that don't have a
suffixed override); the platform-suffixed form takes precedence
when the active `PLATFORM` matches the suffix.

| Base directive  | Per-platform variants | Purpose                                                                                                                                                                                              |
|-----------------|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `GAME_AREA …`   | `GAME_AREA_CPC …`     | Screen-area rectangle. ZX assumes 32×24; CPC mode-1 cells are 40×25, so authors typically need a different rectangle. Phase A1 adds the `_CPC` suffix; other platforms add their own suffix as needed. |
| `SOUND <E>=<S>` | `SOUND_CPC <E>=<S>`   | SFX symbol bindings (`SOUND ENEMY_KILLED=BEEPFX_HIT_3`). ZX maps to `BEEPFX_*`; CPC maps to Arkos SFX indices. The two forms coexist in the same `Game.gdata`. Per OQ8 (deferred from a general `SOUND_MAP` mechanism). |
| `CPC_PALETTE …` | n/a (CPC-only)        | Explicit CPC firmware-palette indices (or `.gpl` reference) passed to `cpct_img2tileset` for PNG-to-CPC conversion. Per OQ5: defaults to standard CPC firmware palette when absent.                  |

The dispatch is done in `datagen.pl`: when parsing `BEGIN_GAME_CONFIG`,
a directive `<NAME>_<PLATFORM_UPPERCASE>` shadows the base `<NAME>`
directive iff the current build's `PLATFORM` matches. The mechanism
is general — adding another per-platform variant later (e.g.
`SCREEN_DIMENSIONS_CPC` if it turns out to be useful separately
from `GAME_AREA`) is just one more table entry.

3. **Renaming `ZX_TARGET`** to `PLATFORM` is also propagated to
   `Makefile.common`'s `ZX_TARGET` shell-grep
   (`Makefile.common:106`) — toolchain.md tracks this.

**No other syntax extensions in Phase A1.** Specifically:

- No `PLATFORM_IF zx128 … END_PLATFORM_IF` blocks.
- No new `PATCH_*` directives beyond the existing `PATCH_SCREEN`.
- BTile / sprite / hero `.gdata` files remain syntactically unchanged.

**Optional later extensions (deferred — track as Open Questions)**:

- `PLATFORM_ATTR PIXELS_LAYOUT=linear|mode1|mode0` on a BTile, to
  declare what pixel encoding the bytes are in for *hand-authored*
  CPC-native pixel data (rare; PNG-driven is the expected path).
- A `BEGIN_PLATFORM <name> … END_PLATFORM` wrapper that gates a sub-
  region of a `.gdata` file for one platform. Useful only if file-level
  shadowing proves too coarse — wait until we see real use cases.
- A general `SOUND_MAP` mechanism (per `audio.md` AU6) that supersedes
  the `SOUND_<PLATFORM>` directives. Deferred per OQ8 ("specific sound
  form for CPC, for the moment").

### 2.4 Auto-conversion vs hand-authored override boundary

The design has **three tiers**, in increasing override cost:

| Tier | Authoring | Platforms covered | Cost |
|------|-----------|-------------------|------|
| 1. **Auto-convert from PNG** | One PNG file under `game_data/png/`, referenced by `PNG_DATA` in a shared `.gdata` | All platforms whose converter can handle the PNG | Minimal — just author the PNG |
| 2. **Per-platform PNG**       | `game_data/png/foo.png` (default) + `cpc6128/game_data/png/foo.png` (overlay), same `.gdata` referencing `game_data/png/foo.png` | All platforms — overlay PNG shadows shared PNG | Medium — duplicate art |
| 3. **Per-platform `.gdata`**  | `cpc6128/game_data/btiles/Foo.gdata` shadows the shared one entirely | One platform | High — duplicate metadata too |

Tier 1 is the happy path. The author draws once in PNG, and each
platform's converter (PNG → ZX pixels+attrs, PNG → CPC mode-1
pixels+palette, etc.) does the right thing. This works because PNG is
a *common authoring format* both platforms can target, and because
the `PNG_DATA` directive is **per-cell PNG reading, not pre-baked
pixel bytes**.

Tier 2 is needed when the PNG's *content* must differ — e.g.,
because the CPC's palette permits things the ZX doesn't (or vice
versa, when monochrome ZX detail must be exaggerated to compensate
for attribute clash). The overlay-PNG approach lets `.gdata` files
stay shared.

Tier 3 is the escape hatch for irreducible divergence — e.g., a
sprite that has more frames on CPC because the larger palette
allows finer animation, or whose `COLOR` differs in non-obvious
ways. **The `.gdata` file is shadowed entirely**.

**Boundary rule**: prefer Tier 1; fall back to Tier 2 for art
differences; reserve Tier 3 for cases where metadata itself
diverges. Tier 1 is the design goal of "mostly shared `.gdata`".

### 2.5 Tracker music, SFX, and other non-PNG assets

The overlay mechanism described above is **file-level** and
**recursive** — it applies to every file under
`<platform>/game_data/`, not just BTile / sprite PNGs. That covers
several other per-platform asset categories without new
machinery:

- **Tracker music** (`game_data/music/*.asm`, `.aks`, `.pt3`):
  ZX uses Vortex / Arkos for AY (on ZX128) and BeepFX for the
  48K beeper; CPC uses Arkos on its AY. The binary tracker data
  is *platform-specific* even when both use Arkos (different
  player routines, different replayer assumptions). Shared
  `.gdata` declares `TRACKER_SONG FILE=game_data/music/music1.asm`
  with a single path; each platform overlay provides its own
  binary file at that same relative path. After overlay copy,
  `build/game_data/music/music1.asm` is the correct platform's
  data. Format/driver choice and player integration belong to
  `audio.md`; the asset pipeline simply transports the right
  file per platform.
- **BEEPFX SOUND IDs** (`SOUND ENEMY_KILLED=BEEPFX_HIT_3` in
  `Game.gdata`): these reference a ZX-specific SFX bank. Per OQ8
  resolution, CPC uses a new **`SOUND_CPC`** directive in the same
  `Game.gdata` (Arkos SFX indices on CPC, e.g.
  `SOUND_CPC ENEMY_KILLED=ARKOS_HIT_3`). The two forms coexist;
  `datagen.pl` selects based on the active platform. A general
  `SOUND_MAP` mechanism remains a long-term refactor option (see
  `audio.md` AU6) but is explicitly deferred.
- **Per-platform `game_src/`** (custom C/asm per game): same
  overlay rule. `game_src/menu.c` shared by default; if a
  particular platform needs a different `menu.c` (e.g. because
  of a platform-specific keyboard scan or audio init detail),
  it ships one under `<platform>/game_src/menu.c` and the
  overlay copy shadows the shared file. Covered by the same
  copy step as `game_data/` in Phase A2.
- **Per-platform loading screens** (`.scr`): handled by
  separate per-platform converters (`png2scr.pl` for ZX,
  `png2cpcscr.pl` or cpctelera-tool for CPC); the source PNGs
  may be shared (Tier 1) or platform-specific (Tier 2). See
  §3.2.

No new precedence or merging machinery is required for any of
these — they all fall out of the file-level recursive overlay
copy described in §2.2.

---

## 3. Tooling changes

### 3.1 `datagen.pl` changes

The bulk of datagen needs **minimal changes** if file-level
shadowing is done at the `make config` stage (see §2.2). The
fundamental split for CPC vs ZX pixel/palette work is:

- **ZX path stays Perl-internal.** `RAGE::PNGFileUtils` continues
  to handle PNG → ZX byte arrays + ZX attribute bytes, exactly as
  today. No CPC code is added to `PNGFileUtils.pm`.
- **CPC path delegates to cpctelera.** PNG → CPC byte arrays is
  done by invoking cpctelera's `cpct_img2tileset` Bash script (which
  wraps the `Img2CPC` binary) as a **subprocess** from datagen.
  cpctelera owns mode-0/1/2 pixel encoding, palette mapping, and the
  awkward two-pixels-per-byte mode-0 interleaving — bug-for-bug
  compatible with the runtime that consumes the bytes. See
  `cpc-renderer.md` §5 for the integration choice; see Phase A5
  below for the wiring.

The changes needed inside datagen are:

1. **`PLATFORM` directive in GAME_CONFIG** (mandatory once
   migration completes — see Phase A1). Add parsing in the
   `GAME_CONFIG` state branch alongside `ZX_TARGET` (current
   parsing site `tools/datagen.pl:762-773`; emit feature macros
   via `generate_conditional_build_features()` whose body lives
   around `tools/datagen.pl:3507-3523`). Emit
   `BUILD_FEATURE_PLATFORM_<UPPERCASE>`.
2. **Per-platform dispatch in the PNG path.** Add a thin
   `$platform`-aware dispatcher around the per-asset PNG handling
   in `validate_and_compile_btile()` / `validate_and_compile_sprite()`:
   - For ZX platforms, the existing call into
     `RAGE::PNGFileUtils::png_to_pixels_and_attrs()` (or
     equivalent — current ZX byte+attr extraction surface) is
     unchanged.
   - For CPC platforms, datagen instead invokes a new helper
     `tools/cpc_asset_convert.pl` (or `.sh`) which shells out to
     `cpct_img2tileset` with the appropriate flags
     (`--mode 1`, tile width/height, sprite vs tileset, mask
     handling), captures its generated `.c`/`.h` outputs, and
     splices them into `build/generated/`. Detailed flag mapping
     belongs to `cpc-renderer.md` §5.
   - The dispatcher decides which path to take by reading
     `$game_config->{'platform'}` (or the equivalent already-parsed
     value from item 1). No CPC pixel/palette logic is added to
     `RAGE::PNGFileUtils`.
3. **No change to `pixels_to_byte()`** (`tools/datagen.pl:2593`).
   It stays as the ZX 1-bpp linear encoder. There is no Perl-side
   CPC equivalent; the CPC byte layout is produced by the
   cpctelera subprocess.
4. **No change to the ZX attribute byte writer** in
   `generate_sprite()` / `generate_screen()`. CPC has no
   attribute byte; per OQ2 resolution, the engine is parameterised
   to not require a per-BTile/per-cell colour token on CPC at
   all — what CPC needs instead (palette setup, etc.) is part of
   cpctelera's generated `.c`/`.h` output and lands in
   `build/generated/` already-formed. The engine-side
   parameterisation is `gfx.md`'s territory.
5. **`get_sprite_engine()` generalises** — today it returns
   `'sp1'` or `'jsp'`; it becomes `get_gfx_backend()` returning
   `'sp1'`, `'jsp'`, `'cpc'`, etc. The CPC backend choice
   is forced by the platform; the ZX backend remains
   user-selectable (`SPRITE_ENGINE` directive in GAME_CONFIG).
6. **`features.h` macros**: add `BUILD_FEATURE_PLATFORM_*` and
   `BUILD_FEATURE_GFX_BACKEND_*`.
7. **PNG path resolution under overlays** (per OQ7 resolution).
   `datagen.pl` must be invoked with **`cwd = build/`** so that
   `PNG_DATA FILE=game_data/png/foo.png` resolves to
   `build/game_data/png/foo.png` — the post-`make config` location
   where the overlay copy has already taken precedence. Today the
   doc convention says PNG paths are "relative to the repository
   top" (`doc/DATAGEN.md:88-89`); the Phase A1 work updates the
   Makefile invocation to `cd build && datagen.pl …` and updates
   `doc/DATAGEN.md` to match. This is the only fix needed for
   overlay-aware PNG resolution.
8. **Per-platform GAME_CONFIG directive dispatch** (per OQ1, OQ5,
   OQ8 resolutions). A small table in `datagen.pl` declares which
   `BEGIN_GAME_CONFIG` directives have per-platform variants
   (`GAME_AREA`, `SOUND`, plus the CPC-only `CPC_PALETTE`). When
   parsing the config block, a directive whose name ends in
   `_<PLATFORM_UPPERCASE>` (e.g. `GAME_AREA_CPC`) shadows the
   base directive iff the active build's `PLATFORM` matches the
   suffix. See §2.3 for the syntax and the full list.

The asymmetry (ZX Perl-native, CPC subprocess) is deliberate: it
avoids re-implementing in Perl a pixel encoder that cpctelera
already maintains and that the CPC runtime consumes natively. It
also means the boundary between "RAGE1 asset pipeline" and
"cpctelera asset pipeline" is one clean process boundary, not a
shared format that has to track upstream changes.

Things datagen **does not** need to change:

- Parsing of all gameplay directives (`HOTZONE`, `ENEMY`, `ITEM`,
  flow rules, etc.) — they are platform-neutral.
- The state machine for `BEGIN_*` / `END_*` (no new top-level
  constructs in Phase A1).
- The `PATCH_SCREEN` mechanism (unchanged).
- The CLI surface (still takes a list of `.gdata` files; the
  Makefile arranges them in the correct order).

### 3.2 `mapgen.pl` + `btilegen.pl` changes

**`btilegen.pl`** needs **no changes** — it emits `.gdata` blocks
with `PNG_DATA` references; the per-platform decoding happens in
datagen. Whatever PNG / `.tiledef` pair btilegen reads is
authored once; both platforms decode it.

**`mapgen.pl`** needs **minor changes**:

- `mapgen.pl` outputs `auto_*.gdata` BTile definitions with
  `PNG_DATA` references that include `XPOS`, `YPOS`, etc. Today
  these are platform-neutral (the byte layout is decided by datagen
  later). **No change needed for the happy path** (Tier 1).
- The check-map / btile-report side outputs are diagnostic only;
  they're not part of the produced game. They may continue to
  visualise in "ZX colours" since they're for the author. **No
  change needed.**
- One small ZX-coupling to address: `mapgen.pl` cap of
  `--screen-cols 32 --screen-rows 24` is not enforced today, but
  the engine pipeline assumes ZX screen dims downstream. CPC mode 1
  is 40 cells wide × 25 tall. The CLI is already parameterised
  (`tools/mapgen.pl:62-63`), so the *tool* is fine — but the
  *engine* needs to support these dims (out of scope here; see
  `gfx.md`).

**Per-platform converters**: the asset pipeline now has a clean
two-track structure:

| Asset kind                   | ZX path                                              | CPC path                                                                          |
|------------------------------|------------------------------------------------------|-----------------------------------------------------------------------------------|
| BTile / sprite (PNG → bytes) | `RAGE::PNGFileUtils` (Perl-internal)                 | `cpct_img2tileset` invoked as subprocess via `tools/cpc_asset_convert.pl` wrapper |
| Loading screen (PNG → `.scr`) | `tools/png2scr.pl` (Perl-internal)                  | `tools/png2cpcscr.pl` *or* invoke a cpctelera converter — to be decided in A5     |
| Tracker music / SFX          | tracker-format pass-through (today: Vortex `.aks`)   | Arkos / cpctelera-compatible tracker pass-through — see `audio.md`                |

The architectural rule:
- **ZX-side asset conversion stays inside the Perl `RAGE::*` library
  modules** (`PNGFileUtils.pm` and friends), exactly as today.
- **CPC-side asset conversion delegates to cpctelera tools as
  subprocesses**, via a thin `tools/cpc_asset_convert.pl` wrapper
  whose job is to give the cpctelera scripts a fixed invocation
  surface (decoupled from cpctelera's `CPCT_PATH`-environment
  assumptions). See `cpc-renderer.md` Phase R3 for the wrapper
  design.
- We do **not** have parallel `datagen-zx.pl` and `datagen-cpc.pl`
  tools — there is one `datagen.pl`, and it dispatches internally on
  `PLATFORM`, calling into Perl modules for ZX and shelling out for
  CPC.

### 3.3 PNG → ZX vs PNG → CPC

| Aspect            | PNG → ZX (today)                                | PNG → CPC (planned)                                                                                            |
|-------------------|-------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| Author-side PNG   | Use `ZX-Spectrum.gpl` palette in GIMP           | Use a CPC firmware-palette `.gpl` for mode 0/1                                                                 |
| Per-cell colours  | 2 colours per 8×8 cell                          | Mode 1: 4 colours per screen, free within cell; Mode 0: 16 colours per screen, free within cell                |
| Per-cell attrs    | 1 attribute byte per cell                       | None (CPC has no attribute byte)                                                                               |
| Pixel encoding    | 1-bpp linear, MSB-first                         | Mode 1: 2-bpp packed; Mode 0: 4-bpp packed (interleaved) — handled by cpctelera, not by RAGE1                  |
| Tool entry point  | `RAGE::PNGFileUtils::png_to_pixels_and_attrs()` | `tools/cpc_asset_convert.pl` wrapper invoking `cpct_img2tileset` (`--mode 1 --tw … --th … [--mask]`)           |
| Author-time       | Just draw, then `PNG_DATA …` in `.gdata`        | Same — author draws, references PNG, build does the rest                                                       |
| Build-time path   | datagen invokes `RAGE::PNGFileUtils` and emits ZX byte arrays + ZX attr arrays | datagen invokes `cpc_asset_convert.pl`; cpctelera generates `.c`/`.h` under `build/generated/`; datagen wires it into the build |
| Ownership of pixel-encoding semantics | RAGE1 (Perl)                    | cpctelera (upstream) — RAGE1 only marshals inputs/outputs                                                       |

The fundamental authoring promise — *one PNG, both platforms* — is
viable as long as the PNG is drawn within a colour budget that both
platforms can express. The conservative default is "draw within
the ZX 15-colour palette and 2-colours-per-cell constraint, and
the CPC will render it at a similar look". For richer CPC art,
authors use Tier 2 (per-platform PNG overlay, with a CPC-friendly
palette) or Tier 3 (per-platform `.gdata`).

The asymmetry (Perl on ZX, subprocess on CPC) keeps the surface
area small: we never duplicate cpctelera's mode-0/1/2 encoding logic
in Perl, and we never have to track upstream encoding changes.

---

## 4. Phased work plan

The phases below are **asset-pipeline-internal**. They assume the
build-matrix changes from `toolchain.md` land in parallel; the
phase-exit testing criteria capture that dependency.

Numbering convention: **A** = Asset pipeline; phases **A1, A2, …**;
tasks within a phase **A1-1, A1-2, …**.

Each task is small enough that a reviewer can hold it in their head;
where appropriate it is independently testable. Phase-exit criteria
explicitly require `make all-test-builds` and the
`tests/00regression/` ZX screenshot tests to be green (per the
top-level plan's back-compat policy).

### Phase A1 — Introduce `PLATFORM`, prove ZX stays green

**Goal**: rename `ZX_TARGET` → `PLATFORM` and prove that introducing
the multi-platform vocabulary breaks nothing for the existing ZX games.
No CPC work yet.

- **A1-1** Add `PLATFORM <name>` parsing to `BEGIN_GAME_CONFIG` in
  `tools/datagen.pl`, alongside existing `ZX_TARGET`.
  Accepted values: `zx48`, `zx128`. Emit
  `BUILD_FEATURE_PLATFORM_ZX48` / `BUILD_FEATURE_PLATFORM_ZX128`.
  When `PLATFORM` is present, also emit the legacy `ZX_TARGET=…`
  derived value for backwards compatibility.
  *Test*: ad-hoc — add `PLATFORM zx128` to one test game, build, diff
  the generated `features.h` to confirm both old and new macros
  appear.
  *Expected outcome*: existing games (none using `PLATFORM`) build
  unchanged; the one updated game has the new macro.
- **A1-2** Add a deprecation warning printed from datagen when
  `ZX_TARGET` is used without a `PLATFORM`. Do not yet fail; this
  is a guidance pass.
  *Test*: `make all-test-builds` — observe one warning per test game.
- **A1-3** Migrate every `games/*/game_data/game_config/Game.gdata`
  to `PLATFORM` (`zx48` or `zx128`) and remove `ZX_TARGET`.
  *Test*: `make all-test-builds`, `tests/00regression/` green.
- **A1-4** Update `Makefile.common`'s `ZX_TARGET = $(shell grep …
  ZX_TARGET …)` query to read `PLATFORM` instead and map it back to
  `ZX_TARGET=48|128` internally (Makefile-128 / Makefile-48 selection
  still uses the legacy variable).
  *Test*: `make build48`, `make build128`, `make build`,
  `make all-test-builds`.
- **A1-5** Update `doc/DATAGEN.md` to document `PLATFORM` as the
  preferred directive and `ZX_TARGET` as deprecated.
  *Test*: doc-only; visual review.
- **A1-6** Implement the **platform-selection rule** (per §2.1
  "Platform-selection rule"): a build resolves its target platform
  as `CLI override > Game.gdata's PLATFORM directive`. If the
  resolved platform is **not** the game's declared default AND no
  `<platform>/game_data/` overlay directory exists for it, the
  build is rejected with a clear error (e.g. *"game `foo` does not
  declare an overlay for platform `cpc6128` — add `cpc6128/game_data/`
  to opt in"*). The declared default does not need an overlay; the
  shared `game_data/` IS its data.
  *What to change*: `tools/detect-platform.sh` and the top-level
  `Makefile`'s `config` target gain the rejection check.
  *Test*: build a ZX-only game with `make build-cpc6128`; observe
  the rejection. Build the same game with `make build` (no
  suffix); observe success.

**Phase-exit criteria for A1**:
- `make all-test-builds` green.
- `tests/00regression/` ZX screenshot tests green.
- All checked-in games use `PLATFORM`.
- `ZX_TARGET` still accepted for backwards compatibility with
  external games, with a deprecation warning.
- The CLI-override + overlay-required rule is enforced (A1-6).

### Phase A2 — Sibling tree + overlay copy

**Goal**: introduce the `<platform>/game_data/` sibling overlay tree
and the `make config` file-level overlay step, with no overlay files
in any game yet (i.e., the overlay tree is empty, but the mechanism
exists).

- **A2-1** Extend the `config` target in the top-level `Makefile`
  (around `Makefile:44-57`) so that, after copying the shared
  `$(TARGET_GAME)/game_data/` and `$(TARGET_GAME)/game_src/` into
  `build/`, it also overlay-copies
  `$(TARGET_GAME)/$(PLATFORM)/game_data/` and
  `$(TARGET_GAME)/$(PLATFORM)/game_src/` when those directories
  exist. The recursive copy must shadow shared files at the same
  relative path (later `cp -r` wins by default).
  *Test*: build all test games unchanged (no overlay dirs exist
  yet); confirm `make all-test-builds` green.
- **A2-2** Verify both overlay axes work — `game_data/` **and**
  `game_src/`. Add a transient smoke test that creates
  `games/minimal/zx48/game_src/menu.c` with a one-line diff (e.g.
  a printf), runs `make build-minimal`, confirms the overlay
  version is what's compiled. Remove the smoke test file.
  *Test*: local ad-hoc; nothing checked in.
- **A2-3** Verify music/SFX overlay transport works. Add a
  transient smoke test that creates
  `games/default/zx128/game_data/music/music1.asm` shadowing the
  shared one with a recognisable byte change (e.g. one extra
  null byte at end), runs `make build-default`, confirms the
  overlay file is what lands in `build/game_data/music/music1.asm`.
  Remove the smoke test file.
  *Test*: local ad-hoc; nothing checked in.
- **A2-4** Document the sibling-tree convention in
  `doc/DATAGEN.md` and in `doc/multiplatform-plan/README.md`
  (cross-link).
  *Test*: doc-only.
- **A2-5** Confirm `--game-data-dir` for `mapgen.pl` still points
  at the **shared** `game_data/` (overlay mechanics are at copy
  time, not at tool-author time): no change to mapgen invocations
  expected.
  *Test*: `make build-mapgen` still works.

**Phase-exit criteria for A2**:
- Overlay mechanism exists for `game_data/` and `game_src/`
  (verified via A2-2/A2-3 smoke tests).
- `make all-test-builds` green.
- `tests/00regression/` green.

### Phase A3 — Per-platform dispatch seam in `datagen.pl`

**Goal**: introduce the `$platform`-aware dispatch seam in
`datagen.pl` around PNG-driven BTile / sprite handling, with **only
the ZX branch implemented**. The CPC branch is a placeholder that
errors out cleanly (`die "CPC asset conversion not yet wired — see
Phase A5"`). The seam is added so A5 can land additively without
touching the dispatcher's surrounding logic again.

This phase deliberately does **not** touch `RAGE::PNGFileUtils`.
Per the §3.1 pivot, CPC asset conversion is handled by a
subprocess (cpctelera's `cpct_img2tileset`) called from a new
helper, not by per-platform branches inside PNGFileUtils. The seam
lives in `datagen.pl`'s asset-processing routines, not in
`PNGFileUtils.pm`.

- **A3-1** Introduce a `dispatch_png_asset_handling($platform, ...)`
  helper in `datagen.pl`. For `$platform =~ /^zx/`, route to the
  existing `RAGE::PNGFileUtils` call sites. For `$platform =~ /^cpc/`,
  `die` with a clear message pointing at Phase A5.
  *Test*: `make all-test-builds` byte-identical to pre-A3 output
  (diff `build/generated/`).
- **A3-2** Re-route all current PNG-driven asset call sites in
  `validate_and_compile_btile()` / `validate_and_compile_sprite()`
  through the new dispatcher. ZX paths unchanged.
  *Test*: `make all-test-builds` byte-identical; ZX
  `tests/00regression/` green.
- **A3-3** Document the dispatcher in `doc/DATAGEN.md` — name the
  function, the dispatch keys, and the convention that CPC paths
  shell out rather than going through `RAGE::PNGFileUtils`.

**Phase-exit criteria for A3**:
- `datagen.pl` exposes the dispatcher seam.
- CPC dispatch path exists but is intentionally a hard error.
- ZX byte-for-byte output unchanged.
- `make all-test-builds` green.
- `tests/00regression/` green.

### Phase A4 — Platform-aware overlay precedence proven end-to-end on ZX

**Goal**: prove that the overlay tree actually does what's promised,
using ZX as the only platform. Picks a test game and gives it a
trivial overlay that visibly differs.

- **A4-1** Pick `games/minimal` as the smoke-test game.
- **A4-2** Add `games/minimal/zx128/game_data/btiles/Live.gdata`
  that differs from the shared one in, say, attribute (red instead
  of yellow). The shared `Live.gdata` stays unchanged.
- **A4-3** Set `games/minimal/game_data/game_config/Game.gdata`'s
  `PLATFORM zx128`, build, and confirm the overlay won.
  *Test*: `make build-minimal`; `make run` and visual check; or add
  a screenshot regression test for it.
- **A4-4** Revert the overlay file so `games/minimal` is back to
  single-platform. The capability is now proven.
- **A4-5** Add a CI regression test under `tests/00regression/`
  named `overlay_shadow` that always exercises this end-to-end
  (it shadows a BTile and asserts the screenshot diff).

**Phase-exit criteria for A4**:
- The sibling-overlay mechanism is exercised in CI.
- `make all-test-builds` green.
- `tests/00regression/overlay_shadow` green.

### Phase A5 — CPC asset conversion via cpctelera subprocess

**Goal**: stand up the CPC side of the asset pipeline by wiring
`datagen.pl` to invoke cpctelera's `cpct_img2tileset` as a
subprocess for CPC platforms. No Perl-side CPC encoders are added
(the architectural pivot in §3.1/§3.3). No CPC engine yet (that
is `gfx.md` / `cpc-renderer.md`); this phase ends with `datagen.pl`
capable of *emitting* CPC byte arrays into `build/generated/cpc/`,
even if no engine yet consumes them.

This phase depends on **cpc-renderer.md** Phase R1 (cpctelera
vendored as `external/cpctelera`) and R3 (`cpct_img2tileset`
reachable on PATH or via the wrapper) having landed. If those
haven't landed yet, A5 stalls — sequence A5 after R3 in the
top-level plan.

- **A5-1** Add `tools/cpc_asset_convert.pl` — a thin Perl wrapper
  around `cpct_img2tileset` (and its sprite-sheet invocation mode,
  which replicates cpctelera's `IMG2SPRITES` Makefile macro). The
  wrapper gives datagen a fixed call surface decoupled from
  cpctelera's `CPCT_PATH` environment-variable assumptions.
  Inputs: PNG path, mode (0/1; mode 1 default per OQ3), tile/sprite
  dimensions, mask flag, **optional explicit palette** (per OQ5:
  list of CPC firmware-palette indices, or a path to a `.gpl` file).
  When the palette argument is provided, it is forwarded to
  `cpct_img2tileset` as its `--palette` argument; when absent, the
  standard CPC firmware palette is used. The palette typically
  comes from the new `CPC_PALETTE` directive in `Game.gdata` (see
  §2.3); the wrapper itself just accepts it as an input.
  Outputs: a `.c`/`.h` pair under `build/generated/cpc/`.
  *Test*: unit-test the wrapper against a known PNG with (a) the
  default palette and (b) a hand-specified palette; compare the
  generated `.c`/`.h` against a checked-in reference for each case.
- **A5-2** Add a per-platform dispatcher in `datagen.pl` around
  PNG-driven BTile / sprite handling. For ZX platforms the existing
  `RAGE::PNGFileUtils` path is taken; for CPC platforms the
  dispatcher invokes `tools/cpc_asset_convert.pl` with the
  appropriate arguments derived from the `.gdata` declarations.
  *Test*: ZX builds remain byte-identical (diff `build/generated/`
  against pre-A5 output); CPC dispatch path can be exercised
  manually with a `PLATFORM cpc6128` test game.
- **A5-3** Introduce `games/minimal/cpc6128/game_data/game_config/Game.gdata`
  with `PLATFORM cpc6128` and minimal overrides; run `datagen.pl`
  manually to confirm cpctelera-generated `.c`/`.h` lands in
  `build/generated/cpc/`. **Do not yet wire into
  `make all-test-builds`** — there is no CPC backend to compile
  against.
  *Test*: inspect generated `.c` by hand; confirm pixel-packing
  looks plausible against the input PNG.
- **A5-4** Coordinate with `cpc-renderer.md` (R3-2) on the wrapper
  contract: which arguments the wrapper expects, which output paths
  it writes to, and how cpctelera's variable-naming conventions
  feed into `build/generated/cpc/`. Document the contract in a new
  `doc/CPC-ASSET-WRAPPER.md` (or as a section of `cpc-renderer.md`).
  *Test*: doc-only.
- **A5-5** Add a CPC loading-screen path. The Tier-1 default is
  to invoke `cpct_img2tileset` in a screen-encoding mode (one of
  cpctelera's existing flags); if that proves inadequate, add a
  thin `tools/png2cpcscr.pl` that uses cpctelera's underlying
  Img2CPC binary directly. Wire it into the Makefile next to
  `png2scr.pl`.
  *Test*: produce a `.scr` from a sample PNG; verify size and
  palette match CPC expectations.

**Phase-exit criteria for A5**:
- `datagen.pl` with `PLATFORM cpc6128` produces CPC `.c`/`.h`
  artifacts under `build/generated/cpc/` via the cpctelera wrapper.
- ZX builds remain byte-identical to A4 output (`diff
  build/generated/` shows no changes for ZX-only test games).
- `make all-test-builds` (ZX-only) green.
- `tests/00regression/` (ZX) green.
- No CPC binary built end-to-end yet (the engine isn't there yet).
- The wrapper contract is documented and stable.

### Phase A6 — Platform-scoped patches

**Goal**: extend the existing `patches/` mechanism to be
platform-aware via the sibling tree, completing the precedence
story.

- **A6-1** The `make config` overlay step (Phase A2's recursive
  `cp -r` of `<platform>/game_data/`) already transports any
  `<platform>/game_data/patches/map/*.gdata` **and**
  `<platform>/game_data/patches/flow/*.gdata` into the
  corresponding `build/game_data/patches/{map,flow}/` directories.
  A6-1 is a **verification step**, not an implementation step:
  add platform-scoped patches under both `patches/map/` and
  `patches/flow/` of a test game, confirm both land in `build/`,
  are read by datagen at build time, and apply as expected.
  Per OQ6 resolution, the existing `patches/` mechanism — which
  is the official extension point for mapgen-generated screens
  and rules — stays exactly as it is; the only addition is that
  it now also accepts a platform-overlaid copy.
  *Test*: ad-hoc — add the files, build, inspect `build/`, then
  inspect the generated screen layout and rule table in
  `build/generated/` for the patched changes.
- **A6-2** Document the layering in `doc/DATAGEN.md`:
  - Shared regular `.gdata` is loaded first.
  - Shared `patches/` are loaded next (post-load, additive on top
    of shared `.gdata`).
  - Platform-scoped overlay `.gdata` (Tier 3) shadows shared
    files **before** loading begins (it is a filesystem replacement
    in `build/`).
  - Platform-scoped `patches/` (under `<platform>/game_data/patches/`)
    are loaded **last**, additive on top of everything.
  *Test*: doc-only.
- **A6-3** Add a regression test under `tests/00regression/` that
  exercises platform-scoped patches (a screen with a CPC-only enemy
  added via `cpc6128/game_data/patches/map/Screen01.gdata`). Skip on
  ZX runs once the CPC test target lands.

**Phase-exit criteria for A6**:
- Three-tier overlay (file shadow → patch → platform patch) works
  end-to-end on at least one synthetic game.
- `make all-test-builds` (ZX) green.

### Phase A7 — Cleanups, deprecation, docs

**Goal**: close out the migration cleanly.

- **A7-1** Remove the `ZX_TARGET` alias from `datagen.pl` (still
  emit a clear error message if used).
- **A7-2** Migrate any external test fixtures and update
  `doc/multiplatform-plan/README.md` cross-references.
- **A7-3** Update `tools/mapgen.pl` `--help` output to mention
  the per-platform overlay convention.
- **A7-4** Add an "assets pipeline overview" section to the
  top-level `doc/multiplatform-plan/README.md` with a single
  figure showing the three-tier overlay.

**Phase-exit criteria for A7**:
- No code reference to `ZX_TARGET` remains.
- `make all-test-builds` green.
- `tests/00regression/` green.
- Docs reflect the final state.

---

## 5. Risks

- **Risk: the "two-colours-per-cell" attribute model leaks deeper
  than expected into engine code that consumes assets.**
  Datagen emits per-cell ATTR bytes that the engine then writes
  to the ZX attribute file (`0x5800-0x5AFF`). The CPC has no
  equivalent; per-cell colour resolution is implicit in the
  pixel data itself. If any engine logic (e.g., colour-flash
  effects, palette swaps, monochrome-mode optimisations in
  `tools/datagen.pl:2740` and around) is built around the
  attribute byte being a first-class entity, the CPC backend
  may need a synthesised "shadow attribute table" or a parallel
  data path.
  *Mitigation*: this risk lives at the boundary between `assets.md`
  (what we emit) and `gfx.md` (what the engine consumes). On the
  asset side: ZX still emits attribute bytes through the existing
  `RAGE::PNGFileUtils` path; CPC asset bytes come from cpctelera
  (which carries colour information inside the pixel data, with no
  attribute byte). The CPC backend (owned by `gfx.md`) decides
  whether to synthesise a shadow attribute table for cross-
  platform engine code, lower it to a palette index, or drop it
  entirely. Coordinate with the `gfx.md` author once that doc
  lands.

- **Risk: PNG-driven assets that "look fine" on ZX may produce
  poor CPC results, especially in mode-1 (4 colours per screen
  global).**
  CPC mode 1's *4 colours total* is far more restrictive per-screen
  than ZX's *2 colours per cell, 15 colours global*. cpctelera's
  `cpct_img2tileset` does its best to map the input PNG into the
  declared palette, but the result depends entirely on the input.
  *Mitigation*: the three-tier authoring model (§2.4) explicitly
  accommodates this — authors who care can produce per-platform
  PNGs (Tier 2). For the happy-path test games, picking ZX colours
  that map cleanly to CPC firmware palette (e.g., bright primary
  colours) keeps the auto-conversion sane. cpctelera converters
  also accept explicit palette arguments — the wrapper script
  (Phase A5-1) makes that surface available. Track as Open
  Question 3.

- **Risk: mapgen's `auto_*.gdata` outputs may be regenerated
  during builds (currently they are committed to repos as part of
  `make build-mapgen`) and inadvertently overwrite per-platform
  overlays.**
  mapgen writes into `game_data/btiles/auto_*.gdata` (not into
  `<platform>/`), so overlays cannot accidentally be overwritten
  — but the *shared* `auto_*.gdata` can be. Authors who hand-edit
  the auto-generated files (as people do) get bitten.
  *Mitigation*: the pre-existing risk now has a new failure mode
  under overlays: if an author edits a *per-platform* version of
  `auto_*.gdata` to hand-tune CPC tile metadata, then later reruns
  mapgen (which rewrites only the *shared* version), the shared
  changes will be silently overridden by the platform overlay at
  copy time — confusing to debug. Document the convention in
  `doc/MAPGEN.md` that hand-edits to tile metadata belong in
  overlays (and that the convention is "re-run mapgen, then
  inspect overlay deltas, not the other way around").

- **Risk: dataset / banking arithmetic changes when CPC byte
  layouts produce assets of different sizes than ZX.**
  CPC mode-0 pixels are 4 bpp (twice the bytes of ZX); mode 1
  is 2 bpp (same size as ZX). Sprite + BTile data is what gets
  paged into datasets, so the per-dataset capacity calculation
  (`DATASET_MAXSIZE`, `Makefile.common:50`) may need to be
  re-thought for CPC.
  *Mitigation*: defer to `banking.md`. The cpctelera subprocess
  in Phase A5 produces the right bytes; the byte budget is a
  separate concern.

- **Risk: the file-level shadow semantics are too coarse — authors
  end up duplicating BTile pixel data they didn't want to
  duplicate.**
  This is the cost of rejecting key-level merging.
  *Mitigation*: monitor during execution. If the duplication
  cost becomes painful, add a `BEGIN_PLATFORM` syntax extension
  (§2.3 deferred extension) — but only once we have real evidence.

- **Risk: `datagen.pl` is monolithic (4400 lines) and a
  `$platform`-driven seam may proliferate `if ($platform eq …)`
  branches throughout.**
  Threading the parameter everywhere risks cosmetic damage to a
  tool that is already hard to navigate.
  *Mitigation*: concentrate platform-coupled logic in **one
  place**: the per-platform dispatcher introduced in Phase A3.
  Inside `datagen.pl` itself, the platform branch should be
  limited to (a) the `PLATFORM` parsing in GAME_CONFIG, (b) the
  dispatcher's ZX-vs-CPC routing decision, and (c) the
  sprite-engine / gfx-backend choice. Everything ZX-specific
  stays inside `RAGE::PNGFileUtils` (unchanged); everything
  CPC-specific stays inside `tools/cpc_asset_convert.pl`. Resist
  the temptation to scatter `if` branches across the 4400 lines.

- **Risk: existing external games (not in this repo) use
  `ZX_TARGET` and will need a manual edit.**
  The deprecation pass (A1-2) and alias (A1-4) cushion this, but
  eventually A7-1 removes the alias.
  *Mitigation*: A7-1 emits a clear error message pointing at the
  migration. Communicate via `ROADMAP.md` and release notes.

---

## 6. Open Questions

All 8 questions raised during the initial drafting were resolved
during the first user review (2026-05-23). The questions and their
resolutions are preserved below for the historical record; the
plan body has been updated accordingly.

1. **Screen dimensions: per-platform or parametrised?**
   ZX = 32×24 cells. CPC mode-1 = 40×25 cells. mapgen already
   takes `--screen-cols / --screen-rows` (`tools/mapgen.pl:62-63`)
   so the *tool* is parametric, but in practice all current games
   are authored at 32×24.
   **Decision (2026-05-23): per-platform `GAME_AREA`.** A new
   `GAME_AREA_<PLATFORM>` directive in `BEGIN_GAME_CONFIG` lets
   authors declare different game-area rectangles per platform;
   the base `GAME_AREA` remains the implicit default for platforms
   without a suffixed override. See §2.3 for the syntax.

2. **Whether the CPC build needs a synthesised per-BTile colour
   token at all.**
   Today ZX emits `INK_x | PAPER_y | BRIGHT` strings into
   `uint8_t … = { … }` arrays that the engine consumes. CPC has
   no attribute byte: cpctelera-generated pixel data already
   carries colour, and the palette is global.
   **Decision (2026-05-23): skip on CPC; parameterise the engine
   to not need it.** The CPC build emits no per-BTile colour
   token; gfx.md generalises the HAL so engine code does not
   require one on platforms where it has no meaning. Hotzone
   highlighting and any other "drop a colour annotation on a
   cell" effect are gfx_*-API extension points to be designed
   in `gfx.md`, not asset-pipeline synthesised tokens.

3. **Default CPC colour mode: mode 0 (160×200, 16 colours) or
   mode 1 (320×200, 4 colours)?**
   **Decision (2026-05-23): Mode 1.** Closer to ZX resolution
   and cell grid; mode 0 deferred to per-game opt-in via
   `cpct_img2tileset --mode 0` in the wrapper.

4. **Should we support a per-platform `game_src/<platform>/` overlay
   of custom C code too?**
   **Decision (2026-05-23): yes, supported.** The mechanism is
   identical to the `game_data/` overlay (recursive `cp -r` in
   `make config`, file-level shadow). Implemented as part of
   Phase A2's overlay-copy step.

5. **Palette table: hard-coded RGB tuples or external `.gpl` file?**
   **Decision (2026-05-23): extend the tooling to accept an
   explicit CPC palette.** A new `CPC_PALETTE` directive in
   `BEGIN_GAME_CONFIG` lets authors specify a palette per game;
   the `tools/cpc_asset_convert.pl` wrapper forwards it to
   `cpct_img2tileset --palette`. When unset, the standard CPC
   firmware palette is used. See §2.3 and Phase A5-1.

6. **Backward-compat policy for the `patches/flow/` directory in
   the Makefile.**
   Today `Makefile.common:182` globs `patches/flow/*.gdata`,
   which contain `BEGIN_RULE … END_RULE` blocks that get appended
   to the global rule table.
   **Decision (2026-05-23): leave the existing `patches/`
   mechanism (both `patches/map/` and `patches/flow/`) exactly
   as it is.** It exists for the case where mapgen automatically
   emits screens and rules and the author wants to customise them
   afterwards — that use case is preserved. The new addition is
   that `<platform>/game_data/patches/{map,flow}/` is also
   transported via the overlay copy, giving platform-specific
   patches. Implementation: Phase A6.

7. **`PNG_DATA FILE=…` paths.**
   Today PNG paths are *relative to the repository top*
   (`doc/DATAGEN.md:88-89`), but the per-platform overlay copy
   lands the right per-platform PNG at
   `build/game_data/png/foo.png`.
   **Decision (2026-05-23): fix datagen invocation to run with
   `cwd = build/`** so `PNG_DATA FILE=game_data/png/foo.png`
   resolves to the overlay-copied file under `build/`. The
   Makefile and `doc/DATAGEN.md` are updated as part of Phase A1.

8. **CPC SOUND ID mapping.**
   ZX `Game.gdata` declares `SOUND ENEMY_KILLED=BEEPFX_HIT_3`,
   etc. CPC needs different mappings.
   **Decision (2026-05-23): add a per-platform `SOUND_CPC`
   directive (and, by symmetry, a `SOUND_<PLATFORM>` family) in
   `BEGIN_GAME_CONFIG`.** Both forms coexist in shared
   `Game.gdata`; `datagen.pl` selects based on the active
   platform. A general `SOUND_MAP` mechanism (owned by `audio.md`
   AU6) remains a longer-term refactor option but is explicitly
   deferred. See §2.3.

---

*End of assets.md.*
