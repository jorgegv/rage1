////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "hotzone.h"
#include "util.h"
#include "game_state.h"
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

void hotzone_activate_all_endofgame_zones(void) {
    static uint8_t i,j;
    static struct hotzone_info_s *hzi;
    static struct map_screen_s *s;

    i = MAP_NUM_SCREENS;
    while ( i-- ) {
        s = &map[ i ];
        j = s->hotzone_data.num_hotzones;
        while ( j-- ) {
            hzi = &s->hotzone_data.hotzones[ j ];
            if ( hzi->type == HZ_TYPE_END_OF_GAME )
                SET_HOTZONE_FLAG( *hzi, F_HOTZONE_ACTIVE );
        }
    }
}

void hotzone_deactivate_all_endofgame_zones(void) {
    static uint8_t i,j;
    static struct hotzone_info_s *hzi;
    static struct map_screen_s *s;

    i = MAP_NUM_SCREENS;
    while ( i-- ) {
        s = &map[ i ];
        j = s->hotzone_data.num_hotzones;
        while ( j-- ) {
            hzi = &s->hotzone_data.hotzones[ j ];
            if ( hzi->type == HZ_TYPE_END_OF_GAME )
                RESET_HOTZONE_FLAG( *hzi, F_HOTZONE_ACTIVE );
        }
    }
}

