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

#include "features.h"

#include "rage1/btile.h"
#include "rage1/memory.h"
#include "rage1/debug.h"
#include "rage1/game_state.h"

#include "game_data.h"

#define SCREEN_MAX_ROW	23
#define SCREEN_MAX_COL	31
#define SCREEN_SIZE	( ( SCREEN_MAX_ROW + 1 ) * ( SCREEN_MAX_COL + 1 ) )

// when using a packed tile type map, we pack 4 tiles per byte
// if not, we use 1 byte per tile
#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
    #define TILE_TYPE_DATA_SIZE		( SCREEN_SIZE / 4 )
#else
    #define TILE_TYPE_DATA_SIZE		( SCREEN_SIZE )
#endif

// an array to store the type of the tile which is on each screen position
// TT_DECORATION, TT_OBSTACLE, ...
uint8_t screen_pos_tile_type_data[ TILE_TYPE_DATA_SIZE ];

// draw a given btile

// If we are using animated btiles, we include a generic function to display
// a given frame (btile_draw_frame), and a compatibility function
// (btile_draw) which just calls btile_draw_frame with frame number 0.  If
// animated btiles are not in use, we include an optimized version of
// btile_draw (the one that was used when animated btiles were not
// implemented)

#ifdef BUILD_FEATURE_ANIMATED_BTILES
void btile_draw_frame( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box, uint8_t num_frame ) {
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
#ifdef BUILD_FEATURE_GAMEAREA_COLOR_FULL
                sp1_PrintAtInv( r, c, b->frames[ num_frame ].attrs[ n ], (uint16_t)b->frames[ num_frame ].tiles[ n ] );
#else
                sp1_PrintAtInv( r, c, game_state.default_mono_attr, (uint16_t)b->frames[ num_frame ].tiles[ n ] );
#endif
                SET_TILE_TYPE_AT( r, c, type );
            }
        }
}

void btile_draw( uint8_t row, uint8_t col, struct btile_s *b, uint8_t type, struct sp1_Rect *box ) {
    btile_draw_frame( row, col, b, type, box, 0 );	// frame number 0 always exists
}

// we could move this function to the upper bank: we would then need to
// handle it like sprite animation, with a new flag BTILE_NEED_REDRAW so
// that animation calculations happen in upper memory and redrawing happens
// afterwards in low memory.  This function is small so for now it's not too
// interesting to do it, but may be it is in the future

void btile_animate_all( void ) {
    uint8_t btile_pos_id;
    uint16_t btile_id;
    uint8_t max_frames,num_frame;
    struct btile_pos_s *btile_pos;
    struct btile_s *btile;
    struct animation_data_s *anim;

    uint16_t i = game_state.current_screen_ptr->animated_btile_data.num_btiles;
    while ( i-- ) {
        btile_pos_id = game_state.current_screen_ptr->animated_btile_data.btiles[ i ].btile_pos_id;
        btile_id = game_state.current_screen_ptr->animated_btile_data.btiles[ i ].btile_id;
        btile_pos = &game_state.current_screen_ptr->btile_data.btiles_pos[ btile_pos_id ];

        // if the btile has state and is NOT active, skip quickly
        if ( ( btile_pos->state_index != ASSET_NO_STATE ) &&
            ! IS_BTILE_ACTIVE( all_screen_asset_state_tables[ game_state.current_screen_ptr->global_screen_num ].states[ btile_pos->state_index ].asset_state ) )
            continue;

        // we animate if there is no state ( no state = always active ), or if the btile is active

        anim = &game_state.current_screen_ptr->animated_btile_data.btiles[ i ].anim;
        max_frames = dataset_get_banked_btile_ptr( btile_id )->sequences[ anim->current.sequence ].num_frames;

        // animation_sequence_tick returns 1 if a frame change is needed, 0 if not
        if ( animation_sequence_tick( anim, max_frames ) ) {
            btile = dataset_get_banked_btile_ptr( btile_id );
            num_frame = btile->sequences[ anim->current.sequence ].frame_numbers[ anim->current.sequence_counter ];
            btile_draw_frame( btile_pos->row, btile_pos->col, btile, btile_pos->type, &game_area, num_frame );
        }
    }
}

#else // BUILD_FEATURE_ANIMATED_BTILES not defined

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
#ifdef BUILD_FEATURE_GAMEAREA_COLOR_FULL
                sp1_PrintAtInv( r, c, b->attrs[n], (uint16_t)b->tiles[n] );
#else
                sp1_PrintAtInv( r, c, game_state.default_mono_attr, (uint16_t)b->tiles[n] );
#endif
                SET_TILE_TYPE_AT( r, c, type );
            }
        }
}

#endif // BUILD_FEATURE_ANIMATED_BTILES

void btile_remove( uint8_t row, uint8_t col, struct btile_s *b ) {
    uint8_t dr, dc, rmax, cmax;

    rmax = b->num_rows;
    cmax = b->num_cols;
    for ( dr = 0; dr < rmax; ++dr )
        for ( dc = 0; dc < cmax; ++dc ) {
            sp1_PrintAtInv( row + dr, col + dc, DEFAULT_BG_ATTR, ' ' );
            SET_TILE_TYPE_AT( row + dr, col + dc, TT_DECORATION );
        }
}

// clears tile type array
void btile_clear_type_all_screen(void) {
    uint16_t i = TILE_TYPE_DATA_SIZE;
    while ( i-- ) screen_pos_tile_type_data[ i ] = 0;
    // When using a packed tile type map, TT_DECORATION(=0) in all 4 positions
    // When not, TT_DECORATION as well
}

#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
    #define TYPE_MAP_BTILE_BITS 2
    #define TYPE_MAP_BTILES_PER_BYTE 4
    #define TYPE_MAP_BTILE_LOW_BITS_MASK 0x03
#endif

#ifdef BUILD_FEATURE_BTILE_2BIT_TYPE_MAP
// Accelerated functions for getting/setting tile types
uint8_t btile_get_tile_type( uint8_t row, uint8_t col ) {
    uint8_t pos = ( row * 32 + col ) / TYPE_MAP_BTILES_PER_BYTE;
    uint8_t rot = TYPE_MAP_BTILE_BITS * ( col & TYPE_MAP_BTILE_LOW_BITS_MASK );
    return ( ( screen_pos_tile_type_data[ pos ] >> rot ) & TYPE_MAP_BTILE_LOW_BITS_MASK );
}

void btile_set_tile_type( uint8_t row, uint8_t col, uint8_t type ) {
    uint8_t pos = ( row * 32 + col ) / TYPE_MAP_BTILES_PER_BYTE;
    uint8_t rot = TYPE_MAP_BTILE_BITS * ( col & TYPE_MAP_BTILE_LOW_BITS_MASK );
    screen_pos_tile_type_data[ pos ] = ( screen_pos_tile_type_data[ pos ] & ( ~( TYPE_MAP_BTILE_LOW_BITS_MASK << rot ) ) ) | ( type << rot );
}
#endif
