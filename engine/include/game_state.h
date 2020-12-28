////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _GAME_STATE_H
#define _GAME_STATE_H

//#include <spectrum.h>
#include <input.h>
#include <stdint.h>

#include "map.h"
#include "sprite.h"
#include "hero.h"
#include "bullet.h"
#include "inventory.h"

// game state struct and related definitions
//  struct
struct game_state_s {

   // current and previous screen indexes in map table
   uint8_t current_screen;
   uint8_t previous_screen;

   // hero info and state
   struct hero_info_s hero;

   // bullets info and state
   struct bullet_info_s bullet;

   // game flags, see below
   uint16_t flags;

   // user flags are checked and manipulated from flow rules
   uint16_t user_flags;

   // controller data
   struct controller_info_s controller;

   // inventory data: grabbed items
   struct inventory_info_s inventory;

   // enemies left
   uint16_t enemies_alive;
};

extern struct game_state_s game_state;

// reset game state to initial state
void game_state_reset_initial(void);

// manage game state when moving to a new screen
void game_state_goto_screen(uint8_t screen );

// game flags macros and definitions
#define GET_GAME_FLAG(f)	(game_state.flags & (f))
#define SET_GAME_FLAG(f)	(game_state.flags |= (f))
#define RESET_GAME_FLAG(f)	(game_state.flags &= ~(f))

// player has just entered a new screen
#define F_GAME_ENTER_SCREEN		0x0001
// player has exhausted his lives
#define F_GAME_OVER			0x0002
// player has finished the game successfully
#define F_GAME_END			0x0004
// player has collided with a sprite
#define F_GAME_PLAYER_DIED		0x0008
// game has just started
#define F_GAME_START			0x0010
// all items collected
#define F_GAME_GOT_ALL_ITEMS		0x0020
// inside EXIT hotzone
#define F_GAME_INSIDE_EXIT_ZONE		0x0040
// all enemies killed
#define F_GAME_ALL_ENEMIES_KILLED	0x0080

// user flags macros and definitions
#define GET_USER_FLAG(f)	(game_state.user_flags & (f))
#define SET_USER_FLAG(f)	(game_state.user_flags |= (f))
#define RESET_USER_FLAG(f)	(game_state.user_flags &= ~(f))

#endif // _GAME_STATE_H
