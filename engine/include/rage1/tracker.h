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

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

void init_tracker_sound_effects( void );
void tracker_play_fx( uint8_t effect_id );

#endif // _TRACKER_H
