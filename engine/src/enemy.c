////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/zx/spectrum.h>

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
    static struct sprite_graphic_data_s *g;
    uint8_t n;

    n = num_enemies;
    while( n-- ) {
        // we reset coordinates for all enemies, even those that are not
        // active (they may be activated later)

        g = dataset_get_banked_sprite_ptr( enemies[n].num_graphic );

        // reset enemy state to initial values

        // animation
        // enemies[n].animation.current.sequence is already assigned at data definition
        animation_reset_state( &enemies[n].animation );
        // position - update also xmax and ymax
        enemies[n].position.x.part.integer = enemies[n].movement.data.linear.initx;
        enemies[n].position.y.part.integer = enemies[n].movement.data.linear.inity;
        enemies[n].position.x.part.fraction = 0;
        enemies[n].position.y.part.fraction = 0;
        enemies[n].position.xmax = enemies[n].position.x.part.integer + g->width - 1;
        enemies[n].position.ymax = enemies[n].position.y.part.integer + g->height - 1;
        // movement
        enemies[n].movement.data.linear.dx = enemies[n].movement.data.linear.initdx;
        enemies[n].movement.data.linear.dy = enemies[n].movement.data.linear.initdy;

        // move enemy to initial position, only if it is active
        if ( IS_ENEMY_ACTIVE( game_state.current_screen_asset_state_table_ptr[ enemies[n].state_index ].asset_state ) )
            sp1_MoveSprPix( enemies[n].sprite, &game_area, g->frame_data.frames[0], enemies[n].position.x.part.integer, enemies[n].position.y.part.integer );
    }
}

// void enemy_animate_and_move_all( void )
// void enemy_animate_and_move_all( uint8_t num_enemies, struct enemy_info_s *enemies )
// both moved to banked_code

void enemy_redraw_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    uint8_t n;
    static struct sprite_graphic_data_s *g;

    n = num_enemies;
    while( n-- ) {
        if ( IS_ENEMY_ACTIVE( game_state.current_screen_asset_state_table_ptr[ enemies[n].state_index ].asset_state ) &&
            ( ENEMY_NEEDS_REDRAW( game_state.current_screen_asset_state_table_ptr[ enemies[n].state_index ].asset_state ) ) ) {

            // precalc some values
            g = dataset_get_banked_sprite_ptr( enemies[n].num_graphic );

            // move/animate sprite into new position
            // sprite may need update either because of animation, movement, or both
            sp1_MoveSprPix( enemies[n].sprite, &game_area,
                g->frame_data.frames[ g->sequence_data.sequences[ enemies[n].animation.current.sequence ].frame_numbers[ enemies[n].animation.current.sequence_counter ] ],
                enemies[n].position.x.part.integer, enemies[n].position.y.part.integer );
            RESET_ENEMY_FLAG( game_state.current_screen_asset_state_table_ptr[ enemies[n].state_index ].asset_state, F_ENEMY_NEEDS_REDRAW );
        }
    }
}

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    uint8_t i;
    i = num_enemies;
    while ( i-- ) sprite_move_offscreen( enemies[i].sprite );
}

