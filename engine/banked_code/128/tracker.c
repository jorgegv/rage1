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
#include <intrinsic.h>

#include "features.h"

#include "rage1/tracker.h"
#include "rage1/banked.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_TRACKER

#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    #include "rage1/arkos2.h"
#endif

// muted flag - if 1, sound does not play
uint8_t muted;
uint8_t current_song = 255;	// invalid song

void init_tracker( void ) {
    // tracker-independent initialization: sound muted, first song active
    muted = 1;
    tracker_select_song( 0 );

    // tracker dependent code below
    // no special code for Arkos2
}

void tracker_select_song( uint8_t song_id ) {
    // do nothing if the required song is already the current one
    if ( current_song == song_id )
        return;

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

void tracker_rewind( void ) {
    uint8_t was_muted = muted;
    tracker_stop();

    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    ply_akg_init( all_songs[ current_song ], DEFAULT_SUBSONG );
#endif

    // tracker independent code again
    if ( ! was_muted )
        tracker_start();
}

void tracker_do_periodic_tasks( void ) {
    // return immediately if we are muted
    if ( muted ) return;

    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    // must be called with ints disabled!
    // if called from ISR, no need for EI/DI pair below!
    //intrinsic_di();
    ply_akg_play();
    //intrinsic_ei();
#endif
}

// Arkos2: songs table
// Arkos2: extern void *all_songs[] - generated externally

#ifdef BUILD_FEATURE_TRACKER_SOUNDFX

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
    // ignore if invalid effect id - effect numbers are 1 .. TRACKER_SOUNDFX_NUM_EFFECTS
    // NOT zero-based!
    if ( ( ! effect_id ) || ( effect_id > TRACKER_SOUNDFX_NUM_EFFECTS ) )
        return;

    // tracker dependent code below
#ifdef BUILD_FEATURE_TRACKER_ARKOS2
    // volume in arkos fx player is inverted: 0 -> max, 16 -> min
    ply_akg_playsoundeffect( effect_id, TRACKER_SOUNDFX_CHANNEL, 16 - TRACKER_SOUNDFX_VOLUME );
#endif
}

// Arkos2: sound effects table
// Arkos2: extern void *all_sound_effects[] - generated externally

#endif // BUILD_FEATURE_TRACKER

#endif // BUILD_FEATURE_TRACKER_SOUNDFX
