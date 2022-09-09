////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <intrinsic.h>
#include <input.h>
#include <stdlib.h>

#include "features.h"

#include "rage1/game_state.h"
#include "rage1/interrupts.h"
#include "rage1/screen.h"
#include "rage1/sound.h"
#include "rage1/controller.h"
#include "rage1/sp1engine.h"
#include "rage1/sprite.h"
#include "rage1/collision.h"
#include "rage1/bullet.h"
#include "rage1/debug.h"
#include "rage1/btile.h"
#include "rage1/game_loop.h"
#include "rage1/flow.h"
#include "rage1/enemy.h"
#include "rage1/hero.h"
#include "rage1/dataset.h"
#include "rage1/codeset.h"
#include "rage1/memory.h"

#include "game_data.h"

void check_game_pause(void) {
   if ( controller_pause_key_pressed() ) {
      in_wait_nokey();
      while ( ! controller_pause_key_pressed() ) ;
      in_wait_nokey();
   }
}

void check_game_flags( void ) {

    // update screen data if the player has entered new screen
    // also done whe game has just started
    if ( GET_LOOP_FLAG( F_LOOP_ENTER_SCREEN ) || GET_GAME_FLAG( F_GAME_START )) {

       // draw screen and reset sprites
       map_draw_screen( game_state.current_screen_ptr );
       enemy_reset_position_all( 
          game_state.current_screen_ptr->enemy_data.num_enemies, 
          game_state.current_screen_ptr->enemy_data.enemies
       );
       bullet_reset_all();
       RESET_GAME_FLAG( F_GAME_START );
    }

    // check if player has been hit by an enemy
    if ( GET_LOOP_FLAG( F_LOOP_HERO_HIT ) ) {
     hero_handle_hit();
    }

    // check if hero needs to be redrawn
    if ( GET_LOOP_FLAG( F_LOOP_REDRAW_HERO ) ) {
        hero_draw();
        // all loop flags are reset at the beginning of the game loop
    }

    // check if sound fx needs to be played
    if ( GET_LOOP_FLAG( F_LOOP_PLAY_SOUNDFX ) ) {
        sound_play_pending_fx();
        // all loop flags are reset at the beginning of the game loop
    }
}

void move_enemies(void) {
   RUN_ONLY_ONCE_PER_FRAME;

   // move enemies
   enemy_animate_and_move_all();

   // redraw enemies that have changed position
   enemy_redraw_all(
      game_state.current_screen_ptr->enemy_data.num_enemies, 
      game_state.current_screen_ptr->enemy_data.enemies
   );
}

void move_bullets(void) {
   RUN_ONLY_ONCE_PER_FRAME;

   // move active shots
   bullet_animate_and_move_all();

   // redraw bullets that have moved
   bullet_redraw_all();
}

void check_controller(void) {
   game_state.controller.state = controller_read_state();
}

void do_hero_actions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    hero_animate_and_move();

#ifdef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
    hero_check_tiles_below();
#endif

    if ( game_state.controller.state & IN_STICK_FIRE )
        hero_shoot_bullet();

#ifdef BUILD_FEATURE_ADVANCED_DAMAGE_MODE
    if ( game_state.hero.health.immunity_timer )
        hero_do_immunity_expiration();
#endif
}

void check_collisions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    collision_check_hero_with_sprites();
    collision_check_bullets_with_sprites();
}

void show_heartbeat(void) {
    if ( current_time.frame & 0x08 ) {
        sp1_PrintAtInv(GAME_AREA_BOTTOM, GAME_AREA_RIGHT, DEFAULT_BG_ATTR, ' ');
    } else {
        sp1_PrintAtInv(GAME_AREA_BOTTOM, GAME_AREA_RIGHT, INK_YELLOW | PAPER_GREEN, ' ');
    }
}

void run_main_game_loop(void) {

   // seed PRNG. It is important that this is done here, after the menu has been run
   // and the controller has been selected. This involves the human user, and so
   // introduces a random factor in the frame and seconds counter, which are then
   // used to set the initial seed of the PRNG
   srand( ( current_time.sec << 8 ) | current_time.frame );

   // reset game vars and setup initial state
   game_state_reset_initial();
   hero_update_lives_display();

#ifdef BUILD_FEATURE_INVENTORY
   inventory_show();
#endif

   // run user game initialization, if any
   run_game_function_user_game_init();

   // run main game loop
   while ( ! ( GET_GAME_FLAG( F_GAME_OVER ) || GET_GAME_FLAG( F_GAME_END ) ) ) {

      // check if game has been paused (press 'y')
      check_game_pause();

      // reset all loop flags for a clear iteration
      RESET_ALL_LOOP_FLAGS();

      // check flow rules before the regular ones. We trust the user :-)

      // these must be run first, because they can change the current
      // screen, hero position, sprites, etc.
      // changes game_state
      check_flow_rules();

      // check_hotzones removed: they are now checked with flow_rules

      // update sprites
      // does not change game_state
      move_enemies();
      move_bullets();

      // read controller
      // changes game_state
      check_controller();

      // do all hero related actions: update main character position, shoot
      // bullets if fire pressed, grab nearby items
      // changes game_state
      do_hero_actions();

      // check collisions
      // changes game_state
      check_collisions();

      // check game flags and react to conditions
      // changes game_state
      check_game_flags();

      // run user game loop function, if any
      run_game_function_user_game_loop();

      // update screen
      sp1_UpdateNow();

      // do not add an intrinsic_halt() here - It will waste cycles.
      // if some of these previous functions do not need to be executed continuously
      // but e.g. just once every frame, please check the frame counter at
      // current_time.frame and ignore the call if needed. See how it has been
      // done in move_sprites()

      // test light just to be sure we did not hang
//      show_heartbeat();
   }

   // end of main game loop
   // we reach here if game over or game finished successfully

   // cleanup

   // free sprites in the current screen
   map_exit_screen( game_state.current_screen_ptr );

   // move all moving things off-screen:
   hero_move_offscreen();
   enemy_move_offscreen_all(
      game_state.current_screen_ptr->enemy_data.num_enemies,
      game_state.current_screen_ptr->enemy_data.enemies
   );
   bullet_move_offscreen_all();

}

