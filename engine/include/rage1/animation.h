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

void animation_sequence_tick( struct animation_data_s *anim, uint8_t max_frames );

#endif	// _ANIMATION_H
