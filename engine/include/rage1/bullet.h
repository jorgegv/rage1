////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _BULLET_H
#define _BULLET_H

#include <stdint.h>
#include <games/sp1.h>

#include "features.h"

#include "rage1/types.h"
#include "rage1/sprite.h"

struct bullet_movement_data_s {
    int8_t dx,dy;	// position increments, absolute
    uint8_t delay;	// frames between position updates (inv of speed)
};

struct bullet_state_data_s {
    struct sp1_ss *sprite;
    struct position_data_s position;
    int8_t dx, dy;		// current x and y increments
    uint8_t delay_counter;	// current delay counter
    uint8_t *frame;		// frame data for this bullet
    uint8_t flags;
};
extern struct bullet_state_data_s bullet_state_data[];

struct bullet_info_s {
    uint8_t width, height;
    uint8_t **frames;
    struct bullet_movement_data_s movement;
    struct bullet_state_data_s *bullets;
    uint8_t active_bullets;
    uint8_t reload_delay;
    uint8_t reloading;
#ifndef BUILD_FEATURE_HERO_WEAPON_AUTOFIRE
    uint8_t firing;
#endif
};

// bullet initialization
void init_bullets( void );
void bullet_init_sprites( void );

// call this when the hero has pressed fire
void bullet_add( void );
// move all shot sprites
void bullet_animate_and_move_all(void);
// reset all shots
void bullet_reset_all(void);
void bullet_move_offscreen_all(void);
//redraw
void bullet_redraw_all( void );

// flags macros and definitions
#define GET_BULLET_FLAG(s,f)		( (s).flags & (f) )
#define SET_BULLET_FLAG(s,f)		( (s).flags |= (f) )
#define RESET_BULLET_FLAG(s,f)		( (s).flags &= ~(f) )

#define F_BULLET_ACTIVE		0x01
#define F_BULLET_NEEDS_REDRAW	0x02
#define F_BULLET_MOVE_OFFSCREEN	0x04

#define IS_BULLET_ACTIVE(s)		(GET_BULLET_FLAG((s),F_BULLET_ACTIVE))
#define BULLET_NEEDS_REDRAW(s)		(GET_BULLET_FLAG((s),F_BULLET_NEEDS_REDRAW))
#define BULLET_MOVE_OFFSCREEN(s)	(GET_BULLET_FLAG((s),F_BULLET_MOVE_OFFSCREEN))

#endif // _BULLET_H
