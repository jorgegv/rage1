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

#ifdef BUILD_FEATURE_TRACKER_ARKOS2

#include "rage1/arkos2.h"

void tracker_specific_init( void ) {
    // no special code for Arkos2
}

void tracker_specific_select_song( uint8_t song_id ) {
    ply_akg_init( all_songs[ song_id ], DEFAULT_SUBSONG );
}

void tracker_specific_start( void ) {
    // no special code for Arkos2
}

void tracker_specific_stop( void ) {
    ply_akg_stop();
}

void tracker_specific_rewind( void ) {
    ply_akg_init( all_songs[ current_song ], DEFAULT_SUBSONG );
}

void tracker_specific_do_periodic_tasks( void ) {
    // must be called with ints disabled!
    // if called from ISR, no need for EI/DI pair below!
    //intrinsic_di_if_needed();
    ply_akg_play();
    //intrinsic_ei_if_needed();
}

#ifdef BUILD_FEATURE_TRACKER_SOUNDFX

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void tracker_specific_init_sound_effects( void ) {
    ply_akg_initsoundeffects( all_sound_effects );
}

void tracker_specific_play_fx( uint8_t effect_id ) {
    // volume in arkos fx player is inverted: 0 -> max, 16 -> mute
    ply_akg_playsoundeffect( effect_id, TRACKER_SOUNDFX_CHANNEL, 16 - TRACKER_SOUNDFX_VOLUME );
}

// include the asm player
void wrapper( void ) __naked {
__asm
    include "engine/banked_code/128/arkos2-stubs_asm.inc"
    include "engine/banked_code/128/arkos2-player_asm.inc"
__endasm;
}

#endif // BUILD_FEATURE_TRACKER_SOUNDFX

#endif // BUILD_FEATURE_TRACKER_ARKOS2

