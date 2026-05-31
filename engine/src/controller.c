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
   // KBD_DEFAULT_* are ASCII characters (e.g. 'Q'); we resolve them to
   // backend scancodes at boot. Per input.md §5 phase IN3-3 the spec
   // accepts one runtime input_lookup_key() per direction here as a
   // small trade-off for cross-platform default-key portability.
   game_state.controller.keys.up    = input_lookup_key( KBD_DEFAULT_UP    );
   game_state.controller.keys.down  = input_lookup_key( KBD_DEFAULT_DOWN  );
   game_state.controller.keys.left  = input_lookup_key( KBD_DEFAULT_LEFT  );
   game_state.controller.keys.right = input_lookup_key( KBD_DEFAULT_RIGHT );
   game_state.controller.keys.fire  = input_lookup_key( KBD_DEFAULT_FIRE  );
   // Default to keyboard control so input works out of the box. A game's
   // MENU function may still override this (e.g. a controller-select
   // screen), but a game with no MENU function no longer boots with a
   // dead controller: previously type stayed CTRL_TYPE_UNDEFINED (0),
   // which input_state_read() does not dispatch, so the hero could not
   // move at all (see games/minimal_audio_cpc regression).
   game_state.controller.type = CTRL_TYPE_KEYBOARD;
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
