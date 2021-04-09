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
    if (    ( x >= CELL_TO_PIXEL_COORD( h->col ) 		) &&
            ( x <  CELL_TO_PIXEL_COORD( h->col + h->width ) 	) &&
            ( y >= CELL_TO_PIXEL_COORD( h->row ) 		) &&
            ( y <  CELL_TO_PIXEL_COORD( h->row + h->height ) 	)
        )
        return 1;
    else
        return 0;
}
