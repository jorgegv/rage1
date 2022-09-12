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
#include "rage1/sprite.h"

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
                sp1_MoveSprPix( bs->sprite, &game_area, bs->frame, bs->position.x, bs->position.y );
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

struct bullet_info_s bullet_startup_data = {
    .width		= BULLET_SPRITE_WIDTH,
    .height		= BULLET_SPRITE_HEIGHT,
    .frames		= NULL,	// will be initialized at runtime, comes from home_bank assets ptr
    .movement		= {
        .dx = BULLET_MOVEMENT_DX,
        .dy = BULLET_MOVEMENT_DY,
        .delay = BULLET_MOVEMENT_DELAY,
        },
    .num_bullets	= BULLET_MAX_BULLETS,
    .bullets		= &bullet_state_data[0],
    .reload_delay	= BULLET_RELOAD_DELAY,
    .reloading		= 0,
};

// Bullet Sprites initialization function
void bullet_init_sprites(void) {
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
    memcpy( &game_state.bullet, &bullet_startup_data, sizeof( struct bullet_info_s ) );
    game_state.bullet.frames = home_assets->all_sprite_graphics[ BULLET_SPRITE_ID ].frame_data.frames;
}
