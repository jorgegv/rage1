////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "map.h"
#include "game_data.h"
#include "game_state.h"
#include "hero.h"
#include "inventory.h"
#include "controller.h"

/////////////////////////////////////
//
// Game functions
//
/////////////////////////////////////

// running game state
struct game_state_s game_state;

void game_state_reset_initial(void) {

   // current_screen.{row,col} are set by this function
   game_state_goto_screen( MAP_INITIAL_SCREEN );

   // reset everything
   hero_reset_all();
   bullet_reset_all();
   inventory_reset_all();
   map_sprites_reset_all();
   hotzone_deactivate_all_endofgame_zones();
   game_state.enemies_alive = map_count_enemies_all();

   // reset all flags and set initial ones
   RESET_ALL_GAME_FLAGS();
   RESET_ALL_LOOP_FLAGS();
   RESET_ALL_USER_FLAGS();
   SET_GAME_FLAG( F_GAME_START );
}

// change to a new screen
void game_state_goto_screen(uint8_t screen) {

    // move all spritess and bullets off-screen
    sprite_move_offscreen_all( map[ game_state.current_screen ].sprite_data.num_sprites,
        map[ game_state.current_screen ].sprite_data.sprites );
    bullet_move_offscreen_all();

    // update basic screen data
    game_state.previous_screen = game_state.current_screen;
    game_state.current_screen = screen;

    // set flag
    SET_LOOP_FLAG( F_LOOP_ENTER_SCREEN );
}
