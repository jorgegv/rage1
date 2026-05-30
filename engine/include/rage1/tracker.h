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

// On 128K builds these symbols are provided as banked-call macros from
// banked_function_defs.h (included via memory.h). When that header is
// pulled in *before* this one, the macros are already defined and the
// real prototypes must be suppressed to avoid "too many arguments to
// macro" errors. The #ifndef guards make this header order-independent
// while keeping the prototypes visible on builds where the function is
// a real linkable symbol (the banked-code build itself).

/////////////////////////////
// Tracker music functions
/////////////////////////////

#ifndef init_tracker
void init_tracker( void );
#endif
#ifndef tracker_select_song
void tracker_select_song( uint8_t song_id );
#endif
#ifndef tracker_start
void tracker_start( void );
#endif
#ifndef tracker_stop
void tracker_stop( void );
#endif
#ifndef tracker_do_periodic_tasks
void tracker_do_periodic_tasks( void );
#endif
#ifndef tracker_rewind
void tracker_rewind( void );
#endif

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

#ifndef init_tracker_sound_effects
void init_tracker_sound_effects( void );
#endif
#ifndef tracker_play_fx
void tracker_play_fx( uint8_t effect_id );
#endif
#ifndef tracker_request_fx
void tracker_request_fx( uint16_t fxid );
#endif
#ifndef tracker_play_pending_fx
void tracker_play_pending_fx( void );
#endif

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
