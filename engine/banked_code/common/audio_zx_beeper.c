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
#include <sound/bit.h>

#include "features.h"

#include "rage1/game_state.h"

#include "rage1/banked.h"

#ifdef BUILD_FEATURE_ZX_TARGET_128
// this one is only needed when compiling for 128
// for 48 mode the beepr gets initialized by regular BSS init code
extern uint8_t _sound_bit_state;
void init_beeper( void ) {
    _sound_bit_state = 0;
}
#endif

void beeper_request_fx( void *sfx ) {
    game_state.beeper_fx = sfx;
    SET_LOOP_FLAG( F_LOOP_PLAY_BEEPER_FX );
}

void beeper_play_pending_fx( void ) {
    bit_beepfx( game_state.beeper_fx );
}

void beeper_play_fx( void *sfx ) {
    bit_beepfx( sfx );
}
