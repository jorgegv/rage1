////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/hotzone.h"
#include "rage1/util.h"
#include "rage1/game_state.h"

#include "game_data.h"

uint8_t hotzone_is_inside( struct hotzone_info_s *h, uint8_t x, uint8_t y ) {
    if (    ( x >= h->position.coords.u8.x_int	) &&
            ( x <= h->position.xmax 	) &&
            ( y >= h->position.coords.u8.y_int	) &&
            ( y <= h->position.ymax	)
        )
        return 1;
    else
        return 0;
}
