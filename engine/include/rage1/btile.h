////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _BTILE_H
#define _BTILE_H

#include <stdint.h>

// Big tiles functions and definitions
// A big tile is an array of regular 8x8 char tiles, arranged in
// rectangular form. Array is in row form. Tiles can be either
// <256, for regular UDGs, or >=256 for address-specified ones

// struct for defining a big tile
struct btile_s {
    uint8_t num_rows,num_cols;
    uint8_t **tiles;
    uint8_t *attrs;
};

// struct for defining a tile's position on a given screen
struct btile_pos_s {
    uint8_t type;
    uint8_t row, col;
    struct btile_s *btile;
    uint16_t flags;
};

void btile_draw( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box );
void btile_remove( uint8_t row, uint8_t col, struct btile_s *b );

// big tile types

// decoration: sprites pass through it
#define TT_DECORATION	0x00
// obstacle: sprites do not pass through
#define TT_OBSTACLE	0x01
// item: it can be grabbed by the hero
#define TT_ITEM		0x02

// array which contains the btile type on each position of the screen
// also, macro for getting the btile type at a given screen position
extern uint8_t screen_pos_tile_type[];
#define TILE_TYPE_AT(srow,scol)		( screen_pos_tile_type[ (srow) * 32 + (scol) ] )
void btile_clear_type_all_screen(void);

// btile flags macros and definitions
#define GET_BTILE_FLAG(s,f)	( (s).flags & (f) )
#define SET_BTILE_FLAG(s,f)	( (s).flags |= (f) )
#define RESET_BTILE_FLAG(s,f)	( (s).flags &= ~(f) )

#define F_BTILE_ACTIVE	0x0001

#define IS_BTILE_ACTIVE(s)	(GET_BTILE_FLAG((s),F_BTILE_ACTIVE))

#endif
