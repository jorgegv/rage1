////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _GFX_H
#define _GFX_H

#include <stdint.h>

#include "features.h"

/////////////////////////////////////////////////////////////////////
// Generic GFX API
//
// All engine code uses these names.  Each backend-specific header
// (gfx_sp1.h, gfx_alt.h, ...) must provide:
//
//   Types (as typedefs):
//     gfx_sprite_t       - opaque handle to a hardware sprite
//     gfx_rect_t         - rectangle (row, col, width, height)
//     gfx_print_ctx_t    - print-string context
//     gfx_attr_t         - attribute byte (inert on CPC, see §2.1)
//     gfx_xpos_t         - integer screen X pixel coord (uint8_t on ZX, uint16_t on CPC/Layer-2)
//     gfx_ypos_t         - integer screen Y pixel coord (uint8_t on ZX, uint16_t on CPC/Layer-2)
//     gfx_tile_id_t      - tile/glyph identifier passed to gfx_tile_put/gfx_tile_register
//                          (uint16_t on ZX: UDG code <256 or tile address; cache index on CPC)
//
//   Constants (as #defines):
//     GFX_CLEAR_TILE     - flag: clear tiles in a rect
//     GFX_CLEAR_COLOUR   - flag: clear colour in a rect
//     GFX_PSS_INVALIDATE - flag: invalidate on print
//     GFX_PRINT_CTX_INIT(area, attr) - static initializer for print ctx
//     GFX_SCREEN_COLS    - screen width  in character cells (ZX: 32)
//     GFX_SCREEN_ROWS    - screen height in character cells (ZX: 24)
//
//   Macros (mapping to library functions):
//     gfx_invalidate(rect)
//     gfx_update()
//     gfx_sprite_destroy(s)
//     gfx_sprite_set_threshold(s, xt, yt)
//     gfx_sprite_move_pixel(s, clip, frame, x, y)
//     gfx_sprite_move_cell(s, clip, frame, row, col)
//     gfx_sprite_get_row(s)
//     gfx_sprite_get_col(s)
//     gfx_sprite_get_width(s)
//     gfx_sprite_get_height(s)
//     gfx_tile_put(row, col, attr, tile)      - tile is a gfx_tile_id_t
//     gfx_tile_register(index, graphic)       - index is a gfx_tile_id_t
//     gfx_clear_rect(rect, attr, ch, flags)
//     gfx_print_set_pos(ctx, row, col)
//     gfx_print_set_clip(ctx, rect)
//     gfx_print_string(ctx, str)
//
/////////////////////////////////////////////////////////////////////

// Include the backend-specific header
#ifdef BUILD_FEATURE_GFX_BACKEND_SP1
    #include "rage1/gfx_sp1.h"
#endif

#ifdef BUILD_FEATURE_GFX_BACKEND_ALT
    #include "rage1/gfx_alt.h"
#endif

#ifdef BUILD_FEATURE_GFX_BACKEND_JSP
    #include "rage1/gfx_jsp.h"
#endif

// Real functions (multi-step, backend-specific body in .c files)
void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char );
gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols );
void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color );
// Park a sprite off-screen (Phase G5 — gfx.md §G5-4).  Single out-of-line
// __z88dk_fastcall function (body in sprite.c) so every callsite emits one call;
// each backend parks at its own GFX_PARK_ROW / GFX_PARK_COL.
void gfx_sprite_park( gfx_sprite_t *s ) __z88dk_fastcall;

// global initialization
void init_gfx( void );

#endif // _GFX_H
