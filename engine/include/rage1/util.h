////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _UTIL_H
#define _UTIL_H

#include "features.h"

#define PIXEL_TO_CELL_COORD(a)		( pixel_to_cell_coord( (a) ) )
#define CELL_TO_PIXEL_COORD(a)		( cell_to_pixel_coord( (a) ) )

extern uint8_t pixel_to_cell_coord( uint8_t a ) __z88dk_fastcall;
extern uint8_t cell_to_pixel_coord( uint8_t a ) __z88dk_fastcall;

#endif //_UTIL_H
