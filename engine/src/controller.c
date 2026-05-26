////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/input.h"

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
   game_state.controller.type = 0;
}

uint8_t controller_read_state(void) {
   return input_state_read( game_state.controller.type, &game_state.controller.keys );
}

uint8_t controller_pause_key_pressed(void) {
   return input_key_pressed( INPUT_SCANCODE_PAUSE );
}

void controller_reset_all(void) {
   game_state.controller.type = CTRL_TYPE_UNDEFINED;
}
