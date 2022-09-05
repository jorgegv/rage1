////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <games/sp1.h>

#include "features.h"

#include "rage1/btile.h"

#include "game_data.h"

#include "rage1/banked.h"


#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP

// Accelerated functions for getting/setting tile types

uint8_t btile_get_tile_type( uint8_t row, uint8_t col ) {
    uint8_t pos = ( row * 32 + col ) / 4;
    uint8_t rot = 2 * ( col & 0x03 );
    return ( ( screen_pos_tile_type_data[ pos ] >> rot ) & 0x03 );
}

void btile_set_tile_type( uint8_t row, uint8_t col, uint8_t type ) {
    uint8_t pos = ( row * 32 + col ) / 4;
    uint8_t rot = 2 * ( col & 0x03 );
    screen_pos_tile_type_data[ pos ] = ( screen_pos_tile_type_data[ pos ] & ( ~( 0x03 << rot ) ) ) | ( type << rot );
}

#endif
