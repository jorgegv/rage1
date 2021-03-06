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

#include "rage1/btile.h"

#include "game_data.h"

#define SCREEN_MAX_ROW	23
#define SCREEN_MAX_COL	31
#define SCREEN_SIZE	( ( SCREEN_MAX_ROW + 1 ) * ( SCREEN_MAX_COL + 1 ) )

// an array to store the type of the tile which is on each screen position
// TT_DECORATION, TT_OBSTACLE, ...
uint8_t screen_pos_tile_type[ SCREEN_SIZE ];

// draw a given btile
void btile_draw( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box ) {
    static uint8_t dr, dc, r, c, n, rmax, cmax;
    static uint8_t brmin, brmax, bcmin, bcmax;

    brmin = box->row;
    bcmin = box->col;
    brmax = brmin + box->height - 1;
    bcmax = bcmin + box->width - 1;

    n = 0;	// tile counter
    rmax = b->num_rows;
    cmax = b->num_cols;
    for ( dr = 0; dr < rmax; ++dr )
        for ( dc = 0; dc < cmax; ++dc, ++n ) {
            r = row + dr;
            c = col + dc;
            if ( ( r >= brmin ) && ( r <= brmax ) && ( c >= bcmin ) && ( c <= bcmax ) )  {
                sp1_PrintAtInv( r, c, b->attrs[n], (uint16_t)b->tiles[n] );
                TILE_TYPE_AT( r, c ) = type;
            }
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
