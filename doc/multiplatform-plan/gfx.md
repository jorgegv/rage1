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
| `gfx_init(bg_attr, bg_char)` | gfx.h:69 | **(a) already agnostic** | `bg_attr` is a packed Spectrum attribute; `bg_char` is a glyph in the charset. Per the two-layer model (§1.2 obs 4): ZX consumes `bg_attr`; CPC ignores it (uses backend default pens from `cpc-renderer.md`). `bg_char` is universal (charset glyph index). |
| `gfx_invalidate(rect)` | sp1.h:30 / jsp.h:29 | **(a)** | Generic notion: dirty-rect for next redraw. |
| `gfx_update()` | sp1.h:31 / jsp.h:30 | **(a)** | "Flush back-buffer to screen." Universal. |
| **Sprite lifecycle** | | | |
| `gfx_sprite_create(rows, cols)` | gfx.h:70 | **(a) already agnostic** | Units are 8×8 cells, where a cell is 8×8 pixels in the platform's own pixel coordinate system — 8×8 ZX pixels on ZX (32×24 grid), 8×8 mode-1 pixels on CPC mode 1 (40×25 grid). Count semantics are identical across platforms; backends translate cell counts into native byte layouts internally. |

| `gfx_sprite_destroy(s)` | sp1.h:35 / jsp.h:34 | **(a)** | Universal. |
| `gfx_sprite_set_color(s, color)` | gfx.h:71 | **(a) already agnostic** | `color` is a `gfx_attr_t`. Per the two-layer model (§1.2 obs 4): ZX consumes it (Spectrum attribute byte); CPC ignores it (sprite colour is baked into the sprite pixel data emitted by the asset pipeline). |
| `gfx_sprite_set_threshold(s, xt, yt)` | sp1.h:37-38 / jsp.h:36 | **(c) ZX-specific** | SP1-only sub-pixel optimisation. JSP no-ops it. CPC will no-op. Keep as a no-op call (cheap to leave in API). |
| **Sprite movement** | | | |
| `gfx_sprite_move_pixel(s, clip, frame, x, y)` | sp1.h:41 / jsp.h:39-40 | **(b) generalisable** | `x, y` widened to per-platform typedef `gfx_xpos_t`/`gfx_ypos_t` (Phase G4): `uint8_t` on ZX (256×192 fits a byte; ZX backends use only the lower byte and short-circuit accordingly to avoid 16-bit cost); `uint16_t` on CPC (320×200) and on future ZX Next layer-2 (320×256), which both overflow `uint8_t` in x. |

| `gfx_sprite_move_cell(s, clip, frame, row, col)` | sp1.h:42 / jsp.h:41-42 | **(a) effectively** | Cell coords (uint8_t each). ZX max 32×24, CPC mode-1 40×25 — both fit in uint8_t. |
| **Sprite query** | | | |
| `gfx_sprite_get_row(s)` / `_get_col(s)` | sp1.h:45-46 / jsp.h:45-46 | **(a)** | Returns cell coords. SP1 reads `s->row/col`; JSP computes `ypos/8`, `xpos/8`. CPC will do similarly. |
| `gfx_sprite_get_width(s)` / `_get_height(s)` | sp1.h:47-48 / jsp.h:47-48 | **(a)** | Returns cell count. Universal. |
| **Tile drawing** | | | |
| `gfx_tile_put(r, c, attr, tile)` | sp1.h:51 / jsp.h:51 | **(b) generalisable** | `tile` is `gfx_tile_id_t` (`uint16_t`) — value <256 means registered mono glyph slot; value ≥256 means pointer to pre-converted platform-native bytes (see §2.3). `attr` follows the two-layer model (§1.2 obs 4): ZX consumes it; CPC ignores it. |
| `gfx_tile_register(idx, graphic)` | sp1.h:52 / jsp.h:52 | **(a) already agnostic** | `idx` is a single byte (256 tile slots). `graphic` is **always an 8-byte mono UDG pattern** (8 rows × 1 byte = 8×8 1-bit-per-pixel mono pixels) — an API-level invariant on every backend, not a ZX detail. ZX backends (SP1/JSP) store the 8 bytes as-is (native UDG). CPC backend converts at register-time (or first draw) by bit-expanding 1bpp → mode-1 2bpp, using the backend's fixed default pen pair (per `cpc-renderer.md`; see §1.2 obs 4 — `attr` is ignored on CPC), producing a 16-byte mode-1 block (4 pixels/byte × 8 rows × 2 bytes/row). Cache is keyed by `idx`. Scope: this covers single-colour / text / charset tiles. Multi-colour BTile graphics use the address-specified pointer flavour above and carry pre-converted, platform-native bytes from the asset pipeline (owned by `assets.md`). |

| **Rectangle ops** | | | |
| `gfx_clear_rect(rect, attr, ch, flags)` | sp1.h:55 / jsp.h:55 | **(a) already agnostic** | `ch` is a charset glyph; `flags` are the `GFX_CLEAR_*` bitmask (universal). `attr` follows the two-layer model (§1.2 obs 4): ZX consumes it; CPC ignores it (CPC clears to backend default pen). |
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
   Engine code currently leaks the parking row by referencing this
   constant directly (e.g. `sprite_move_offscreen`). Phase G5
   introduces `gfx_sprite_park(s)` as a first-class HAL entrypoint
   (per Q5); the parking row becomes backend-internal (ZX row 24,
   CPC row 25, ZX Next row 32), and engine code stops referencing
   `OFF_SCREEN_ROW` entirely.

4. **Two-layer colour model — attribute layer is optional / ZX-only**.
   RAGE1's graphics surface is decomposed into two layers:
   - **Bitmap layer** (universal): every backend consumes opaque
     pixel-data bytes. ZX backends consume 1bpp mono UDG bytes (and
     address-specified UDG pointers). CPC backend consumes either
     pre-baked colour-in-pixel bytes (mode-1 packed, from the asset
     pipeline) for multi-colour BTiles, or mono UDG bytes converted
     at register-time to a mode-1 block using a fixed default pen
     pair (for text glyphs — see `gfx_tile_register` row and §2.3).
     Engine code never inspects the bitmap bytes — it carries them
     by tile-ID or address-specified pointer.
   - **Attribute layer** (OPTIONAL, ZX-only): the `uint8_t attr`
     parameter (PAPER|INK|BRIGHT|FLASH layout) flowing through
     `gfx_init`, `gfx_tile_put`, `gfx_clear_rect`, `GFX_PRINT_CTX_INIT`
     and `gfx_sprite_set_color` is **consumed by SP1/JSP exactly as
     today, and silently ignored on CPC**. The CPC backend accepts
     the `attr` parameter on the API surface for source-compatibility
     but does nothing with it. CPC colour comes entirely from the
     bitmap data plus a fixed/per-game pen palette owned by
     `cpc-renderer.md`. The `0xF8` INK-mask in
     `engine/src/sprite.c:70` and `engine/src/gfx_jsp.c:43-44` is a
     ZX-internal concern, not part of the HAL.

   **Trade-off:** per-call colour change (e.g. "draw this digit
   yellow this frame, red next") is transparent on ZX via `attr`,
   but not on CPC — on CPC the colour is baked into the registered
   tile data, so per-call variation requires either (a) multiple
   registered tiles, one per colour variant, or (b) a CPC-specific
   palette-swap effect (mode-1 only has 4 pens, so pen-cycling is
   cheap). Engine cases that rely on per-call `attr` variation stay
   ZX-only or get a documented CPC-side workaround in
   `cpc-renderer.md`.

   The single exception where `attr` IS consumed on CPC is
   `gfx_set_border` — see §2.7.

5. **`DEFAULT_BG_ATTR`, `INK_*`, `PAPER_*`** macros: pulled in from
   `<arch/spectrum.h>` (and from `game_data.h`, generated by
   `datagen.pl`). Used as raw `uint8_t` values at call sites: e.g.
   `engine/src/map.c:35`, `engine/src/game_loop.c:152-154`,
   `engine/src/hero.c:303`, `engine/src/inventory.c:48,67`. Per the
   two-layer model (obs 4), these macros stay ZX-only — the CPC
   backend never references them. The leak from `<arch/spectrum.h>`
   into engine code is acceptable as long as either the call sites
   sit in ZX-only code paths, or the macros expand to inert values
   on CPC. Phase G3 picks one approach.


6. **Attribute clash model**. The 0xF8 INK-replacement mask
   (`engine/src/sprite.c:70` and the comment at
   `engine/src/gfx_jsp.c:42-44`) assumes "ink+paper+bright share one
   byte per 8×8 cell". This is a ZX-internal concern that lives
   entirely inside the SP1/JSP backends and does NOT cross the HAL.
   On CPC mode 0/1 each pixel has its own pen, no clash, no shared
   attribute, and `attr` is ignored anyway (per obs 4). The HAL
   doesn't need to abstract clash semantics — the two-layer model
   keeps the concept ZX-internal.

7. **1-byte tile IDs**. `gfx_tile_register(idx, gfx)` `idx` is a `uint8_t`
   = 256 max distinct UDGs. SP1's `sp1_PrintAtInv` also accepts a
   16-bit "tile" which is actually a ROM glyph address for IDs ≥256.
   `engine/src/btile.c:64,136` casts `(uint16_t)b->tiles[n]`. JSP
   replicates the same dual-purpose semantics. CPC has neither concept
   natively, but the mono-UDG contract is platform-neutral — the CPC
   backend maintains its own glyph table by bit-expanding the 8-byte
   mono pattern to a 16-byte mode-1 block at register-time (using a
   fixed default pen pair; see §1.2 obs 4 and `gfx_tile_register`
   row). The two flavours of `tile` argument — small ID (registered
   mono glyph) vs 16-bit pointer (pre-converted multi-colour BTile
   bytes from the asset pipeline) — are an unambiguous discriminator
   in both ZX and CPC backends.

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
    a hard ABI break — the parameter type widens to a per-platform
    typedef `gfx_xpos_t`/`gfx_ypos_t` (Phase G4): `uint8_t` on
    ZX48/ZX128 (so the ZX build pays no 16-bit cost for an
    always-zero high byte; backends short-circuit accordingly via
    compile-time specialisation), `uint16_t` on CPC and on future
    ZX Next layer-2 (320×256, x ALSO overflows uint8_t). The
    widening is therefore not CPC-only — it is the right answer for
    any ≥256-wide future platform. This is the single most concrete
    signature change required.

12. **Sprite frame pointer ABI**. `gfx_sprite_move_pixel(..., uint8_t
    *frame, ...)` — `frame` is a raw pointer into a backend-specific
    pixel-data layout. SP1 and JSP share the same interleaved
    mask+graphic `(rows+1) * 16 * cols` byte stream
    (`engine/src/sprite.c:42-61`); sprite assets are interchangeable
    between the two ZX backends. CPC will use a different layout
    (mode-1 pre-baked pixel bytes). The *type* is opaque, but the
    per-platform asset converter must emit the right bytes.
    *Asset-side concern — see assets.md*; for `gfx_*` the contract
    "callers hand `gfx_*` an opaque `uint8_t *` produced by the
    platform's asset pipeline" already holds.


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
`engine/lowmem/`. This is **structural on ZX128**: SP1's data region
lives inside the `0xC000` 16 KB slot (roughly 0xD1ED..0xFFFF per
`etc/rage1-config.yml`) — the slot that ZX128 paging swaps. Any
`gfx_*` call ultimately touches SP1 data, so it cannot run from code
that lives in a swapped-in bank: that bank would also have to be
paging over SP1's storage. JSP is **not** structurally bound to that
region (its data could live below 0xC000), but in RAGE1 it is
configured with the same memory layout for symmetry with SP1, so
the constraint applies uniformly across both ZX backends today.

**On CPC the constraint is not hardware-forced**: CPC6128 has four
independent 16 KB paging windows (0x0000, 0x4000, 0x8000, 0xC000)
that can each page to any of 8 RAM banks. A `gfx_*` data region in
one window can be reachable from banked code that swaps a *different*
window — so `gfx_*`-from-banked-code is a placement decision, not a
hardware prohibition. The CPC memory layout (owned by
`cpc-renderer.md`) and the CPC paging-window allocation (owned by
`banking.md`) together decide whether the CPC build takes advantage
of that flexibility or keeps the ZX discipline for portability. The
safe default is to keep the discipline uniform: relax it on CPC only
if a concrete use case asks for it.

In both cases the `gfx_*` HAL surface only needs `#include`-visibility
in the TUs that call it.


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

Per the two-layer model (§1.2 obs 4), the attribute layer is
**optional and ZX-only**. We do NOT try to project ZX attribute
semantics onto CPC. `gfx_attr_t` exists purely for ABI hygiene
(callers stop saying `uint8_t` and start naming the parameter type);
its semantics are entirely backend-defined:

- **SP1 / JSP**: `typedef uint8_t gfx_attr_t;` — Spectrum attribute
  byte (`PAPER|INK|BRIGHT|FLASH` layout). Consumed by every
  attribute-taking HAL call exactly as today.
- **CPC**: `typedef uint8_t gfx_attr_t;` — **inert**. The CPC
  backend accepts the value on the API for source-compatibility but
  does nothing with it (`(void) attr;`). The one exception is
  `gfx_set_border( gfx_attr_t color )`, where the value is consumed
  as a pen index in the current CPC palette (see §2.7).

This resolves Q2 (storage width): `uint8_t` on every platform, since
the type is inert on CPC and there is no encoding to widen.

CPC colour for `gfx_*`-rendered output comes from two places that
neither involve the `attr` argument:
- The **bitmap layer** carries colour-in-pixels for multi-colour
  BTiles (asset pipeline emits CPC-native bytes).
- Mono UDG glyphs (text, charset) bit-expand to mode-1 using a
  **backend default pen pair**, configured at init time and owned
  by `cpc-renderer.md`.

Per-call colour variation (e.g. flashing tint) is a ZX-only
ergonomic; CPC games that need per-tile colour variation either
register multiple tiles (one per colour variant) or use a CPC-
specific palette-cycle effect — see `cpc-renderer.md`.

A portable constructor macro stays useful on ZX so engine call sites
don't name `INK_*` / `PAPER_*` directly:

```c
// gfx_sp1.h / gfx_jsp.h
#define GFX_ATTR( ink, paper, bright, flash )   /* pack into 1 byte */
#define GFX_DEFAULT_BG_ATTR                     DEFAULT_BG_ATTR

// gfx_cpctel.h
#define GFX_ATTR( ink, paper, bright, flash )   0   /* inert on CPC */
#define GFX_DEFAULT_BG_ATTR                     0
```

Engine call sites use `GFX_ATTR(GFX_YELLOW, GFX_GREEN, 0, 0)` (or a
precomputed `GFX_ATTR_HEARTBEAT_ON` constant per game) instead of
`INK_YELLOW | PAPER_GREEN`. On ZX the macro expands to a packed
attribute byte; on CPC it expands to `0` and is discarded inside
the backend. No CPC pen-mapping table is required.

`game_state.default_mono_attr` (`engine/src/btile.c:66,138`) becomes
`gfx_attr_t` typed.

### 2.2 Pixel coordinate widening — `gfx_xpos_t` / `gfx_ypos_t`

Introduce typedefs for sprite pixel coordinates:

```c
// gfx_sp1.h, gfx_jsp.h  (ZX: 256×192, byte-sized fits)
typedef uint8_t  gfx_xpos_t;
typedef uint8_t  gfx_ypos_t;

// gfx_cpctel.h  (CPC mode 1: 320×200, x needs 9 bits)
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

Tile data flowing through `gfx_tile_put` has **two distinct flavours**,
distinguished unambiguously by the form of the `tile` argument
(small ID vs 16-bit pointer):

- **Mono UDG tile** — `tile` argument in `0..255`: index into the
  glyph slot registered via `gfx_tile_register(idx, graphic)`. The
  registered `graphic` is **always 8 bytes of 1-bit-per-pixel mono
  pattern** (UDG-shape, 8 rows × 1 byte), an API invariant on every
  backend. Used for text glyphs, charset, and small single-colour
  decoration tiles. ZX backends (SP1/JSP) store the 8 bytes natively;
  the CPC backend bit-expands 1bpp → mode-1 2bpp at register-time
  (or first draw) producing a 16-byte mode-1 block, using a fixed
  default pen pair (per `cpc-renderer.md`; the `attr` parameter is
  ignored on CPC — see §1.2 obs 4).
- **Multi-colour pre-converted tile** — `tile` argument ≥ 256:
  16-bit pointer to platform-native pre-converted pixel bytes
  emitted by the asset pipeline (`engine/src/btile.c:64,136` casts a
  `uint8_t *` to `uint16_t`). Used by BTiles assembled from
  pre-converted graphics. Layout is platform-specific (ZX:
  interleaved mask+graphic UDG bytes; CPC: mode-1 packed pixel
  bytes), owned by `assets.md`.

(`gfx_print_string` consumes characters that resolve to small IDs
via the registered charset; same flavour as the mono UDG case.)

Replace the polysemic `uint16_t tile` parameter with an explicit type:

```c
typedef uint16_t gfx_tile_id_t;     // <256: mono glyph slot
                                    // >=256: native-bytes pointer

void gfx_tile_put( uint8_t row, uint8_t col,
                   gfx_attr_t attr, gfx_tile_id_t tile );

void gfx_tile_register( uint8_t idx, uint8_t *graphic );  // graphic = 8 mono UDG bytes
```

For the CPC backend `gfx_tile_id_t` discriminates by value range
exactly as on ZX: small ID → look up the cached mode-1 block produced
from the registered mono UDG bytes; pointer ≥256 → consume the
pre-converted CPC-native pixel bytes from the asset pipeline. **The
asset-side machinery for the multi-colour case is owned by
`assets.md`**; the mono case is handled entirely inside the backend.

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

// gfx_cpctel.h
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

The colour mask is a ZX-only concern. On CPC, sprite colour is baked
into the sprite pixel data emitted by the asset pipeline; the CPC
backend's `gfx_sprite_set_color` accepts the `color` parameter for
source-compatibility and discards it (per the two-layer model,
§1.2 obs 4). No CPC mask, no per-cell attribute store.

### 2.7 Border colour

`zx_border( INK_BLACK )` calls in `engine/src/gfx_sp1.c:28` and
`engine/src/gfx_jsp.c:28` (also in `engine/src/debug.c:75-79` for
visual panic output).

Introduce a `gfx_set_border( gfx_attr_t color )` HAL function. This
is the **documented exception** to the "attr is ignored on CPC" rule
(§1.2 obs 4): the border has to be some colour somewhere, so the
`color` argument IS consumed on every backend, with backend-defined
meaning:
- **ZX (SP1/JSP)**: `color` is a Spectrum colour (0..7); the backend
  wraps `zx_border()`.
- **CPC**: `color` is a pen index in the current palette (typically
  pen 0, with palette setup owned by `cpc-renderer.md`).

Raster-bar / split-raster effects (visual panics, alarms) are NOT
part of the HAL — games that want them implement platform-specific
custom code. Debug-panic flash code becomes backend-portable for the
single-colour case only.

### 2.8 Feature-flag rename: `BUILD_FEATURE_GFX_BACKEND_*`

`BUILD_FEATURE_SPRITE_ENGINE_*` is misleading now that the backend
owns tiles, text, and clear/invalidate in addition to sprites. Rename
to `BUILD_FEATURE_GFX_BACKEND_*` with values matching the GFX_BACKEND
short-name = library short-name rule (toolchain.md §3.1): `SP1`,
`JSP`, `CPCTEL` (cpctelera), and `CPCRS` reserved for cpcrslib as a
future entrant. Per the project-wide backwards-compat policy, the
old `BUILD_FEATURE_SPRITE_ENGINE_*` macros remain emitted alongside
the new ones indefinitely so external games that `#ifdef` on them
continue to build. Mechanical rename across:


- `engine/include/rage1/gfx.h:56,60,64`
- `engine/src/gfx_sp1.c:25,35` / `gfx_jsp.c:19,61`
- `engine/src/sprite.c:25,74`
- `engine/src/interrupts.c:89`
- `build/generated/features.h` (via `tools/datagen.pl:3303-3304`)
- `tools/datagen.pl:3304` — emit `GFX_BACKEND_*` instead of `SPRITE_ENGINE_*`
- `Makefile.common:35-38,130` — variable `BUILD_GFX_BACKEND` replaces
  `BUILD_SPRITE_ENGINE`; corresponding `.gdata` keyword
  `GFX_BACKEND` replaces `SPRITE_ENGINE` (with **permanent
  backwards-compat alias** in `datagen.pl`: both `SPRITE_ENGINE`
  and `GFX_BACKEND` keywords stay accepted indefinitely per README
  §5.6, silently mapped).
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
engine/include/rage1/gfx_cpctel.h     # backend header: typedefs, macros
engine/src/gfx_cpctel.c               # multi-step real bodies:
                                   #   gfx_init, gfx_sprite_create,
                                   #   gfx_sprite_set_color,
                                   #   any other CPC-only helpers
```

`engine/include/rage1/gfx.h` gains a third `#ifdef`:

```c
#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL
    #include "rage1/gfx_cpctel.h"
#endif
```

### 3.2 What `gfx_cpctel.h` must provide

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

// macros mapping to renderer-library calls (pseudo-names — actual
// cpctelera-side symbol names per cpc-renderer.md; e.g. dirty-rect
// invalidate may map to a per-backend wrapper around cpct_drawSprite
// / cpct_etm_drawTilemap or to a thin shadow-buffer routine, TBD
// in Phase R4)
#define gfx_invalidate(rect)             gfx_cpctel_invalidate(rect)
#define gfx_update()                     gfx_cpctel_flush()
// ... and so on for every gfx_* macro the contract requires
```

### 3.3 What `gfx_cpctel.c` must provide

The three multi-step real functions, guarded by the new feature flag:

```c
#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL

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

#endif // BUILD_FEATURE_GFX_BACKEND_CPCTEL
```

### 3.4 What the CPC renderer library must offer (HAL-side
requirements)

This list defines the **minimum contract** the chosen library must
satisfy or that `gfx_cpctel.c` must paper over. The detailed evaluation
against candidates is in `cpc-renderer.md`.

- **Mode 1 (or mode 0) screen setup** with dirty-rect support
  (engine contract is `gfx_invalidate` + `gfx_update`, matching
  SP1/JSP — no double buffering on any backend). A candidate CPC
  library may internally use a back-buffer to implement its
  dirty-rect updates; that is an implementation detail behind the
  same invalidate+update API surface RAGE1 consumes.

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

Anything the library does not natively offer, `gfx_cpctel.c` synthesises
on top, but the more the library provides the smaller the backend.

### 3.5 Wiring into the build

- `Makefile.common` — extend `BUILD_GFX_BACKEND` matcher to accept
  `cpctel` and pull cpctelera sources into the build from
  `external/cpctelera/cpctelera/src/` (the cpctelera submodule
  added by toolchain.md Phase T0; see [cpc-renderer.md §4.2](cpc-renderer.md)
  for the exact glob list).
- `tools/datagen.pl` — emit
  `BUILD_FEATURE_GFX_BACKEND_CPCTEL` when the `.gdata` selects `cpctel`.
- **Platform / backend selection rule**: the `gfx_*` backend is one
  axis (SP1, JSP, CPCTEL). The *target machine* is another (ZX48, ZX128,
  CPC464, CPC6128 — CPC664 runs the cpc464 binary; covered by
  `toolchain.md`). The matrix is
  constrained: any CPC graphics backend (`cpctel` today, future
  `cpcrs`) implies a CPC machine target; SP1/JSP imply a ZX machine
  target. `datagen.pl` should validate.

### 3.6 What the engine does *not* need to know

- That CPC has pens vs Spectrum's INK. Once `gfx_attr_t` is in place
  the engine is colour-agnostic.
- The CPC video memory layout (mode-1 2-bit pixels packed
  four-per-byte, mode-0 4-bit pixels packed two-per-byte, with
  interleaved scan-line order driven by the CRTC, etc.). The backend
  hides it.

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
    `get_sprite_engine` etc. — rename to `get_gfx_backend`). Both
    `SPRITE_ENGINE` and `GFX_BACKEND` keywords stay accepted
    indefinitely in `.gdata` parsing per README §5.6 (silent
    alias).
  - Test: `grep -rn BUILD_SPRITE_ENGINE` returns zero matches; all
    `make all-test-builds` variants pass; smoke build of a game
    that still declares `SPRITE_ENGINE` in its `.gdata` succeeds.
- **G2-3** Migrate engine-owned game `.gdata` files (RAGE1's own
  test games) to use `GFX_BACKEND`.
  - What: update `games/minimal_jsp/.../Game.gdata`,
    `games/default_jsp/.../Game.gdata` to use the new keyword.
    External games are NOT migrated — they continue using
    `SPRITE_ENGINE` if they want (silent alias, per §5.6).
  - Test: regression still green.
- **G2-4** *(originally "remove SPRITE_ENGINE alias" — DROPPED
  per README §5.6.)* Documentation pass: confirm the
  `SPRITE_ENGINE` ↔ `GFX_BACKEND` alias is present and silent in
  `datagen.pl`; record the rename in `CHANGELOG.md` as "old name
  remains accepted indefinitely". No removal.
- **Phase-exit criteria**:
  - `BUILD_SPRITE_ENGINE` (the Makefile variable) is gone from
    Makefiles, scripts, and tools — replaced with
    `BUILD_GFX_BACKEND`.
  - `SPRITE_ENGINE` (the `.gdata` keyword) is still accepted —
    verified by a smoke build of a game that uses it.
  - `BUILD_FEATURE_SPRITE_ENGINE_*` and `BUILD_FEATURE_GFX_BACKEND_*`
    macros are both emitted in `features.h` (per §5.6).
  - All test games still build and screenshot-match.

### Phase G3 — Attribute & border abstraction

Goal: get colour values out of engine code as raw Spectrum constants,
so the same engine source compiles unchanged on CPC where the attr
layer is inert (per §1.2 obs 4 / §2.1 two-layer model).

- **G3-1** Introduce `gfx_attr_t` typedef in the ZX backend headers
  (CPC backend lands its own in Phase G7).
  - What: add `typedef uint8_t gfx_attr_t;` to `gfx_sp1.h` and
    `gfx_jsp.h`. Migrate any function signature that takes an
    attribute byte: `gfx_init(uint8_t,uint8_t)` →
    `gfx_init(gfx_attr_t,uint8_t)`; similarly `gfx_sprite_set_color`,
    `gfx_clear_rect`, `gfx_tile_put`, `GFX_PRINT_CTX_INIT`. On ZX the
    typedef is `uint8_t` so the binary is unchanged.
  - Test: all builds + regression green.
- **G3-2** Introduce `GFX_ATTR(ink, paper, bright, flash)` and
  `GFX_DEFAULT_BG_ATTR` in ZX backend headers.
  - What: define the macro in `gfx_sp1.h` and `gfx_jsp.h` (both expand
    to the standard packed byte). Update `gfx.c:18` to use
    `GFX_DEFAULT_BG_ATTR`. The CPC backend (Phase G7) will define both
    to expand to `0` (inert).
  - Test: builds green; binary unchanged.
- **G3-3** Migrate every engine call site away from raw `INK_*` /
  `PAPER_*` / `DEFAULT_BG_ATTR` to `GFX_ATTR()` or named `GFX_ATTR_*`
  constants. Sites listed in §1.2 item 5.
  - What: substitute. Each substitution is one or two lines.
  - Test: regression green at the end. Mid-task ZX visuals unchanged.
- **G3-4** Introduce `gfx_set_border( gfx_attr_t )`. This is the
  documented exception where `color` IS consumed on CPC (per §2.7).
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
  headers: `uint8_t` on ZX48/ZX128 backends (256×192 fits a byte; ZX
  builds avoid 16-bit cost), `uint16_t` on CPC backends (320×200 in
  mode 1, wider in mode 0/2) and on future ZX Next layer-2 backends
  (320×256). ZX backends must internally use only the lower byte and
  short-circuit codegen accordingly (compile-time specialisation).
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
- **G5-4** Introduce `gfx_sprite_park(gfx_sprite_t *s)` as a
  first-class HAL entrypoint (resolves Q5). Each backend hard-codes
  its own parking row (`OFF_SCREEN_ROW` becomes backend-internal):
  SP1/JSP row 24, CPC mode-1 row 25, future ZX Next layer-2 row 32.
  Replace every `sprite_move_offscreen` callsite and every direct
  `OFF_SCREEN_ROW` reference in engine code with `gfx_sprite_park(s)`.
- **Phase-exit criteria**:
  - `grep -rn '\b32\b\|\b24\b' engine/include engine/src` — manually
    verify remaining literals are not screen-geometry.
  - `grep -rn 'OFF_SCREEN_ROW' engine/include engine/src` returns
    empty (the constant is now backend-internal).
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

- **G7-1** Add `engine/include/rage1/gfx_cpctel.h` providing the full
  contract (typedefs, constants, macros — all stubbed). Macros may
  expand to empty `do{}while(0)` or to a `cpc_*` symbol that resolves
  to a no-op extern.
- **G7-2** Add `engine/src/gfx_cpctel.c` with `gfx_init`,
  `gfx_sprite_create`, `gfx_sprite_set_color` as stubs guarded by
  `#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL`.
- **G7-3** Add `cpctel` as a recognised value to `tools/datagen.pl`
  and to `Makefile.common`'s `BUILD_GFX_BACKEND` matcher (per
  README §5.4 naming rule). Build target may not link yet (no
  actual library) but the C source must compile.
- **G7-4** Compile-test: configure a minimal game with
  `GFX_BACKEND cpctel` and verify all `engine/src/*.c` files
  compile clean against the stub backend (`zcc` may not link a
  real binary at this point — the goal is C-level type-checking).

  The compile-test "game" — `games/00cpc-compile-test/` — is a
  **synthetic test target**, not a real game. Concretely: a
  hand-written minimal `game_data/game_config/Game.gdata` with
  `PLATFORM cpc6128` and `GFX_BACKEND cpctel`, a single trivial BTile
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

Goal: a renderable, playable CPC build of `games/minimal_cpc` (the
dedicated CPC stub game created by `cpc-renderer.md` R4-3). This is
where the CPC renderer library lands as live engine code.

> **Note on the two `minimal*` games.** During Phase 1, RAGE1 keeps
> **both** `games/minimal` (ZX-only) and `games/minimal_cpc`
> (CPC-only) as independent stubs. The split avoids forcing
> `games/minimal` to grow CPC overlays before the engine's
> cross-platform plumbing (assets / overlays / HAL split) is mature
> enough to keep a single game building on both platforms. Once that
> plumbing is solid — typically late Phase G9 / Phase A6 — the two
> are merged into a single `games/minimal` that opts into both ZX
> and CPC. `testing.md` TS6 owns the retirement of CPC-only stubs.
> See [testing.md §4.1](testing.md) and [cpc-renderer.md R4](cpc-renderer.md).

- **G8-1** Confirm `external/cpctelera/` (added in toolchain.md Phase
  T0, configured/pinned in cpc-renderer.md Phase R1) is on the
  include path and source glob of the active `Makefile-cpc-flat`
  (or `-banked`). No new vendoring at this phase; G8 consumes what
  T0/R1 already shipped.
- **G8-2** Implement `gfx_cpctel.c` real bodies on top of the library.
- **G8-3** Build a CPC target: `make build target_game=games/minimal_cpc
  GFX_BACKEND=cpctel PLATFORM=cpc6128` (exact knob names defined in
  `toolchain.md`). Output: a CDT or DSK image. `games/minimal_cpc/`
  is the CPC-only stub created by `cpc-renderer.md` R4-3;
  `games/minimal` remains the ZX-only reference and is not built
  for CPC during Phase G8.
- **G8-4** Add CPC screenshot regression alongside ZX regression
  (machinery extended in `testing.md`). Initial coverage:
  `minimal_cpc`.
- **G8-5** Iterate on visual parity: hero / enemies / BTiles render
  correctly. Crisp parity with the ZX reference screenshot is *not*
  required (different palette, different attribute model); the
  acceptance criterion is **functional**: same game logic produces
  same gameplay state.
- **Phase-exit criteria**:
  - `games/minimal_cpc` builds and runs on a CPC emulator
    (Caprice32 or similar) with hero / enemy movement and one
    screen of BTiles rendered correctly.
  - `games/minimal` (ZX) and all other ZX test games still build
    and screenshot-match.

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
    `cpctel-cpc6128` lanes.

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
  *Impact*: `gfx_tile_put` accepts both `0..255` (mono glyph index)
  and ≥256 (pointer to pre-converted multi-colour bytes). On CPC
  each flavour takes a different path inside the backend (see §2.3).  
  *Mitigation*: discrimination is by value range — small ID dispatches
  to a direct array lookup of the cached mode-1 block produced from
  the registered mono UDG bytes (CPC backend bit-expands 1bpp → 2bpp
  at register-time); pointer ≥256 dispatches to consuming the
  pre-converted CPC-native bytes emitted by the asset pipeline
  (`assets.md`). Per-call cost is one branch on `tile < 256` plus the
  selected path. No hash-table lookup required — the asset pipeline
  pre-allocates the cache slots and bakes the right pointer/ID values
  into BTile definitions at build time.

- **R5 — Banked-code accidentally calls `gfx_*`.**  
  *Impact*: Today no banked TU touches `gfx_*` (verified §1.3). On
  ZX128 this is a **hardware constraint** — SP1 data lives in the
  `0xC000` bank-switched slot, so banked code paging that slot
  cannot safely call `gfx_*` (see §1.3 "Notable absences"). On CPC
  it is a **portability convention** — CPC's independent paging
  windows make the placement legal in principle, but the engine
  keeps the same discipline by default to preserve cross-platform
  parity.  
  *Mitigation*: keep banked TUs free of `gfx_*` includes; add a
  CI grep guard: `grep -r 'gfx_' engine/banked_code/` must return
  empty. The guard enforces the portability rule uniformly; if the
  CPC build later relaxes the rule for a specific case
  (`banking.md` / `cpc-renderer.md` decision), the guard's scope
  narrows accordingly.

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

- **Q1 — Glyph vs tile register entrypoint.** RESOLVED: one entrypoint
  (`gfx_tile_register`). **BTile cells are ALWAYS 16-bit pointers,
  never small IDs.** The form of the `tile` argument to `gfx_tile_put`
  (1-byte ID vs 16-bit pointer) is itself the discriminator: small ID
  → registered mono glyph; pointer ≥256 → pre-converted bitmap from
  the asset pipeline. CPC backend partitions accordingly with no API
  change. See §2.3 for the two-flavour contract.


- **Q2 — `gfx_attr_t` storage width.** RESOLVED: `uint8_t` on every
  platform. The two-layer model (§1.2 obs 4 / §2.1) makes the type
  inert on CPC — there is no encoding to widen. ZX keeps the
  Spectrum attribute byte semantics; CPC discards the value
  (`(void) attr;`) except for the single-pen `gfx_set_border`
  exception (§2.7) where it's interpreted as a CPC pen index, which
  also fits in a byte.

- **Q3 — Backwards-compat window for `SPRITE_ENGINE` keyword.**
  RESOLVED: **indefinite**. `SPRITE_ENGINE` stays accepted forever as
  a `.gdata` alias for `GFX_BACKEND`; `datagen.pl` maps it silently;
  `BUILD_FEATURE_SPRITE_ENGINE_*` macros stay emitted alongside the
  new `BUILD_FEATURE_GFX_BACKEND_*` ones. No removal scheduled. Per
  the project-wide policy "backwards compatibility is indefinite" —
  there are external games already using RAGE1 and the project does
  not require their migration.


- **Q4 — BTile geometry generalisation ownership.** RESOLVED:
  per-platform overlays. Two patterns are supported: (1) same 32×24
  layout on both ZX and CPC (CPC uses a 32×24 subset of its 40×25
  screen; no overlay needed); (2) different layouts per platform,
  with the CPC variant living in `<cpc-platform>/game_data/` per the
  standard overlay mechanism (assets.md §2.1, README.md §5.3). No
  auto-extension; the game author opts in to per-platform layouts by
  supplying an overlay. HAL contract unchanged: `gfx_*` never renders
  out-of-screen cells; engine-side clipping (`box`/`clip` rects)
  handles bounds on both platforms.


- **Q5 — Off-screen sprite parking strategy.** RESOLVED: add
  `gfx_sprite_park(gfx_sprite_t *s)` as a first-class HAL entrypoint
  in Phase G5. Each backend parks at its own row, kept entirely
  backend-internal: SP1/JSP row 24, CPC mode-1 row 25, ZX Next
  layer-2 row 32 (future) — generally "one row beyond the visible
  cell-row count". Engine code drops all `OFF_SCREEN_ROW` and
  hard-coded row-24 references.


- **Q6 — Border colour API.** RESOLVED:
  `gfx_set_border(gfx_attr_t color)` is the HAL entrypoint —
  single-shot border set. The argument is interpreted per-platform:
  ZX = Spectrum colour 0..7; CPC = pen index in the current palette.
  This is the documented exception to the "attr is ignored on CPC"
  rule (§1.2 obs 4) — the border has to land somewhere on CPC, so
  the value is consumed here. See §2.7 for the backend wrappers.
  Raster-bar / split-raster effects are NOT part of the HAL; games
  that want them implement platform-specific custom code.


- **Q7 — Multi-mode CPC.** RESOLVED for Phase 1: **mode 1 only**.
  Modes 0 (160×200, 16 colours) and 2 (640×200, 2 colours) are
  deferred, but the HAL is explicitly designed to accommodate them
  later without API change: the two-layer model (§1.2 obs 4 / §2.1)
  makes the bitmap layer opaque to the engine, so future modes are
  a backend-internal mode-parameter concern; cell-quantum (8×8
  platform-pixels) and pixel-coord widening (G4: `uint16_t` on CPC)
  already work for all three modes (mode 0 grid = 20×25, mode 1 =
  40×25, mode 2 = 80×25; mode-2's 640-wide max x fits in uint16_t).
  When a future phase adds modes 0/2, the backend grows a mode
  parameter at init time — no separate `gfx_cpctel_modeN_*` variants
  required. Per-mode asset emission is owned by `assets.md`
  (converter takes a mode param); per-mode palette setup is owned
  by `cpc-renderer.md`.


- **Q8 — MSX option.** RESOLVED: MSX is kept as an open future
  option (Z80 + VDP, tile-based, fits the 8×8-cell model — the HAL
  generalises cleanly to MSX VDP screen 1/2 without rework). Phase 1
  does not add MSX, but every HAL choice in this doc must stay
  MSX-friendly. **C64 is OUT OF SCOPE** for this project entirely —
  its 6502 architecture and sprite+bitmap graphics model would
  require a separate porting project, not a backend within this
  design.


- **Q9 — Pixel coordinate widening default.** RESOLVED: per-platform
  typedef. `gfx_xpos_t` / `gfx_ypos_t` = `uint8_t` on ZX48/ZX128
  (256×192 fits a byte), `uint16_t` on CPC (320×200 or larger) and
  on future ZX Next layer-2 (320×256). Chosen for efficiency — ZX
  builds avoid paying 16-bit arithmetic cost for an always-zero
  high byte. Engine code uses the typedefs uniformly; the only ABI
  break to engine code is the typedef widening on CPC/Next.

