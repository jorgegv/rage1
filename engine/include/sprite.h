////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _SPRITES_H
#define _SPRITES_H

#include <stdint.h>

#include "map.h"
#include "util.h"

// structs for storing a single sprite's data on a screen
struct  sprite_animation_data_s {
    uint8_t num_frames;		// number of frames for this sprite
    uint8_t **frames;		// array of ptrs to sprite frames (SP1 layout)
    uint8_t delay;		// frames are rotated every 'delay' calls
    uint8_t current_frame;	// current sprite frame
    uint8_t delay_counter;	// current frame delay counter
};

struct  position_data_s {
    uint8_t x,y;		// current sprite position
    uint8_t xmax,ymax;		// current sprite bottom right coords
};

#define SPRITE_MOVE_LINEAR		0x00
struct  sprite_movement_data_s {
    uint8_t type;			// LINEAR, etc.
    uint8_t delay;			// dx,dy are added every 'delay' calls
    uint8_t delay_counter;		// current movement delay counter
    union {				// this union must be the last struct component
        struct {
            uint8_t xmin,xmax;		// sprite moves bouncing in a rectangle
            uint8_t ymin,ymax;		// (xmin,ymin)-(xmax,ymax)
            int8_t dx,dy;		// current position increments
            uint8_t initx,inity;	// reset positions
            int8_t initdx,initdy;	// reset increments
        } linear;
    } data;
};

struct sprite_info_s {
    struct sp1_ss *sprite;				// ptr to SP1 sprite struct
    uint8_t width,height;				// dimensions in pixels ( rows,cols * 8 )
    struct sprite_animation_data_s animation;		// sprite animation data
    struct position_data_s position;		// sprite position data
    struct sprite_movement_data_s movement;		// sprite movement data
    uint16_t flags;					// flags
};

// sprite flags macros and definitions
#define GET_SPRITE_FLAG(s,f)	( (s).flags & (f) )
#define SET_SPRITE_FLAG(s,f)	( (s).flags |= (f) )
#define RESET_SPRITE_FLAG(s,f)	( (s).flags &= ~(f) )

#define F_SPRITE_ACTIVE	0x0001
#define F_SPRITE_BOUNCE	0x0002

#define IS_SPRITE_ACTIVE(s)	(GET_SPRITE_FLAG((s),F_SPRITE_ACTIVE))
#define SPRITE_MUST_BOUNCE(s)	(GET_SPRITE_FLAG((s),F_SPRITE_BOUNCE))

// sets all sprites in a sprite set to initial positions and frames
void sprite_reset_position_all( uint8_t num_sprites, struct sprite_info_s *sprites );

// animates and moves all sprites in a sprite set according to their rules
void sprite_animate_and_move_all( uint8_t num_sprites, struct sprite_info_s *sprites );

// move sprite off screen
void sprite_move_offscreen( struct sp1_ss *s );
void sprite_move_offscreen_all( uint8_t num_sprites, struct sprite_info_s *sprites );

// callback function and static params to set a sprite attributes
struct attr_param_s {
    uint8_t attr;
    uint8_t attr_mask;
};

extern struct attr_param_s sprite_attr_param;
void sprite_set_cell_attributes( uint16_t count, struct sp1_cs *c );

#endif // _SPRITES_H
