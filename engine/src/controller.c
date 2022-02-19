////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <input.h>

#include "rage1/controller.h"
#include "rage1/game_state.h"
#include "rage1/debug.h"

/////////////////////////////////////
//
// Controller initialization
//
/////////////////////////////////////

void init_controllers(void) {
   game_state.controller.keys.up    = KBD_UP;
   game_state.controller.keys.down  = KBD_DOWN;
   game_state.controller.keys.left  = KBD_LEFT;
   game_state.controller.keys.right = KBD_RIGHT;
   game_state.controller.keys.fire  = KBD_FIRE;
   game_state.controller.pause_key  = KBD_PAUSE;
   game_state.controller.type = 0;
}

uint8_t controller_read_state(void) {
   switch ( game_state.controller.type ) {
      case CTRL_TYPE_KEYBOARD: return in_JoyKeyboard( &game_state.controller.keys );
      case CTRL_TYPE_KEMPSTON: return in_JoyKempston();
      case CTRL_TYPE_SINCLAIR1: return in_JoySinclair1();
   }
   return 0;
}

uint8_t controller_pause_key_pressed(void) {
   return in_KeyPressed( game_state.controller.pause_key );
}

void controller_reset_all(void) {
   game_state.controller.type = CTRL_TYPE_UNDEFINED;
}
