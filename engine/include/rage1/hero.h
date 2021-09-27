////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _HERO_H
#define _HERO_H

#include <input.h>
#include <games/sp1.h>
#include <stdint.h>
#include <string.h>

#include "rage1/types.h"
#include "rage1/sprite.h"
#include "rage1/controller.h"

// animation data for the hero sprite
// there are 4 animation sequences, for up, down, left and right movements
// They may point to the same frame sets, of course
struct hero_animation_data_s {
    uint8_t sequence_up;	// frame sequences for all directions
    uint8_t sequence_down;
    uint8_t sequence_left;
    uint8_t sequence_right;
    uint8_t delay;		// frames are rotated every 'delay' calls
    uint8_t current_sequence;	// current sequence
    uint8_t current_frame;	// current sprite frame
    uint8_t delay_counter;	// current frame delay counter
    uint8_t *last_frame_ptr;	// last used frame
};

// movement data for the hero sprite
#define MOVE_NONE	0
#define MOVE_UP		IN_STICK_UP
#define MOVE_DOWN	IN_STICK_DOWN
#define MOVE_LEFT	IN_STICK_LEFT
#define MOVE_RIGHT	IN_STICK_RIGHT
#define MOVE_ALL	( MOVE_UP | MOVE_DOWN | MOVE_LEFT | MOVE_RIGHT )
struct hero_movement_data_s {
    uint8_t last_direction;
    uint8_t dx,dy;
};

struct hero_info_s {
    struct sp1_ss *sprite;                      // ptr to SP1 sprite struct
    uint8_t num_graphic;			// index in global sprite table
    struct hero_animation_data_s animation;	// animation data	
    struct position_data_s position;	// position data
    struct hero_movement_data_s movement;	// movement data
    uint8_t flags;				// flags
    uint8_t num_lives;				// lives
    uint8_t lives_btile_num;			// btile used to draw remaining lives
};

// a pre-filled hero_info_s struct for game reset
// generated by datagen.pl in game_data.c
extern struct hero_info_s hero_startup_data;
extern struct sp1_ss *hero_sprite;

// hero flags macros and definitions
#define GET_HERO_FLAG(s,f)	( (s).flags & (f) )
#define SET_HERO_FLAG(s,f)	( (s).flags |= (f) )
#define RESET_HERO_FLAG(s,f)	( (s).flags &= ~(f) )

#define F_HERO_ALIVE	0x0001

#define IS_HERO_ALIVE(s)	(GET_HERO_FLAG((s),F_HERO_ALIVE))

void init_hero(void);
void hero_reset_all(void);
void hero_reset_position(void);
void hero_animate_and_move( void );
void hero_shoot_bullet( void );
void hero_pickup_items(void);
void hero_update_lives_display(void);
void hero_draw(void);
void hero_set_position_x( struct hero_info_s *h, uint8_t x);
void hero_set_position_y( struct hero_info_s *h, uint8_t y);
void hero_move_offscreen(void);
void hero_init_sprites(void);

#endif // _HERO_H
