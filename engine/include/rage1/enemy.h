////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _ENEMY_H
#define _ENEMY_H

#include "rage1/sprite.h"
#include "rage1/types.h"

#define ENEMY_MOVE_LINEAR		0x00
struct  enemy_movement_data_s {
    uint8_t type;			// LINEAR, etc.
    uint8_t delay;			// dx,dy are added every 'delay' calls
    uint8_t delay_counter;		// current movement delay counter
    union {				// this union must be the last struct component
        struct {
            uint8_t xmin,xmax;		// enemy moves bouncing in a rectangle
            uint8_t ymin,ymax;		// (xmin,ymin)-(xmax,ymax)
            int8_t dx,dy;		// current position increments
            uint8_t initx,inity;	// reset positions
            int8_t initdx,initdy;	// reset increments
        } linear;
    } data;
};

struct enemy_info_s {
    struct sp1_ss *sprite;				// ptr to SP1 sprite struct
    uint8_t width,height;				// dimensions in pixels ( rows,cols * 8 )
    struct sprite_animation_data_s animation;		// sprite animation data
    struct position_data_s position;			// enemy position data
    struct enemy_movement_data_s movement;		// enemy movement data
    uint16_t flags;					// flags
};

// enemy flags macros and definitions
#define GET_ENEMY_FLAG(s,f)	( (s).flags & (f) )
#define SET_ENEMY_FLAG(s,f)	( (s).flags |= (f) )
#define RESET_ENEMY_FLAG(s,f)	( (s).flags &= ~(f) )

#define F_ENEMY_ACTIVE	0x0001
#define F_ENEMY_BOUNCE	0x0002

#define IS_ENEMY_ACTIVE(s)	(GET_ENEMY_FLAG((s),F_ENEMY_ACTIVE))
#define ENEMY_MUST_BOUNCE(s)	(GET_ENEMY_FLAG((s),F_ENEMY_BOUNCE))

// sets all enemies in a enemy set to initial positions and frames
void enemy_reset_position_all( uint8_t num_enemies, struct enemy_info_s *enemies );

// animates and moves all enemies in a enemy set according to their rules
void enemy_animate_and_move_all( uint8_t num_enemies, struct enemy_info_s *enemies );

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies );

#endif // _ENEMY_H
