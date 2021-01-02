////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "memory.h"
#include "sp1engine.h"
#include "interrupts.h"
#include "controller.h"
#include "game_data.h"
#include "screen.h"
#include "game_loop.h"
#include "hero.h"
#include "game_state.h"
#include "game_config.h"

#include "debug.h"

void init_program(void) {
   init_memory();
   init_sp1();
   init_interrupts();
   init_controllers();
   init_screen_sprite_tables();
   init_hero();
}


void main(void)
{
   init_program();

   // run one-time initialization, if any
   if ( game_config.game_functions.run_user_init )
      game_config.game_functions.run_user_init();

   while (1) {

      if ( game_config.game_functions.run_menu )
         game_config.game_functions.run_menu();

      if ( game_config.game_functions.run_intro )
         game_config.game_functions.run_intro();

      run_main_game_loop();

      if ( GET_GAME_FLAG( F_GAME_OVER ) ) {
         if ( game_config.game_functions.run_game_over )
            game_config.game_functions.run_game_over();
      } else {
         if ( game_config.game_functions.run_game_end )
            game_config.game_functions.run_game_end();
      }
   }
}
