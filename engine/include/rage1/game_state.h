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

#include <input.h>
#include <stdint.h>

#include "features.h"

#include "rage1/map.h"
#include "rage1/sprite.h"
#include "rage1/hero.h"
#include "rage1/bullet.h"
#include "rage1/inventory.h"

#include "game_data.h"

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

#ifdef BUILD_FEATURE_FLOW_VARS
// table of all flow vars
extern uint8_t all_flow_vars[];

// resets flow vars in all screens
void game_state_flow_vars_reset_all(void);
#endif

// definition for an offset value that means "NO STATE" for an asset
#define	ASSET_NO_STATE	(0xff)

// game state struct and related definitions
//  struct
struct game_state_s {

   // current, next screen indexes in map table and some cached values
   uint8_t current_screen;
   struct {
      uint8_t num_screen;
      uint8_t hero_x;
      uint8_t hero_y;
   } warp_next_screen;
   struct map_screen_s *current_screen_ptr;
   struct asset_state_s *current_screen_asset_state_table_ptr;

   // currently mapped dataset
   uint8_t active_dataset;

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
   //  * game_events: similar to loop flags but for actions that happen due
   //    to direct player interaction.  It is also reset at the end of the
   //    game loop
   //
   //   * user flags: they are checked and manipulated from FLOWGEN rules
   //
   uint8_t flags;
   uint8_t loop_flags;
   uint8_t game_events;
   uint8_t user_flags;

   // controller data
   struct controller_info_s controller;

   // inventory data: grabbed items
   struct inventory_info_s inventory;

   // enemies left
   uint16_t enemies_alive;
   uint16_t enemies_killed;

   // pointer to beeper sound fx to play when required
   void *beeper_fx;
   // id of tracker sound fx to play when required
   uint16_t tracker_fx;

#ifdef BUILD_FEATURE_GAME_TIME
   // game_time: seconds elapsed since start of game
   uint16_t game_time;
#endif

#ifdef BUILD_FEATURE_CUSTOM_STATE_DATA
   // custom state data
   uint8_t custom_data[ CUSTOM_STATE_DATA_SIZE ];
#endif

#ifndef BUILD_FEATURE_GAMEAREA_COLOR_FULL
   uint8_t default_mono_attr;
#endif
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


// 0x0001 value unused
// the hero nust be redrawn
#define F_LOOP_REDRAW_HERO		0x0002
// inside EXIT hotzone
#define F_LOOP_WARP_TO_SCREEN		0x0004
// an item was picked up
#define F_LOOP_ITEM_GRABBED		0x0008
// play pending beeper effect
#define F_LOOP_PLAY_BEEPER_FX		0x0010
// play pending tracker effect
#define F_LOOP_PLAY_TRACKER_FX		0x0020

///////////////////////////////////////////////
// game events macros and definitions
///////////////////////////////////////////////

#define GET_GAME_EVENT(f)	(game_state.game_events & (f))
#define SET_GAME_EVENT(f)	(game_state.game_events |= (f))
#define RESET_GAME_EVENT(f)	(game_state.game_events &= ~(f))
#define RESET_ALL_GAME_EVENTS()	(game_state.game_events = 0)

// player has received a hit
#define E_HERO_WAS_HIT			0x0001
// enemy was hit
#define E_ENEMY_WAS_HIT			0x0002
// an item was picked up
#define E_ITEM_WAS_GRABBED		0x0004
// a crumb was picked up
#define E_CRUMB_WAS_GRABBED		0x0008
// the hero died
#define E_HERO_DIED			0x0010
// a bullet was shot
#define E_BULLET_WAS_SHOT		0x0020

///////////////////////////////////////////////
// user flags macros and definitions
///////////////////////////////////////////////

#define GET_USER_FLAG(f)	(game_state.user_flags & (f))
#define SET_USER_FLAG(f)	(game_state.user_flags |= (f))
#define RESET_USER_FLAG(f)	(game_state.user_flags &= ~(f))
#define RESET_ALL_USER_FLAGS()	(game_state.user_flags = 0)


#endif // _GAME_STATE_H
