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

#ifdef BUILD_FEATURE_MUSIC_TRACKER

// muted flag - if 1, sound does not play
uint8_t muted;
uint8_t current_song;

void tracker_init( void ) {
    // tracker-independent initialization: sound muted, first song active
    muted = 1;
    tracker_select_song( 0 );
    // tracker dependent code below
}

void tracker_select_song( uint8_t song_id ) {
    current_song = song_id;
    // tracker dependent code below
}

void tracker_start( void ) {
    muted = 0;
    // tracker dependent code below
}

void tracker_stop( void ) {
    muted = 1;
    // tracker dependent code below
}

void tracker_do_periodic_tasks( void ) {
    // return immediately if we are muted
    if ( muted ) return;
    // tracker dependent code below
}

// songs table
// extern void *all_songs[] - generated externally

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void tracker_init_sound_effects( void ) {
    // tracker dependent code below
}

void tracker_play_fx( uint8_t effect_id ) {
    // tracker dependent code below
}


// effects table
// extern void *all_sound_effects[] - generated externally

#endif // BUILD_FEATURE_MUSIC_TRACKER
