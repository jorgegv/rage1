//////l//////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <input.h>

#include "features.h"

#include "rage1/memory.h"
#include "rage1/sp1engine.h"
#include "rage1/interrupts.h"
#include "rage1/controller.h"
#include "rage1/screen.h"
#include "rage1/game_loop.h"
#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/debug.h"
#include "rage1/dataset.h"
#include "rage1/codeset.h"
#include "rage1/charset.h"
#include "rage1/timer.h"

#include "rage1/banked.h"

#include "game_data.h"

void init_program(void) {

   // from this point, RAGE1 takes full control of the machine and memory
   init_memory();
   init_sp1();
   init_interrupts();
   init_datasets();

#ifdef	BUILD_FEATURE_CODESETS
   init_codesets();
#endif

#ifdef BUILD_FEATURE_ZX_TARGET_128
   // this must be called after datasets have been initialized
   init_banked_code();
#endif

   init_controllers();
   init_hero();

#ifdef BUILD_FEATURE_HERO_HAS_WEAPON
   init_bullets();
#endif

#ifdef BUILD_FEATURE_ZX_TARGET_128
   // this one is only needed when compiling for 128
   // for 48 mode the beepr gets initialized by regular BSS init code
   init_beeper();
#endif

#ifdef	BUILD_FEATURE_CUSTOM_CHARSET
   init_custom_charset();
#endif

#ifdef BUILD_FEATURE_GAME_TIME
   init_timer();
#endif
#ifdef BUILD_FEATURE_TRACKER
   init_tracker();
#endif
#ifdef BUILD_FEATURE_TRACKER_SOUNDFX
   init_tracker_sound_effects();
#endif

   // this must be called last
   interrupt_enable_periodic_isr_tasks();
}

void main(void)
{
#ifdef BUILD_FEATURE_LOADING_SCREEN_WAIT_ANY_KEY
   in_wait_key();
   in_wait_nokey();
#endif

   init_program();

   // run one-time initialization, if any
   run_game_function_user_init();
   while (1) {
      run_game_function_menu();
      run_game_function_intro();
      run_main_game_loop();
      if ( GET_GAME_FLAG( F_GAME_OVER ) ) {
         run_game_function_game_over();
      } else {
         run_game_function_game_end();
      }
   }
}
