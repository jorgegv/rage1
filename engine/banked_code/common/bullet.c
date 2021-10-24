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

#include "rage1/banked.h"

void bullet_animate_and_move_all(void) {
    uint8_t i;
    struct bullet_info_s *bi;
    struct bullet_state_data_s *bs;

    bi = &game_state.bullet;   

    i = bi->num_bullets;
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
