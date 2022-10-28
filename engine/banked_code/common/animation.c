////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "rage1/animation.h"

#include "game_data.h"

#include "rage1/banked.h"

void animation_sequence_tick( struct animation_data_s *anim, uint8_t max_frames ) {
    if ( anim->current.sequence_delay_counter ) {
        // sequence_delay_counter is active, animation is waiting for next cycle
        if ( ! --anim->current.sequence_delay_counter ) {
            // if it reaches 0, we have finished the wait period, so
            // reload the frame_delay_counter so that on the next
            // iteration we do the frame animation logic, and reset
            // animation to initial frame index
            anim->current.frame_delay_counter = anim->delay_data.frame_delay;
            anim->current.sequence_counter = 0;
        }
    } else {
        // sequence_delay_counter is 0, so frame_delay_counter must be
        // active, animation is animating frames
        if ( ! --anim->current.frame_delay_counter ) {
            // if it reaches 0, we have finished wait period between
            // animation frames, get next frame if possible

            // reload frame_delay_counter.  sequence_counter holds the
            // current frame index into the sequence
            anim->current.frame_delay_counter = anim->delay_data.frame_delay;

            // check for the next frame
            if ( ++anim->current.sequence_counter == max_frames ) {
                // there were no more frames, so restart sequence and go to sequence_delay loop
                anim->current.sequence_delay_counter = anim->delay_data.sequence_delay;
                anim->current.sequence_counter = 0;	// initial frame index
            }
        }
    }
}
