////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _VORTEX2_H
#define _VORTEX2_H

#include <stdint.h>

// taken from Z88DK include/psg/vt2.h

extern void ay_vt2_init( uint8_t *song ) __z88dk_fastcall;
extern void ay_vt2_play( void );  // Called on interrupt, trashes main register + ix,iy
extern void ay_vt2_start( void ); // Setup to play song N
extern void ay_vt2_stop( void );  // Stop playing
extern void ay_vt2_mute( void );  // Mute playign

#endif // _VORTEX2_H
