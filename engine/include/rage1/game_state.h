////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _GAME_STATE_H
#define _GAME_STATE_H

//#include <spectrum.h>
#include <input.h>
#include <stdint.h>

#include "rage1/map.h"
#include "rage1/sprite.h"
#include "rage1/hero.h"
#include "rage1/bullet.h"
#include "rage1/inventory.h"

// a structure for holding the runtime state for an asset and its value at reset
// if this structure is ever changed, its size _must_ be a power of 2!
struct asset_state_s {
   uint8_t	asset_state;		// the runtime state for the asset
   uint8_t	asset_initial_state;	// the initial state for the asset at game reset
};

struct asset_state_table_s {
   uint8_t		num_states;
   struct asset_state_s	*states;
};

// table of asset state tables for each screen
extern struct asset_state_table_s all_screen_asset_state_tables[];

// resets state for all game assets in all screens
void game_state_assets_reset_all(void);

// definition for an offset value that means "NO STATE" for an asset
#define	ASSET_NO_STATE	(0xff)

// game state struct and related definitions
//  struct
struct game_state_s {

   // current, previous screen indexes in map table and some cached values
   uint8_t current_screen;
   uint8_t next_screen;
   struct map_screen_s *current_screen_ptr;

   // hero info and state
   struct hero_info_s hero;

   // bullets info and state
   struct bullet_info_s bullet;

   // game flags:
   //
   //   * flags: game indicators that are preserved during the game.  If a
   //     flag is set a here, it will be kept set during the whole game
   //
   //   * loop flags: game condition results.  They are set in the different
   //     game loop functions and reacted upon in a central place.  They are
   //     all reset at the end of the game loop
   //
   //   * user flags: they are checked and manipulated from FLOWGEN rules
   //
   uint8_t flags;
   uint8_t loop_flags;
   uint8_t user_flags;

   // controller data
   struct controller_info_s controller;

   // inventory data: grabbed items
   struct inventory_info_s inventory;

   // enemies left
   uint16_t enemies_alive;
   uint16_t enemies_killed;

};

extern struct game_state_s game_state;

// reset game state to initial state
void game_state_reset_initial(void);

// manage game state when moving to a new screen
void game_state_switch_to_next_screen( void );

///////////////////////////////////////////////
// game flags macros and definitions
///////////////////////////////////////////////

#define GET_GAME_FLAG(f)	(game_state.flags & (f))
#define SET_GAME_FLAG(f)	(game_state.flags |= (f))
#define RESET_GAME_FLAG(f)	(game_state.flags &= ~(f))
#define RESET_ALL_GAME_FLAGS()	(game_state.flags = 0)

// player has exhausted his lives
#define F_GAME_OVER			0x0001
// player has finished the game successfully
#define F_GAME_END			0x0002
// all items collected
#define F_GAME_GOT_ALL_ITEMS		0x0004
// all enemies killed
#define F_GAME_ALL_ENEMIES_KILLED	0x0008
// game has just started
#define F_GAME_START			0x0010

///////////////////////////////////////////////
// loop flags macros and definitions
///////////////////////////////////////////////

#define GET_LOOP_FLAG(f)	(game_state.loop_flags & (f))
#define SET_LOOP_FLAG(f)	(game_state.loop_flags |= (f))
#define RESET_LOOP_FLAG(f)	(game_state.loop_flags &= ~(f))
#define RESET_ALL_LOOP_FLAGS()	(game_state.loop_flags = 0)


// player has just entered a new screen
#define F_LOOP_ENTER_SCREEN		0x0001
// player has collided with a sprite
#define F_LOOP_HERO_HIT			0x0004
// inside EXIT hotzone
#define F_LOOP_WARP_TO_SCREEN		0x0008
// enemy was hit
#define F_LOOP_ENEMY_HIT		0x0010
// an item was picked up
#define F_LOOP_ITEM_GRABBED		0x0020

///////////////////////////////////////////////
// user flags macros and definitions
///////////////////////////////////////////////

#define GET_USER_FLAG(f)	(game_state.user_flags & (f))
#define SET_USER_FLAG(f)	(game_state.user_flags |= (f))
#define RESET_USER_FLAG(f)	(game_state.user_flags &= ~(f))
#define RESET_ALL_USER_FLAGS()	(game_state.user_flags = 0)


#endif // _GAME_STATE_H
