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

#include "features.h"

#include "rage1/sprite.h"
#include "rage1/types.h"

#define ENEMY_MOVE_LINEAR		0x00
struct  enemy_movement_data_s {
    uint8_t type;				// LINEAR, etc.
    uint8_t delay;				// dx,dy are added every 'delay' calls
    uint8_t delay_counter;			// current movement delay counter
    union {					// this union must be the last struct component
        struct {
            uint8_t xmin,xmax;			// enemy moves bouncing in a rectangle
            uint8_t ymin,ymax;			// (xmin,ymin)-(xmax,ymax)
            int8_t dx,dy;			// current position increments
            uint8_t initx,inity;		// reset positions
            int8_t initdx,initdy;		// reset increments
            uint8_t sequence_a, sequence_b;	// sprite animation sequences (see FLAGS)
        } linear;
    } data;
    uint8_t flags;				// movement flags
};

struct enemy_info_s {
    struct sp1_ss *sprite;				// ptr to SP1 sprite struct
    uint8_t num_graphic;				// sprite graphics index
    uint8_t color;					// sprite color
    struct animation_data_s animation;			// sprite animation data
    struct position_data_s position;			// enemy position data
    struct enemy_movement_data_s movement;		// enemy movement data
    uint8_t state_index;				// index into screen asset state table
};

// enemy state macros and definitions
#define GET_ENEMY_FLAG(s,f)	( (s) & (f) )
#define SET_ENEMY_FLAG(s,f)	( (s) |= (f) )
#define RESET_ENEMY_FLAG(s,f)	( (s) &= ~(f) )

#define F_ENEMY_ACTIVE			0x01
#define F_ENEMY_NEEDS_REDRAW		0x02

#define IS_ENEMY_ACTIVE(s)			(GET_ENEMY_FLAG((s),F_ENEMY_ACTIVE))
#define ENEMY_NEEDS_REDRAW(s)			(GET_ENEMY_FLAG((s),F_ENEMY_NEEDS_REDRAW))

// enemy movement state flags
#define GET_ENEMY_MOVE_FLAG(s,f)	( (s).flags & (f) )
#define F_ENEMY_MOVE_BOUNCE			0x01
#define F_ENEMY_MOVE_CHANGE_SEQUENCE_VERT	0x02
#define F_ENEMY_MOVE_CHANGE_SEQUENCE_HORIZ	0x04

#define ENEMY_MOVE_MUST_BOUNCE(s)			(GET_ENEMY_MOVE_FLAG((s),F_ENEMY_MOVE_BOUNCE))
#define ENEMY_MOVE_CHANGES_SEQUENCE_VERT(s)		(GET_ENEMY_MOVE_FLAG((s),F_ENEMY_MOVE_CHANGE_SEQUENCE_VERT))
#define ENEMY_MOVE_CHANGES_SEQUENCE_HORIZ(s)		(GET_ENEMY_MOVE_FLAG((s),F_ENEMY_MOVE_CHANGE_SEQUENCE_HORIZ))

// sets all enemies in a enemy set to initial positions and frames
void enemy_reset_position_all( uint8_t num_enemies, struct enemy_info_s *enemies );

// animates and moves all enemies in the current screen according to their rules
void enemy_animate_and_move_all( void );
void enemy_animate_and_move( uint8_t num_enemies, struct enemy_info_s *enemies );

// redraws enemies if needed
void enemy_redraw_all( uint8_t num_enemies, struct enemy_info_s *enemies );

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies );

#endif // _ENEMY_H
