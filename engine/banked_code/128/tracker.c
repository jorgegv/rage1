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

#ifdef BUILD_FEATURE_TRACKER

#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    #include "rage1/arkos2.h"
#endif

// muted flag - if 1, sound does not play
uint8_t muted;
uint8_t current_song;

void init_tracker( void ) {
    // tracker-independent initialization: sound muted, first song active
    muted = 1;
    tracker_select_song( 0 );
    // tracker dependent code below
    // no special code for Arkos2
}

void tracker_select_song( uint8_t song_id ) {
    current_song = song_id;
    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_init( all_songs[ song_id ], DEFAULT_SUBSONG );
#endif
}

void tracker_start( void ) {
    muted = 0;
    // tracker dependent code below
    // no special code for Arkos2
}

void tracker_stop( void ) {
    muted = 1;
    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_stop();
#endif
}

void tracker_do_periodic_tasks( void ) {
    // return immediately if we are muted
    if ( muted ) return;
    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_play();
#endif
}

// Arkos2: songs table
// Arkos2: extern void *all_songs[] - generated externally

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void init_tracker_sound_effects( void ) {
    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_initsoundeffects( all_sound_effects );
#endif
}

void tracker_play_fx( uint8_t effect_id ) {
    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_playsoundeffect( effect_id );
#endif
}

// Arkos2: sound effects table
// Arkos2: extern void *all_sound_effects[] - generated externally

#endif // BUILD_FEATURE_TRACKER
