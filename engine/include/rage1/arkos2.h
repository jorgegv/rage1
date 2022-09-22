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

// Arkos C prototypes
void ply_akg_init( void *song, unsigned int subsong ) __z88dk_callee;
void ply_akg_play( void );
void ply_akg_stop( void );
void ply_akg_initsoundeffects( void *effects_table[] ) __z88dk_fastcall;
void ply_akg_playsoundeffect( unsigned int effect ) __z88dk_fastcall;

// songs table
extern void *all_songs[];

// sound effects table
extern void *all_sound_effects[];

// this subsong will be used always
#define DEFAULT_SUBSONG	0

#endif // _ARKOS2_H
