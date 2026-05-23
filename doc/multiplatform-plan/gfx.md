# Graphics HAL: `gfx_*` generalisation + CPC backend integration

This document is the Graphics chapter of the RAGE1 cross-platform plan
(see `doc/multiplatform-plan/README.md` for the parent plan). It covers
the audit of the existing `gfx_*` API surface, the ZX-specific
assumptions baked into it, and the phased work needed to turn it into
**the** multi-platform graphics HAL — with SP1, JSP and a new Amstrad
CPC backend all sitting behind a single API. The architectural anchor
from the parent plan is non-negotiable: **`gfx_*` is the HAL; there is
no second abstraction layer above it**.

This is a living document. Phases below are sized for execution but may
be split, merged or revised once contact with the code happens.
Out-of-scope items are noted at section heads and link to the document
that owns them.

Conventions used in this file:

- Code references use `file_path:line` form (clickable in most editors).
- Phases are tagged `G1`, `G2`, …; tasks within them `G1-1`, `G1-2`, …
- "ZX game" = any of the existing `games/*` test games. Their behaviour
  must match the pre-change screenshot regression baseline at every
  phase exit.

---

## 1. Current state audit

### 1.1 API surface (function-by-function classification)

The full public contract is declared at
`engine/include/rage1/gfx.h:18-66` (header comment block lists every
type / constant / macro a backend must provide) plus the three
multi-step real functions at `engine/include/rage1/gfx.h:69-71`:

```
void gfx_init( uint8_t bg_attr, uint8_t bg_char );
gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols );
void gfx_sprite_set_color( gfx_sprite_t *s, uint8_t color );
```

Backend headers map each macro to library calls:
SP1 backend at `engine/include/rage1/gfx_sp1.h`,
JSP backend at `engine/include/rage1/gfx_jsp.h`.
Backend real-function bodies live in `engine/src/sprite.c:25-74`
(SP1's `gfx_sprite_create` / `gfx_sprite_set_color`), `engine/src/gfx_sp1.c`
(SP1's `gfx_init`), and `engine/src/gfx_jsp.c` (all three for JSP).

The table below classifies every documented API element:

| API element | Defined at | Class | Notes |
|---|---|---|---|
| **Types** | | | |
| `gfx_sprite_t` | sp1.h:17 / jsp.h:17 | **(c) ZX-specific** | Opaque to callers, OK as opaque. But its existence forces the per-backend sprite struct to expose `row`, `col`, `width`, `height`, `xpos`, `ypos`, `cols`, `rows` (used by inline-macro getters below). |
| `gfx_rect_t` | sp1.h:18 / jsp.h:18 | **(b) generalisable** | Layout is `{row, col, width, height}` in 8×8 cells. CPC mode 1 also has 8×8 cells in a 40×25 grid, so the *shape* generalises; only the bounds change. |
| `gfx_print_ctx_t` | sp1.h:19 / jsp.h:19 | **(c) ZX-specific** | Opaque, but `GFX_PRINT_CTX_INIT` initialiser leaks the backend struct layout (see below). |
| **Constants / static initialisers** | | | |
| `GFX_CLEAR_TILE`, `GFX_CLEAR_COLOUR` | sp1.h:22-23 / jsp.h:22-23 | **(a) already agnostic** | Both backends define them. CPC backend will too. |
| `GFX_PSS_INVALIDATE` | sp1.h:24 / jsp.h:24 | **(a)** | JSP already shows it can be a no-op (0x00). |
| `GFX_PRINT_CTX_INIT(area, attr)` | sp1.h:25-26 / jsp.h:25 | **(c) ZX-specific** | Used at file scope to initialise static print contexts (e.g. `engine/src/debug.c:24`, `engine/src/hero.c:296`, `engine/src/map.c:24`). Each backend must provide its own. CPC can follow the JSP pattern (cleaner, just `{ &area, attr, 0, 0 }`). |
| **Init / frame** | | | |
| `gfx_init(bg_attr, bg_char)` | gfx.h:69 | **(b) generalisable** | `bg_attr` is a packed Spectrum attribute; `bg_char` is a glyph in the ROM/UDG charset. Needs an attribute abstraction. |
| `gfx_invalidate(rect)` | sp1.h:30 / jsp.h:29 | **(a)** | Generic notion: dirty-rect for next redraw. |
| `gfx_update()` | sp1.h:31 / jsp.h:30 | **(a)** | "Flush back-buffer to screen." Universal. |
| **Sprite lifecycle** | | | |
| `gfx_sprite_create(rows, cols)` | gfx.h:70 | **(b)** | Units are 8×8 cells. Generalisable but on CPC mode 1 a "cell" is 8 hardware pixels horizontally = 4 logical (mode-1) pixels — the *count* maps fine, the per-pixel resolution differs. |
| `gfx_sprite_destroy(s)` | sp1.h:35 / jsp.h:34 | **(a)** | Universal. |
| `gfx_sprite_set_color(s, color)` | gfx.h:71 | **(b)** | `color` is a Spectrum attribute byte. Generalises to "platform attribute" once we have the abstraction. |
| `gfx_sprite_set_threshold(s, xt, yt)` | sp1.h:37-38 / jsp.h:36 | **(c) ZX-specific** | SP1-only sub-pixel optimisation. JSP no-ops it. CPC will no-op. Keep as a no-op call (cheap to leave in API). |
| **Sprite movement** | | | |
| `gfx_sprite_move_pixel(s, clip, frame, x, y)` | sp1.h:41 / jsp.h:39-40 | **(c) ZX-specific signature** | `x, y` are `uint8_t`. ZX screen is 256×192, fits in a byte each. **CPC mode 1 is 320×200 — x overflows uint8_t**. This is the most concrete blocker. |
| `gfx_sprite_move_cell(s, clip, frame, row, col)` | sp1.h:42 / jsp.h:41-42 | **(a) effectively** | Cell coords (uint8_t each). ZX max 32×24, CPC mode-1 40×25 — both fit in uint8_t. |
| **Sprite query** | | | |
| `gfx_sprite_get_row(s)` / `_get_col(s)` | sp1.h:45-46 / jsp.h:45-46 | **(a)** | Returns cell coords. SP1 reads `s->row/col`; JSP computes `ypos/8`, `xpos/8`. CPC will do similarly. |
| `gfx_sprite_get_width(s)` / `_get_height(s)` | sp1.h:47-48 / jsp.h:47-48 | **(a)** | Returns cell count. Universal. |
| **Tile drawing** | | | |
| `gfx_tile_put(r, c, attr, tile)` | sp1.h:51 / jsp.h:51 | **(c) ZX-specific** | `tile` parameter type leaks: it is `uint16_t` carrying either a 1-byte tile ID (UDG/ROM charset) or a 16-bit ROM-graphic pointer (SP1's "address-specified" tile). The `attr` is a Spectrum attribute byte. Both need abstracting. |
| `gfx_tile_register(idx, graphic)` | sp1.h:52 / jsp.h:52 | **(c) ZX-specific** | `idx` is a single byte (256 tile slots). `graphic` is an 8-byte UDG (8×8 mono pixels, attribute stored separately). CPC has no native UDG concept — backend must internally maintain a glyph cache and a separate attribute store. |
| **Rectangle ops** | | | |
| `gfx_clear_rect(rect, attr, ch, flags)` | sp1.h:55 / jsp.h:55 | **(b) generalisable** | `ch` is a glyph in the charset; `attr` is platform attribute; `flags` are the `GFX_CLEAR_*` bitmask. Universal once attribute is abstracted. |
| **Text printing** | | | |
| `gfx_print_set_pos(ctx, r, c)` | sp1.h:58 / jsp.h:58 | **(a)** | Cell coords. Universal. |
| `gfx_print_set_clip(ctx, rect)` | sp1.h:59 / jsp.h:59 | **(b)** | Currently a direct struct-field write (`ctx->bounds = rect` for SP1; `ctx->clip = rect` for JSP). The fact that it has to be a macro that knows the field name is the only abstraction issue — CPC backend just supplies its own field-named macro. |
| `gfx_print_string(ctx, str)` | sp1.h:60 / jsp.h:60 | **(a)** | Universal. |

**Summary**: of 22 documented API elements, **6 are already
platform-agnostic, 7 are generalisable with a parameter or semantics
change, and 9 carry hard ZX assumptions** (mostly in the attribute /
tile / pixel-coordinate triad).

### 1.2 ZX-specific assumptions

The following assumptions are baked into the API contract or into the
data flowing through it. Each must be addressed by the generalisation
strategy in Section 2.

1. **8×8 cell geometry**. Both backends index in 8×8 character cells.
   Hard-coded in `screen_pos_tile_type_data` (`engine/include/rage1/btile.h:93-94`
   uses literal `* 32 + col`). On CPC mode 1, the cell is also 8×8
   pixels — but the screen is **40 cells wide × 25 cells tall**, not
   32×24. The 8×8 quantum is portable; the **map stride 32** is not.
   *Note: the BTile geometry generalisation itself lives above the
   gfx_* layer — see Open Question Q4.*

2. **32×24 game-area dimensions**. `screen.c:14`:
   `gfx_rect_t full_screen = { 0, 0, 32, 24 };` — hard-coded. Plus all
   the screen-area macros (`GAME_AREA_*`, `LIVES_AREA_*`, etc.)
   emitted by `tools/datagen.pl:2183-2202` derive from
   `game_config->game_area->{top,left,right,bottom}` in the `.gdata`.
   The *infrastructure* is parameterised; only the **default** is ZX.

3. **`OFF_SCREEN_ROW = 24`** at `engine/include/rage1/screen.h:19`.
   Anchored to 24 rows. Becomes wrong on CPC where the grid is 25
   rows tall — though for CPC the off-screen row could equally be 25
   or any value ≥ playfield height.

4. **Spectrum attribute byte** as the universal colour-carrying type.
   `uint8_t attr` with `PAPER|INK|BRIGHT|FLASH` layout flows through
   `gfx_init`, `gfx_tile_put`, `gfx_clear_rect`, `GFX_PRINT_CTX_INIT`,
   and the field-attribute parameter on `gfx_sprite_set_color`. The
   `0xF8` INK-mask in `engine/src/sprite.c:70` and
   `engine/src/gfx_jsp.c:43-44` is the most-explicit example. CPC has
   pen/paper indices on top of mode-dependent palette tables — utterly
   different.

5. **`DEFAULT_BG_ATTR`, `INK_*`, `PAPER_*`** macros: pulled in from
   `<arch/spectrum.h>` (and from `game_data.h`, generated by
   `datagen.pl`). Used as raw `uint8_t` values at call sites: e.g.
   `engine/src/map.c:35`, `engine/src/game_loop.c:152-154`,
   `engine/src/hero.c:303`, `engine/src/inventory.c:48,67`. These leak
   from the include `arch/spectrum.h` into engine code with no `gfx_*`
   indirection.

6. **Attribute clash model**. The 0xF8 INK-replacement mask
   (`engine/src/sprite.c:70` and the comment at
   `engine/src/gfx_jsp.c:42-44`) assumes "ink+paper+bright share one
   byte per 8×8 cell". On CPC mode 0/1, each pixel has its own pen,
   no clash, no shared attribute. The HAL must hide this difference.

7. **1-byte tile IDs**. `gfx_tile_register(idx, gfx)` `idx` is a `uint8_t`
   = 256 max distinct UDGs. SP1's `sp1_PrintAtInv` also accepts a
   16-bit "tile" which is actually a ROM glyph address for IDs ≥256.
   `engine/src/btile.c:64,136` casts `(uint16_t)b->tiles[n]`. JSP
   replicates the same dual-purpose semantics. CPC has neither concept
   natively — the backend will need to maintain its own glyph table.

8. **BAT (Background Attribute Table) semantics**. SP1 maintains a
   shadow of the screen attribute byte per cell. `sp1_PrintAtInv`,
   `sp1_ClearRectInv`, `sp1_MoveSprPix` all interact with the BAT for
   attribute-preserved redraws. JSP replicates this with its own back-
   buffer. CPC backend (e.g. cpctelera-based) will have its own
   internal back-buffer / dirty-rect model. The contract from the
   engine's perspective is already abstract — invalidate + update —
   so this is *implementation-level* leakage, not API leakage.

9. **`zx_border(INK_BLACK)`** called from both `gfx_init`s
   (`engine/src/gfx_sp1.c:28`, `engine/src/gfx_jsp.c:28`). The border
   colour concept does exist on CPC (mode-independent border ink), so
   this is *generalisable*; today it's just hard-coded inside backends.

10. **`<arch/spectrum.h>` include** at the top of `engine/src/gfx.c`,
    `gfx_sp1.c`, `gfx_jsp.c`, `btile.c`, `map.c`, `inventory.c`,
    `charset.c`, `debug.c`, `enemy.c` (via `<arch/zx.h>`), and others.
    These pull in ZX-specific constants and inline asm helpers. A
    platform-portable engine must either move all platform-specific
    arch includes into the backend headers, or guard them.

11. **Pixel coordinates are `uint8_t`**. `gfx_sprite_move_pixel(s,
    clip, frame, x, y)` uses `uint8_t x, y`. **ZX screen 256×192 fits;
    CPC mode-1 320×200 *overflows in x*** (max x can be 319). This is
    a hard ABI break — either the parameter type widens to `uint16_t`
    on platforms that need it, or callers convert. This is the
    single most concrete signature change required.

12. **Sprite frame pointer ABI**. `gfx_sprite_move_pixel(..., uint8_t
    *frame, ...)` — `frame` is a raw pointer into a backend-specific
    pixel-data layout. SP1 expects an interleaved mask+graphic
    `(rows+1) * 16 * cols` byte stream (`engine/src/sprite.c:42-61`).
    JSP expects a different layout. CPC will expect another. The
    *type* is opaque, but the per-platform asset converter must emit
    the right bytes. *Asset-side concern — see assets.md*; for `gfx_*`
    the contract "callers hand `gfx_*` an opaque `uint8_t *` produced
    by the platform's asset pipeline" already holds.

### 1.3 Caller inventory (engine code using `gfx_*`)

Comprehensive `grep gfx_` across `engine/src/`, `engine/include/`,
`engine/banked_code/`, `engine/lowmem/` (excluding the backends
themselves). The full list of call sites:

**`gfx_sprite_t *` typed variables and struct members:**
- `engine/include/rage1/bullet.h:25` — `gfx_sprite_t *sprite;` in `struct bullet_state_data_s`
- `engine/include/rage1/enemy.h:38` — `gfx_sprite_t *sprite;` in `struct enemy_info_s`
- `engine/include/rage1/hero.h:71` — `gfx_sprite_t *sprite;` in `struct hero_info_s`
- `engine/include/rage1/hero.h:86` — `extern gfx_sprite_t *hero_sprite;`
- `engine/include/rage1/sprite.h:43,46` — function signatures
- `engine/src/bullet.c:59,99,104` — bullet sprite lifecycle
- `engine/src/hero.c:120,321` — hero sprite definition
- `engine/src/map.c:186,192,208` — per-screen enemy sprite alloc/free
- `engine/src/sprite.c:21,22,37,39,67,76,77` — sprite helpers
- `engine/banked_code/*` — **no direct `gfx_sprite_t` uses** (banked
  code touches sprite *flags*, not gfx primitives).

**`gfx_rect_t` typed variables and struct members:**
- `engine/include/rage1/btile.h:64,68` — `btile_draw*()` signatures
- `engine/include/rage1/map.h:81` — `gfx_rect_t box;` in screen
  background-data struct
- `engine/include/rage1/screen.h:23` — `extern gfx_rect_t full_screen;`
- `engine/src/screen.c:14` — definition `gfx_rect_t full_screen = { 0, 0, 32, 24 };`
- Areas generated by `tools/datagen.pl:2187` — `game_area`,
  `lives_area`, `debug_area`, `inventory_area`, `title_area`. Emitted
  into `build/generated/game_data.c` and declared in
  `build/generated/game_data.h`.

**`gfx_print_ctx_t` static contexts:**
- `engine/src/debug.c:24` — `debug_ctx`
- `engine/src/hero.c:296` — `lives_display_ctx`
- `engine/src/map.c:24` — `title_ctx`

**`gfx_*` macro / function calls (by site):**
- `engine/src/btile.c:64,66,136,138,154` — `gfx_tile_put` (the main
  background renderer; cell-and-attribute write)
- `engine/src/bullet.c:50,104,105` — `gfx_sprite_move_pixel`,
  `gfx_sprite_create`, `gfx_sprite_set_threshold`
- `engine/src/charset.c:30` — `gfx_tile_register` (custom charset
  upload)
- `engine/src/debug.c:28,32,33,36` — `gfx_print_*` + `gfx_clear_rect`
- `engine/src/enemy.c:56,78` — `gfx_sprite_move_pixel` (per-frame
  enemy redraw)
- `engine/src/game_loop.c:152,154,263` — `gfx_tile_put` (heartbeat),
  `gfx_update`
- `engine/src/hero.c:99,141,215-220,303,321` — `gfx_sprite_move_pixel`,
  `gfx_sprite_get_height/width/row/col`, `gfx_clear_rect`,
  `gfx_sprite_create`
- `engine/src/inventory.c:48,67` — `gfx_clear_rect`
- `engine/src/map.c:35,119,121-122,186-208` — `gfx_clear_rect`,
  `gfx_print_*`, `gfx_sprite_create/set_color/destroy`
- `engine/src/sprite.c:22,77` — `gfx_sprite_move_cell`, `gfx_sprite_destroy`
- `engine/include/rage1/debug.h:25` — `#define debug_flush() gfx_update()`

**Notable absences**: no `gfx_*` calls in `engine/banked_code/` or
`engine/lowmem/`. Banked code touches state flags and animation; the
actual graphics primitives all run from low memory. Good — this means
the `gfx_*` HAL surface only needs `#include`-visibility in low-memory
TU compilation units, not in banked TUs.

**Total active call sites**: roughly **45** `gfx_*` function/macro
invocations (excluding type-only uses, include lines, and member-
struct declarations) across **12** engine files. Manageable. None of
them perform pointer arithmetic on `gfx_sprite_t` or `gfx_rect_t` —
they treat them as opaque typedefs. The only struct-field reads are
the four `gfx_sprite_get_*` inline macros and `ctx->bounds`/`ctx->clip`
assignment inside `gfx_print_set_clip`, both confined to the backend
headers.

**Dead API note**: `gfx_print_set_clip(ctx, rect)` is declared in the
HAL but has **no current callers** in `engine/` or test games (verify
with `grep -rn gfx_print_set_clip engine/ games/`). It exists for
completeness of the print-context API surface. Phase G2 should either
keep it (as part of a frozen HAL surface) or flag for removal in a
later cleanup. Keeping it costs nothing; removing it would require
auditing external users.

This is a healthy starting point: the engine is already disciplined
about using the HAL; the leakage is in the *values* passed (attribute
bytes, glyph IDs) not in the *shape* of calls.

---

## 2. Generalisation strategy

This section names concrete new types / parameters / macros for each
ZX-specific surface identified in §1.2. The strategy throughout is:

- **Keep `gfx_*` as the only HAL.** No new abstraction layer.
- **Prefer additive over breaking.** Where a type/parameter widens
  (e.g. pixel coords), introduce it as a new typedef that defaults to
  the historical width on ZX builds.
- **Push platform colour reasoning out of engine source.** Engine code
  never names "INK", "PAPER", "BRIGHT" again — only `gfx_attr_t` values
  produced by `gfx_attr()` helpers and `GFX_DEFAULT_BG_ATTR`.
- **Generated code respects the abstraction.** `tools/datagen.pl`
  emits portable types and helper macros, not raw Spectrum attribute
  bytes. Engine of generated-data work lives in `assets.md`.

### 2.1 Attribute abstraction — `gfx_attr_t`

Replace `uint8_t` colour parameters with a typedef `gfx_attr_t` whose
storage size is backend-defined:

- SP1 / JSP: `typedef uint8_t gfx_attr_t;` (Spectrum attribute byte).
- CPC: `typedef uint8_t gfx_attr_t;` if a single packed
  ink/paper-index encoding is workable, or `typedef uint16_t
  gfx_attr_t;` if pen+paper+style won't fit. **The exact encoding is
  CPC-backend territory — see `cpc-renderer.md`**. From the HAL's
  perspective the type is opaque.

A platform-portable constructor in the backend header lets engine code
build attribute values without naming Spectrum constants:

```c
// gfx_sp1.h / gfx_jsp.h
#define GFX_ATTR( ink, paper, bright, flash )   /* pack into 1 byte */
#define GFX_DEFAULT_BG_ATTR                     DEFAULT_BG_ATTR

// gfx_cpc.h (sketch)
#define GFX_ATTR( ink, paper, bright, flash )   /* pack pen/paper, ignore bright/flash */
#define GFX_DEFAULT_BG_ATTR                     GFX_ATTR(15, 0, 0, 0)
```

Engine call sites stop saying `INK_YELLOW | PAPER_GREEN` and start
saying `GFX_ATTR(GFX_YELLOW, GFX_GREEN, 0, 0)` (or use a precomputed
`GFX_ATTR_HEARTBEAT_ON` constant per game in `game_config`). The
colour-palette enums (`GFX_BLACK..GFX_WHITE`) are an 8-colour common
denominator across ZX (8 inks/8 papers) and CPC mode 1 (4 pens picked
from a 27-colour palette, indirectly mapped). **Mapping
table per platform lives in the backend.**

`game_state.default_mono_attr`
(`engine/src/btile.c:66,138`) becomes `gfx_attr_t` typed.

### 2.2 Pixel coordinate widening — `gfx_xpos_t` / `gfx_ypos_t`

Introduce typedefs for sprite pixel coordinates:

```c
// gfx_sp1.h, gfx_jsp.h  (ZX: 256×192, byte-sized fits)
typedef uint8_t  gfx_xpos_t;
typedef uint8_t  gfx_ypos_t;

// gfx_cpc.h  (CPC mode 1: 320×200, x needs 9 bits)
typedef uint16_t gfx_xpos_t;
typedef uint8_t  gfx_ypos_t;
```

Update the function declaration in `gfx.h`:

```c
void gfx_sprite_move_pixel( gfx_sprite_t *s, gfx_rect_t *clip,
                            uint8_t *frame,
                            gfx_xpos_t x, gfx_ypos_t y );
```

Engine struct members that store hero/enemy/bullet sub-pixel position
(`engine/include/rage1/hero.h` etc., field `position.x` — the
`uint8_t integer` part of a fixed-point) **also need widening on CPC**.
That work touches `engine/src/hero.c`, `enemy.c`, `bullet.c` plus the
generated movement-bounds expressions in `tools/datagen.pl:1887-1890`.
This change set is non-trivial and is one of the bigger generalisation
items; flagged as Phase G4 below.

### 2.3 Tile / glyph abstraction

Three semantic flavours flow through `gfx_tile_put` today:

- **Small tile ID** (0-255): index into the registered tile / UDG / ROM
  charset table. Used for text and small decoration BTiles.
- **Address-specified tile** (16-bit graphic pointer ≥256): raw
  pointer to an 8-byte UDG pattern. Used by BTiles assembled from
  pre-converted graphics (`engine/src/btile.c:64,136` casts a `uint8_t
  *` to `uint16_t`).
- **Special characters** in printed strings, via `gfx_print_string`.

Replace the polysemic `uint16_t tile` parameter with an explicit type:

```c
typedef uint16_t gfx_tile_id_t;     // ZX backend: keeps SP1 semantics

void gfx_tile_put( uint8_t row, uint8_t col,
                   gfx_attr_t attr, gfx_tile_id_t tile );

void gfx_tile_register( uint8_t idx, uint8_t *graphic );
```

For the CPC backend `gfx_tile_id_t` will be a backend-internal cache
index. The asset pipeline emits CPC-native pixel bytes for each
registered tile; the runtime maps `idx` → cached pixel block at draw
time. **The asset-side machinery is owned by `assets.md`**; from the
HAL's perspective the contract is "calls match the ZX semantics, the
backend implements its own caching".

Open question (Q1): do we need a separate `gfx_glyph_register` for
text glyphs vs `gfx_tile_register` for background tiles? On ZX they
share the 256-slot character set; on CPC they may not. Probably stays
as one entrypoint, with a CPC-internal partition.

### 2.4 Print context generalisation

`GFX_PRINT_CTX_INIT(area, attr)` is the only static-initialiser macro
in the HAL. It is used at **file scope** to initialise static
`gfx_print_ctx_t` values (e.g. `engine/src/map.c:24`,
`engine/src/hero.c:296`). The macro **must** be backend-resolvable at
preprocessing time, so it has to live in `gfx_<backend>.h`. JSP shows
the right pattern at `engine/include/rage1/gfx_jsp.h:25`. CPC backend
will follow.

No engine-code change is required — the abstraction is already correct.

### 2.5 Screen geometry parameterisation

The hard-coded 32×24 needs to go away:

- `engine/src/screen.c:14` — replace literal with a backend-supplied
  `GFX_SCREEN_COLS` / `GFX_SCREEN_ROWS` pair:
  ```c
  gfx_rect_t full_screen = { 0, 0, GFX_SCREEN_COLS, GFX_SCREEN_ROWS };
  ```
- `engine/include/rage1/screen.h:19-20` — `OFF_SCREEN_ROW` becomes
  `GFX_SCREEN_ROWS` (or rename the macro to `GFX_OFFSCREEN_ROW` and
  let the backend define it).
- `engine/include/rage1/btile.h:93-94` — the inline
  `screen_pos_tile_type_data[ (srow) * 32 + (scol) ]` macros must use
  `GFX_SCREEN_COLS`. Also affects `engine/src/btile.c:20-21,176-184`.
- `tools/datagen.pl` — already takes screen geometry from
  `game_config->game_area` in `.gdata`, so the *generated* code is
  fine; only the engine-side defaults / hard-codes need lifting.

Backend headers define the constants:

```c
// gfx_sp1.h, gfx_jsp.h
#define GFX_SCREEN_COLS   32
#define GFX_SCREEN_ROWS   24

// gfx_cpc.h
#define GFX_SCREEN_COLS   40
#define GFX_SCREEN_ROWS   25
```

*Note*: BTile geometry, hotzone math and `.gdata` screen-data
literals all assume 32-wide screens at the **game data** level. Lifting
them out is a *separate* concern that lives above `gfx_*` and is owned
by `assets.md` / `banking.md` / a future "engine geometry" doc.

### 2.6 Sprite size / colour mask abstraction

`engine/src/sprite.c:67-72` exposes the 0xF8 attribute mask via the
SP1-specific `sprite_attr_param.attr_mask` struct
(`engine/include/rage1/sprite.h:48-52`). JSP hides the same mask
inside its backend (`engine/src/gfx_jsp.c:43-44`).

Move the mask entirely inside backends — no caller should need to
specify it. The current `attr_param_s` struct and the
`sprite_set_cell_attributes` SP1 callback become backend-private.
`gfx_sprite_set_color(s, color)` is already the correct caller-visible
contract.

The CPC backend may not need a mask at all (per-pixel pens), so it
just stores the colour and applies it on draw.

### 2.7 Border colour

`zx_border( INK_BLACK )` calls in `engine/src/gfx_sp1.c:28` and
`engine/src/gfx_jsp.c:28` (also in `engine/src/debug.c:75-79` for
visual panic output).

Introduce a `gfx_set_border( gfx_attr_t color )` HAL function. Each
backend wraps its native call. Debug-panic flash code becomes
backend-portable too.

### 2.8 Feature-flag rename: `BUILD_FEATURE_GFX_BACKEND_*`

`BUILD_FEATURE_SPRITE_ENGINE_*` is misleading now that the backend
owns tiles, text, and clear/invalidate in addition to sprites. Rename
to `BUILD_FEATURE_GFX_BACKEND_*` (values: `SP1`, `JSP`, `CPC`, future
`ALT` for experiments). Mechanical rename across:

- `engine/include/rage1/gfx.h:56,60,64`
- `engine/src/gfx_sp1.c:25,35` / `gfx_jsp.c:19,61`
- `engine/src/sprite.c:25,74`
- `engine/src/interrupts.c:89`
- `build/generated/features.h` (via `tools/datagen.pl:3303-3304`)
- `tools/datagen.pl:3304` — emit `GFX_BACKEND_*` instead of `SPRITE_ENGINE_*`
- `Makefile.common:35-38,130` — variable `BUILD_GFX_BACKEND` replaces
  `BUILD_SPRITE_ENGINE`; corresponding `.gdata` keyword
  `GFX_BACKEND` replaces `SPRITE_ENGINE` (with **backwards-compat
  alias** in `datagen.pl`: accept both `SPRITE_ENGINE` and
  `GFX_BACKEND` keywords during a deprecation window).
- `Makefile-48:22`
- `tools/mem-summary-*.sh` (4 files)
- `tools/loadertool.pl:181-190`
- `games/minimal_jsp/game_data/game_config/Game.gdata:4`,
  `games/default_jsp/game_data/game_config/Game.gdata:7`

(See Phase G2 below for staging.)

### 2.9 What stays put

These ZX-isms are **not** moved into the HAL, intentionally:

- The 8×8 cell quantum: shared by ZX and CPC, no need to abstract.
- The flag-byte semantics of `GFX_CLEAR_TILE` / `GFX_CLEAR_COLOUR`:
  already abstract.
- Animation sequence / frame data flow: lives above `gfx_*` (in
  `animation.h`); no HAL involvement.
- BTile higher-level structure (`struct btile_s`, `struct
  btile_pos_s`): geometry abstraction is an *asset/datagen* concern,
  not a HAL concern.

---

## 3. CPC backend integration

This section is the HAL-side integration. **Choice of CPC graphics
library (cpctelera vs alternatives), licence audit, asset-tool
marriage, and CPC sprite/tile pixel format all live in
`cpc-renderer.md`.** Below we assume *some* CPC renderer library
exists and is callable from C with z88dk-compatible (or SDCC-CPC)
linkage.

### 3.1 File layout

Mirror the SP1 / JSP pattern:

```
engine/include/rage1/gfx_cpc.h     # backend header: typedefs, macros
engine/src/gfx_cpc.c               # multi-step real bodies:
                                   #   gfx_init, gfx_sprite_create,
                                   #   gfx_sprite_set_color,
                                   #   any other CPC-only helpers
```

`engine/include/rage1/gfx.h` gains a third `#ifdef`:

```c
#ifdef BUILD_FEATURE_GFX_BACKEND_CPC
    #include "rage1/gfx_cpc.h"
#endif
```

### 3.2 What `gfx_cpc.h` must provide

Same contract as the existing two — every typedef/constant/macro
declared in the `gfx.h:18-66` comment block. Concretely:

```c
// types
typedef struct cpc_sprite_s    gfx_sprite_t;
typedef struct cpc_rect        gfx_rect_t;
typedef struct cpc_print_ctx   gfx_print_ctx_t;
typedef uint8_t                gfx_attr_t;          // see §2.1
typedef uint16_t               gfx_xpos_t;          // see §2.2
typedef uint8_t                gfx_ypos_t;
typedef uint16_t               gfx_tile_id_t;       // see §2.3

// screen geometry (mode 1 default)
#define GFX_SCREEN_COLS        40
#define GFX_SCREEN_ROWS        25

// constants
#define GFX_CLEAR_TILE         0x01
#define GFX_CLEAR_COLOUR       0x02
#define GFX_PSS_INVALIDATE     0x00     // no-op
#define GFX_PRINT_CTX_INIT(area, attr)   { &(area), (attr), 0, 0 }
#define GFX_DEFAULT_BG_ATTR              GFX_ATTR(15, 0, 0, 0)

// macros mapping to renderer-library calls
#define gfx_invalidate(rect)             cpc_renderer_invalidate(rect)
#define gfx_update()                     cpc_renderer_flush()
// ... and so on for every gfx_* macro the contract requires
```

### 3.3 What `gfx_cpc.c` must provide

The three multi-step real functions, guarded by the new feature flag:

```c
#ifdef BUILD_FEATURE_GFX_BACKEND_CPC

void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char ) {
    // 1. set CPC mode 1 (or whatever mode the game chose)
    // 2. clear screen with bg_attr / bg_char
    // 3. initialise glyph cache / tile cache
    // 4. invalidate full_screen and flush
}

gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
    // 1. allocate from a pre-sized sprite descriptor pool
    //    (same shape as JSP's _sprite_pool at gfx_jsp.c:23)
    // 2. set dimensions
    // 3. return pointer
}

void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color ) {
    // store colour for later sprite-draw blits
}

void gfx_set_border( gfx_attr_t color ) {
    // wrap renderer-library border-set
}

#endif // BUILD_FEATURE_GFX_BACKEND_CPC
```

### 3.4 What the CPC renderer library must offer (HAL-side
requirements)

This list defines the **minimum contract** the chosen library must
satisfy or that `gfx_cpc.c` must paper over. The detailed evaluation
against candidates is in `cpc-renderer.md`.

- **Mode 1 (or mode 0) screen setup**, double-buffered or with
  dirty-rect support.
- **8×8 tile blit**: stamp an 8×8 pixel block at a cell coord.
- **Sprite blit with mask** at pixel (x, y), arbitrary size in cells.
- **Sprite-park / off-screen handling** (or a way to skip the blit
  when clipped fully outside the playfield, like JSP does at
  `engine/src/gfx_jsp.c:54-57`).
- **Border colour set**.
- **Glyph cache / tile registration** (or a way for the backend to
  build one).
- **Print one glyph at cell coord with colour**.
- **Clear rect (tile + colour)**.
- **Invalidate + flush** (or an immediate-mode write surface).

Anything the library does not natively offer, `gfx_cpc.c` synthesises
on top, but the more the library provides the smaller the backend.

### 3.5 Wiring into the build

- `Makefile.common` — extend `BUILD_GFX_BACKEND` matcher to accept
  `cpc` and pull cpctelera sources into the build from
  `external/cpctelera/cpctelera/src/` (the cpctelera submodule
  added by toolchain.md Phase T0; see [cpc-renderer.md §4.2](cpc-renderer.md)
  for the exact glob list).
- `tools/datagen.pl` — emit
  `BUILD_FEATURE_GFX_BACKEND_CPC` when the `.gdata` selects `cpc`.
- **Platform / backend selection rule**: the `gfx_*` backend is one
  axis (SP1, JSP, CPC). The *target machine* is another (ZX48, ZX128,
  CPC464, CPC6128 — CPC664 runs the cpc464 binary; covered by
  `toolchain.md`). The matrix is
  constrained: `cpc` backend implies a CPC machine target; SP1/JSP
  imply a ZX machine target. `datagen.pl` should validate.

### 3.6 What the engine does *not* need to know

- That CPC has pens vs Spectrum's INK. Once `gfx_attr_t` is in place
  the engine is colour-agnostic.
- The CPC video memory layout (mode-1 4-bit pixels packed two-per-byte
  with an interleaved scan-line order, etc.). The backend hides it.
- Whether the renderer library is cpctelera or anything else.

---

## 4. Phased work plan

Each phase ends with `make all-test-builds` green for ZX (mandatory)
and screenshot regression green for any *unaffected* ZX games (best
effort mid-phase; mandatory at phase exit per the parent plan's
architectural anchor). Phases are *commit groups*; individual tasks
inside a phase need not each leave a green tree, but every phase exit
must.

### Phase G1 — Audit completion & test scaffolding

Goal: make sure we know exactly what we're changing and we can detect
breakage early. **No production code changes**.

- **G1-1** Pin the screenshot baseline.
  - What: run `tests/00regression/` against every `games/*` test game on
    every supported `BUILD_GFX_BACKEND` (currently `sp1`, `jsp`) ×
    every ZX target (48, 128). Tag the resulting PNG set as the
    "pre-multiplatform" baseline.
  - Test: `tests/00regression/` reports zero diff against itself
    after a clean rebuild.
  - Outcome: known-good baseline pinned in CI.
- **G1-2** Add `BUILD_FEATURE_GFX_BACKEND_*` synonym (alias).
  - What: in `tools/datagen.pl`, when the existing
    `BUILD_FEATURE_SPRITE_ENGINE_*` macro is emitted, *also* emit
    `BUILD_FEATURE_GFX_BACKEND_*`. **Both names compile.** No engine
    `#ifdef` touched yet.
  - Test: existing builds pass; `grep` confirms both macros present
    in `build/generated/features.h`.
  - Outcome: engine source can be migrated incrementally to the new
    name in G2 without flipping every backend at once.
- **G1-3** Annotate caller inventory in code.
  - What: add brief `// HAL-CALLER` style comments at each of the ~45
    sites enumerated in §1.3 — or, if the team prefers a non-invasive
    record, leave the inventory in this document only. Lightweight
    house-keeping.
  - Test: build still green.
  - Outcome: discoverability for the next phases.
- **Phase-exit criteria**:
  - All test games build and screenshot-match baseline on both `sp1`
    and `jsp` backends.
  - `BUILD_FEATURE_GFX_BACKEND_*` aliases are visible in
    `features.h` for every backend currently in use.

### Phase G2 — Rename `SPRITE_ENGINE` → `GFX_BACKEND` (mechanical)

Goal: get the naming consistent before any semantic work. Big diff
but mechanical and low-risk.

- **G2-1** Flip engine `#ifdef`s.
  - What: change every `BUILD_FEATURE_SPRITE_ENGINE_*` to
    `BUILD_FEATURE_GFX_BACKEND_*` in: `gfx.h:56,60,64`, `gfx_sp1.c:25,35`,
    `gfx_jsp.c:19,61`, `sprite.c:25,74`, `interrupts.c:89`. The alias
    from G1-2 keeps things compiling during the migration.
  - Test: all backends build, all games pass regression.
- **G2-2** Migrate Makefiles, scripts, and tools.
  - What: rename `BUILD_SPRITE_ENGINE` → `BUILD_GFX_BACKEND` in every
    occurrence — `Makefile.common:35-38,130,315`, `Makefile-48:22`,
    `tools/mem-summary-*.sh` (rename files too), `tools/loadertool.pl`,
    `tools/datagen.pl:3303-3304` (and the surrounding helpers
    `get_sprite_engine` etc. — rename to `get_gfx_backend`). Accept
    both `SPRITE_ENGINE` and `GFX_BACKEND` keywords in `.gdata` parsing
    for the duration of one release (deprecation window).
  - Test: `grep -rn BUILD_SPRITE_ENGINE` returns zero matches; all
    `make all-test-builds` variants pass.
- **G2-3** Migrate game `.gdata` keywords.
  - What: update `games/minimal_jsp/.../Game.gdata`,
    `games/default_jsp/.../Game.gdata` (and any external games via a
    grep-and-suggest) to use `GFX_BACKEND` keyword.
  - Test: regression still green.
- **G2-4** Remove the `SPRITE_ENGINE` alias.
  - What: delete the alias emission from G1-2 and the keyword
    backwards-compat path from G2-2. Add a `datagen.pl` error message
    pointing at the new keyword if the old one is encountered.
  - Test: `make all-test-builds` green.
- **Phase-exit criteria**:
  - No occurrence of `SPRITE_ENGINE` anywhere in engine, tools,
    Makefiles or game data — checked by `grep -r SPRITE_ENGINE`.
  - All test games still build and screenshot-match.

### Phase G3 — Attribute & border abstraction

Goal: get colour values out of engine code as raw Spectrum constants.

- **G3-1** Introduce `gfx_attr_t` typedef in all three (well, two —
  CPC not landed yet) backend headers.
  - What: add `typedef uint8_t gfx_attr_t;` to `gfx_sp1.h` and
    `gfx_jsp.h`. Migrate any function signature that takes an
    attribute byte: `gfx_init(uint8_t,uint8_t)` →
    `gfx_init(gfx_attr_t,uint8_t)`; similarly `gfx_sprite_set_color`,
    `gfx_clear_rect`, `gfx_tile_put`, `GFX_PRINT_CTX_INIT`. On ZX the
    typedef is `uint8_t` so the binary is unchanged.
  - Test: all builds + regression green.
- **G3-2** Introduce `GFX_ATTR(ink, paper, bright, flash)` and
  `GFX_DEFAULT_BG_ATTR` in backend headers.
  - What: define the macro in `gfx_sp1.h` and `gfx_jsp.h` (both expand
    to the standard packed byte). Update `gfx.c:18` to use
    `GFX_DEFAULT_BG_ATTR`.
  - Test: builds green; binary unchanged.
- **G3-3** Migrate every engine call site away from raw `INK_*` /
  `PAPER_*` / `DEFAULT_BG_ATTR` to `GFX_ATTR()` or named `GFX_ATTR_*`
  constants. Sites listed in §1.2 item 5.
  - What: substitute. Each substitution is one or two lines.
  - Test: regression green at the end. Mid-task ZX visuals unchanged.
- **G3-4** Introduce `gfx_set_border( gfx_attr_t )`.
  - What: add to `gfx_sp1.h` (wraps `zx_border`), `gfx_jsp.h`
    (likewise). Replace the two `zx_border()` calls inside backends'
    `gfx_init` with `gfx_set_border()`. Replace the calls inside
    `engine/src/debug.c:75-79` with `gfx_set_border()` too.
  - Test: borders still flash correctly on debug panic (manual
    verification or recorded screenshot).
- **Phase-exit criteria**:
  - `grep -rn 'INK_\|PAPER_\|zx_border' engine/src engine/include` —
    only matches are inside backend `gfx_*` files, which is fine.
  - All test games build and screenshot-match.

### Phase G4 — Pixel coordinate widening

Goal: enable CPC's 320-pixel horizontal range without breaking ZX
binaries.

- **G4-1** Introduce `gfx_xpos_t` / `gfx_ypos_t` typedefs in backend
  headers; default `uint8_t` on ZX backends.
- **G4-2** Update `gfx_sprite_move_pixel` declaration in `gfx.h:70`
  (no — the signature is currently in the macro mappings; lift it to
  a real declaration if needed for type-checking).
- **G4-3** Update `engine/src/hero.c`, `enemy.c`, `bullet.c` to use
  the typedefs for the *integer* part of fixed-point positions.
  Their fractional part (`uint8_t`) stays.
  - What: introduce `struct hero_position_s { gfx_xpos_t x; ... }` or
    similar (existing struct in `hero.h`).
  - Caveat: the .integer part of position fields is currently
    `uint8_t` inside a `union` with a `uint16_t value`. Widening x to
    `uint16_t` while keeping the fixed-point fractional bits adjacent
    is *not* free — `position.x.value` becomes 24 bits if naive.
    Alternative: keep ZX position structs as today; introduce a
    parallel `gfx_pos16_t` only when `gfx_xpos_t == uint16_t`. **This
    is the trickiest semantic ripple of the whole plan.** See
    Risk R3.
  - Test: ZX regression green; manual visual check that no bullet /
    enemy / hero jitters.
- **G4-4** Update `tools/datagen.pl:1887-1890` (movement bounds
  generation) to emit the right width per backend.
- **Phase-exit criteria**:
  - ZX builds binary-identical or near-identical to G3 exit (no
    perf regression).
  - Code compiles cleanly with `gfx_xpos_t == uint16_t` defined for a
    hypothetical CPC backend (verified by adding a temporary
    test header).

### Phase G5 — Geometry & off-screen abstraction

Goal: lift hard-coded 32×24 / OFF_SCREEN_ROW=24 out of engine code.

- **G5-1** Define `GFX_SCREEN_COLS` / `GFX_SCREEN_ROWS` in backend
  headers.
- **G5-2** Replace literal `32`, `24` and the `OFF_SCREEN_ROW` /
  `OFF_SCREEN_COLUMN` / `SCREEN_MAX_ROW` / `SCREEN_MAX_COL` /
  `SCREEN_SIZE` definitions:
  - `engine/include/rage1/screen.h:19-20` — `OFF_SCREEN_ROW = 24`
  - `engine/src/screen.c:14` — `gfx_rect_t full_screen = { 0, 0, 32, 24 }`
  - `engine/include/rage1/btile.h:93-94` — `(srow) * 32 + (scol)` stride
  - `engine/src/btile.c:20-22` — `SCREEN_MAX_ROW=23`, `SCREEN_MAX_COL=31`,
    `SCREEN_SIZE` — replace with `GFX_SCREEN_ROWS - 1` / `GFX_SCREEN_COLS - 1`
    / `GFX_SCREEN_ROWS * GFX_SCREEN_COLS`
  - (Re-verify exact line numbers at edit time; cite by symbol if drift
    becomes a maintenance burden.)
- **G5-3** Confirm `tools/datagen.pl` still emits the right area
  rectangles — `game_area`, `lives_area`, etc. come from `.gdata` and
  should not be affected; only the engine-side fallbacks change.
- **Phase-exit criteria**:
  - `grep -rn '\b32\b\|\b24\b' engine/include engine/src` — manually
    verify remaining literals are not screen-geometry.
  - ZX regression green.

### Phase G6 — Tile / glyph abstraction

Goal: dispel the polysemic `uint16_t` tile parameter.

- **G6-1** Add `typedef uint16_t gfx_tile_id_t;` in backend headers
  (ZX: same width, same semantics; CPC: backend-internal cache index).
- **G6-2** Migrate `gfx_tile_put` and `gfx_tile_register` signatures.
  Update call sites in `btile.c`, `charset.c`, `game_loop.c`,
  `hero.c`.
- **G6-3** Decide on Q1 (separate glyph-register entrypoint?). Likely
  defer to CPC backend execution.
- **Phase-exit criteria**:
  - No `(uint16_t)` cast on tile arguments in engine source.
  - ZX regression green.

### Phase G7 — CPC backend skeleton (stub)

Goal: prove the integration shape works with a no-op CPC backend
target. **Still no real CPC rendering**; this is the framing.

- **G7-1** Add `engine/include/rage1/gfx_cpc.h` providing the full
  contract (typedefs, constants, macros — all stubbed). Macros may
  expand to empty `do{}while(0)` or to a `cpc_*` symbol that resolves
  to a no-op extern.
- **G7-2** Add `engine/src/gfx_cpc.c` with `gfx_init`,
  `gfx_sprite_create`, `gfx_sprite_set_color` as stubs guarded by
  `#ifdef BUILD_FEATURE_GFX_BACKEND_CPC`.
- **G7-3** Add `cpc` as a recognised value to `tools/datagen.pl` and
  to `Makefile.common`'s `BUILD_GFX_BACKEND` matcher. Build target
  may not link yet (no actual library) but the C source must compile.
- **G7-4** Compile-test: configure a minimal game with `GFX_BACKEND
  cpc` and verify all `engine/src/*.c` files compile clean against
  the stub backend (`zcc` may not link a real binary at this point —
  the goal is C-level type-checking).

  The compile-test "game" — `games/00cpc-compile-test/` — is a
  **synthetic test target**, not a real game. Concretely: a
  hand-written minimal `game_data/game_config/Game.gdata` with
  `PLATFORM cpc6128` and `GFX_BACKEND cpc`, a single trivial BTile
  declaration referencing one PNG (existing or trivially drawn), a
  hero declaration, one screen referencing the BTile, and the
  minimum flow-rule set required by datagen. No music, no enemies,
  no bullets. The point is to exercise the largest possible
  surface of `engine/src/*.c` against the stub backend with the
  smallest possible `.gdata` set. Lives under `games/` to be
  picked up by `make all-test-builds`; the leading `00` keeps it
  first in `ls` ordering.
- **Phase-exit criteria**:
  - All existing ZX test games still build green on `sp1` and `jsp`.
  - `games/00cpc-compile-test/` compiles its `engine/src/*.c`
    against the CPC stub backend with no errors (linkage may
    fail; that is acceptable).

### Phase G8 — Real CPC backend wiring

Goal: a renderable, playable CPC build of at least `games/minimal`.
This is where the CPC renderer library lands as live engine code.

- **G8-1** Confirm `external/cpctelera/` (added in toolchain.md Phase
  T0, configured/pinned in cpc-renderer.md Phase R1) is on the
  include path and source glob of the active `Makefile-cpc-flat`
  (or `-banked`). No new vendoring at this phase; G8 consumes what
  T0/R1 already shipped.
- **G8-2** Implement `gfx_cpc.c` real bodies on top of the library.
- **G8-3** Build a CPC target: `make build target_game=games/minimal
  GFX_BACKEND=cpc PLATFORM=cpc6128` (exact knob names defined in
  `toolchain.md`). Output: a CDT or DSK image.
- **G8-4** Add CPC screenshot regression alongside ZX regression
  (machinery extended in `testing.md`). Initial coverage: `minimal`.
- **G8-5** Iterate on visual parity: hero / enemies / BTiles render
  correctly. Crisp parity with the ZX reference screenshot is *not*
  required (different palette, different attribute model); the
  acceptance criterion is **functional**: same game logic produces
  same gameplay state.
- **Phase-exit criteria**:
  - `games/minimal` builds and runs on a CPC emulator (Caprice32 or
    similar) with hero / enemy movement and one screen of BTiles
    rendered correctly.
  - All ZX test games still build and screenshot-match.

### Phase G9 — CPC backend hardening

Goal: bring more games up, address whatever surface-area issues G8
surfaced.

- **G9-1** Bring up `games/blobs`, `games/crumbs`, `games/mapgen` on
  CPC.
- **G9-2** Address any HAL gaps discovered during G8 / G9-1 — e.g.
  CPC-specific clipping wrinkles, glyph-cache eviction strategy,
  border-flash timing.
- **G9-3** Add a CPC line to the CI matrix.
- **Phase-exit criteria**:
  - At least 3 distinct test games run on CPC.
  - CI is green on `sp1-zx48`, `sp1-zx128`, `jsp-zx48`, `jsp-zx128`,
    `cpc-cpc6128` lanes.

---

## 5. Risks

- **R1 — Attribute / palette semantic mismatch.**  
  *Impact*: ZX games that rely on specific INK+PAPER combinations
  will render with a different (CPC-mapped) palette. Some games may
  look visually wrong on CPC.  
  *Mitigation*: `GFX_ATTR(ink, paper, bright, flash)` constructor +
  per-platform mapping table. Game-specific overrides handled via the
  per-platform overlay tree (owned by `assets.md`). Accept that ZX
  attribute clash and CPC mode-1 pen-per-pixel will produce slightly
  different aesthetics — same gameplay, not pixel-identical.

- **R2 — JSP backend regressions during HAL rename.**  
  *Impact*: JSP only landed recently; its test surface is narrower
  than SP1. A rename / refactor sweep may break JSP first because
  fewer screenshot tests exercise it.  
  *Mitigation*: G1-1 pins JSP screenshots before any change; each
  phase exits only when both backends are green; pair-program /
  reviewer-bot on G2 (the riskiest mechanical phase).

- **R3 — Pixel coordinate widening in fixed-point math.**  
  *Impact*: The hero/enemy/bullet position structs use a union to
  share the same bytes between an integer and a fixed-point value.
  Widening the integer to `uint16_t` while preserving the fixed-point
  arithmetic without breaking codegen — especially under SDCC z80
  backend — is non-trivial.  
  *Mitigation*: Phase G4 is staged carefully. If the union approach
  doesn't survive widening, fall back to a parallel
  `position_x16` field used only on platforms with `gfx_xpos_t ==
  uint16_t`; the asset/datagen pipeline picks the right one per
  platform. Verify generated assembler size before/after.

- **R4 — Tile-ID polysemy on CPC.**  
  *Impact*: `gfx_tile_put` accepts both 0-255 (charset index) and
  ≥256 (UDG pointer). On CPC the backend has to translate the
  pointer to a cached pixel block — costly per-call.  
  *Mitigation*: CPC backend builds a tile-pointer → cache-slot map
  at `gfx_tile_register` time (when ZX would store a UDG pointer,
  the CPC backend stores a converted pixel block) and at run time
  does a hash-or-direct-array lookup. Falls into the asset pipeline
  (assets.md) for the conversion proper; here we just acknowledge
  the lookup cost.

- **R5 — Banked-code accidentally calls `gfx_*`.**  
  *Impact*: Today no banked TU touches `gfx_*` (verified §1.3). If a
  future feature adds such a call from banked memory the bank-switch
  semantics break.  
  *Mitigation*: keep banked TUs free of `gfx_*` includes; add a
  CI grep guard: `grep -r 'gfx_' engine/banked_code/` must return
  empty.

- **R6 — `gfx_*` macros that perform raw struct-field writes.**  
  *Impact*: `gfx_print_set_clip(ctx, rect)` writes `ctx->bounds` on
  SP1 and `ctx->clip` on JSP. If a future caller assumes a particular
  field name (e.g. introspects ctx directly), the abstraction breaks.  
  *Mitigation*: forbid direct ctx field access at code-review time;
  add a brief comment on `gfx_print_ctx_t` declarations: "treat as
  opaque, use gfx_print_*".

- **R7 — Schedule blow-up at G8.**  
  *Impact*: Phase G8 (real CPC backend) has the most unknowns — depends
  on a library evaluation outcome owned by `cpc-renderer.md`, plus
  toolchain marriage owned by `toolchain.md`. Slippage there cascades
  here.  
  *Mitigation*: G7 (stub) provides an early integration test that
  doesn't depend on the library choice. Most of the HAL generalisation
  work in G3–G6 is done before G8; if G8 slips, the engine is still
  in a measurably better state.

- **R8 — Pixel-coordinate change ripples beyond `gfx_*`.**  
  *Impact*: Hotzone definitions, collision math, and hero/enemy
  movement velocity all read position bytes. Widening to 16-bit may
  cost performance and code size on ZX, even though semantically
  uint8_t still works.  
  *Mitigation*: keep `gfx_xpos_t == uint8_t` on ZX backends so ZX
  generated code is unchanged. Only CPC pays the 16-bit cost. Verify
  ZX `make mem` deltas at G4 exit.

- **R9 — `arch/spectrum.h` includes scattered across engine.**  
  *Impact*: ~9 engine sources `#include <arch/spectrum.h>` directly.
  If the engine targets CPC, those includes fail compilation on a
  non-ZX toolchain.  
  *Mitigation*: this is somewhat out-of-scope for gfx_*, but flagged
  here because the cleanup goes hand-in-hand: every direct `arch/`
  include in engine source should be replaced by HAL-provided
  equivalents. Track as part of Phase G3 (border abstraction
  eliminates `zx_border`) and Phase G7 (CPC stub forces every
  remaining include onto a portable path).

---

## 6. Open Questions

These need user resolution before or during execution. Numbered for
cross-reference from the parent plan.

- **Q1 — Glyph vs tile register entrypoint.**  
  Do we keep one `gfx_tile_register` for both text glyphs and BTile
  cells, or split into `gfx_glyph_register` (text, ID 0-255) and
  `gfx_tile_register` (background, may exceed 255)? Default answer:
  one entrypoint, CPC backend partitions internally. Confirm before
  G6.

- **Q2 — `gfx_attr_t` storage width.**  
  Stay `uint8_t` on all platforms (including CPC), or let CPC widen
  to `uint16_t` for pen+paper+effects in one value? Default: `uint8_t`
  everywhere if CPC's encoding fits; switch to `uint16_t` *only* if
  the CPC backend genuinely needs it. Decide during G3.

- **Q3 — Backwards-compat window for `SPRITE_ENGINE` keyword.**  
  How long do we accept the old `.gdata` keyword as an alias? One
  release? Until G7? Permanently? Default suggestion: one full
  release after G2 exit, then remove. Confirm.

- **Q4 — BTile geometry generalisation ownership.**  
  BTile data (in `.gdata`) is currently authored for a 32×24 screen
  with 8×8 cells. On CPC mode 1 (40×25) a "minimal" game's screen
  doesn't fit the same canvas. Does the asset pipeline auto-extend
  the screen-data lines, or does the per-platform overlay supply
  CPC-shaped BTile data? **Owned by `assets.md`** but flagged here
  because it affects whether `gfx_*` ever sees out-of-range cell
  coordinates. The HAL contract should *not* attempt to render
  out-of-screen cells; engine-side clipping (already done via
  `box`/`clip` rects) handles this.

- **Q5 — Off-screen sprite parking strategy.**  
  Today `sprite_move_offscreen` uses `OFF_SCREEN_ROW = 24` (one row
  beyond ZX's 24-row playfield). On CPC the equivalent is row 25 or
  beyond. Should the HAL expose `gfx_sprite_park(s)` as a dedicated
  entrypoint, removing the need for engine code to know off-screen
  coordinates at all? JSP already does internal parking
  (`engine/src/gfx_jsp.c:51,55`). Recommendation: add
  `gfx_sprite_park` as a first-class API in G5. Confirm.

- **Q6 — Border colour API.**  
  Confirm `gfx_set_border( gfx_attr_t )` is the right shape. Some
  games may want border-cycle effects (raster bars on ZX, CPC split-
  raster equivalents). Default: API is single-shot border set;
  per-platform "raster bar" support is *not* part of `gfx_*` and goes
  through user-game custom code. Confirm.

- **Q7 — Multi-mode CPC.**  
  CPC has modes 0 (160×200, 16 colours), 1 (320×200, 4 colours), 2
  (640×200, 2 colours). Mode 1 is the obvious match for a ZX
  8×8-cell engine. Do we plan for mode-0 or mode-2 games on CPC at
  all? Default: **mode 1 only** in Phase 1; mode-0 / mode-2 are open
  research, would require their own `gfx_cpc_*` variants. Confirm.

- **Q8 — MSX / C64 placeholder.**  
  Per the parent task, MSX and C64 are sketch-only. The HAL design
  here generalises cleanly to MSX VDP screen modes (tile-based, no
  attribute byte but per-row colour table for screen 1; per-tile
  pattern + colour for screen 2). For C64 it does *not* generalise
  to bitmap mode without significant rework, and the 6502 toolchain
  is a separate axis. Is any HAL choice here disqualifying for
  either? Best-effort answer: no, but C64 will need a different
  backend file pattern (no z88dk).

- **Q9 — Pixel coordinate widening default.**  
  The §2.2 strategy commits to **parallel typedef per platform**
  (ZX stays `uint8_t`, CPC widens to `uint16_t`). Q9 is recorded
  here only as the explicit decision point — if a future review
  prefers a uniform `uint16_t` everywhere (simpler code, marginal
  ZX cost), revisit §2.2 + Phase G4 scope accordingly. Default
  stands unless contested.
