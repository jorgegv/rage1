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

#include "rage1/crumb.h"

#include "game_data.h"

void crumb_was_grabbed ( uint8_t type ) {
    all_crumb_types[ type ].counter++;
    if ( all_crumb_types[ type ].do_action != NULL )
        all_crumb_types[ type ].do_action( &all_crumb_types[ type ] );
}

void crumb_reset_all( void ) {
    uint8_t i = CRUMB_NUM_TYPES;
    while ( i-- ) {
        all_crumb_types[ i ].counter = 0;
    }
}
