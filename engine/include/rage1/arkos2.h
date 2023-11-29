////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _ARKOS2_H
#define _ARKOS2_H

// Tracker declarations that are specific for Arkos2 player

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

// Arkos C prototypes
void ply_akg_init( void *song, uint16_t subsong ) __z88dk_callee;
void ply_akg_play( void );
void ply_akg_stop( void );
void ply_akg_initsoundeffects( void *effects_table[] ) __z88dk_fastcall;
void ply_akg_playsoundeffect( uint16_t effect, uint16_t channel, uint16_t inv_volume ) __z88dk_callee;

// this subsong will be used always
#define DEFAULT_SUBSONG	0

#endif // _ARKOS2_H
