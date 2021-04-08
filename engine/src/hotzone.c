////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1.h"

uint8_t hotzone_is_inside( struct hotzone_info_s *h, uint8_t x, uint8_t y ) {
    if (    ( x >= h->x 		) &&
            ( x <  ( h->x + h->width ) 	) &&
            ( y >= h->y  		) &&
            ( y <  ( h->y + h->height )	)
        )
        return 1;
    else
        return 0;
}
