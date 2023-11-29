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

#include "rage1/tracker.h"
#include "rage1/banked.h"
#include "rage1/interrupts.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_TRACKER_VT2

#include "rage1/vortex2.h"

void tracker_specific_init( void ) {
    // no special code for Vortex2
}

void tracker_specific_select_song( uint8_t song_id ) {
    ay_vt2_init( all_songs[ song_id ] );
}

void tracker_specific_start( void ) {
    ay_vt2_start();
}

void tracker_specific_stop( void ) {
    ay_vt2_stop();
}

void tracker_specific_rewind( void ) {
    ay_vt2_init( all_songs[ current_song ] );
}

void tracker_specific_do_periodic_tasks( void ) {
    ay_vt2_play();
}

// we need to do the following because Vortex is not supported by Z88DK when
// compiling for NEWLIB

// include the asm player
void vortex2_wrapper( void ) __naked {
__asm
    include "engine/banked_code/128/vortex2-player_asm.inc"
__endasm;
}

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

// Vortex2 does not support sound fx

#ifdef BUILD_FEATURE_TRACKER_SOUNDFX
  #error Vortex2 does not support Sound FX!
#endif

#endif // BUILD_FEATURE_TRACKER_VT2

