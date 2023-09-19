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
#include "rage1/beeper.h"

#include "game_data.h"

#include "rage1/banked.h"

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON

void bullet_animate_and_move_all(void) {
    uint8_t i;
    struct bullet_info_s *bi;
    struct bullet_state_data_s *bs;

    bi = &game_state.bullet;

    if ( ! bi->active_bullets )
        return;

    i = BULLET_MAX_BULLETS;
    while ( i-- ) {
        bs = &bi->bullets[ i ];

        // skip if it's not active
        if ( ! GET_BULLET_FLAG ( *bs, F_BULLET_ACTIVE ) )
            continue;

        // skip if delay has not passed
        if ( bs->delay_counter-- )
            continue;

        // reset delay counter and update coords
        bs->delay_counter = bi->movement.delay;
        bs->position.x += bs->dx;
        bs->position.y += bs->dy;

        // if we have reached game area borders, deactivate bullet and move it offscreen
        if ( ( bs->position.x > CELL_TO_PIXEL_COORD( GAME_AREA_RIGHT + 1 ) - bi->width ) ||
                ( bs->position.x < CELL_TO_PIXEL_COORD( GAME_AREA_LEFT ) ) ||
                ( bs->position.y > CELL_TO_PIXEL_COORD( GAME_AREA_BOTTOM + 1 ) - bi->height ) ||
                ( bs->position.y < CELL_TO_PIXEL_COORD( GAME_AREA_TOP ) )
            ) { // then
            // move bullet offscreen and deactivate
            SET_BULLET_FLAG( *bs, F_BULLET_MOVE_OFFSCREEN );
            continue;
        }

        // check for obstacles
        if (
                // moving right:
                ( ( bs->dx > 0 ) && ( ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y ), 			PIXEL_TO_CELL_COORD( bs->position.x + bi->width ) ) == TT_OBSTACLE ) ||
                                      ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height - 1 ),	PIXEL_TO_CELL_COORD( bs->position.x + bi->width ) ) == TT_OBSTACLE ) ) ) ||
                // moving left:
                ( ( bs->dx < 0 ) && ( ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y ),			PIXEL_TO_CELL_COORD( bs->position.x - 1 ) ) == TT_OBSTACLE ) ||
                                      ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height - 1 ),	PIXEL_TO_CELL_COORD( bs->position.x - 1 ) ) == TT_OBSTACLE ) ) ) ||
                // moving down:
                ( ( bs->dy > 0 ) && ( ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height ),		PIXEL_TO_CELL_COORD( bs->position.x ) ) == TT_OBSTACLE ) ||
                                      ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height ),		PIXEL_TO_CELL_COORD( bs->position.x + bi->width - 1 ) ) == TT_OBSTACLE ) ) ) ||
                // moving up:
                ( ( bs->dy < 0 ) && ( ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y - 1 ),			PIXEL_TO_CELL_COORD( bs->position.x ) ) == TT_OBSTACLE ) ||
                                      ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y - 1 ),			PIXEL_TO_CELL_COORD( bs->position.x + bi->width - 1 ) ) == TT_OBSTACLE ) ) )
            ) { // then
            // move bullet offscreen and deactivate
            SET_BULLET_FLAG( *bs, F_BULLET_MOVE_OFFSCREEN );
            continue;
        }
        // adjust xmax, ymax and move sprite to new position
        bs->position.xmax = bs->position.x + bi->width - 1;
        bs->position.ymax = bs->position.y + bi->height - 1;
        SET_BULLET_FLAG( *bs, F_BULLET_NEEDS_REDRAW );
    }
}

void bullet_add( void ) {
    struct bullet_state_data_s *bs;
    uint8_t i;
    uint8_t h_dy, v_dx;
    struct bullet_info_s *bi;
    struct hero_info_s *hero;

    bi = &game_state.bullet;
    if ( bi->active_bullets == BULLET_MAX_BULLETS )
        return;

    hero = &game_state.hero;

    // search for an inactive slot in hero table
    i = BULLET_MAX_BULLETS;
    while ( i-- ) {
        bs = &game_state.bullet.bullets[ i ];
        if ( ! GET_BULLET_FLAG( *bs, F_BULLET_ACTIVE ) ) {
            SET_BULLET_FLAG( *bs, F_BULLET_ACTIVE );
            &game_state.bullet.active_bullets++;
            h_dy = ( HERO_SPRITE_HEIGHT - bi->height ) / 2;
            v_dx = ( HERO_SPRITE_WIDTH - bi->width ) / 2;

            if ( hero->movement.last_direction & MOVE_UP ) {
                    bs->position.x = hero->position.x + v_dx;
                    bs->position.y = hero->position.y - bi->height;
                    bs->dx = 0;
                    bs->dy = -bi->movement.dy;
                    bs->frame = bi->frames[ BULLET_SPRITE_FRAME_UP ];
            }
            if ( hero->movement.last_direction & MOVE_DOWN ) {
                    bs->position.x = hero->position.x + v_dx;
                    bs->position.y = hero->position.ymax + 1;
                    bs->dx = 0;
                    bs->dy = bi->movement.dy;
                    bs->frame = bi->frames[ BULLET_SPRITE_FRAME_DOWN ];
            }
            if ( hero->movement.last_direction & MOVE_LEFT ) {
                    bs->position.x = hero->position.x - bi->width;
                    bs->position.y = hero->position.y + h_dy;
                    bs->dx = -bi->movement.dx;
                    bs->dy = 0;
                    bs->frame = bi->frames[ BULLET_SPRITE_FRAME_LEFT ];
            }
            if ( hero->movement.last_direction & MOVE_RIGHT ) {
                    bs->position.x = hero->position.xmax + 1;
                    bs->position.y = hero->position.y + h_dy;
                    bs->dx = bi->movement.dx;
                    bs->dy = 0;
                    bs->frame = bi->frames[ BULLET_SPRITE_FRAME_RIGHT ];
            }
            bs->position.xmax = bs->position.x + bi->width - 1;
            bs->position.ymax = bs->position.y + bi->height - 1;
            bs->delay_counter = bi->movement.delay;

            // slot found, set game event and return
            SET_GAME_EVENT( E_BULLET_WAS_SHOT );
            return;
        }
    }
}

#endif // BUILD_FEATURE_HERO_HAS_WEAPON
