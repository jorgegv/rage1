////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// G7: ZX arch include routed through the platform shim (byte-identical on ZX,
// compiles under +cpc — see rage1/platform.h).
#include "rage1/platform.h"
#include <intrinsic.h>
#include <stdlib.h>

#include "rage1/input.h"
#include "rage1/gfx.h"
#include "rage1/game_state.h"
#include "rage1/interrupts.h"
#include "rage1/screen.h"
#include "rage1/audio.h"
#include "rage1/controller.h"
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
#include "rage1/timer.h"

#include "game_data.h"

void check_game_pause(void) {
   if ( controller_pause_key_pressed() ) {
      input_wait_nokey();
      while ( ! controller_pause_key_pressed() ) ;
      input_wait_nokey();
   }
}

void check_loop_flags( void ) {

    // update screen data if the player has entered new screen
    // also done whe game has just started
    if ( GET_GAME_FLAG( F_GAME_START ) ) {

       // draw screen and reset sprites
       map_draw_screen( game_state.current_screen_ptr );
       enemy_reset_position_all( 
          game_state.current_screen_ptr->enemy_data.num_enemies, 
          game_state.current_screen_ptr->enemy_data.enemies
       );

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
       bullet_reset_all();
#endif // BUILD_FEATURE_HERO_HAS_WEAPON

       // G8 (CPC direct-write renderer): map_draw_screen() just cleared the
       // game area (wiping the hero that hero_reset_position() drew), and the
       // hero is steady so the loop would not otherwise redraw it.  On the
       // ZX/SP1 backend the hero is a composited sprite LAYER and survives the
       // tile-layer clear, so no redraw is needed.  Request a hero redraw here
       // (handled by the F_LOOP_REDRAW_HERO branch immediately below, in this
       // same call — AFTER the screen has been drawn) so the hero is visible
       // on the first frame.  ZX is unaffected (guarded out — byte-identical).
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )
       SET_LOOP_FLAG( F_LOOP_REDRAW_HERO );
#endif

       RESET_GAME_FLAG( F_GAME_START );
    }

    // check if hero needs to be redrawn
    if ( GET_LOOP_FLAG( F_LOOP_REDRAW_HERO ) ) {
        hero_draw();
        // all loop flags are reset at the beginning of the game loop
    }

    // check if sound fx needs to be played
    if ( GET_LOOP_FLAG( F_LOOP_PLAY_BEEPER_FX ) ) {
        audio_sfx_beeper_play_pending();
        // all loop flags are reset at the beginning of the game loop
    }

#ifdef BUILD_FEATURE_AUDIO_SFX_TRACKER
    // check if tracker sound fx needs to be played
    if ( GET_LOOP_FLAG( F_LOOP_PLAY_TRACKER_FX ) ) {
        audio_sfx_tracker_play_pending();
        // all loop flags are reset at the beginning of the game loop
    }
#endif
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

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
void move_bullets(void) {
   RUN_ONLY_ONCE_PER_FRAME;

   // move active shots
   bullet_animate_and_move_all();

   // redraw bullets that have moved
   bullet_redraw_all();
}
#endif

void check_controller(void) {
   // Per-frame keyboard-state refresh. No-op on ZX (z88dk's in_stick_*
   // read the port synchronously every call); on CPC this calls
   // cpct_scanKeyboard() once per frame. Keeping the call site in
   // engine code now (Phase IN3-4) avoids a sweep when the CPC backend
   // lands. See doc/multiplatform-plan/input.md §3.3 input_scan.
   input_scan();
   game_state.controller.state = controller_read_state();
}

void do_hero_actions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    hero_animate_and_move();

#ifdef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
    hero_check_tiles_below();
#endif

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
    hero_shoot_bullet();
#endif

#ifdef BUILD_FEATURE_HERO_ADVANCED_DAMAGE_MODE
    hero_do_immunity_expiration();
#endif
}

void check_collisions(void) {
    RUN_ONLY_ONCE_PER_FRAME;

    collision_check_hero_with_sprites();
#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
    collision_check_bullets_with_sprites();
#endif // BUILD_FEATURE_HERO_HAS_WEAPON
}

#ifdef BUILD_FEATURE_ANIMATED_BTILES
void animate_btiles( void ) {
    RUN_ONLY_ONCE_PER_FRAME;
    btile_animate_all();
}
#endif

#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )
// CPC heartbeat: alternate a white filled-circle tile and a blank tile at the
// bottom-right of the game area, toggling on current_time.frame bit 3 (~6 Hz).
// On CPC there is no attribute RAM, so we can't blink by colour like the ZX does;
// instead we swap the tile GRAPHIC.  These are direct CPC mode-1 tile graphics:
// JSP_CELL_BYTES = 16 bytes per cell, COLUMN-MAJOR (the left byte-column's 8 pixel
// lines, then the right byte-column's 8 lines — see external/jsp/lib/cpc/
// jsp_screen.asm).  Each byte is mode-1 packed; a white pixel (pen 1, see
// gfx_jsp.c palette) sets the plane-0 bit in bits 7..4 (4 px/byte).  gfx_tile_put
// renders a tile id >= 256 — here the graphic's address — as a direct tile
// pointer, bypassing the (ZX-only) font table.  attr is inert on CPC.
static const uint8_t heartbeat_circle_tile[16] = {
    0x30, 0x70, 0xF0, 0xF0, 0xF0, 0xF0, 0x70, 0x30,   // left  byte-column, lines 0..7
    0xC0, 0xE0, 0xF0, 0xF0, 0xF0, 0xF0, 0xE0, 0xC0,   // right byte-column, lines 0..7
};
static const uint8_t heartbeat_blank_tile[16] = { 0 };

void show_heartbeat(void) {
    const uint8_t *tile = ( current_time.frame & 0x08 ) ? heartbeat_blank_tile
                                                        : heartbeat_circle_tile;
    gfx_tile_put( GAME_AREA_BOTTOM, GAME_AREA_RIGHT, GFX_DEFAULT_BG_ATTR, (gfx_tile_id_t) tile );
}
#else
void show_heartbeat(void) {
    if ( current_time.frame & 0x08 ) {
        gfx_tile_put(GAME_AREA_BOTTOM, GAME_AREA_RIGHT, GFX_DEFAULT_BG_ATTR, ' ');
    } else {
        gfx_tile_put(GAME_AREA_BOTTOM, GAME_AREA_RIGHT, GFX_ATTR(GFX_YELLOW, GFX_GREEN, 0, 0), ' ');
    }
}
#endif

// this one is not needed, this task is run from the ISR
// void run_music_tasks( void ) {
//    RUN_ONLY_ONCE_PER_FRAME;
//    audio_music_tick();
//}

void run_main_game_loop(void) {

   // seed PRNG. It is important that this is done here, after the menu has been run
   // and the controller has been selected. This involves the human user, and so
   // introduces a random factor in the frame and seconds counter, which are then
   // used to set the initial seed of the PRNG
   srand( ( current_time.sec << 8 ) | current_time.frame );

   // reset game vars and setup initial state
   game_state_reset_initial();
#ifdef BUILD_FEATURE_SCREEN_AREA_LIVES_AREA
   hero_update_lives_display();
#endif
#ifdef BUILD_FEATURE_HERO_ADVANCED_DAMAGE_MODE_USE_HEALTH_DISPLAY_FUNCTION
   HERO_HEALTH_DISPLAY_FUNCTION();
#endif

#ifdef BUILD_FEATURE_INVENTORY
   inventory_show();
#endif

#ifdef BUILD_FEATURE_AUDIO_MUSIC
   // start music
   // music is playing via interrupts
   audio_music_select_song( TRACKER_IN_GAME_SONG );
   audio_music_rewind();
   audio_music_start();
#endif

   // run user game initialization, if any
   run_game_function_user_game_init();

   // run main game loop
   while ( ! ( GET_GAME_FLAG( F_GAME_OVER ) || GET_GAME_FLAG( F_GAME_END ) ) ) {

#ifdef BUILD_FEATURE_GAME_TIME
      // update timers
      timer_update_all_timers();
#endif

      // check if game has been paused (press 'y')
      check_game_pause();

      // reset all loop flags and game events for a clear iteration
      RESET_ALL_LOOP_FLAGS();
      RESET_ALL_GAME_EVENTS();

      // check flow rules before the regular ones. We trust the user :-)

      // these must be run first, because they can change the current
      // screen, hero position, sprites, etc.
      // changes game_state
      check_flow_rules();

      // check_hotzones removed: they are now checked with flow_rules

      // update sprites
      // does not change game_state
      move_enemies();

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
      move_bullets();
#endif

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

      // run game events rule table
      check_game_event_rules();

      // run user game loop function, if any
      run_game_function_user_game_loop();


      // Loop flags are used as a way to defer code execution until the end
      // of the game loop.  Loop flags may be changed by enemy code, sprite
      // code, etc.  but crucially, by flow rule code (both in flow rules
      // and in event rules).  So this function should be called at the very
      // end of the game loop.

      // check loop flags and react to conditions.
      // changes game state
      check_loop_flags();

#ifdef BUILD_FEATURE_ANIMATED_BTILES
      animate_btiles();
#endif

      // CPC heartbeat indicator (debug liveness light): drawn just before the
      // screen update so it appears the same frame.  CPC-only so ZX builds are
      // byte-unchanged.
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )
      show_heartbeat();
#endif

      // update screen
      gfx_update();

      // do not add an intrinsic_halt() here - It will waste cycles.
      // if some of these previous functions do not need to be executed
      // continuously but e.g.  just once every frame, please use the
      // RUN_ONLY_ONCE_PER_FRAME macro at the very beginning of the
      // function.  See how it has been done e.g.  in move_sprites()
   }

   // end of main game loop
   // we reach here if game over or game finished successfully

   // cleanup

#ifdef BUILD_FEATURE_AUDIO_MUSIC
   // stop music
   audio_music_stop();
#endif

   // free sprites in the current screen
   map_exit_screen( game_state.current_screen_ptr );

   // move all moving things off-screen:
   hero_move_offscreen();
   enemy_move_offscreen_all(
      game_state.current_screen_ptr->enemy_data.num_enemies,
      game_state.current_screen_ptr->enemy_data.enemies
   );

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
   bullet_move_offscreen_all();
#endif // BUILD_FEATURE_HERO_HAS_WEAPON

}
