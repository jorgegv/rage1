////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

//
// CPC 'cpctel' gfx backend (REAL — Phase R4; was a Phase G7 stub).
//
// Full gfx HAL contract for the Amstrad CPC 'cpctel' backend
// (library short-name 'cpctel' -> files gfx_cpctel.{h,c}, symbol prefix
// gfx_cpctel_*, feature macro BUILD_FEATURE_GFX_BACKEND_CPCTEL — README §5.4).
//
// This header mirrors EVERY typedef / constant / macro that gfx_sp1.h and
// gfx_jsp.h provide so the whole RAGE1 engine type-checks under +cpc.  Phase
// R4 replaces the G7 stub bodies with REAL mode-1 rendering built on the
// translated cpctelera primitives in engine/src/cpc/ (cpct_video.asm,
// cpct_gfx_m1.asm, cpct_strings_m1.asm).  The renderer is direct-write
// (immediate mode): gfx_invalidate/gfx_update are no-ops on CPC (no back
// buffer), matching the "immediate-mode write surface" option of gfx.md §3.4.
//
// Tile flavour dispatch (README §5.8): gfx_tile_put's `tile` arg is a mono
// glyph slot (0..255, registered via gfx_tile_register) or a 16-bit pointer
// (>=256) to 8 mono UDG bytes (CPC mono mode — README §5.9).  Both flavours
// are 8 mono UDG bytes, bit-expanded to a 16-byte mode-1 block at blit time
// via the 512-byte mono LUT built once at gfx_init from the resolved pen pair.
//
// Two-layer colour model (gfx.md §2.1 / README §5.5): the bitmap layer is
// universal; the ZX `attr` (PAPER|INK|BRIGHT|FLASH) layer is ZX-only and is
// (void)-discarded on CPC EVERYWHERE except gfx_set_border (border ink does
// exist on CPC).  Hence every attr-carrying macro below evaluates its other
// arguments but ignores `attr`.
//

#ifndef _GFX_CPCTEL_H
#define _GFX_CPCTEL_H

#include <stdint.h>

//--- Types ---
// Pixel coordinate widths (Phase G4 — gfx.md §G4-1).
// CPC mode-1 is 320x200, so coordinates are widened to uint16_t (vs uint8_t on
// the ZX 256x192 backends).  Engine code uses these typedefs at every integer
// screen-pixel-coordinate site, so the same source compiles on byte- and
// word-coordinate backends.
typedef uint16_t                 gfx_xpos_t;
typedef uint16_t                 gfx_ypos_t;

// Tile / glyph identifier (Phase G6 — gfx.md §G6-1 / README §5.8).
// On CPC the id is a backend-internal tile-cache index for values 0..255
// (mono glyph slot) and a 16-bit pointer to platform-native bytes for values
// >= 256.  Kept 16-bit-wide to carry both flavours, exactly as ZX does.
typedef uint16_t                 gfx_tile_id_t;

// Attribute byte (gfx.md §2.1).  Inert on CPC (two-layer colour model): the
// type exists for source-compatibility but the backend never consumes it.
typedef uint8_t                  gfx_attr_t;

// Rectangle (row, col, width, height) — same shape as sp1_Rect / jsp_rect so
// the engine's `gfx_rect_t full_screen = { 0, 0, COLS, ROWS };` initialiser
// and every gfx_rect_t consumer compile unchanged.
typedef struct gfx_cpctel_rect_s {
    uint8_t row;
    uint8_t col;
    uint8_t width;
    uint8_t height;
} gfx_rect_t;

// Opaque sprite handle.  Minimal placeholder descriptor at G7; the real
// cpctel backend (G8) extends/replaces this with its native sprite struct.
// Carries the fields the HAL query/threshold macros below reference so they
// type-check.  Coordinates use the widened pixel typedefs.
typedef struct gfx_cpctel_sprite_s {
    uint8_t      row;
    uint8_t      col;
    uint8_t      width;
    uint8_t      height;
    gfx_xpos_t   xthresh;
    gfx_ypos_t   ythresh;
} gfx_sprite_t;

// Print-string context.  Mirrors SP1's static GFX_PRINT_CTX_INIT shape: a
// POINTER to a bounds rect plus an attribute byte (inert on CPC).  The bounds
// member is a pointer (not an embedded struct) so the engine's file-scope
// `gfx_print_ctx_t x = GFX_PRINT_CTX_INIT(area, attr);` initialisers — where
// `area` is a global gfx_rect_t — are constant expressions (taking &area),
// exactly as on SP1.
typedef struct gfx_cpctel_print_ctx_s {
    gfx_rect_t *bounds;
    gfx_attr_t  attr;
} gfx_print_ctx_t;

//--- Constants ---
// Rect-clear flags (inert at G7; placeholder bit values).
#define GFX_CLEAR_TILE             0x01
#define GFX_CLEAR_COLOUR           0x02
// Print-context invalidate flag (inert on CPC, mirrors JSP's 0x00).
#define GFX_PSS_INVALIDATE         0x00
// Static initialiser for a print context: { &bounds, attr } (pointer to the
// area rect, matching SP1 — keeps file-scope initialisers constant).
#define GFX_PRINT_CTX_INIT(area, attr)   { &(area), (attr) }

// Screen geometry in cells (Phase G5 — gfx.md §G5-1 / §1.2 obs 1).
// CPC mode-1 renders a 40x25 character grid (8x8 cells, 320x200 pixels).
#define GFX_SCREEN_COLS            40
#define GFX_SCREEN_ROWS            25

//--- Attribute layer (ZX-only — inert on CPC, see gfx.md §2.1) ---
// These colour-index names and the GFX_ATTR packer exist for source
// compatibility (engine code references GFX_BLACK etc. in ZX-derived call
// sites).  On CPC the packed attribute byte is never consumed — colour comes
// from the bitmap layer plus the per-game pen palette (cpc-renderer.md).
// The numeric values mirror the ZX INK_*/PAPER_* ordering for identical
// constant-folding; the bytes are simply discarded by the CPC backend.
#define GFX_BLACK                  0
#define GFX_BLUE                   1
#define GFX_RED                    2
#define GFX_MAGENTA                3
#define GFX_GREEN                  4
#define GFX_CYAN                   5
#define GFX_YELLOW                 6
#define GFX_WHITE                  7
#define GFX_ATTR(ink,paper,bright,flash) \
    ( (uint8_t)( ((flash) << 7) | ((bright) << 6) | ((paper) << 3) | (ink) ) )
// Default background attribute (per-game value generated by datagen into
// DEFAULT_BG_ATTR).  Inert on CPC but kept for source compatibility.
#define GFX_DEFAULT_BG_ATTR        DEFAULT_BG_ATTR

//--- Initialization ---
// gfx_init() is a real function (multi-step), defined in gfx_cpctel.c.
#define gfx_invalidate(rect)                   gfx_cpctel_invalidate(rect)
#define gfx_update()                           gfx_cpctel_update()
// gfx_set_border() — the SINGLE attr-consuming entry point on CPC (border ink
// exists on CPC, gfx.md §2.7).  Routed through a backend extern (G8 maps the
// ZX colour 0..7 to a CPC pen).
#define gfx_set_border(color)                  gfx_cpctel_set_border((color))

//--- Sprite lifecycle ---
// gfx_sprite_create() / gfx_sprite_set_color() are real functions defined in
// gfx_cpctel.c.
#define gfx_sprite_destroy(s)                  gfx_cpctel_sprite_destroy((s))
// Threshold is an SP1 concept; mirror SP1's field-poke shape so the engine's
// gfx_sprite_set_threshold() callsite type-checks (fields are inert at G7).
#define gfx_sprite_set_threshold(s,xt,yt) \
    do { (s)->xthresh = (xt); (s)->ythresh = (yt); } while(0)

//--- Sprite movement ---
// frame/clip/coords are accepted on the API surface; bodies are stubs (G8).
#define gfx_sprite_move_pixel(s,clip,fr,x,y) \
    gfx_cpctel_move_sprite_clipped((s),(clip),(fr),(x),(y))
#define gfx_sprite_move_cell(s,clip,fr,r,c) \
    gfx_cpctel_move_sprite_clipped((s),(clip),(fr),(gfx_xpos_t)((c)*8),(gfx_ypos_t)((r)*8))

// Park a sprite off-screen (Phase G5 — gfx.md §G5-4).  Backend-internal slot:
// CPC mode-1 has 25 visible rows, so park at row 25 (one below the grid),
// column 0.  Engine code never references these directly; it calls
// gfx_sprite_park() (single out-of-line __z88dk_fastcall in sprite.c).
#define GFX_PARK_ROW                           25
#define GFX_PARK_COL                           0

//--- Sprite query ---
#define gfx_sprite_get_row(s)                  ((s)->row)
#define gfx_sprite_get_col(s)                  ((s)->col)
#define gfx_sprite_get_width(s)                ((s)->width)
#define gfx_sprite_get_height(s)               ((s)->height)

//--- Tile drawing ---
// attr is (void)-discarded on CPC (two-layer colour model, gfx.md §2.1).
#define gfx_tile_put(r,c,attr,tile)            gfx_cpctel_tile_put((r),(c),(attr),(tile))
#define gfx_tile_register(idx,gfx)             gfx_cpctel_tile_register((idx),(gfx))

//--- Rectangle operations ---
#define gfx_clear_rect(rect,attr,ch,flags)     gfx_cpctel_clear_rect((rect),(attr),(ch),(flags))

//--- Text printing ---
#define gfx_print_set_pos(ctx,r,c)             gfx_cpctel_print_set_pos((ctx),(r),(c))
#define gfx_print_set_clip(ctx,rect)           ((ctx)->bounds = (rect))
#define gfx_print_string(ctx,str)              gfx_cpctel_print_string((ctx),(str))

//--- Backend externs (REAL bodies in gfx_cpctel.c — Phase R4) ---
// gfx_invalidate / gfx_update are no-ops on CPC (direct-write renderer, no
// back buffer — gfx.md §3.4 immediate-mode option).
void gfx_cpctel_invalidate( gfx_rect_t *rect );
void gfx_cpctel_update( void );
void gfx_cpctel_set_border( uint8_t color );
void gfx_cpctel_sprite_destroy( gfx_sprite_t *s );
void gfx_cpctel_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                     uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y );
void gfx_cpctel_tile_put( uint8_t row, uint8_t col, gfx_attr_t attr, gfx_tile_id_t tile );
void gfx_cpctel_tile_register( gfx_tile_id_t idx, uint8_t *graphic );
void gfx_cpctel_clear_rect( gfx_rect_t *rect, gfx_attr_t attr, uint8_t ch, uint8_t flags );
void gfx_cpctel_print_set_pos( gfx_print_ctx_t *ctx, uint8_t row, uint8_t col );
void gfx_cpctel_print_string( gfx_print_ctx_t *ctx, char *str );

//--- Public CPC-only render helpers (used by CPC test games / future banked
//    boot path — NOT part of the cross-platform HAL).  Draw a pre-baked
//    mode-1 sprite (solid, no mask) of byte-width `bw` and pixel-height `h`
//    at cell (row,col).  `data` is row-major mode-1 bytes (4 px/byte).
void gfx_cpctel_draw_sprite_cell( uint8_t row, uint8_t col,
                                  uint8_t *data, uint8_t bw, uint8_t h );

#endif // _GFX_CPCTEL_H
