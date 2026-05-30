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
// Phase G7 — CPC backend skeleton (STUB).
//
// Stub bodies for the 'cpctel' gfx backend, guarded by
// BUILD_FEATURE_GFX_BACKEND_CPCTEL.  Every body is a no-op / returns zero.
// NO real CPC rendering: the goal is C-level type-checking of the whole
// RAGE1 engine under +cpc against the stub backend.  Real bodies land in
// Phase G8 (real CPC backend wiring) on top of the translated cpctelera
// primitives (engine/src/cpc/, from Phase R1-5).
//
// Two-layer colour model (gfx.md §2.1 / README §5.5): the ZX `attr` byte is
// inert on CPC and is (void)-discarded here EVERYWHERE except gfx_set_border
// (which on CPC sets the border ink — a real concept; still a stub at G7).
//

#include "rage1/gfx.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL

// Stub sprite pool storage.  A single static descriptor is handed out by the
// stub allocator below; the real cpctel backend (G8) replaces this with a
// proper pool.
static gfx_sprite_t _stub_sprite;

//--- Initialization ---
void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char ) {
    (void) bg_attr;     // §2.1: attr layer is ZX-only, inert on CPC
    (void) bg_char;
    // G8: set CPC mode 1, clear screen to default pen, init renderer.
}

//--- Sprite lifecycle ---
gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
    _stub_sprite.width  = cols;
    _stub_sprite.height = rows;
    // G8: allocate a real CPC sprite descriptor from the pool.
    return &_stub_sprite;
}

void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color ) {
    (void) s;
    (void) color;       // §2.1: colour comes from the bitmap layer on CPC
    // G8: no-op on CPC (colour is baked into the registered tile/sprite data).
}

//--- Initialization helpers ---
void gfx_cpctel_invalidate( gfx_rect_t *rect ) {
    (void) rect;
    // G8: mark the rect dirty in the back-buffer.
}

void gfx_cpctel_update( void ) {
    // G8: blit the dirty regions to the CPC screen.
}

void gfx_cpctel_set_border( uint8_t color ) {
    (void) color;
    // G8: the SINGLE attr-consuming entry point on CPC — map the ZX colour
    // 0..7 to a CPC pen and program the border.
}

//--- Sprite movement / destroy ---
void gfx_cpctel_sprite_destroy( gfx_sprite_t *s ) {
    (void) s;
    // G8: return the sprite descriptor to the pool.
}

void gfx_cpctel_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                     uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y ) {
    (void) s;
    (void) clip;
    (void) frame;
    (void) x;
    (void) y;
    // G8: park if frame==NULL or off the clip rect; otherwise draw the frame.
}

//--- Tile drawing ---
void gfx_cpctel_tile_put( uint8_t row, uint8_t col, gfx_attr_t attr, gfx_tile_id_t tile ) {
    (void) row;
    (void) col;
    (void) attr;        // §2.1: attr discarded on CPC
    (void) tile;
    // G8: blit the registered tile (mono glyph slot < 256, or 16-bit
    // native-bytes pointer >= 256) into the cell.
}

void gfx_cpctel_tile_register( gfx_tile_id_t idx, uint8_t *graphic ) {
    (void) idx;
    (void) graphic;
    // G8: bit-expand the 8-byte mono pattern into a mode-1 block (fixed
    // default pen pair) and cache it under idx.
}

//--- Rectangle operations ---
void gfx_cpctel_clear_rect( gfx_rect_t *rect, gfx_attr_t attr, uint8_t ch, uint8_t flags ) {
    (void) rect;
    (void) attr;        // §2.1: attr discarded on CPC
    (void) ch;
    (void) flags;
    // G8: fill the rect with the default pen / clear tile.
}

//--- Text printing ---
void gfx_cpctel_print_set_pos( gfx_print_ctx_t *ctx, uint8_t row, uint8_t col ) {
    (void) ctx;
    (void) row;
    (void) col;
    // G8: set the print cursor in the context.
}

void gfx_cpctel_print_string( gfx_print_ctx_t *ctx, char *str ) {
    (void) ctx;
    (void) str;
    // G8: render the string through the mono-glyph tile path (§5.9).
}

#endif // BUILD_FEATURE_GFX_BACKEND_CPCTEL
