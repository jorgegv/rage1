# CPC Asset Wrapper ↔ datagen Contract

Phase A5-4 documentation.

> # ⚠ RETIRED 2026-06-06 (Phase 4J R10)
> The `cpct_img2tileset` host converter, its `tools/cpc_asset_convert.pl`
> wrapper, and the `external/cpctelera` submodule it depended on were **all
> removed in R10**, together with the interim `gfx_cpctel` backend. CPC asset
> conversion is now done **in-process** by datagen's `RAGE::AssetBackend`
> (CPC Mode-1), needing no external host tool. This document is retained only
> as a historical record of the removed wrapper↔datagen contract.

## Overview

For CPC platforms, RAGE1's asset pipeline shells out to cpctelera's
`cpct_img2tileset` tool via a thin Perl wrapper (`tools/cpc_asset_convert.pl`).
This document records the exact interface between `datagen.pl` and the wrapper,
the output paths, and how cpctelera's variable-naming conventions feed into
`build/generated/cpc/`.

See also `doc/multiplatform-plan/README.md §5.1` and
`doc/multiplatform-plan/assets.md Phase A5` for the architectural rationale.

---

## §1. Wrapper invocation by datagen

`datagen.pl` calls the wrapper from `_cpc_invoke_tileset_converter` (around
line 1675) via Perl's `system( @cmd )`.  The wrapper is always invoked as:

```
perl <repo>/tools/cpc_asset_convert.pl \
    --mode   <tileset|spritesheet>     \
    --cpc-mode 1                       \
    --tile-w 8                         \
    --tile-h 8                         \
    --basename cpc_asset_<png_basename> \
    --output  <build/generated/cpc/<png_basename>> \
    [--mask]                           \
    [--palette-fw <n,n,n,...>]         \
    <absolute-path-to-CROPPED-temp-png>
```

### PNG crop region (review fix #2)

`cpct_img2tileset` / `img2cpc` do **not** crop — they convert the *whole* PNG
sheet.  The ZX path honours the `PNG_DATA XPOS=.. YPOS=.. WIDTH=.. HEIGHT=..`
crop region (via `RAGE::PNGFileUtils`); the CPC path must too.

Therefore `datagen.pl` (`_cpc_crop_png_region`, using GD) **pre-extracts** the
`WIDTH×HEIGHT` region at `(XPOS,YPOS)` from the source PNG into a temporary PNG
and feeds *that* temp file to the wrapper (the last positional argument above).
The temp file is deleted after conversion.  So a `ROWS=1 COLS=1` BTile with
`WIDTH=8 HEIGHT=8` yields exactly **one** tile (the requested 8×8 region), not
the full sheet's worth of tiles.

The generated C identifiers are still derived from the *original* PNG basename
(not the temp file name), so they remain stable and meaningful.

### Invocation modes

| Mode           | Used for            | Extra flag   |
|----------------|---------------------|--------------|
| `tileset`      | BTile `PNG_DATA` (full-colour) | (none)        |
| `spritesheet`  | Sprite `PNG_DATA` (full-colour AND mono) | `--mask` |

### Fixed arguments (Phase A5)

| Argument       | Value          | Rationale                                     |
|----------------|----------------|-----------------------------------------------|
| `--cpc-mode`   | `1`            | Mode 1 (4 colours, 160×200) is the default    |
| `--tile-w`     | `8`            | One RAGE1 tile cell = 8 pixels wide           |
| `--tile-h`     | `8`            | One RAGE1 tile cell = 8 pixels tall           |

### Basename convention

`--basename` is `cpc_asset_<png_basename>` where `<png_basename>` is the
PNG filename without extension.  Examples:

| PNG path                       | basename             |
|--------------------------------|----------------------|
| `game_data/png/btile.png`      | `cpc_asset_btile`    |
| `game_data/png/hero_walk.png`  | `cpc_asset_hero_walk`|

This prefix ensures generated C identifiers don't collide with game-side code
and are easily grep-able.

### Palette

The `--palette-fw` value is resolved with this precedence (in
`_cpc_invoke_tileset_converter`):

1. **Per-call override** — mono sprites pass the resolved mono pen pair
   (§5.10; see §4) via `$opts->{palette_override}`.
2. **`CPC_PALETTE`** from `Game.gdata` (comma-separated firmware colour
   numbers) — the authoritative source for full-colour assets.
3. **Wrapper built-in default** (`mode 1: 1,24,20,6`) when neither is set.

For full-colour games, `CPC_PALETTE` MUST be specified; the built-in default
is a generic fallback only.

---

## §2. Output paths and file naming

Given `--output build/generated/cpc/<stem>`, the wrapper produces:

| File                              | Contents                                  |
|-----------------------------------|-------------------------------------------|
| `build/generated/cpc/<stem>.c`    | Mode-1 pixel byte arrays + tileset array  |
| `build/generated/cpc/<stem>.h`    | `extern` declarations, `#define` constants|

The stem equals `<png_basename>` (e.g., `btile` for `btile.png`).

The `build/generated/cpc/` directory is created by the wrapper (via
`File::Path::make_path`) on first use.

### Reproducibility

Img2CPC derives its `.h` include guard and the `.c` `#include` from the
machine-absolute output path.  The wrapper rewrites both to a deterministic,
basename-only form so output is reproducible across build directories:

```c
// header: deterministic guard
#ifndef __CPC_ASSET_BTILE_H_
#define __CPC_ASSET_BTILE_H_
...
#endif

// source: relative include
#include "btile.h"
```

---

## §3. Generated C naming conventions (cpctelera output)

cpctelera's `cpct_img2tileset` (via Img2CPC) produces the following identifiers
given `--basename cpc_asset_<base>`:

| Identifier                       | Type                          | Description                    |
|----------------------------------|-------------------------------|--------------------------------|
| `cpc_asset_<base>_tileset[N]`    | `u8 * const`                  | Pointer array, 1 entry per tile|
| `cpc_asset_<base>` (1 tile) /<br>`cpc_asset_<base>_NN` (≥2 tiles) | `const u8[W * H]` | Pixel bytes for tile NN |
| `CPC_ASSET_<BASE>[_NN]_W`        | `#define`                     | Tile width in bytes            |
| `CPC_ASSET_<BASE>[_NN]_H`        | `#define`                     | Tile height in bytes           |

- `N` indexes into the tileset (0-based).
- **Single-tile output omits the numeric suffix**: a converted region yielding
  exactly one tile is named `cpc_asset_<base>` (no `_00`); multi-tile output uses
  `_00`, `_01`, … with as many digits as needed.  Because the post-crop region
  (review fix #2) is sized to exactly the requested `WIDTH×HEIGHT`, a 1×1 BTile
  produces a single unsuffixed tile.
- `W` and `H` are the byte dimensions: for mode-1 8×8 pixels, `W=2`, `H=8`
  (2 bytes × 8 rows = 16 bytes/tile).

### How datagen consumes the tileset array

`datagen.pl` references the `_tileset[]` **pointer array** (NOT the individual
tile symbols) so it never has to reproduce cpctelera's per-tile naming/suffix
rule.  It generates `btile_<name>_frame_<f>_tiles[]` arrays:

```c
// Emitted by datagen.pl for a 1×1 BTile (ROWS=1, COLS=1, FRAMES=1):
#include "cpc/btile.h"
uint8_t *btile_PngBtile_frame_0_tiles[1] = {
    (uint8_t*)cpc_asset_btile_tileset[0]
};
```

For a 2×3 BTile (rows=2, cols=3), frame 0 references tileset entries 0..5;
frame 1 (if animated) references entries 6..11; and so on.

Sprites likewise reference the `_tileset[]` array (one entry per frame):

```c
// Emitted by datagen.pl for an N-frame extern Sprite:
#include "cpc/<base>.h"
uint8_t *sprite_<name>_frames[N] = {
    (uint8_t*)cpc_asset_<base>_tileset[0],
    ...
};
```

This indirection avoids hardcoding `cpct_img2tileset`'s index-numbering format
in datagen.

---

## §4. MONO vs FULL-COLOR dispatch

Controlled by `COLOR MODE=MONO|FULL` in `Game.gdata`.  The dispatch is
**asset-kind-specific** — BTiles and sprites diverge under MONO (README §5.9):

| Mode        | BTile dispatch                                   | Sprite dispatch                                  |
|-------------|--------------------------------------------------|--------------------------------------------------|
| MONO        | **ZX path** — shared 1bpp UDG bytes, byte-identical to ZX (cpct_img2tileset SKIPPED) | **cpctelera** — 2bpp pre-baked via `--mode spritesheet --mask`, palette = resolved mono pen pair (§5.10) |
| FULL-COLOR  | cpctelera via `_cpc_invoke_tileset_converter` (tileset mode) | cpctelera (spritesheet mode), palette = `CPC_PALETTE` |

Implementation:

- `dispatch_png_asset_handling` (`tools/datagen.pl`) checks
  `$game_config->{'color'}{'mode'}` and routes to `_cpc_mono_dispatch`
  (MONO) or `_cpc_fullcolor_dispatch` (FULL-COLOR).
- `_cpc_mono_dispatch` distinguishes BTile vs sprite by the terminal function
  name: `png_to_pixels_and_attrs` ⇒ BTile (replays the ZX pipeline lazily on
  the source path, returning ZX 1bpp data); `pick_pixel_data_by_color_from_png`
  ⇒ sprite (invokes the converter).  The shared entry points (`load_png_file`,
  `map_png_colors_to_zx_colors`, the `png_*mirror`/`png_rotate` transforms) are
  deferred onto a lightweight CPC PNG object so the terminal function can decide.

### Mono pen pair → palette resolution (§5.10)

For mono sprites, `_cpc_mono_pen_palette` derives the 4-entry mode-1
`--palette-fw` from the game's `gamearea_attr`:

- pen 0 = `gamearea_attr` **PAPER** (background) colour → CPC firmware number
- pen 1 = `gamearea_attr` **INK** (foreground) colour → CPC firmware number
- pens 2–3 = `0` (black, unused)

Colour-name → CPC firmware-number uses the canonical README §5.10 table
(`BLACK 0, BLUE 1/2, RED 3/6, MAGENTA 4/8, GREEN 9/18, CYAN 10/20, YELLOW
12/24, WHITE 13/26` for normal/BRIGHT), honouring any per-game
`CPC_COLOR_MAP` override.  An explicit `CPC_PALETTE` directive, if present,
overrides the auto-derived palette outright (it is the authoritative source).

Example: `GAMEAREA_ATTR=INK_YELLOW|PAPER_BLUE` → palette `1,12,0,0`
(pen0=BLUE=1, pen1=YELLOW=12).

---

## §5. Platform-deviation note (A5-3)

Phase A5-3 specifies `PLATFORM cpc6128` for the manual test, but `cpc6128`
(the banked CPC build) does not exist until Phase T3.  The A5-3 test game
uses `PLATFORM cpc464` (cpc-flat) instead.  The A5-2 dispatch is platform-
family-agnostic (`/^cpc/` regex), so the implementation works for both.

---

## §6. A5-5 loading-screen path — deferred

A5-5 would add a `tools/png2cpcscr.pl` or a cpct_img2tileset screen-mode
invocation for CPC loading screens.  This is deferred from Phase A5:

- cpctelera's `cpct_img2tileset` does not natively produce a raw CPC `.scr`
  (6144-byte screen buffer); its output format is always C source.
- A separate `Img2CPC` invocation with `-m screen` produces mode-1 pixel data,
  but packaging it as a 17 KB CPC `.scr` file requires additional tooling.
- The CPC engine (G8) is not yet at a stage where a loading screen can be
  tested end-to-end.

Plan for A5-5: add `tools/png2cpcscr.pl` wrapping `Img2CPC --m 1 --screen`
alongside the existing `tools/png2scr.pl` and wire it into `Makefile-cpc-flat`.
Gate on the CPC engine landing (Phase G8).
