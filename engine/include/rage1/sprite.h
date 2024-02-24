////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _SPRITE_H
#define _SPRITE_H

#include <stdint.h>
#include <games/sp1.h>

#include "rage1/animation.h"

#include "features.h"

//////////////////////////////////////////////////////////////////////////
// structs for storing a single copy of each sprite graphics in memory
//////////////////////////////////////////////////////////////////////////

// structs for storing a single sprite's data
struct  sprite_graphic_data_s {
    uint8_t width,height;               // dimensions in pixels ( rows,cols * 8 )
    // all frames for this sprite
    struct {
        uint8_t num_frames;             // number of frames for this sprite
        uint8_t **frames;               // ptr to array of ptrs to sprite frames (SP1 layout)
    } frame_data;
    // all animation sequences for this sprite
    struct {
        uint8_t num_sequences;
        struct animation_sequence_s *sequences;
    } sequence_data;
};

//////////////////////////////////////////////////////////////////////////
// utility functions and data structs
//////////////////////////////////////////////////////////////////////////

// move sprite off screen
void sprite_move_offscreen( struct sp1_ss *s ) __z88dk_fastcall;

// allocate/free a sprite
struct sp1_ss *sprite_allocate( uint8_t rows, uint8_t cols);
void sprite_free( struct sp1_ss *s ) __z88dk_fastcall;

// set a sprite color
void sprite_set_color( struct sp1_ss *s, uint8_t color );

// callback function and static params to set a sprite attributes
struct attr_param_s {
    uint8_t attr;
    uint8_t attr_mask;
};

//extern struct attr_param_s sprite_attr_param;
void sprite_set_cell_attributes( uint16_t count, struct sp1_cs *c );

#endif // _SPRITE_H
