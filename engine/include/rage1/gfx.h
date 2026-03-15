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
//
//   Constants (as #defines):
//     GFX_CLEAR_TILE     - flag: clear tiles in a rect
//     GFX_CLEAR_COLOUR   - flag: clear colour in a rect
//     GFX_PSS_INVALIDATE - flag: invalidate on print
//     GFX_PRINT_CTX_INIT(area, attr) - static initializer for print ctx
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
//     gfx_tile_put(row, col, attr, tile)
//     gfx_tile_register(index, graphic)
//     gfx_clear_rect(rect, attr, ch, flags)
//     gfx_print_set_pos(ctx, row, col)
//     gfx_print_string(ctx, str)
//
/////////////////////////////////////////////////////////////////////

// Include the backend-specific header
#ifdef BUILD_FEATURE_SPRITE_ENGINE_SP1
    #include "rage1/gfx_sp1.h"
#endif

#ifdef BUILD_FEATURE_SPRITE_ENGINE_ALT
    #include "rage1/gfx_alt.h"
#endif

#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP
    #include "rage1/gfx_jsp.h"
#endif

// Real functions (multi-step, backend-specific body in .c files)
void gfx_init( uint8_t bg_attr, uint8_t bg_char );
gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols );
void gfx_sprite_set_color( gfx_sprite_t *s, uint8_t color );

#endif // _GFX_H
