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

#include "btile.h"
#include "game_data.h"

// an array to store the type of the tile which is on each screen position
// TT_DECORATION, TT_OBSTACLE, ...
#define SCREEN_SIZE	(24*32)
uint8_t screen_pos_tile_type[ SCREEN_SIZE ];

// draw a given btile
void btile_draw( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type ) {
    static uint8_t dr, dc, n, rmax, cmax;

    n = 0;	// tile counter
    rmax = b->num_rows;
    cmax = b->num_cols;
    for ( dr = 0; dr < rmax; ++dr )
        for ( dc = 0; dc < cmax; ++dc, ++n ) {
            sp1_PrintAtInv( row + dr, col + dc, b->attrs[n], (uint16_t)b->tiles[n] );
            TILE_TYPE_AT( row + dr, col + dc ) = type;
        }
}

void btile_remove( uint8_t row, uint8_t col, struct btile_s *b ) {
    static uint8_t dr, dc, rmax, cmax;

    rmax = b->num_rows;
    cmax = b->num_cols;
    for ( dr = 0; dr < rmax; ++dr )
        for ( dc = 0; dc < cmax; ++dc ) {
            sp1_PrintAtInv( row + dr, col + dc, DEFAULT_BG_ATTR, ' ' );
            TILE_TYPE_AT( row + dr, col + dc ) = TT_DECORATION;
        }
}

// clears tile type array
void btile_clear_type_all_screen(void) {
    uint16_t i = SCREEN_SIZE;
    while ( i-- ) { screen_pos_tile_type[ i ] = TT_DECORATION; }
}
