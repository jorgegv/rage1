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
#include <stdint.h>

#include "features.h"

#include "game_data.h"

#include "rage1/banked.h"

// when using a packed tile type map, we pack more tiles per byte
// if not, we use 1 byte per tile
#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
    #define TILE_TYPE_TILE_BITS		2
    #define TILE_TYPE_TILES_PER_BYTE	4
    #define TILE_TYPE_TYPE_BITMASK	0x03
    #define TILE_TYPE_POSITION_BITMASK	0x03
#endif

#ifdef BUILD_FEATURE_BTILE_4BIT_TYPE_MAP
    #define TILE_TYPE_TILE_BITS		4
    #define TILE_TYPE_TILES_PER_BYTE	2
    #define TILE_TYPE_TYPE_BITMASK	0x0f
    #define TILE_TYPE_POSITION_BITMASK	0x01
#endif

#if ( defined( BUILD_FEATURE_BTILE_2BIT_TYPE_MAP ) || defined( BUILD_FEATURE_BTILE_4BIT_TYPE_MAP ) )
// Accelerated functions for getting/setting tile types
uint8_t btile_get_tile_type( uint8_t row, uint8_t col ) {
    uint8_t pos = ( row * 32 + col ) / TILE_TYPE_TILES_PER_BYTE;
    uint8_t rot = TILE_TYPE_TILE_BITS * ( col & TILE_TYPE_POSITION_BITMASK );
    return ( ( screen_pos_tile_type_data[ pos ] >> rot ) & TILE_TYPE_TYPE_BITMASK );
}

void btile_set_tile_type( uint8_t row, uint8_t col, uint8_t type ) {
    uint8_t pos = ( row * 32 + col ) / TILE_TYPE_TILES_PER_BYTE;
    uint8_t rot = TILE_TYPE_TILE_BITS * ( col & TILE_TYPE_POSITION_BITMASK );
    screen_pos_tile_type_data[ pos ] = ( screen_pos_tile_type_data[ pos ] & 
        ( ~( TILE_TYPE_TYPE_BITMASK << rot ) ) ) | ( type << rot );
}
#endif

#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
    #define TILE_TYPE_DATA_SIZE		( SCREEN_SIZE / 4 )
#endif

#ifdef BUILD_FEATURE_BTILE_4BIT_TYPE_MAP
    #define TILE_TYPE_DATA_SIZE		( SCREEN_SIZE / 2 )
#endif

#ifndef TILE_TYPE_DATA_SIZE
    #define TILE_TYPE_DATA_SIZE		( SCREEN_SIZE )
#endif

