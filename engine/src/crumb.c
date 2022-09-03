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
    all_crumbs[ type ].counter++;
    if ( all_crumbs[ type ].do_action != NULL )
        all_crumbs[ type ].do_action();
}

void crumb_reset_all( void ) {
    uint8_t i = CRUMB_NUM_TYPES;
    while ( i-- ) {
        all_crumbs[ i ].counter = 0;
    }
}
