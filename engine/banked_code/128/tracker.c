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
#include "rage1/game_state.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_TRACKER

/////////////////////////////////////////////////////
// include the proper file for the tracker used

#ifdef BUILD_FEATURE_TRACKER_ARKOS2
  #include "rage1/arkos2.h"
#endif

#ifdef BUILD_FEATURE_TRACKER_VORTEX2
  #include "rage1/vortex2.h"
#endif

/////////////////////////////////////////////////////
/////////////////////////////////////////////////////

// muted flag - if 1, sound does not play
uint8_t muted;
uint8_t current_song = 255;	// invalid song

void init_tracker( void ) {
    tracker_specific_init();
    // tracker-independent initialization: sound muted, first song active
    muted = 1;
    tracker_select_song( 0 );
}

void tracker_select_song( uint8_t song_id ) {
    // do nothing if the required song is already the current one
    if ( current_song == song_id )
        return;
    current_song = song_id;

    uint8_t was_muted = muted;
    tracker_stop();
    tracker_specific_select_song( song_id );
    if ( ! was_muted )
        tracker_start();
}

void tracker_start( void ) {
    muted = 0;
    tracker_specific_start();
}

void tracker_stop( void ) {
    muted = 1;
    tracker_specific_stop();
}

void tracker_rewind( void ) {
    uint8_t was_muted = muted;
    tracker_stop();
    tracker_specific_rewind();
    if ( ! was_muted )
        tracker_start();
}

void tracker_do_periodic_tasks( void ) {
    // return immediately if we are muted
    if ( muted ) return;
    tracker_specific_do_periodic_tasks();
}

// songs table
// extern void *all_songs[] - generated externally

// sound effects table
// extern void *all_sound_effects[] - generated externally

#ifdef BUILD_FEATURE_TRACKER_SOUNDFX

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void init_tracker_sound_effects( void ) {
    tracker_specific_init_sound_effects();
}

void tracker_play_fx( uint8_t effect_id ) {
    // ignore if invalid effect id > TRACKER_SOUNDFX_NUM_EFFECTS
    // NOT zero-based!
    if ( effect_id > TRACKER_SOUNDFX_NUM_EFFECTS )
        return;
    tracker_specific_play_fx( effect_id );
}

void tracker_play_pending_fx( void ) {
    tracker_specific_play_fx( game_state.tracker_fx );
}

void tracker_request_fx( uint16_t fxid ) {
    game_state.tracker_fx = fxid;
    SET_LOOP_FLAG( F_LOOP_PLAY_TRACKER_FX );
}

#endif // BUILD_FEATURE_TRACKER_SOUNDFX
#endif // BUILD_FEATURE_TRACKER
