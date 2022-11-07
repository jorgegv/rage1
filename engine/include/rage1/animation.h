////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _ANIMATION_H
#define _ANIMATION_H

#include <stdint.h>

// an animation sequence is an array of frame numbers
// the frame numbers in a sequence are used to show the corresponding frame for the sprite
struct animation_sequence_s {
    uint8_t num_elements;              // number of elements in this sequence
    uint8_t *frame_numbers;            // ptr to array of sequence of frame numbers
};

//////////////////////////////////////////////////////////////////////////
// animation data structs which can be included in others (e.g. enemy, hero, etc.)
//////////////////////////////////////////////////////////////////////////

struct animation_data_s {
    struct {
        uint8_t frame_delay;		// frames are changed every 'frame_delay' calls
        uint8_t sequence_delay;		// a sequence is repeated after waiting 'sequence_delay' screen frames
    } delay_data;
    struct {
        uint8_t sequence;		// current animation sequence
        uint8_t sequence_counter;	// current sequence index (used to get frame number)
        uint8_t frame_delay_counter;	// current frame delay counter
        uint8_t sequence_delay_counter;	// current sequence delay counter
    } current;
};

uint8_t animation_sequence_tick( struct animation_data_s *anim, uint8_t max_frames );
void animation_set_sequence( struct animation_data_s *anim, uint8_t sequence );
void animation_reset_state( struct animation_data_s *anim );

#endif	// _ANIMATION_H
