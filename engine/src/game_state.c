////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "features.h"

#include "rage1/map.h"
#include "rage1/game_state.h"
#include "rage1/hero.h"
#include "rage1/inventory.h"
#include "rage1/controller.h"
#include "rage1/dataset.h"
#include "rage1/timer.h"

#include "game_data.h"

/////////////////////////////////////
//
// Game state data
//
/////////////////////////////////////

// running game state
struct game_state_s game_state;

#ifdef BUILD_FEATURE_FLOW_VARS
uint8_t all_flow_vars[ GAME_NUM_FLOW_VARS ];
#endif

/////////////////////////////////////
//
// Game functions
//
/////////////////////////////////////

// aux functions
struct map_screen_s *get_current_screen_ptr( void ) {
    return &banked_assets->all_screens[ screen_dataset_map[ game_state.current_screen ].dataset_local_screen_num ];
}

struct asset_state_s *get_current_screen_asset_state_table_ptr( void ) {
    return &all_screen_asset_state_tables[ game_state.current_screen ].states[ 0 ];
}


void game_state_reset_initial(void) {

   // reset dataset_currently_active
   game_state.dataset_currently_active = NO_DATASET;

   // set initial screen
   game_state.current_screen = MAP_INITIAL_SCREEN;

   // run ENTER_SCREEN tasks for the initial screen
   map_enter_screen( game_state.current_screen );

   // game_state.current_screen_ptr must be updated here, not before. 
   // map_enter_screen might have switched datasets!
   game_state.current_screen_ptr = get_current_screen_ptr();
   game_state.current_screen_asset_state_table_ptr = get_current_screen_asset_state_table_ptr();

   // reset everything
   hero_reset_all();

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
   bullet_reset_all();
#endif

#ifdef BUILD_FEATURE_INVENTORY
   inventory_reset_all();
#endif

#ifdef BUILD_FEATURE_CRUMBS
   crumb_reset_all();
#endif

   game_state_assets_reset_all();

#ifdef BUILD_FEATURE_FLOW_VARS
   game_state_flow_vars_reset_all();
#endif

#ifdef BUILD_FEATURE_GAME_TIME
   timer_reset_all_timers();
#endif

   // Enemies tally
   game_state.enemies_alive = GAME_NUM_TOTAL_ENEMIES;
   game_state.enemies_killed = 0;

   // reset all flags and set initial ones
   RESET_ALL_GAME_FLAGS();
   RESET_ALL_LOOP_FLAGS();
   RESET_ALL_USER_FLAGS();
   SET_GAME_FLAG( F_GAME_START );
}

// change to a new screen
// can't be used on game start!
// this function presumes a next sreen is in game_state.warp_next_screen.num_screen
void game_state_switch_to_next_screen(void) {

    // move all enemies and bullets off-screen
    enemy_move_offscreen_all(
        game_state.current_screen_ptr->enemy_data.num_enemies,
        game_state.current_screen_ptr->enemy_data.enemies
    );

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
    bullet_move_offscreen_all();
#endif

    // run EXIT_SCREEN hooks for the old screen
    map_exit_screen( game_state.current_screen_ptr );

    // switch screen!
    // use the data in game_state.warp_next_screen to update everything: screen, hero pos, etc.
    game_state.current_screen = game_state.warp_next_screen.num_screen;
    hero_set_position_x( &game_state.hero, game_state.warp_next_screen.hero_x );
    hero_set_position_y( &game_state.hero, game_state.warp_next_screen.hero_y );

    // run ENTER_SCREEN tasks for the new screen
    map_enter_screen( game_state.current_screen );

    // game_state.current_screen_ptr must be updated here, not before. 
    // map_enter_screen might have switched datasets!
    game_state.current_screen_ptr = get_current_screen_ptr();
    game_state.current_screen_asset_state_table_ptr = get_current_screen_asset_state_table_ptr();

    // draw the hero in the new position
    hero_draw();

    // set flag
    SET_LOOP_FLAG( F_LOOP_ENTER_SCREEN );
}

void game_state_assets_reset_all(void) {
    uint8_t i,j;
    i = MAP_NUM_SCREENS;
    while ( i-- ) {
        j = all_screen_asset_state_tables[ i ].num_states;
        while ( j-- ) {
            all_screen_asset_state_tables[ i ].states[ j ].asset_state =
                all_screen_asset_state_tables[ i ].states[ j ].asset_initial_state;
        }
    }
}

#ifdef BUILD_FEATURE_FLOW_VARS
void game_state_flow_vars_reset_all(void) {
    uint8_t i;
    i = GAME_NUM_FLOW_VARS;
    while ( i-- ) all_flow_vars[ i ] = 0;
}
#endif
