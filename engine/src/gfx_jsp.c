////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>

#include "rage1/gfx.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_SPRITE_ENGINE_JSP

// Pool storage — sized by datagen.pl constants (emitted in game_data.h)
static struct jsp_sprite_s _sprite_pool[ GFX_JSP_MAX_SPRITES ];
static uint8_t _sprite_pdbs[
    GFX_JSP_MAX_SPRITES *
    (GFX_JSP_MAX_SPRITE_ROWS + 1) * (GFX_JSP_MAX_SPRITE_COLS + 1) * 8 ];

void gfx_init( uint8_t bg_attr, uint8_t bg_char ) {
    static const uint8_t blank[8] = {0,0,0,0,0,0,0,0};
    (void) bg_char;
    zx_border( INK_BLACK );
    jsp_init( (uint8_t *)blank, bg_attr );
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

void gfx_jsp_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
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

#endif // BUILD_FEATURE_SPRITE_ENGINE_JSP
