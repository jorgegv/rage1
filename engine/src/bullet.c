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
#include "rage1/beeper.h"
#include "rage1/debug.h"

#include "game_data.h"

//////////////////////////////
// Bullets definition
//////////////////////////////

struct bullet_state_data_s bullet_state_data[ BULLET_MAX_BULLETS ] = {
	{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 },
	{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 },
	{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 },
	{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 }
};

void init_bullets( void ) {
    bullet_init_sprites();
}

void bullet_add( void ) {
    struct bullet_state_data_s *bs;
    uint8_t i;
    uint8_t h_dy, v_dx;
    struct bullet_info_s *bi;
    struct hero_info_s *hero;

    bi = &game_state.bullet;   
    hero = &game_state.hero;

    // search for an inactive slot in hero table
    i = bi->num_bullets;
    while ( i-- ) {
        bs = &game_state.bullet.bullets[ i ];
        if ( ! GET_BULLET_FLAG( *bs, F_BULLET_ACTIVE ) ) {
            SET_BULLET_FLAG( *bs, F_BULLET_ACTIVE );
            h_dy = ( home_assets->all_sprite_graphics[ hero->num_graphic ].height - bi->height ) >> 1;	// divide by 2
            v_dx = ( home_assets->all_sprite_graphics[ hero->num_graphic ].width - bi->width ) >> 1;	// divide by 2
            switch ( hero->movement.last_direction ) {
                case MOVE_UP:
                    bs->position.x = hero->position.x + v_dx;
                    bs->position.y = hero->position.y - bi->height;
                    bs->dx = 0;
                    bs->dy = -bi->movement.dy;
                    break;
                case MOVE_DOWN:
                    bs->position.x = hero->position.x + v_dx;
                    bs->position.y = hero->position.ymax + 1;
                    bs->dx = 0;
                    bs->dy = bi->movement.dy;
                    break;
                case MOVE_LEFT:
                    bs->position.x = hero->position.x - bi->width;
                    bs->position.y = hero->position.y + h_dy;
                    bs->dx = -bi->movement.dx;
                    bs->dy = 0;
                    break;
                case MOVE_RIGHT:
                    bs->position.x = hero->position.xmax + 1;
                    bs->position.y = hero->position.y + h_dy;
                    bs->dx = bi->movement.dx;
                    bs->dy = 0;
                    break;
            }
            bs->position.xmax = bs->position.x + bi->width - 1;
            bs->position.ymax = bs->position.y + bi->height - 1;
            bs->delay_counter = bi->movement.delay;
            // slot found, return
            beep_fx( SOUND_BULLET_SHOT );
            return;
        }
    }
}

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
            RESET_BULLET_FLAG( *bs, F_BULLET_ACTIVE );
            sprite_move_offscreen( bs->sprite );
            continue;
        }

        // check for obstacles
        if (
                // moving right:
                ( ( bs->dx > 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y ), PIXEL_TO_CELL_COORD( bs->position.x + bi->width ) ) == TT_OBSTACLE ) ) ||
                ( ( bs->dx > 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height - 1 ), PIXEL_TO_CELL_COORD( bs->position.x + bi->width ) ) == TT_OBSTACLE ) ) ||
                // moving left:
                ( ( bs->dx < 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y ), PIXEL_TO_CELL_COORD( bs->position.x - 1 ) ) == TT_OBSTACLE ) ) ||
                ( ( bs->dx < 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height - 1 ), PIXEL_TO_CELL_COORD( bs->position.x - 1 ) ) == TT_OBSTACLE ) ) ||
                // moving down:
                ( ( bs->dy > 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height ), PIXEL_TO_CELL_COORD( bs->position.x ) ) == TT_OBSTACLE ) ) ||
                ( ( bs->dy > 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y + bi->height ), PIXEL_TO_CELL_COORD( bs->position.x + bi->width - 1 ) ) == TT_OBSTACLE ) ) ||
                // moving up:
                ( ( bs->dy < 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y - 1 ), PIXEL_TO_CELL_COORD( bs->position.x ) ) == TT_OBSTACLE ) ) ||
                ( ( bs->dy < 0 ) && ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( bs->position.y - 1 ), PIXEL_TO_CELL_COORD( bs->position.x + bi->width - 1 ) ) == TT_OBSTACLE ) )
            ) { // then
            RESET_BULLET_FLAG( *bs, F_BULLET_ACTIVE );
            sprite_move_offscreen( bs->sprite );
            continue;
        }
        // adjust xmax, ymax and move sprite to new position
        bs->position.xmax = bs->position.x + bi->width - 1;
        bs->position.ymax = bs->position.y + bi->height - 1;
        sp1_MoveSprPix( bs->sprite, &game_area, bi->frames[0], bs->position.x, bs->position.y );

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
