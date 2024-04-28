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

#include "rage1/util.h"

uint8_t pixel_to_cell_coord( uint8_t a ) __z88dk_fastcall {
    return a >> 3;
}

uint8_t cell_to_pixel_coord( uint8_t a ) __z88dk_fastcall {
    return a << 3;
}
