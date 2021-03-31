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

#include "rage1.h"

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
         map_draw_screen( &map[ game_state.current_screen ] );
         sprite_reset_position_all( 
            map[ game_state.current_screen ].sprite_data.num_sprites, 
            map[ game_state.current_screen ].sprite_data.sprites
         );
         bullet_reset_all();
         RESET_GAME_FLAG( F_GAME_START );
      }

      // check if player has died
      if ( GET_LOOP_FLAG( F_LOOP_HERO_HIT ) ) {
         beep_fx( SOUND_HERO_DIED );
         if ( ! --game_state.hero.num_lives )
            SET_GAME_FLAG( F_GAME_OVER );
         else {
            sprite_reset_position_all(
               map[ game_state.current_screen ].sprite_data.num_sprites, 
               map[ game_state.current_screen ].sprite_data.sprites
            );
            hero_reset_position();
            bullet_reset_all();
            hero_update_lives_display();
            SET_HERO_FLAG( game_state.hero, F_HERO_ALIVE );
         }
      }

}

void move_sprites(void) {
   RUN_ONLY_ONCE_PER_FRAME;

   // move enemy sprites
   sprite_animate_and_move_all(
      map[ game_state.current_screen ].sprite_data.num_sprites, 
      map[ game_state.current_screen ].sprite_data.sprites
   );

   // move active shots
   bullet_animate_and_move_all();
}

void check_controller(void) {
   game_state.controller.state = controller_read_state();
}

void do_hero_actions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    hero_animate_and_move();
    hero_pickup_items();
    if ( game_state.controller.state & IN_STICK_FIRE )
        hero_shoot_bullet();
}

void check_collisions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    collision_check_hero_with_sprites();
    collision_check_bullets_with_sprites();
}

void check_hotzones(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    hero_check_if_inside_hotzones();
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
   inventory_show();

   // run user game initialization, if any
   if ( game_config.game_functions.run_user_game_init )
      game_config.game_functions.run_user_game_init();

   // run main game loop
   while ( ! ( GET_GAME_FLAG( F_GAME_OVER ) || GET_GAME_FLAG( F_GAME_END ) ) ) {

      // check if game has been paused (press 'y')
      check_game_pause();

      // reset all loop flags for a clear iteration
      RESET_ALL_LOOP_FLAGS();

      // check hotzones
      // changes game_state
      // hotzones need to be checked at the very beginning of the game loop,
      // because they can change the current screen, hero position, sprites, etc.
      check_hotzones();

      // update sprites
      // does not change game_state
      move_sprites();

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

      // check flow rules before the regular ones. We trust the user :-)
      check_flow_rules();

      // check game flags and react to conditions
      // changes game_state
      check_game_flags();

      // run user game loop function, if any
      if ( game_config.game_functions.run_user_game_loop )
         game_config.game_functions.run_user_game_loop();

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
   map_exit_screen( &map[ game_state.current_screen ] );

   // move all sprites off-screen:
   // hero
   sprite_move_offscreen( game_state.hero.sprite );
   // enemies
   sprite_move_offscreen_all( map[ game_state.current_screen ].sprite_data.num_sprites,
      map[ game_state.current_screen ].sprite_data.sprites );
   // bullets
   bullet_move_offscreen_all();

}

