////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "features.h"

#include "rage1/sound.h"
#include "rage1/beeper.h"
#include "rage1/game_state.h"

#include "rage1/banked.h"

void sound_play_pending_fx( void ) {
    bit_beepfx( game_state.sound_fx );
}