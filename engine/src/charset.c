////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// charset.c

#include <games/sp1.h>
#include <arch/spectrum.h>

#include "features.h"

#include "rage1/charset.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_CUSTOM_CHARSET

// pointer to custom character set: generated in game_data.c
uint8_t custom_charset[8] = { 0,1,2,3,4,5,6,7 };

// custom character set initialization function
void init_custom_charset( void ) {
    uint8_t offset = 0;
    uint8_t i;
    for ( i = CUSTOM_CHARSET_MIN_CHAR; i <= CUSTOM_CHARSET_MAX_CHAR; i++ ) {
        sp1_TileEntry( i, &custom_charset[ offset ] );
        offset += 8;
    }
}

#endif	// BUILD_FEATURE_CUSTOM_CHARSET

