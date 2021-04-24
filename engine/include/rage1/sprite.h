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

// an animation sequence is an array of frame numbers
// the frame numbers in a sequence are used to show the corresponding frame for the sprite
struct animation_sequence_s {
    uint8_t num_elements;              // number of elements in this sequence
    uint8_t *frame_numbers;            // ptr to array of sequence of frame numbers
};

// structs for storing a single sprite's data
struct  sprite_graphic_data_s {
    uint8_t width,height;               // dimensions in pixels ( rows,cols * 8 )
    // all frames for this sprite
    struct {
        uint8_t num_frames;             // number of frames for this sprite
        uint8_t **frames;               // ptr to array of ptrs to sprite frames (SP1 layout)
    } frame_data;
    struct {
        uint8_t num_sequences;
        struct animation_sequence_s *sequences;
    } sequence_data;
};
extern struct sprite_graphic_data_s all_sprite_graphics[];

struct  sprite_animation_data_s {
    struct {
        uint8_t frame_delay;		// frames are changed every 'frame_delay' calls
        uint8_t sequence_delay;		// a sequence is repeated after waiting 'sequence_delay' screen frames
    } delay_data;
    struct {
        uint8_t frame_delay_counter;	// current frame delay counter
        uint8_t sequence;		// current animation sequence
        uint8_t sequence_counter;	// current sequence index (used to get frame number)
        uint8_t sequence_delay_counter;	// current sequence delay counter
    } current;
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
