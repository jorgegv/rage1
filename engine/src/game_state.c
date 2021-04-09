////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/map.h"
#include "rage1/game_state.h"
#include "rage1/hero.h"
#include "rage1/inventory.h"
#include "rage1/controller.h"

#include "game_data.h"

/////////////////////////////////////
//
// Game functions
//
/////////////////////////////////////

// running game state
struct game_state_s game_state;

void game_state_reset_initial(void) {

   // set initial screen
   game_state.current_screen = MAP_INITIAL_SCREEN;

   // run ENTER_SCREEN hooks for the initial screen
   map_enter_screen( &map[ game_state.current_screen ] );

   // reset everything
   hero_reset_all();
   bullet_reset_all();
   inventory_reset_all();
   map_sprites_reset_all();
   game_state.enemies_alive = map_count_enemies_all();
   game_state.enemies_killed = 0;

   // reset all flags and set initial ones
   RESET_ALL_GAME_FLAGS();
   RESET_ALL_LOOP_FLAGS();
   RESET_ALL_USER_FLAGS();
   SET_GAME_FLAG( F_GAME_START );
}

// change to a new screen
// can't be used on game start!
// this function presumes a previous screen
void game_state_goto_screen(uint8_t screen) {

    // move all spritess and bullets off-screen
    sprite_move_offscreen_all( map[ game_state.current_screen ].sprite_data.num_sprites,
        map[ game_state.current_screen ].sprite_data.sprites );
    bullet_move_offscreen_all();

    // run EXIT_SCREEN hooks for the old screen
    map_exit_screen( &map[ game_state.current_screen ] );

    // update basic screen data
    game_state.previous_screen = game_state.current_screen;
    game_state.current_screen = screen;

    // run ENTER_SCREEN hooks for the new screen
    map_enter_screen( &map[ game_state.current_screen ] );

    // draw the hero in the new position
    hero_draw();

    // set flag
    SET_LOOP_FLAG( F_LOOP_ENTER_SCREEN );
}
