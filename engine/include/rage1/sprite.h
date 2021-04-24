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

// structs for storing a single sprite's data on a screen
struct  sprite_animation_data_s {
    uint8_t num_frames;		// number of frames for this sprite
    uint8_t **frames;		// array of ptrs to sprite frames (SP1 layout)
    uint8_t delay;		// frames are rotated every 'delay' calls
    uint8_t current_frame;	// current sprite frame
    uint8_t delay_counter;	// current frame delay counter
};

// move sprite off screen
void sprite_move_offscreen( struct sp1_ss *s );

// callback function and static params to set a sprite attributes
struct attr_param_s {
    uint8_t attr;
    uint8_t attr_mask;
};

extern struct attr_param_s sprite_attr_param;
void sprite_set_cell_attributes( uint16_t count, struct sp1_cs *c );

#endif // _SPRITE_H
