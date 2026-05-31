# CPC Asset Wrapper ↔ datagen Contract

Phase A5-4 documentation.

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
    <absolute-path-to-png>
```

### Invocation modes

| Mode           | Used for            | Extra flag   |
|----------------|---------------------|--------------|
| `tileset`      | BTile `PNG_DATA`    | (none)       |
| `spritesheet`  | Sprite `PNG_DATA`   | `--mask`     |

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

`CPC_PALETTE` from `Game.gdata` (comma-separated firmware colour numbers) is
forwarded to `--palette-fw`.  When absent, the wrapper uses its built-in
default (`mode 1: 1,24,20,6`).  For real games, `CPC_PALETTE` MUST be
specified; the default is a generic fallback only.

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
| `cpc_asset_<base>_NN`            | `const u8[W * H]`             | Pixel bytes for tile NN        |
| `CPC_ASSET_<BASE>_NN_W`          | `#define`                     | Tile width in bytes            |
| `CPC_ASSET_<BASE>_NN_H`          | `#define`                     | Tile height in bytes           |

- `N` indexes into the tileset (0-based).
- Tile indices use as many decimal digits as needed (minimum 2: `_00`, `_01`,
  …, `_09`, `_10`, …, `_99`, `_100`, …).
- `W` and `H` are the byte dimensions: for mode-1 8×8 pixels, `W=2`, `H=8`
  (2 bytes × 8 rows = 16 bytes/tile).

### How datagen consumes the tileset array

`datagen.pl` generates `btile_<name>_frame_<f>_tiles[]` arrays that reference
the tileset pointer array:

```c
// Emitted by datagen.pl for a 1×1 BTile (ROWS=1, COLS=1, FRAMES=1):
#include "cpc/btile.h"
uint8_t *btile_PngBtile_frame_0_tiles[1] = {
    (uint8_t*)cpc_asset_btile_tileset[0]
};
```

For a 2×3 BTile (rows=2, cols=3), frame 0 references tileset entries 0..5;
frame 1 (if animated) references entries 6..11; and so on.

This indirection avoids hardcoding `cpct_img2tileset`'s index-numbering format
in datagen.

---

## §4. MONO vs FULL-COLOR dispatch

Controlled by `COLOR MODE=MONO|FULL` in `Game.gdata`.

| Mode        | BTile dispatch                              | Sprite dispatch                    |
|-------------|---------------------------------------------|------------------------------------|
| MONO        | ZX path (1bpp UDG bytes, shared with ZX)    | cpctelera (2bpp pre-baked, §5.9)   |
| FULL-COLOR  | cpctelera via `_cpc_invoke_tileset_converter`| cpctelera via same                |

Implementation: `dispatch_png_asset_handling` in `datagen.pl` checks
`$game_config->{'color'}{'mode'}` and routes accordingly.  See the function
comment and `tools/datagen.pl` ~line 1560 for the dispatch code.

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
