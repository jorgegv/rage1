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

#include "features.h"

// Big tiles functions and definitions
// A big tile is an array of regular 8x8 char tiles, arranged in
// rectangular form. Array is in row form. Tiles can be either
// <256, for regular UDGs, or >=256 for address-specified ones

// struct for defining a big tile frame
struct btile_frame_s {
    uint8_t **tiles;
    uint8_t *attrs;
};

// struct for defining a big tile
struct btile_s {
    uint8_t num_rows,num_cols;
#ifdef BUILD_FEATURE_ANIMATED_BTILES
    uint8_t num_frames;
    struct btile_frame_s *frames;
    uint8_t num_sequences;
    struct animation_sequence_s *sequences;
#else
    uint8_t **tiles;
    uint8_t *attrs;
#endif
};

// struct for defining a tile's position on a given screen
struct btile_pos_s {
    uint8_t type;
    uint8_t row, col;
    uint8_t btile_id;			// index into the dataset btile table
    uint8_t state_index;		// index into screen asset state table
#ifdef BUILD_FEATURE_ANIMATED_BTILES
    struct animation_data_s *anim;	// animation state data
#endif
};

#ifdef BUILD_FEATURE_ANIMATED_BTILES
void btile_draw_frame( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box, uint8_t num_frame );
void btile_animate_all( void );
#endif

void btile_draw( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box );
void btile_remove( uint8_t row, uint8_t col, struct btile_s *b );

// tile types

// decoration: sprites pass through it
#define TT_DECORATION	0x00
// obstacle: sprites do not pass through
#define TT_OBSTACLE	0x01
// item: it can be grabbed by the hero, only one instance
#define TT_ITEM		0x02
// harmful: a decoration that kills you if you move over it
#define TT_HARMFUL	0x03
// crumb: it can be grabbed by the hero, multiple instances
// crumb type in lower 4 bits, so tile types 0x10 to 0x1F belong to crumbs
#define TT_CRUMB	0x10

// array which contains the btile type on each position of the screen
// also, macro for getting the btile type at a given screen position
extern uint8_t screen_pos_tile_type_data[];

#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
    #define GET_TILE_TYPE_AT(srow,scol)		( btile_get_tile_type( (srow), (scol) ) )
    #define SET_TILE_TYPE_AT(srow,scol,sval)	( btile_set_tile_type( (srow), (scol), (sval) ) )
#else
    #define GET_TILE_TYPE_AT(srow,scol)		( screen_pos_tile_type_data[ (srow) * 32 + (scol) ] )
    #define SET_TILE_TYPE_AT(srow,scol,sval)	( screen_pos_tile_type_data[ (srow) * 32 + (scol) ] = (sval) )
#endif

// Accelerated functions for getting/setting tile types
uint8_t btile_get_tile_type( uint8_t row, uint8_t col );
void btile_set_tile_type( uint8_t row, uint8_t col, uint8_t type );

void btile_clear_type_all_screen(void);

// btile flags macros and definitions
#define GET_BTILE_FLAG(s,f)	( (s) & (f) )
#define SET_BTILE_FLAG(s,f)	( (s) |= (f) )
#define RESET_BTILE_FLAG(s,f)	( (s) &= ~(f) )

#define F_BTILE_ACTIVE	0x0001

#define IS_BTILE_ACTIVE(s)	(GET_BTILE_FLAG((s),F_BTILE_ACTIVE))

#endif
