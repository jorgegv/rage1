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

#include <stdint.h>

#include "features.h"

#include "rage1/types.h"

#define PIXEL_TO_CELL_COORD(a)		( pixel_to_cell_coord( (a) ) )
#define CELL_TO_PIXEL_COORD(a)		( cell_to_pixel_coord( (a) ) )

// On CPC the horizontal pixel range is 0..319, so the pixel<->cell helpers
// must accept/return a 16-bit pixel coordinate (the cell index stays <= 39 so
// it fits in 8 bits, but cell_to_pixel can return up to 312).  ZX keeps the
// historical uint8_t signatures for byte-identical codegen.
#ifdef RAGE1_FEATURE_WIDE_POSITION_COORDS
extern uint8_t   pixel_to_cell_coord( pos_int_t a ) __z88dk_fastcall;
extern pos_int_t cell_to_pixel_coord( uint8_t a ) __z88dk_fastcall;
#else
extern uint8_t pixel_to_cell_coord( uint8_t a ) __z88dk_fastcall;
extern uint8_t cell_to_pixel_coord( uint8_t a ) __z88dk_fastcall;
#endif

#endif //_UTIL_H
