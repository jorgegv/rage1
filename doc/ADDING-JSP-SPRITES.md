# Adding JSP as a Second Sprite Engine Backend for RAGE1

## Table of Contents

- [Table of Contents](#table-of-contents)
- [1. Overview and Strategy](#1-overview-and-strategy)
- [2. Library Comparison Summary](#2-library-comparison-summary)
- [3. Phase 1 — JSP Enhancements](#3-phase-1--jsp-enhancements)
  - [3.1 Sprite color / attribute management](#31-sprite-color--attribute-management)
  - [3.2 Sprite data format alignment with SP1](#32-sprite-data-format-alignment-with-sp1)
  - [3.3 Dynamic sprite allocation (pool)](#33-dynamic-sprite-allocation-pool)
  - [3.4 Safe off-screen parking (`jsp_sprite_park`)](#34-safe-off-screen-parking-jsp_sprite_park)
  - [3.5 Frame-based sprite movement](#35-frame-based-sprite-movement)
  - [3.6 Cell-coordinate sprite movement](#36-cell-coordinate-sprite-movement)
  - [3.7 Clipping rectangle support](#37-clipping-rectangle-support)
  - [3.8 Tile registration and 1-byte tile IDs](#38-tile-registration-and-1-byte-tile-ids)
  - [3.9 Rectangle clear](#39-rectangle-clear)
  - [3.10 Rectangle invalidation](#310-rectangle-invalidation)
  - [3.11 Text printing](#311-text-printing)
  - [3.12 Phase 1 summary: new JSP public API](#312-phase-1-summary-new-jsp-public-api)
- [4. Phase 2 — RAGE1 `gfx_jsp.h` Mapping](#4-phase-2--rage1-gfx_jsph-mapping)
- [5. Phase 3 — RAGE1 Engine Changes](#5-phase-3--rage1-engine-changes)
  - [5.1 `gfx.h` additions](#51-gfxh-additions)
  - [5.2 `datagen.pl` changes](#52-datagenpl-changes)
  - [5.3 Memory map](#53-memory-map)
  - [5.4 Build system](#54-build-system)
- [6. Risks and Open Questions](#6-risks-and-open-questions)
- [7. Complete Task List](#7-complete-task-list)
  - [Phase 1 — JSP enhancements (changes in the JSP repository)](#phase-1--jsp-enhancements-changes-in-the-jsp-repository)
  - [Phase 2 — RAGE1 mapping layer (changes in the RAGE1 repository)](#phase-2--rage1-mapping-layer-changes-in-the-rage1-repository)
  - [Phase 3 — RAGE1 toolchain and build changes](#phase-3--rage1-toolchain-and-build-changes)
  - [Phase 4 — Integration testing](#phase-4--integration-testing)
- [8. Appendix: Full API Mapping Reference](#8-appendix-full-api-mapping-reference)
- [9. Progress Tracking](#9-progress-tracking)
  - [Phase 1 — JSP enhancements (JSP repository)](#phase-1--jsp-enhancements-jsp-repository)
  - [Phase 2 — RAGE1 mapping layer (RAGE1 repository)](#phase-2--rage1-mapping-layer-rage1-repository)
  - [Phase 3 — RAGE1 toolchain and build changes](#phase-3--rage1-toolchain-and-build-changes-1)
  - [Phase 4 — Integration testing](#phase-4--integration-testing-1)
- [Plan execution constraints](#plan-execution-constraints)

---

## 1. Overview and Strategy

The goal is to add JSP as an optional sprite engine backend for RAGE1, selectable at
build time as an alternative to SP1. The primary benefit is memory: JSP uses ~6.1 KB of
fixed overhead versus SP1's ~13.6 KB, freeing ~7.5 KB in 48K mode (approximately 17%
more program space).

**Strategy: fix the library first, then integrate.**

RAGE1 already has a clean gfx abstraction layer (`gfx.h` / `gfx_sp1.h`). The natural
approach would be to write a thick `gfx_jsp.h` adapter that fills every gap between JSP
and SP1. However, many of those gaps represent genuinely missing functionality in JSP
(color management, text printing, tile IDs, etc.) that any serious caller would need.
Adding that logic to the adapter layer means duplicating it wherever JSP is used, and
makes the adapter brittle and hard to maintain.

The better approach is:

- **Phase 1**: Add the missing functionality directly to JSP. After this phase, JSP covers
  every capability that RAGE1 needs from SP1. The two libraries are near-equivalent at the
  API level.

- **Phase 2**: Write `gfx_jsp.h` as a thin mapping layer — mostly direct macro aliases,
  with minimal adapter code. This is the same structure as `gfx_sp1.h`.

- **Phase 3**: Make the minimal changes to RAGE1 (datagen.pl, Makefiles, memory map) to
  wire the new backend into the build.

---

## 2. Library Comparison Summary

This section summarises the current state of each gfx API entry and what Phase 1 must add.

| gfx API                       | SP1 equivalent         | JSP current state       | Phase 1 action                             |
|-------------------------------|------------------------|-------------------------|--------------------------------------------|
| `gfx_init`                    | `sp1_Initialize`       | `jsp_init` (close)      | Thin wrapper; add border                   |
| `gfx_update`                  | `sp1_UpdateNow`        | `jsp_redraw`            | Direct alias — no change needed            |
| `gfx_invalidate(rect)`        | `sp1_Invalidate`       | Missing                 | Add `jsp_invalidate_rect`                  |
| `gfx_sprite_create`           | `sp1_CreateSpr`        | Missing (static only)   | Add pool alloc API                         |
| `gfx_sprite_destroy`          | `sp1_DeleteSpr`        | Missing                 | Add pool free API                          |
| `gfx_sprite_set_color`        | `sp1_IterateSprChar`   | Missing                 | Add color field + apply                    |
| `gfx_sprite_set_threshold`    | SP1 clipping threshold | N/A (no clip in JSP)    | Stub no-op                                 |
| `gfx_sprite_move_pixel`       | `sp1_MoveSprPix`       | Needs frame + clip args | Add `jsp_move_sprite_frame` + clip wrapper |
| `gfx_sprite_move_cell`        | `sp1_MoveSprAbs`       | Missing                 | Add `jsp_move_sprite_cell`                 |
| `gfx_sprite_get_row/col`      | struct fields          | Different fields        | Macros with `/8` conversion                |
| `gfx_sprite_get_width/height` | struct fields          | `cols`/`rows`           | Direct macro aliases                       |
| `gfx_tile_put`                | `sp1_PrintAtInv`       | Missing                 | Add `jsp_tile_put`                         |
| `gfx_tile_register`           | `sp1_TileEntry`        | Missing                 | Add `jsp_tile_register`                    |
| `gfx_clear_rect`              | `sp1_ClearRectInv`     | Missing                 | Add `jsp_clear_rect`                       |
| `gfx_print_set_pos`           | `sp1_SetPrintPos`      | Missing                 | Add print context + function               |
| `gfx_print_string`            | `sp1_PrintString`      | Missing                 | Add print function                         |

Additionally, two safety concerns must be addressed regardless of the API mapping:

- **Out-of-bounds parking**: SP1 clips sprites to a rect; parking at row 24 (`y=192`) is
  safe under SP1 because the clip rect excludes it. Under JSP, calling `jsp_move_sprite`
  with `y=192` accesses `jsp_drt[768]` and beyond — one past the end of the 768-entry
  table — corrupting memory. A safe `jsp_sprite_park` function is required.

- **Sprite graphic data format**: SP1 requires `rows+1` cells per column in the frame
  data; JSP requires `rows` cells. The formats are otherwise byte-identical.
  `datagen.pl` must generate the correct variant for each backend.

---

## 3. Phase 1 — JSP Enhancements

Each enhancement below describes the problem, explores the available options, and gives a
recommended design with the new public API it adds to JSP.

---

### 3.1 Sprite color / attribute management

**Problem**

SP1 stores per-cell colour attributes inside the sprite structure (`struct sp1_cs.attr`
and `attr_mask` per cell) and applies them to ZX Spectrum attribute memory at
`0x5800 + row*32 + col` during each `sp1_UpdateNow()`. RAGE1 sets hero and enemy colours
via `gfx_sprite_set_color(s, color)`.

JSP's draw and move functions never touch attribute memory. The library is pixel-only.
If sprite color is not applied, sprites will use whatever attribute the background tile
has — often wrong (incorrect INK/PAPER, no BRIGHT).

**Options**

**A. Add colour fields to `struct jsp_sprite_s` and apply in C wrapper functions.**
Add `uint8_t color` and `uint8_t color_mask` at offsets `+11` and `+12` (after the
existing `type_ptr` at `+9,+10`). The C-level wrappers `jsp_move_sprite_mask2` and
`jsp_draw_sprite_mask2` call `jsp_apply_sprite_color(sp)` after each draw, iterating the
`rows × cols` cells the sprite occupies and writing the appropriate attribute byte.

**B. Separate function, caller responsibility.**
Add only `jsp_apply_sprite_color(sp)`. Callers must call it explicitly after each move.
This is error-prone: if a caller forgets, colours drift. Not recommended.

**C. Apply colour inside assembly (`_jsp_draw_sprite`).**
Add attribute writes to the DRT update loop. Possible, but bloats the hot path assembly
and mixes pixel and attribute concerns. Not recommended.

**Recommended: Option A.**

New fields (appended to `struct jsp_sprite_s`, preserving all existing offsets +0..+10):

```c
uint8_t color;       // ofs: +11  ZX Spectrum attribute byte (INK|PAPER|BRIGHT)
uint8_t color_mask;  // ofs: +12  0xF8 = preserve paper/bright; 0x00 = full replace
```

New functions:

```c
// Set the colour applied to all sprite cells each frame.
void jsp_sprite_set_color( struct jsp_sprite_s *sp,
                           uint8_t color, uint8_t color_mask );

// Write color to attribute memory for cells at sprite's current position.
// Called automatically by move/draw wrappers; exposed for manual use if needed.
void jsp_apply_sprite_color( struct jsp_sprite_s *sp );
```

`jsp_apply_sprite_color` is called at the end of the C-level wrappers
`jsp_move_sprite_mask2`, `jsp_draw_sprite_mask2`, `jsp_move_sprite_load1`,
`jsp_draw_sprite_load1`. The raw `_jsp_move_sprite` / `_jsp_draw_sprite` assembly
functions remain unchanged.

```c
void jsp_apply_sprite_color( struct jsp_sprite_s *sp ) {
    if ( !sp->color ) return;
    uint8_t r0 = sp->ypos / 8;
    uint8_t c0 = sp->xpos / 8;
    for ( uint8_t r = r0; r < r0 + sp->rows; r++ )
        for ( uint8_t c = c0; c < c0 + sp->cols; c++ ) {
            volatile uint8_t *attr = (uint8_t *)(0x5800 + r * 32 + c);
            *attr = ( *attr & sp->color_mask ) | ( sp->color & ~sp->color_mask );
        }
}
```

**Attribute restoration when a sprite moves**

`jsp_apply_sprite_color` writes attributes for the NEW cell positions of the sprite. But
what restores the attributes at the OLD positions when the sprite moves away? JSP's
`_jsp_move_sprite` marks old cells dirty in the DTT, and `jsp_redraw` restores their
pixel data from the BTT. However, attribute memory (`0x5800`) is completely outside JSP's
DTT/DRT cycle — nothing currently restores the background attribute when a sprite leaves
a cell. The old cells would retain the sprite's colour indefinitely.

The fix is a **Background Attribute Table (BAT)** — a flat 768-byte array
(`uint8_t jsp_bat[]`, one entry per screen cell) storing the ground-truth attribute for
each cell, parallel to the BTT. Any operation that sets attributes also writes to the BAT:
- `jsp_init` fills the entire BAT with `default_attr` (see updated signature below).
- `jsp_tile_put(row, col, attr, tile)` writes `attr` to `jsp_bat[row*32+col]`.
- `jsp_clear_rect` with `JSP_RFLAG_COLOUR` writes `attr` to `jsp_bat` for all cells.

`jsp_redraw` is then updated to restore the BAT attribute alongside pixel data when
processing each dirty cell:

```c
// addition inside the dirty-cell processing loop in jsp_redraw:
*(uint8_t *)(0x5800 + row * 32 + col) = jsp_bat[row * 32 + col];
```

This is one extra memory write per dirty cell — negligible overhead.

`jsp_init` gains a `default_attr` parameter:
```c
void jsp_init( uint8_t *default_bg_tile, uint8_t default_attr );
```
`gfx_init(bg_attr, bg_char)` already carries both values, so the mapping is direct.

The BAT adds 768 bytes to JSP's fixed overhead (~6.1 KB -> ~6.9 KB, still well below
SP1's 13.6 KB). The memory map must accommodate it; it sits between the DTT and the
available program area without alignment constraints.

The sprite attribute lifecycle is now fully symmetric:
- **New position**: pixels drawn by `_jsp_draw_sprite`; attributes written by
  `jsp_apply_sprite_color`.
- **Old position**: pixels restored by `jsp_redraw` from BTT; attributes restored by
  `jsp_redraw` from BAT.

---

### 3.2 Sprite data format alignment with SP1

**Problem**

SP1 sprite graphic data has **`rows+1` cells per column** — the extra cell is allocated
so the drawing routine has room for pixel overflow when the sprite is at a non-zero
sub-cell Y offset. `datagen.pl` generates this format today.

JSP sprite graphic data has **`rows` cells per column**. The PDB's extra `rows+1` row
(which JSP allocates internally) absorbs the drawing overflow without needing it in the
source pixel data.

Both formats use the same per-cell byte layout: for MASK2, 16 bytes of interleaved
`(mask_byte, graphic_byte)` per pixel row, top-to-bottom. The only structural difference
is that SP1 appends one all-transparent extra cell per column.

**Options**

**A. `datagen.pl` generates separate output for SP1 and JSP.**
When building for JSP, omit the trailing zero-row per column. Per-cell content is
unchanged; only the column length changes from `(rows+1)*16` to `rows*16` bytes. Clean,
simple, requires no JSP code changes.

**B. Make JSP accept SP1-format data (`rows+1` cells per column).**
Add a flag or field to indicate extended pixel data. JSP reads `rows+1` cells but treats
only the first `rows` as visible, matching SP1's intent. Allows sharing one set of
generated data between SP1 and JSP builds. More complex, and the sharing benefit is small
since `datagen.pl` runs at every build anyway.

**Recommended: Option A.**

`datagen.pl` emits the correct column length based on the selected engine. No JSP assembly
changes are needed. The per-pixel authoring source data is unchanged.

---

### 3.3 Dynamic sprite allocation (pool)

**Problem**

SP1 allocates sprites dynamically from an internal heap (`sp1_CreateSpr`). RAGE1 calls
`gfx_sprite_create(rows, cols)` at runtime during map loading (hero, enemy types, bullets).

JSP has no dynamic allocation. All sprites must be statically defined with `DEFINE_SPRITE`
at compile time. There is no `malloc`, `free`, or pool management in the library.

**Options**

**A. Compile-time pool: user defines macros before including `jsp.h`.**
`JSP_SPRITE_POOL_SIZE`, `JSP_MAX_SPRITE_ROWS`, `JSP_MAX_SPRITE_COLS` are user-defined;
the library declares pool and PDB arrays internally. Simple, but requires recompiling JSP
when game parameters change.

**B. Runtime pool: user provides storage, library manages slot allocation.**
The user declares pool and PDB arrays (sized from `datagen.pl` constants) and registers
them with JSP via an init call. JSP adds `jsp_sprite_alloc` / `jsp_sprite_free`.
JSP stays stateless with respect to pool memory — no hidden arrays inside the library.

**C. Keep static-only; handle entirely in RAGE1's `gfx_jsp.c`.**
Moves pool management to the adapter layer. Violates the "fix the library" strategy and
duplicates logic for any future non-RAGE1 JSP user.

**Recommended: Option B.**

Respects JSP's "no hidden heap" philosophy and gives full control over memory layout to
the caller. RAGE1's `gfx_init` provides the storage; JSP manages allocation bookkeeping.

New API:

```c
// Provide storage for the sprite pool. Call once, before any jsp_sprite_alloc.
//   pool      : array of jsp_sprite_s[pool_size]
//   pdbs      : flat byte array of size pool_size*(max_rows+1)*(max_cols+1)*8
//   pool_size : number of sprite slots
//   max_rows  : maximum height in cells across all sprites that will be allocated
//   max_cols  : maximum width in cells across all sprites that will be allocated
void jsp_sprite_pool_init( struct jsp_sprite_s *pool, uint8_t *pdbs,
                           uint8_t pool_size,
                           uint8_t max_rows, uint8_t max_cols );

// Claim a slot from the pool. Returns NULL if pool is exhausted.
struct jsp_sprite_s *jsp_sprite_alloc( uint8_t rows, uint8_t cols );

// Return a slot to the pool.
void jsp_sprite_free( struct jsp_sprite_s *sp );
```

`jsp_sprite_alloc` initialises the struct fields (`rows`, `cols`, `pdbuf` pointing into
the PDB array at the correct stride), sets `type_ptr = JSP_TYPE_MASK2` as default, and
zeroes `color`, `color_mask`, and `flags`.

---

### 3.4 Safe off-screen parking (`jsp_sprite_park`)

**Problem**

RAGE1 parks inactive sprites by calling:
```c
gfx_sprite_move_cell( s, &full_screen, NULL, OFF_SCREEN_ROW, OFF_SCREEN_COLUMN );
```
where `OFF_SCREEN_ROW = 24`, `OFF_SCREEN_COLUMN = 0`.

Under SP1 the `full_screen` clip rect prevents rendering at row 24, so no memory is
accessed out of bounds.

Under JSP, `y = 24 * 8 = 192`. The drawing routine computes `start_row = 192 / 8 = 24`,
then accesses `jsp_drt[24*32 + 0] = jsp_drt[768]`. The DRT has exactly 768 entries
(indices 0–767). **This is an out-of-bounds write that silently corrupts memory.**

The same problem affects the "mark old position dirty" step in `_jsp_move_sprite`, which
would access `jsp_dtt` and `jsp_drt` at index 768+.

**Options**

**A. Add `jsp_sprite_park(sp)`: mark current cells dirty, set a `parked` flag, skip future draws.**
Add a `parked` bit to the existing `flags` bitfield (7 bits are currently unused).
`jsp_sprite_park` marks the sprite's current cells dirty (so the background is restored
on the next `jsp_redraw`), then sets `flags.parked = 1`. The `jsp_move_sprite_mask2`
wrapper checks this flag: if set, it calls `_jsp_draw_sprite` (which does not mark the
old position dirty) rather than `_jsp_move_sprite`, then clears the flag.

**B. Add bounds checking inside `_jsp_draw_sprite` assembly.**
Check `start_row >= 24` before the DRT update loop; return without drawing. Simple to
implement but slows the hot drawing path for every sprite on every frame.

**C. Document the constraint; require game code to avoid y=192.**
Not safe — existing RAGE1 engine code relies on the park-at-row-24 idiom.

**Recommended: Option A.**

New flag bit (no struct size change; `flags` byte has 7 unused bits):

```c
struct {
    int initialized : 1;   // bit 0 — existing
    int parked      : 1;   // bit 1 — new
} flags;                   // ofs: +4
```

New function:

```c
// Remove sprite from screen and mark it as inactive.
// The sprite's current cells are marked dirty so the background is restored.
// The sprite will not be drawn until the next jsp_move_sprite_* call.
void jsp_sprite_park( struct jsp_sprite_s *sp );
```

The C-level wrappers `jsp_move_sprite_mask2` / `jsp_move_sprite_load1` handle the flag:

```c
if ( sp->flags.parked ) {
    sp->flags.parked = 0;
    _jsp_draw_sprite( sp, xpos, ypos );   // draw only, no old-position marking
} else {
    _jsp_move_sprite( sp, xpos, ypos );   // mark old dirty + draw
}
```

---

### 3.5 Frame-based sprite movement

**Problem**

SP1's `sp1_MoveSprPix(s, clip, frame_ptr, x, y)` takes the animation frame pointer as an
argument on every call. RAGE1's `gfx_sprite_move_pixel(s, clip, fr, x, y)` passes `fr`
each frame, making animation a one-call operation.

JSP's `jsp_move_sprite(sp, x, y)` uses whatever is currently in `sp->pixels`. The caller
must set `sp->pixels = fr` before calling — a two-step sequence that is not safely
expressible as a simple single macro without a side effect on the struct.

**Options**

**A. Add `jsp_move_sprite_frame(sp, frame, x, y)` to JSP.**
Sets `sp->pixels = frame` and calls the move/draw path (with park-flag handling from §3.4
and color application from §3.1). One-step, safe, self-documenting.

**B. Handle in the RAGE1 gfx_jsp.h macro.**
```c
#define gfx_sprite_move_pixel(s,clip,fr,x,y) \
    do { (s)->pixels=(fr); jsp_move_sprite_mask2((s),(x),(y)); } while(0)
```
Works but exposes struct internals in the macro and ties `gfx_jsp.h` to knowing that
`pixels` is a field in `jsp_sprite_s`.

**Recommended: Option A.**

```c
// Move sprite to (xpos, ypos) using the given frame graphic.
// Type-specific variants (preferred for known type):
void jsp_move_sprite_mask2_frame( struct jsp_sprite_s *sp,
                                  uint8_t *frame,
                                  uint8_t xpos, uint8_t ypos );
void jsp_move_sprite_load1_frame( struct jsp_sprite_s *sp,
                                  uint8_t *frame,
                                  uint8_t xpos, uint8_t ypos );
// Generic dispatch via type_ptr:
void jsp_move_sprite_frame( struct jsp_sprite_s *sp,
                            uint8_t *frame,
                            uint8_t xpos, uint8_t ypos );
```

Each sets `sp->pixels = frame`, handles the parked flag (§3.4), calls the appropriate
assembly move/draw function, then calls `jsp_apply_sprite_color` if `sp->color` is set.

---

### 3.6 Cell-coordinate sprite movement

**Problem**

RAGE1 uses `gfx_sprite_move_cell(s, clip, fr, row, col)` for map-loading code that
positions sprites at cell boundaries. JSP has only pixel-coordinate movement.

**Options**

**A. Add `jsp_move_sprite_cell(sp, frame, row, col)` to JSP** — converts to pixels and calls frame-based move.

**B. Handle in the RAGE1 mapping macro** — trivial one-liner.

**Recommended: Option B.**

This is genuinely a one-expression mapping with no logic. It belongs in `gfx_jsp.h`:

```c
#define gfx_sprite_move_cell(s,clip,fr,r,c) \
    gfx_jsp_move_sprite_clipped((s),(clip),(fr),(c)*8,(r)*8)
```

The conversion `row → y = row*8`, `col → x = col*8` is exact and obvious.

---

### 3.7 Clipping rectangle support

**Problem**

SP1's move functions accept a clipping rectangle that restricts rendering to a region.
RAGE1 passes `&game_area` for all hero/enemy/bullet sprites to prevent them from drawing
over the HUD. Without clipping, a sprite at the bottom of the game area could draw one
pixel-row into the HUD area.

JSP has no clipping. Its drawing routines always access `rows+1` cells starting from the
computed cell position.

**Options**

**A. Full cell-level clipping inside `_jsp_draw_sprite` assembly.**
Before the DRT update loop (lines 432–502 of `jsp_sprite.asm`), skip cells outside the
clip rect. Requires passing the clip rect to the assembly function. Correct, but adds a
per-cell branch to the hot drawing path and grows code size noticeably.

**B. Soft clipping in a C wrapper: cull entirely if any part is out of bounds.**
Before calling `_jsp_move_sprite`, check if the sprite's bounding box is fully inside the
clip rect. If not (entirely outside or partially overlapping the boundary), call
`jsp_sprite_park` instead. The sprite disappears rather than being pixel-clipped.

**C. Rely on RAGE1 game logic to keep sprites within game_area.**
RAGE1's collision detection bounces sprites off wall tiles before they can exit the game
area. The clip rect in SP1 is a safety net, not the primary enforcement mechanism. If
sprites always stay in bounds (which they do in normal play), no clipping is needed.

**Analysis:**

Option A is the most correct but is the most costly. Option B handles the common case
(sprite fully inside game_area) correctly; at the boundary it culls rather than clips,
which is only visible if game data lacks a wall tile at the boundary. Option C relies on
existing logic that is already correct in all shipped games.

**Recommended: Option B, with a documented limitation.**

Add to JSP:

```c
// Returns 1 if the sprite's bounding box at (xpos, ypos) is fully within rect,
// 0 if partially or fully outside.
uint8_t jsp_sprite_in_rect( struct jsp_sprite_s *sp,
                            struct jsp_rect *rect,
                            uint8_t xpos, uint8_t ypos );
```

The `gfx_jsp.h` wrapper calls this before each move. If the sprite is outside the clip
rect, it calls `jsp_sprite_park`. This is four comparisons — negligible overhead.

Document the limitation: sprites partially crossing the game_area boundary are culled
entirely rather than pixel-clipped. This is only observable if game data has no wall
tile at the game area boundary, which is a data authoring error.

---

### 3.8 Tile registration and 1-byte tile IDs

**Problem**

SP1 supports two tile addressing modes in `sp1_PrintAtInv(row, col, attr, tile)`:
- `tile < 256`: 1-byte UDG index into SP1's internal tile array (registered via `sp1_TileEntry`)
- `tile >= 256`: Direct 16-bit pointer to 8-byte graphic data

RAGE1 uses both modes. `datagen.pl` emits `gfx_tile_register(idx, ptr)` for custom
charset tiles and direct pointer values (>= 256) for btile graphics.

JSP's `jsp_draw_background_tile(row, col, pix)` takes only a direct pointer. There is no
tile index table or `sp1_TileEntry` equivalent.

**Options**

**A. Add a 256-entry tile table to JSP.**
`static uint8_t *jsp_tile_table[256]` (512 bytes). `jsp_tile_register(idx, ptr)` stores
the pointer. `jsp_tile_put(row, col, attr, tile)` dispatches: `tile < 256` → lookup table,
`tile >= 256` → direct pointer. Also writes `attr` to attribute memory directly, since
`jsp_draw_background_tile` is pixel-only.

**B. Change `datagen.pl` to always emit direct pointers for JSP.**
Never emit 1-byte tile IDs; always use the graphic data pointer directly. Avoids the table
but requires `datagen.pl` to track graphic data pointer values at compile time.

**Recommended: Option A.**

This matches SP1's API surface exactly, making the mapping trivial. The 512-byte overhead
is tiny compared to the 7.7 KB saved by eliminating SP1's update array. `jsp_tile_put`
becomes the JSP equivalent of `sp1_PrintAtInv`.

New API:

```c
// Register 8-byte tile graphic at 1-byte index (equivalent to sp1_TileEntry).
void jsp_tile_register( uint8_t idx, uint8_t *gfx_ptr );

// Draw tile at (row, col) with colour attribute.
//   tile < 256  : look up via jsp_tile_register table
//   tile >= 256 : treat directly as 8-byte graphic pointer
// Writes attr to ZX Spectrum attribute memory 0x5800+row*32+col.
void jsp_tile_put( uint8_t row, uint8_t col, uint8_t attr, uint16_t tile );
```

`jsp_tile_put` calls `jsp_draw_background_tile` for pixels and writes `attr` to
`*(uint8_t *)(0x5800 + row * 32 + col)` for the colour.

---

### 3.9 Rectangle clear

**Problem**

SP1's `sp1_ClearRectInv(rect, attr, ch, flags)` clears a rectangular screen region,
optionally clearing tile graphics (`SP1_RFLAG_TILE`) and/or colour attributes
(`SP1_RFLAG_COLOUR`). RAGE1 uses this when loading a new screen and during HUD init.

JSP has no rectangle operation.

**Options**

**A. Add `jsp_clear_rect` to JSP** as a C function that loops over cells.

**B. Handle in RAGE1 `gfx_jsp.c`.** Works but puts generic logic in the adapter.

**Recommended: Option A.**

```c
// Flags (same values as SP1 for easy aliasing):
#define JSP_RFLAG_TILE     0x01
#define JSP_RFLAG_COLOUR   0x02

// Clear a rectangular region.
//   rect  : area to clear
//   attr  : colour attribute to fill (if JSP_RFLAG_COLOUR is set)
//   ch    : character code (0-127) for tile fill (if JSP_RFLAG_TILE is set)
//           ch == ' ' (32) or 0 → blank (all-zero) tile
//           other values        → ROM font tile at 0x3D00 + (ch-32)*8
//   flags : combination of JSP_RFLAG_TILE and JSP_RFLAG_COLOUR
void jsp_clear_rect( struct jsp_rect *rect, uint8_t attr,
                     uint8_t ch, uint8_t flags );
```

In the initial implementation, only `ch == ' '` (blank tile) needs to be supported since
RAGE1 only calls `gfx_clear_rect` with `ch = ' '`. ROM font lookup for other characters
can be added when needed. After Option C of §3.11 is implemented, `ch` can be resolved
directly through the tile table, unifying all character/tile lookup in one place.

This function is implemented in C for simplicity. If profiling shows it is a bottleneck
(e.g., large screens with frequent clears), it can be rewritten in Z80 assembly using the
same LDIR-based patterns already present in `jsp_util.asm`.

---

### 3.10 Rectangle invalidation

**Problem**

`gfx_invalidate(rect)` marks all cells in a rectangle as dirty. RAGE1 calls this once at
startup (full screen flush). JSP has per-cell marking (`jsp_dtt_mark_dirty`) but no
rectangle-level function.

**Options**

**A. Add `jsp_invalidate_rect` to JSP.** Simple loop over cells.

**B. Handle in RAGE1 macro.** Also trivial but belongs in the library.

**Recommended: Option A** — natural companion to `jsp_clear_rect`.

```c
// Mark all cells in the rectangle as dirty (will be redrawn on next jsp_redraw).
void jsp_invalidate_rect( struct jsp_rect *rect );
```

Like `jsp_clear_rect`, this is implemented in C for simplicity and can be moved to
assembly if profiling identifies it as a hot path.

---

### 3.11 Text printing

**Problem**

SP1 provides a text output subsystem (`sp1_SetPrintPos`, `sp1_PrintString`) with a print
context that tracks position, clipping rect, and colour attribute. RAGE1 uses this for
screen titles, lives display, and debug output.

JSP has no text output.

**Options**

**A. Add a print context and functions, using ROM font directly.**
Hard-code the ROM font lookup (`0x3D00 + (ch - 32) * 8`) inside `jsp_print_string` and
pass the resulting pointer to `jsp_tile_put`. Simple, but the font is fixed and cannot be
overridden per-character.

**B. Use a third-party font library.** Unnecessary complexity.

**C. Add a print context and functions, routing through the tile ID table from §3.8.**
Character codes 0–127 are valid tile IDs. `jsp_init` pre-populates tile table entries
32–127 with pointers to the corresponding Spectrum ROM font tiles
(`0x3D00 + (ch-32)*8`). `jsp_print_string` then calls
`jsp_tile_put(row, col, ctx->attr, ch)` for each character — the character code IS the
tile ID. This is exactly how SP1 handles its tile array (UDG entries 32–127 default to
the ROM charset). Callers can override individual characters at any time via
`jsp_tile_register(ch, custom_ptr)`, enabling custom fonts with zero additional API
surface.

**Recommended: Option C.**

This design unifies all tile/character lookup through a single table, matches SP1's
approach, and gives font customisation for free. The only cost is the ROM font
pre-initialisation in `jsp_init`, which is a one-time loop of 96 pointer assignments.

`jsp_init` (already gaining `default_attr` from §3.1) also initialises the tile table:

```c
// inside jsp_init(), after clearing the tile table:
for ( uint8_t ch = 32; ch < 128; ch++ )
    jsp_tile_table[ch] = (uint8_t *)(0x3D00 + (uint16_t)(ch - 32) * 8);
```

New struct and macro:

```c
struct jsp_print_ctx {
    struct jsp_rect *clip;   // clipping area (NULL = no clipping)
    uint8_t          attr;   // text colour attribute byte
    uint8_t          row;    // current print row (cell coordinate)
    uint8_t          col;    // current print col (cell coordinate)
};

// Static initialiser matching GFX_PRINT_CTX_INIT(area, attr):
#define JSP_PRINT_CTX_INIT(rect, attr)   { &(rect), (attr), 0, 0 }
```

New functions:

```c
void jsp_print_set_pos( struct jsp_print_ctx *ctx,
                        uint8_t row, uint8_t col );

void jsp_print_string( struct jsp_print_ctx *ctx, const char *str );
```

`jsp_print_string` calls `jsp_tile_put(ctx->row, ctx->col, ctx->attr, ch)` for each
printable character (32–127), advancing `col` and wrapping at the clip rect boundary.
No ROM address arithmetic appears in `jsp_print_string` itself — that knowledge lives
entirely inside the tile table initialised by `jsp_init`.

Tiles drawn by `jsp_print_string` are marked dirty in the DTT (via `jsp_tile_put` ->
`jsp_draw_background_tile`). They become visible on the next `jsp_redraw()` call. For
immediate display (e.g., during map loading outside the main loop), call `jsp_redraw()`
explicitly after `jsp_print_string()`.

---


### 3.12 Phase 1 summary: new JSP public API

After Phase 1, the complete additions to `jsp.h` are:

**Struct additions** (all backward-compatible — appended at end or use spare bits):

```c
// In struct jsp_sprite_s, new fields appended:
uint8_t color;       // +11: ZX attr byte applied each frame (0 = no color management)
uint8_t color_mask;  // +12: mask: 0xF8 = preserve paper/bright; 0x00 = full replace

// In struct { ... } flags — new bit:
int parked : 1;      // bit 1: sprite is off-screen; skip old-position marking on next draw

// New struct:
struct jsp_print_ctx { ... };    // text print context
```

**New internal data tables:**
- `uint8_t jsp_bat[768]` — Background Attribute Table; one attribute byte per screen cell.
  Initialised to `default_attr` by `jsp_init`; updated by `jsp_tile_put` and
  `jsp_clear_rect`; read by `jsp_redraw` to restore attributes when cells are redrawn.
- `uint8_t *jsp_tile_table[256]` — Tile pointer table; entries 32–127 pre-filled with
  ROM font pointers by `jsp_init`; remaining entries NULL until set via `jsp_tile_register`.

**New functions:**

```c
// Color management
void jsp_sprite_set_color( struct jsp_sprite_s *sp, uint8_t color, uint8_t color_mask );
void jsp_apply_sprite_color( struct jsp_sprite_s *sp );

// Pool allocation
void jsp_sprite_pool_init( struct jsp_sprite_s *pool, uint8_t *pdbs,
                           uint8_t pool_size, uint8_t max_rows, uint8_t max_cols );
struct jsp_sprite_s *jsp_sprite_alloc( uint8_t rows, uint8_t cols );
void jsp_sprite_free( struct jsp_sprite_s *sp );

// Safe parking
void jsp_sprite_park( struct jsp_sprite_s *sp );

// Frame-based movement (with integrated park-flag + color handling)
void jsp_move_sprite_mask2_frame( struct jsp_sprite_s *sp, uint8_t *frame,
                                  uint8_t xpos, uint8_t ypos );
void jsp_move_sprite_load1_frame( struct jsp_sprite_s *sp, uint8_t *frame,
                                  uint8_t xpos, uint8_t ypos );
void jsp_move_sprite_frame( struct jsp_sprite_s *sp, uint8_t *frame,
                            uint8_t xpos, uint8_t ypos );

// Bounding-box check
uint8_t jsp_sprite_in_rect( struct jsp_sprite_s *sp,
                            struct jsp_rect *rect,
                            uint8_t xpos, uint8_t ypos );

// Tile table
void jsp_tile_register( uint8_t idx, uint8_t *gfx_ptr );
void jsp_tile_put( uint8_t row, uint8_t col, uint8_t attr, uint16_t tile );

// Rectangle operations
#define JSP_RFLAG_TILE   0x01
#define JSP_RFLAG_COLOUR 0x02
void jsp_clear_rect( struct jsp_rect *rect, uint8_t attr, uint8_t ch, uint8_t flags );
void jsp_invalidate_rect( struct jsp_rect *rect );

// Text printing
#define JSP_PRINT_CTX_INIT(rect, attr)  { &(rect), (attr), 0, 0 }
void jsp_print_set_pos( struct jsp_print_ctx *ctx, uint8_t row, uint8_t col );
void jsp_print_string( struct jsp_print_ctx *ctx, const char *str );
```

**Modified functions** (signature or behaviour changed):
- `jsp_init`: gains `default_attr` parameter → `void jsp_init(uint8_t *default_bg_tile, uint8_t default_attr)`. Pre-fills BAT with `default_attr`; pre-fills tile table entries 32–127 with ROM font pointers.
- `jsp_redraw`: restores BAT attribute for each dirty cell alongside pixel data.
- `jsp_tile_put`: writes `attr` to BAT for the cell alongside drawing the tile.
- `jsp_clear_rect`: writes `attr` to BAT for all cells when `JSP_RFLAG_COLOUR` is set.
- `jsp_move_sprite_mask2`, `jsp_draw_sprite_mask2`: call `jsp_apply_sprite_color`; handle `flags.parked`.
- `jsp_move_sprite_load1`, `jsp_draw_sprite_load1`: same.

**New constants:** `JSP_RFLAG_TILE`, `JSP_RFLAG_COLOUR`, `JSP_PRINT_CTX_INIT`

---

## 4. Phase 2 — RAGE1 `gfx_jsp.h` Mapping

After Phase 1, JSP has a near-complete equivalent for every SP1 function RAGE1 uses.
The mapping layer is thin — mostly direct macro aliases, exactly like `gfx_sp1.h`.

Create `engine/include/rage1/gfx_jsp.h`:

```c
#ifndef _GFX_JSP_H
#define _GFX_JSP_H

#include <jsp.h>

//--- Types ---
typedef struct jsp_sprite_s      gfx_sprite_t;
typedef struct jsp_rect          gfx_rect_t;
typedef struct jsp_print_ctx     gfx_print_ctx_t;

//--- Constants ---
#define GFX_CLEAR_TILE           JSP_RFLAG_TILE
#define GFX_CLEAR_COLOUR         JSP_RFLAG_COLOUR
#define GFX_PSS_INVALIDATE       0x00               // value unused in JSP backend
#define GFX_PRINT_CTX_INIT(a,at) JSP_PRINT_CTX_INIT((a),(at))

//--- Initialization ---
// gfx_init() is a real function defined in gfx_jsp.c
#define gfx_invalidate(rect)                 jsp_invalidate_rect(rect)
#define gfx_update()                         jsp_redraw()

//--- Sprite lifecycle ---
// gfx_sprite_create() real function in gfx_jsp.c
#define gfx_sprite_destroy(s)                jsp_sprite_free(s)
// gfx_sprite_set_color() real function in gfx_jsp.c
#define gfx_sprite_set_threshold(s,xt,yt)    /* no-op: JSP has no threshold concept */

//--- Sprite movement ---
#define gfx_sprite_move_pixel(s,clip,fr,x,y) \
    gfx_jsp_move_sprite_clipped((s),(clip),(fr),(x),(y))
#define gfx_sprite_move_cell(s,clip,fr,r,c) \
    gfx_jsp_move_sprite_clipped((s),(clip),(fr),(c)*8,(r)*8)

//--- Sprite query ---
#define gfx_sprite_get_row(s)                ((s)->ypos / 8)
#define gfx_sprite_get_col(s)                ((s)->xpos / 8)
#define gfx_sprite_get_width(s)              ((s)->cols)
#define gfx_sprite_get_height(s)             ((s)->rows)

//--- Tile drawing ---
#define gfx_tile_put(r,c,attr,tile)          jsp_tile_put((r),(c),(attr),(tile))
#define gfx_tile_register(idx,gfx)           jsp_tile_register((idx),(gfx))

//--- Rectangle operations ---
#define gfx_clear_rect(rect,attr,ch,flags)   jsp_clear_rect((rect),(attr),(ch),(flags))

//--- Text printing ---
#define gfx_print_set_pos(ctx,r,c)           jsp_print_set_pos((ctx),(r),(c))
#define gfx_print_string(ctx,str)            jsp_print_string((ctx),(str))

// Forward declaration for the clipping wrapper (defined in gfx_jsp.c)
void gfx_jsp_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                  uint8_t *frame, uint8_t x, uint8_t y );

#endif // _GFX_JSP_H
```

The only non-trivial entry is `gfx_sprite_move_pixel` / `gfx_sprite_move_cell`, which go
through `gfx_jsp_move_sprite_clipped`. This thin C function in `gfx_jsp.c` handles two
special cases that have no direct JSP counterpart:

1. **NULL frame** — RAGE1 passes `frame = NULL` when parking a sprite (`sprite_move_offscreen`).
   Under SP1 this is safe because SP1 accepts NULL as "keep current frame." Under JSP,
   `sp->pixels = NULL` would corrupt the drawing routine. Detect and call `jsp_sprite_park`.

2. **Soft clipping** — if a non-NULL clip rect is provided and the sprite is fully outside
   it, call `jsp_sprite_park`. If fully inside, move normally.

```c
#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP

void gfx_jsp_move_sprite_clipped(
        gfx_sprite_t *s, gfx_rect_t *clip,
        uint8_t *frame, uint8_t x, uint8_t y )
{
    if ( frame == NULL ) {
        jsp_sprite_park( s );
        return;
    }
    if ( clip && !jsp_sprite_in_rect( s, clip, x, y ) ) {
        jsp_sprite_park( s );
        return;
    }
    jsp_move_sprite_mask2_frame( s, frame, x, y );
}

#endif
```

The three real functions in `gfx_jsp.c` (analogous to `sp1engine.c` and `sprite.c`):

```c
#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP

// Pool storage — sized by datagen.pl constants (see Phase 3)
static struct jsp_sprite_s _sprite_pool[ GFX_JSP_MAX_SPRITES ];
static uint8_t _sprite_pdbs[
    GFX_JSP_MAX_SPRITES *
    (GFX_JSP_MAX_SPRITE_ROWS+1) * (GFX_JSP_MAX_SPRITE_COLS+1) * 8 ];

void gfx_init( uint8_t bg_attr, uint8_t bg_char ) {
    static const uint8_t blank[8] = {0,0,0,0,0,0,0,0};
    zx_border( INK_BLACK );
    jsp_init( (uint8_t *)blank );
    jsp_sprite_pool_init( _sprite_pool, _sprite_pdbs,
                          GFX_JSP_MAX_SPRITES,
                          GFX_JSP_MAX_SPRITE_ROWS,
                          GFX_JSP_MAX_SPRITE_COLS );
    gfx_invalidate( &full_screen );
    gfx_update();
}

gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
    gfx_sprite_t *s = jsp_sprite_alloc( rows, cols );
    DEBUG_ASSERT( s, PANIC_SPRITE_IS_NULL );
    return s;
}

void gfx_sprite_set_color( gfx_sprite_t *s, uint8_t color ) {
    // 0xF8 mask: preserve PAPER and BRIGHT bits, replace INK only
    // (matches SP1's attr_mask = 0xF8 used in sprite.c)
    jsp_sprite_set_color( s, color, 0xF8 );
}

#endif // BUILD_FEATURE_SPRITE_ENGINE_JSP
```

---

## 5. Phase 3 — RAGE1 Engine Changes

### 5.1 `gfx.h` additions

Add one `#ifdef` block after the existing SP1 block:

```c
#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP
    #include "rage1/gfx_jsp.h"
#endif
```

No other changes to `gfx.h` are needed.

---

### 5.2 `datagen.pl` changes

**a) New game config key: `sprite_engine`**

In `game_data/game_config/*.gdata`, add an optional key:
```
sprite_engine: jsp    # or: sp1 (default when absent)
```

**b) Feature flag emission in `features.h`**

When `sprite_engine: jsp`, emit:
```c
#define BUILD_FEATURE_SPRITE_ENGINE_JSP
```
instead of:
```c
#define BUILD_FEATURE_SPRITE_ENGINE_SP1
```

**c) Pool-sizing constants emission in `game_data.h`**

When `sprite_engine: jsp`, also emit:
```c
#define GFX_JSP_MAX_SPRITES       N    // 1(hero) + max_enemies_per_screen + max_bullets
#define GFX_JSP_MAX_SPRITE_ROWS   R    // max height in cells across all sprite definitions
#define GFX_JSP_MAX_SPRITE_COLS   C    // max width in cells across all sprite definitions
```

`datagen.pl` already computes `max_enemies_per_screen` and `max_bullets` for other
features. `GFX_JSP_MAX_SPRITE_ROWS` and `GFX_JSP_MAX_SPRITE_COLS` are the maxima across
all `sprite_height` / `sprite_width` fields in sprite `.gdata` files.

**d) Sprite graphic data format**

When `sprite_engine: jsp`, generate frame data with `rows` cells per column (not `rows+1`).
The per-cell content is unchanged. The emitted C array for each frame has `rows*cols*16`
bytes instead of `(rows+1)*cols*16` bytes.

**e) Makefile fragment**

Emit `build/generated/sprite_engine.mk` containing:
```makefile
BUILD_SPRITE_ENGINE = jsp   # or sp1
```
This allows Makefiles to select the correct memory map and library without parsing
`.gdata` files.

---

### 5.3 Memory map

JSP's data structures occupy the top of RAM at fixed addresses. The RAGE1 linker
configuration must be adjusted to avoid overlap.

**48K comparison:**

| Region            | SP1 layout               | JSP layout               |
|-------------------|--------------------------|--------------------------|
| Rotation tables   | `0xF200–0xFFFF` (3.5 KB) | `0xF200–0xFFFF` (same)   |
| SP1 tile array    | `0xF000–0xF1FF` (512 B)  | — (eliminated)           |
| SP1 update array  | `0xD200–0xEFFF` (7.7 KB) | — (eliminated)           |
| JSP BTT           | —                        | `0xEC00–0xF199` (1.5 KB) |
| JSP DRT           | —                        | `0xE600–0xEB99` (1.5 KB) |
| JSP DTT           | —                        | `0xE5A0–0xE5FF` (96 B)   |
| JSP FTT           | —                        | `0xE540–0xE59F` (96 B)   |
| JSP BAT           | —                        | `0xE240–0xE53F` (768 B)  |
| (unused)          | —                        | `0xE1E4-0xE23F` (92 B)   |
| JP <ISR> opcode   | `0xD1D1-0xD1D3`          | `0xE1E1-0xE1E3`          |
| (unused)          | `0xD101–0xD1D0`          | `0xE101–0xE1E0` (224 B)  |
| Interrupt vector  | `0xD000–0xD100` (257 B)  | `0xE000–0xE100` (257 B)  |
| Available program | `0x5D00–0xCFFF` (~29 KB) | `0x5D00–0xDFFF` (~33 KB) |

Notes on the JSP layout:
- **BTT/DRT/DTT/FTT/BAT** are fixed by the JSP library assembly and cannot be relocated.
  The lowest JSP-owned address is `0xE240` (start of BAT).
- **Interrupt vector** must be 256-byte aligned and placed entirely below `0xE240`.
  `0xE000` is the natural choice (mirrors SP1's `0xD000`, just 4 KB higher).
- JSP 48K gives RAGE1 ~33 KB of program space vs. SP1's ~29 KB — about 4 KB more.
- Holes marked "(unused)" may be used for the stack or scratch memory

**For 128K mode:**

The layout is identical but shifted down 16 KB:

| Region            | SP1 layout               | JSP layout               |
|-------------------|--------------------------|--------------------------|
| Rotation tables   | `0xF200–0xFFFF` (3.5 KB) | `0xB200–0xBFFF` (same)   |
| SP1 update array  | `0xD200–0xEFFF` (7.7 KB) | — (eliminated)           |
| SP1 tile array    | `0xF000–0xF1FF` (512 B)  | — (eliminated)           |
| JSP BTT           | —                        | `0xAC00–0xB199` (1.5 KB) |
| JSP DRT           | —                        | `0xA600–0xAB99` (1.5 KB) |
| JSP DTT           | —                        | `0xA5A0–0xA5FF` (96 B)   |
| JSP FTT           | —                        | `0xA540–0xA59F` (96 B)   |
| JSP BAT           | —                        | `0xA240–0xA53F` (768 B)  |
| (unused)          | —                        | `0xA1E4-0xA23F` (92 B)   |
| JP <ISR> opcode   | `0xD1D1-0xD1D3`          | `0xA1A1-0xA1A3`          |
| (unused)          | `0xD101–0xD1D0`          | `0xA101–0xA1A0` (160 B)  |
| Interrupt vector  | `0xD000–0xD100` (257 B)  | `0xA000–0xA100` (257 B)  |
| Available program | `0x5D00–0xCFFF` (~29 KB) | `0x5D00–0x9FFF` (~17 KB) |

See risk §6.1 for the 128K program size implications.

Files to update:
- `Makefile-48`: update `org`, `IVTABLE_BASE`, stack address.
- `Makefile-128`: same for 128K layout (JSP tables at `0xA240–0xBFFF`; program space
  becomes ~17 KB instead of ~29 KB — see risk §6.1).
- `etc/rage1-config.yml`: update `interrupt_vector_address` and related constants.

Guard all changes with `ifeq ($(BUILD_SPRITE_ENGINE),jsp)` so SP1 builds are unaffected.

---

### 5.4 Build system

In `Makefile.common`:

```makefile
# Include sprite engine selection (written by datagen.pl)
include $(BUILD_DIR)/generated/sprite_engine.mk

ifeq ($(BUILD_SPRITE_ENGINE),jsp)
    JSP_DIR      := $(RAGE1_DIR)/../../../jsp
    EXTRA_CFLAGS += -I$(JSP_DIR)/include
    EXTRA_OBJS   += $(JSP_DIR)/build/jsp.lib
    ENGINE_SRCS  += engine/src/gfx_jsp.c
endif
```

Add a `build-jsp` prerequisite that runs `$(MAKE) -C $(JSP_DIR)` before the RAGE1 compile
step. When building a 128K target, pass `-DSPECTRUM_128` to the JSP build:

```makefile
build-jsp:
    $(MAKE) -C $(JSP_DIR) $(if $(filter 128,$(ZX_TARGET)),CFLAGS=-DSPECTRUM_128,)
```

---

## 6. Risks and Open Questions

**1. JSP 128K program size regression.**
JSP in 128K mode places all tables (BTT/DRT/DTT/FTT/BAT) at `0xA240–0xBFFF`
(below the banked window at `0xC000`), leaving ~17 KB for the main binary versus ~29 KB
with SP1. Measure a representative 128K game's binary size before committing the 128K
memory map changes. The JSP advantage is strongest in 48K mode. Nevertheless, JSP data
structures leave the 0xC000 page completely free, which allows for easier banked code.

**2. `jsp_sprite_park` transition correctness.**
When a sprite transitions from parked back to active, `_jsp_draw_sprite` is called instead
of `_jsp_move_sprite`. Verify that if park and un-park happen within the same frame (two
calls before `jsp_redraw`), the old position cells are still properly marked dirty and
restored to background.

**3. JSP SMC and interrupt safety.**
JSP uses self-modifying code (SMC) for type dispatch and DTT operations. If an interrupt
fires mid-SMC-patch and the ISR also calls JSP functions, state corruption could occur.
RAGE1's ISR only increments a counter, so this conflict does not apply in practice.
Document the constraint for any future ISR changes.

**4. Soft clipping vs. pixel-level clipping.**
The recommended Option B for §3.7 culls sprites entirely at the game_area boundary.
Sprites partially crossing the boundary disappear rather than being clipped. If this
causes visual glitches during testing (e.g., an enemy appears to "teleport" at the edge
of the game area), implement full cell-level clipping (Option A from §3.7) as a follow-up.

**5. `jsp_print_string` / `jsp_redraw` ordering.**
`jsp_print_string` marks tiles dirty but does not call `jsp_redraw`. The RAGE1 main loop
calls `gfx_update()` at the end of each frame, which handles text drawn during the loop.
Text printed during map loading (outside the loop) needs an explicit `gfx_update()` call.
Verify with the map loading code path during integration testing.

**6. IY register usage.**
JSP documentation notes that the ZX Spectrum ROM interrupt routine uses IY. RAGE1 uses a
custom IM2 ISR, so this conflict does not apply. Confirm during 48K loader testing.

**7. `bg_attr` parameter of `gfx_init`.**
JSP's `jsp_init` takes a background tile pointer, not `bg_attr`. The JSP `gfx_init`
ignores the `bg_attr` parameter (passing it as a colour on the `zx_border` call instead).
Background colour attributes for the game area are set by `gfx_clear_rect` and
`gfx_tile_put` when the first screen is drawn, so no separate `bg_attr` initialisation
is needed. Confirm this causes no visible difference at startup.

---

## 7. Complete Task List

### Phase 1 — JSP enhancements (changes in the JSP repository)

| #     | Task                                                                                                                                                       | Effort       |
|-------|------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------|
| P1-0  | Add `uint8_t jsp_bat[768]` (BAT) to JSP data; update `jsp_init` signature (`default_attr`); update `jsp_redraw` to restore BAT attrs for dirty cells       | Small-Medium |
| P1-1  | Add `color`, `color_mask` fields (+11, +12) to `struct jsp_sprite_s`; add `parked` flag bit                                                                | Small        |
| P1-2  | Implement `jsp_sprite_set_color` and `jsp_apply_sprite_color` (C)                                                                                          | Small        |
| P1-3  | Update `jsp_move_sprite_mask2`, `jsp_draw_sprite_mask2`, LOAD1 variants: call `jsp_apply_sprite_color`; handle `flags.parked`                              | Small-Medium |
| P1-4  | Implement `jsp_sprite_park`                                                                                                                                | Small        |
| P1-5  | Implement `jsp_sprite_pool_init`, `jsp_sprite_alloc`, `jsp_sprite_free` (C)                                                                                | Medium       |
| P1-6  | Implement `jsp_move_sprite_mask2_frame`, `jsp_move_sprite_load1_frame`, `jsp_move_sprite_frame`                                                            | Small        |
| P1-7  | Implement `jsp_sprite_in_rect`                                                                                                                             | Small        |
| P1-8  | Implement `jsp_tile_register` and `jsp_tile_put` (tile table + attribute write + BAT update); pre-fill entries 32–127 with ROM font pointers in `jsp_init` | Small-Medium |
| P1-9  | Implement `jsp_clear_rect`                                                                                                                                 | Small        |
| P1-10 | Implement `jsp_invalidate_rect`                                                                                                                            | Small        |
| P1-11 | Implement `struct jsp_print_ctx`, `JSP_PRINT_CTX_INIT`, `jsp_print_set_pos`, `jsp_print_string` (routes through tile table — Option C)                     | Small-Medium |
| P1-12 | Update `jsp.h` with all new declarations, constants, and the updated struct                                                                                | Small        |
| P1-13 | Write JSP tests for new API (using JSP's existing `main.c` test framework)                                                                                 | Medium       |

### Phase 2 — RAGE1 mapping layer (changes in the RAGE1 repository)

| #    | Task                                                                                                                                | Effort       |
|------|-------------------------------------------------------------------------------------------------------------------------------------|--------------|
| P2-1 | Create `engine/include/rage1/gfx_jsp.h` (type aliases, constants, macro mappings)                                                   | Small        |
| P2-2 | Create `engine/src/gfx_jsp.c` (`gfx_init`, `gfx_sprite_create`, `gfx_sprite_set_color`, `gfx_jsp_move_sprite_clipped`, pool arrays) | Small-Medium |
| P2-3 | Add `#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP` block to `engine/include/rage1/gfx.h`                                                  | Trivial      |

### Phase 3 — RAGE1 toolchain and build changes

| #    | Task                                                                                           | Effort  |
|------|------------------------------------------------------------------------------------------------|---------|
| P3-1 | Add `sprite_engine` key parsing to `datagen.pl`; emit correct `BUILD_FEATURE_SPRITE_ENGINE_*`  | Small   |
| P3-2 | Add pool-sizing constant emission to `datagen.pl` (`GFX_JSP_MAX_SPRITES`, `_ROWS`, `_COLS`)    | Small   |
| P3-3 | Add JSP sprite frame data format to `datagen.pl` (JSP mode: `rows` cells/column, not `rows+1`) | Medium  |
| P3-4 | Emit `build/generated/sprite_engine.mk` from `datagen.pl`                                      | Trivial |
| P3-5 | Update `Makefile.common` (include sprite_engine.mk, JSP build, include path, `gfx_jsp.c`)      | Small   |
| P3-6 | Update `Makefile-48` with JSP memory map (guarded by `BUILD_SPRITE_ENGINE = jsp`)              | Medium  |
| P3-7 | Update `Makefile-128` with JSP 128K memory map                                                 | Medium  |
| P3-8 | Update `etc/rage1-config.yml` interrupt vector and stack addresses for JSP layout              | Small   |

### Phase 4 — Integration testing

| #    | Task                                                                              | Pass criteria |
|------|-----------------------------------------------------------------------------------|---------------|
| P4-1 | Build `games/minimal` with JSP; verify hero sprite, movement, screen              | Must pass     |
| P4-2 | Build a game with enemies; verify sprites, colors, animation frames               | Must pass     |
| P4-3 | Build a game with bullets; verify spawn, park, despawn                            | Must pass     |
| P4-4 | Verify text output (screen titles, lives display, debug area if enabled)          | Must pass     |
| P4-5 | `make all-test-builds` with SP1 as default — regression check                     | Must pass     |
| P4-6 | `make mem` for JSP 48K build; confirm no address overlap with JSP data structures | Must pass     |
| P4-7 | Run in FUSE emulator; no visual artifacts at game_area boundary                   | Should pass   |
| P4-8 | (Optional) Build a 128K game with JSP; measure binary size headroom               | Informational |

---

## 8. Appendix: Full API Mapping Reference

Complete mapping after Phase 1+2 are complete. All entries are direct aliases or thin
one-expression macros unless noted.

| gfx API                              | gfx_sp1.h (SP1)                 | gfx_jsp.h (JSP after Phase 1+2)            | Note                        |
|--------------------------------------|---------------------------------|--------------------------------------------|-----------------------------|
| `gfx_sprite_t`                       | `struct sp1_ss`                 | `struct jsp_sprite_s`                      | typedef                     |
| `gfx_rect_t`                         | `struct sp1_Rect`               | `struct jsp_rect`                          | typedef                     |
| `gfx_print_ctx_t`                    | `struct sp1_pss`                | `struct jsp_print_ctx`                     | typedef                     |
| `GFX_CLEAR_TILE`                     | `SP1_RFLAG_TILE`                | `JSP_RFLAG_TILE`                           | constant                    |
| `GFX_CLEAR_COLOUR`                   | `SP1_RFLAG_COLOUR`              | `JSP_RFLAG_COLOUR`                         | constant                    |
| `GFX_PSS_INVALIDATE`                 | `SP1_PSSFLAG_INVALIDATE`        | `0x00`                                     | constant (unused in JSP)    |
| `GFX_PRINT_CTX_INIT`                 | SP1 pss struct init             | `JSP_PRINT_CTX_INIT`                       | macro                       |
| `gfx_init`                           | `sp1_Initialize` + init         | `jsp_init` + pool init                     | real fn, `gfx_jsp.c`        |
| `gfx_invalidate(rect)`               | `sp1_Invalidate(rect)`          | `jsp_invalidate_rect(rect)`                | direct macro                |
| `gfx_update()`                       | `sp1_UpdateNow()`               | `jsp_redraw()`                             | direct macro                |
| `gfx_sprite_create(r,c)`             | `sp1_CreateSpr`+`sp1_AddColSpr` | `jsp_sprite_alloc(r,c)`                    | real fn, `gfx_jsp.c`        |
| `gfx_sprite_destroy(s)`              | `sp1_DeleteSpr(s)`              | `jsp_sprite_free(s)`                       | direct macro                |
| `gfx_sprite_set_color(s,col)`        | `sp1_IterateSprChar` callback   | `jsp_sprite_set_color(s,col,0xF8)`         | real fn, `gfx_jsp.c`        |
| `gfx_sprite_set_threshold(s,x,y)`    | `s->xthresh=x; s->ythresh=y`    | `/* no-op */`                              | stub macro                  |
| `gfx_sprite_move_pixel(s,cl,fr,x,y)` | `sp1_MoveSprPix(...)`           | `gfx_jsp_move_sprite_clipped(...)`         | wrapper: NULL+clip handling |
| `gfx_sprite_move_cell(s,cl,fr,r,c)`  | `sp1_MoveSprAbs(...)`           | `gfx_jsp_move_sprite_clipped(...,c*8,r*8)` | wrapper + coord conversion  |
| `gfx_sprite_get_row(s)`              | `(s)->row`                      | `(s)->ypos / 8`                            | macro                       |
| `gfx_sprite_get_col(s)`              | `(s)->col`                      | `(s)->xpos / 8`                            | macro                       |
| `gfx_sprite_get_width(s)`            | `(s)->width`                    | `(s)->cols`                                | macro                       |
| `gfx_sprite_get_height(s)`           | `(s)->height`                   | `(s)->rows`                                | macro                       |
| `gfx_tile_put(r,c,at,t)`             | `sp1_PrintAtInv(r,c,at,t)`      | `jsp_tile_put(r,c,at,t)`                   | direct macro                |
| `gfx_tile_register(i,g)`             | `sp1_TileEntry(i,g)`            | `jsp_tile_register(i,g)`                   | direct macro                |
| `gfx_clear_rect(rc,at,ch,fl)`        | `sp1_ClearRectInv(...)`         | `jsp_clear_rect(rc,at,ch,fl)`              | direct macro                |
| `gfx_print_set_pos(ctx,r,c)`         | `sp1_SetPrintPos(ctx,r,c)`      | `jsp_print_set_pos(ctx,r,c)`               | direct macro                |
| `gfx_print_string(ctx,str)`          | `sp1_PrintString(ctx,str)`      | `jsp_print_string(ctx,str)`                | direct macro                |

---

## 9. Progress Tracking

### Phase 1 — JSP enhancements (JSP repository)

- [x] **P1-0** Add `uint8_t jsp_bat[768]` (BAT) to JSP data; update `jsp_init` to accept `default_attr` and pre-fill tile table entries 32–127 with ROM font pointers; update `jsp_redraw` to restore BAT attributes when redrawing dirty cells
- [x] **P1-1** Add `color`, `color_mask` fields (+11, +12) to `struct jsp_sprite_s`; add `parked` flag bit
- [x] **P1-2** Implement `jsp_sprite_set_color` and `jsp_apply_sprite_color` (C)
- [x] **P1-3** Update `jsp_move_sprite_mask2`, `jsp_draw_sprite_mask2`, LOAD1 variants: call `jsp_apply_sprite_color`; handle `flags.parked`
- [x] **P1-4** Implement `jsp_sprite_park`
- [x] **P1-5** Implement `jsp_sprite_pool_init`, `jsp_sprite_alloc`, `jsp_sprite_free` (C)
- [x] **P1-6** Implement `jsp_move_sprite_mask2_frame`, `jsp_move_sprite_load1_frame`, `jsp_move_sprite_frame`
- [x] **P1-7** Implement `jsp_sprite_in_rect`
- [x] **P1-8** Implement `jsp_tile_register` and `jsp_tile_put` (tile table lookup + pixel draw + BAT update for attribute)
- [x] **P1-9** Implement `jsp_clear_rect`
- [x] **P1-10** Implement `jsp_invalidate_rect`
- [x] **P1-11** Implement `struct jsp_print_ctx`, `JSP_PRINT_CTX_INIT`, `jsp_print_set_pos`, `jsp_print_string` (Option C: routes character codes through tile table)
- [x] **P1-12** Update `jsp.h` with all new declarations, constants, and the updated struct
- [x] **P1-13** Write JSP tests for new API (using JSP's existing `main.c` test framework)

### Phase 2 — RAGE1 mapping layer (RAGE1 repository)

- [ ] **P2-1** Create `engine/include/rage1/gfx_jsp.h` (type aliases, constants, macro mappings)
- [ ] **P2-2** Create `engine/src/gfx_jsp.c` (`gfx_init`, `gfx_sprite_create`, `gfx_sprite_set_color`, `gfx_jsp_move_sprite_clipped`, pool arrays)
- [ ] **P2-3** Add `#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP` block to `engine/include/rage1/gfx.h`

### Phase 3 — RAGE1 toolchain and build changes

- [ ] **P3-1** Add `sprite_engine` key parsing to `datagen.pl`; emit correct `BUILD_FEATURE_SPRITE_ENGINE_*`
- [ ] **P3-2** Add pool-sizing constant emission to `datagen.pl` (`GFX_JSP_MAX_SPRITES`, `_ROWS`, `_COLS`)
- [ ] **P3-3** Add JSP sprite frame data format to `datagen.pl` (JSP mode: `rows` cells/column, not `rows+1`)
- [ ] **P3-4** Emit `build/generated/sprite_engine.mk` from `datagen.pl`
- [ ] **P3-5** Update `Makefile.common` (include `sprite_engine.mk`, JSP build, include path, `gfx_jsp.c`)
- [ ] **P3-6** Update `Makefile-48` with JSP memory map (guarded by `BUILD_SPRITE_ENGINE = jsp`)
- [ ] **P3-7** Update `Makefile-128` with JSP 128K memory map
- [ ] **P3-8** Update `etc/rage1-config.yml` interrupt vector and stack addresses for JSP layout

### Phase 4 — Integration testing

- [ ] **P4-1** Build `games/minimal` with JSP; verify hero sprite, movement, screen
- [ ] **P4-2** Build a game with enemies; verify sprites, colors, animation frames
- [ ] **P4-3** Build a game with bullets; verify spawn, park, despawn
- [ ] **P4-4** Verify text output (screen titles, lives display, debug area if enabled)
- [ ] **P4-5** `make all-test-builds` with SP1 as default — regression check
- [ ] **P4-6** `make mem` for JSP 48K build; confirm no address overlap with JSP data structures
- [ ] **P4-7** Run in FUSE emulator; no visual artifacts at game_area boundary
- [ ] **P4-8** _(Optional)_ Build a 128K game with JSP; measure binary size headroom

## Plan execution constraints

- Try to refactor or do changes in a way that each change can be tested if possible
- Do small commits, ideally one per task of the ones indicated
- Keep commit messages concise but informative
- Whenever you need to check if a given thing does what is intended, ask me for feedback if needed
- Try to work as autonomously as possible, but do not try so hard that you make huge modifications without advice
- Commit messages should start with "jsp: phase X: "
- It's not needed to let me review on each commit. Just stop after each phase mandatorily, or if you feel you need advice.
- Mark each task as done in the previous list when you commit that task