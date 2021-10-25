////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "rage1/bullet.h"
#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/screen.h"
#include "rage1/util.h"
#include "rage1/debug.h"
#include "rage1/sound.h"

#include "game_data.h"

void init_bullets( void ) {
    bullet_init_sprites();
}

void bullet_redraw_all( void ) {
    uint8_t i;
    struct bullet_info_s *bi;
    struct bullet_state_data_s *bs;

    bi = &game_state.bullet;

    i = bi->num_bullets;
    while ( i-- ) {
        bs = &bi->bullets[ i ];

        // skip if it's not active
        if ( IS_BULLET_ACTIVE( *bs ) ) {
            if ( BULLET_MOVE_OFFSCREEN( *bs ) ) {
                sprite_move_offscreen( bs->sprite );
                RESET_BULLET_FLAG( *bs, F_BULLET_MOVE_OFFSCREEN );
                RESET_BULLET_FLAG( *bs, F_BULLET_ACTIVE );
            }
            if ( BULLET_NEEDS_REDRAW( *bs ) ) {
                sp1_MoveSprPix( bs->sprite, &game_area, bi->frames[0], bs->position.x, bs->position.y );
                RESET_BULLET_FLAG( *bs, F_BULLET_NEEDS_REDRAW );
            }
        }
    }
}

void bullet_reset_all(void) {
    uint8_t i;
    struct sp1_ss *save;

    i = game_state.bullet.num_bullets;
    while ( i-- ) {
        save = game_state.bullet.bullets[ i ].sprite;
        memset( &game_state.bullet.bullets[ i ], 0, sizeof( struct bullet_state_data_s ) );
        game_state.bullet.bullets[ i ].sprite = save;
        sprite_move_offscreen( save );
    }
}

void bullet_move_offscreen_all(void) {
    uint8_t i;

    i = game_state.bullet.num_bullets;
    while ( i-- )
        sprite_move_offscreen( game_state.bullet.bullets[i].sprite );
}

// Bullet Sprites initialization function
void bullet_init_sprites(void) {
    struct bullet_info_s *bi;
    struct sp1_ss *bs;
    uint8_t i;

    // SP1 sprite data
    i = BULLET_MAX_BULLETS;
    while ( i-- ) {
	bullet_state_data[i].sprite = bs = sprite_allocate( 1, 1 );
	bs->xthresh = BULLET_SPRITE_XTHRESH;
	bs->ythresh = BULLET_SPRITE_YTHRESH;
    }

    // initialize remaining game_state.bullet struct fields
    bi = &game_state.bullet;
    bi->width = BULLET_SPRITE_WIDTH;
    bi->height = BULLET_SPRITE_HEIGHT;
    bi->frames = BULLET_SPRITE_FRAMES;
    bi->movement.dx = BULLET_MOVEMENT_DX;
    bi->movement.dy = BULLET_MOVEMENT_DY;
    bi->movement.delay = BULLET_MOVEMENT_DELAY;
    bi->num_bullets = BULLET_MAX_BULLETS;
    bi->bullets = &bullet_state_data[0];
    bi->reload_delay = BULLET_RELOAD_DELAY;
    bi->reloading = 0;
}
