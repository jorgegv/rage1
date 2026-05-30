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

#include "rage1/gfx.h"
#include "rage1/animation.h"

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

// move sprite off screen — legacy public name; permanent backwards-compat alias
// for gfx_sprite_park() (Phase G5 — gfx.md §G5-4).  Pure macro alias: it adds no
// second out-of-line body, so the only park function emitted is gfx_sprite_park().
#define sprite_move_offscreen(s)	gfx_sprite_park((s))

// free a sprite
void sprite_free( gfx_sprite_t *s ) __z88dk_fastcall;

// callback function and static params to set a sprite attributes
struct attr_param_s {
    uint8_t attr;
    uint8_t attr_mask;
};

#endif // _SPRITE_H
