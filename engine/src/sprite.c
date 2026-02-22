////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include "rage1/gfx.h"
#include "rage1/game_state.h"
#include "rage1/sprite.h"
#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/util.h"

#include "game_data.h"

void sprite_move_offscreen( gfx_sprite_t *s ) __z88dk_fastcall {
    gfx_sprite_move_cell( s, &full_screen, NULL, OFF_SCREEN_ROW, OFF_SCREEN_COLUMN );
}

#ifdef BUILD_FEATURE_SPRITE_ENGINE_SP1

// standard hook to set sprite attributes. This is a strange function,
// its parameters must be passed through 2 global variables, defined below :-/
struct attr_param_s sprite_attr_param;

#pragma disable_warning 85
static void sprite_set_cell_attributes( uint16_t count, struct sp1_cs *c ) {
    c->attr		= sprite_attr_param.attr;
    c->attr_mask	= sprite_attr_param.attr_mask;
}

gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
    uint8_t c;
    gfx_sprite_t *s;

    // create the sprite and first column
    s = sp1_CreateSpr(SP1_DRAW_MASK2LB, SP1_TYPE_2BYTE,
        rows + 1,	// number of rows including the blank bottom one
        0,		// left column graphic offset
        0		// z-plane
    );
    // ensure s is not NULL
    DEBUG_ASSERT( s, PANIC_SPRITE_IS_NULL );

    // add all remaining columns
    for ( c = 1; c <= cols - 1; c++ ) {
        sp1_AddColSpr(s,
            SP1_DRAW_MASK2,		// drawing function
            0,				// sprite type
            ( rows + 1 ) * 16 * c,	// nth column graphic offset; 16 is because type is 2BYTE (mask+graphic)
            0				// z-plane
        );
    }

    // add final empty column
    sp1_AddColSpr(s, SP1_DRAW_MASK2RB, 0, 0, 0);

    // return the sprite
    return s;
}

void gfx_sprite_set_color( gfx_sprite_t *s, uint8_t color ) {
    // add color
    sprite_attr_param.attr = color;
    sprite_attr_param.attr_mask = 0xF8;
    sp1_IterateSprChar( s, sprite_set_cell_attributes );
}

#endif // BUILD_FEATURE_SPRITE_ENGINE_SP1

void sprite_free( gfx_sprite_t *s ) __z88dk_fastcall {
    gfx_sprite_destroy( s );
}
