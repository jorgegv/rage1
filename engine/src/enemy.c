////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/zx.h>

#include "rage1/game_state.h"
#include "rage1/sprite.h"
#include "rage1/enemy.h"
#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/util.h"
#include "rage1/dataset.h"
#include "rage1/animation.h"

#include "rage1/memory.h"

#include "game_data.h"

void enemy_reset_position_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    struct enemy_info_s *e;
    struct sprite_graphic_data_s *g;
    uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// eficiency matters ;-)

        // we reset coordinates for all enemies, even those that are not
        // active (they may be activated later)

        g = dataset_get_banked_sprite_ptr( e->num_graphic );

        // reset enemy state to initial values

        // animation
        // e->animation.current.sequence is already assigned at data definition
        animation_reset_state( &e->animation );
        // position - update also xmax and ymax
        e->position.x = e->movement.data.linear.initx;
        e->position.y = e->movement.data.linear.inity;
        e->position.xmax = e->position.x + g->width - 1;
        e->position.ymax = e->position.y + g->height - 1;
        // movement
        e->movement.data.linear.dx = e->movement.data.linear.initdx;
        e->movement.data.linear.dy = e->movement.data.linear.initdy;

        // move enemy to initial position, only if it is active
        if ( IS_ENEMY_ACTIVE( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state ) )
            sp1_MoveSprPix( e->sprite, &game_area, g->frame_data.frames[0], e->position.x, e->position.y );
    }
}

// void enemy_animate_and_move_all( void )
// void enemy_animate_and_move_all( uint8_t num_enemies, struct enemy_info_s *enemies )
// both moved to banked_code

void enemy_redraw_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    uint8_t n;
    struct enemy_info_s *e;
    struct sprite_graphic_data_s *g;
    struct animation_data_s *anim;
    struct position_data_s *pos;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// efficiency matters ;-)
        if ( IS_ENEMY_ACTIVE( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state ) &&
            ( ENEMY_NEEDS_REDRAW( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state ) ) ) {

            // precalc some values
            g = dataset_get_banked_sprite_ptr( e->num_graphic );
            anim = &e->animation;
            pos = &e->position;

            // move/animate sprite into new position
            // sprite may need update either because of animation, movement, or both
            sp1_MoveSprPix( e->sprite, &game_area,
                g->frame_data.frames[ g->sequence_data.sequences[ anim->current.sequence ].frame_numbers[ anim->current.sequence_counter ] ],
                pos->x, pos->y );
            RESET_ENEMY_FLAG( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state, F_ENEMY_NEEDS_REDRAW );
        }
    }
}

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    uint8_t i;
    i = num_enemies;
    while ( i-- ) sprite_move_offscreen( enemies[i].sprite );
}

