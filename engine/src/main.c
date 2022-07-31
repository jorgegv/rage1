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

#include "game_data.h"

void init_program(void) {
   init_memory();
   init_sp1();
   init_interrupts();
   init_datasets();
#ifdef	BUILD_FEATURE_CODESETS
   init_codesets();
#endif	// BUILD_FEATURE_CODESETS
   init_controllers();
   init_hero();
   init_bullets();
}

void main(void)
{
   init_program();

#ifdef BUILD_FEATURE_LOADING_SCREEN_WAIT_ANY_KEY
   in_wait_key();
   in_wait_nokey();
#endif

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
