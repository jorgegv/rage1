////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _TRACKER_H
#define _TRACKER_H

#include <stdint.h>

#include "features.h"

/////////////////////////////
// Tracker music functions
/////////////////////////////

void init_tracker( void );
void tracker_select_song( uint8_t song_id );
void tracker_start( void );
void tracker_stop( void );
void tracker_do_periodic_tasks( void );
void tracker_rewind( void );

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void init_tracker_sound_effects( void );
void tracker_play_fx( uint8_t effect_id );
void tracker_request_fx( uint16_t fxid );
void tracker_play_pending_fx( void );

// Songs and FX tables
extern void *all_songs[];
extern void *all_sound_effects[];

extern uint8_t muted;
extern uint8_t current_song;

////////////////////////////////////////////////////////////////////
// The following functions must be provided by any tracker that is
// integrated in RAGE1
////////////////////////////////////////////////////////////////////

void tracker_specific_init( void );
void tracker_specific_select_song( uint8_t song_id );
void tracker_specific_start( void );
void tracker_specific_stop( void );
void tracker_specific_do_periodic_tasks( void );
void tracker_specific_rewind( void );
void tracker_specific_init_sound_effects( void );
void tracker_specific_play_fx( uint8_t effect_id );

#endif // _TRACKER_H
