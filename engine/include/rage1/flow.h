////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _FLOW_H
#define _FLOW_H

#include <arch/spectrum.h>

#include "features.h"

////////////////////////////////////////////////
//
// FLOWGEN RULE CHECKS
//
////////////////////////////////////////////////

// flow rule check constants
// always update RULE_CHECK_MAX when adding new checks!
#define RULE_CHECK_GAME_FLAG_IS_SET		0
#define RULE_CHECK_GAME_FLAG_IS_RESET		1
#define RULE_CHECK_LOOP_FLAG_IS_SET		2
#define RULE_CHECK_LOOP_FLAG_IS_RESET		3
#define RULE_CHECK_USER_FLAG_IS_SET		4
#define RULE_CHECK_USER_FLAG_IS_RESET		5
#define RULE_CHECK_LIVES_EQUAL			6
#define RULE_CHECK_LIVES_MORE_THAN		7
#define RULE_CHECK_LIVES_LESS_THAN		8
#define RULE_CHECK_ENEMIES_ALIVE_EQUAL		9
#define RULE_CHECK_ENEMIES_ALIVE_MORE_THAN	10
#define RULE_CHECK_ENEMIES_ALIVE_LESS_THAN	11
#define RULE_CHECK_ENEMIES_KILLED_EQUAL		12
#define RULE_CHECK_ENEMIES_KILLED_MORE_THAN	13
#define RULE_CHECK_ENEMIES_KILLED_LESS_THAN	14
#define RULE_CHECK_CALL_CUSTOM_FUNCTION		15
#define RULE_CHECK_ITEM_IS_OWNED		16
#define RULE_CHECK_HERO_OVER_HOTZONE		17
#define RULE_CHECK_SCREEN_FLAG_IS_SET		18
#define RULE_CHECK_SCREEN_FLAG_IS_RESET		19
#define RULE_CHECK_FLOW_VAR_EQUAL		20
#define RULE_CHECK_FLOW_VAR_MORE_THAN		21
#define RULE_CHECK_FLOW_VAR_LESS_THAN		22
#define RULE_CHECK_GAME_TIME_EQUAL		23
#define RULE_CHECK_GAME_TIME_MORE_THAN		24
#define RULE_CHECK_GAME_TIME_LESS_THAN		25
#define RULE_CHECK_GAME_EVENT_HAPPENED		26

#define RULE_CHECK_MAX				26

struct flow_rule_check_s {
    uint8_t type;
    union {
        uint16_t					unused;		// for checks that do not need data
        struct { uint8_t	flag; }			flag_state;	// USER_FLAG_*, GAME_FLAG_*, LOOP_FLAG_*, SCREEN_FLAG
        struct { uint8_t	count; }		lives;		// INC_LIVES
        struct { uint16_t	count; }		enemies;	// ENEMIES_ALIVE_*, ENEMIES_KILLED_*
        struct { uint8_t	function_id, param; }	custom;		// CALL_CUSTOM_FUNCTION
        struct { uint16_t	item_id; }		item;		// ITEM_IS_OWNED
        struct { uint8_t	num_hotzone; }		hotzone;	// HERO_INSIDE_HOTZONE
        struct { uint8_t	var_id, value; }	flow_var;	// FLOW_VAR_*
        struct { uint16_t	seconds; }		game_time;	// GAME_TIME_*
        struct { uint8_t	event; }		game_event;	// GAME_EVENT_HAPPENED
    } data;
};

////////////////////////////////////////////////
//
// FLOWGEN RULE ACTIONS
//
////////////////////////////////////////////////

// flow rule action constants
// always update RULE_ACTION_MAX when adding new actions!
#define RULE_ACTION_SET_USER_FLAG		0
#define RULE_ACTION_RESET_USER_FLAG		1
#define RULE_ACTION_PLAY_SOUND			2
#define RULE_ACTION_INC_LIVES			3
#define RULE_ACTION_CALL_CUSTOM_FUNCTION	4
#define RULE_ACTION_END_OF_GAME			5
#define RULE_ACTION_WARP_TO_SCREEN		6
#define RULE_ACTION_ENABLE_HOTZONE		7
#define RULE_ACTION_DISABLE_HOTZONE		8
#define RULE_ACTION_ENABLE_BTILE		9
#define RULE_ACTION_DISABLE_BTILE		10
#define RULE_ACTION_ADD_TO_INVENTORY		11
#define RULE_ACTION_REMOVE_FROM_INVENTORY	12
#define RULE_ACTION_SET_SCREEN_FLAG		13
#define RULE_ACTION_RESET_SCREEN_FLAG		14
#define RULE_ACTION_FLOW_VAR_STORE		15
#define RULE_ACTION_FLOW_VAR_INC		16
#define RULE_ACTION_FLOW_VAR_ADD		17
#define RULE_ACTION_FLOW_VAR_DEC		18
#define RULE_ACTION_FLOW_VAR_SUB		19
#define RULE_ACTION_TRACKER_SELECT_SONG		20
#define RULE_ACTION_TRACKER_MUSIC_STOP		21
#define RULE_ACTION_TRACKER_MUSIC_START		22
#define RULE_ACTION_TRACKER_PLAY_FX		23
#define RULE_ACTION_HERO_ENABLE_WEAPON		24
#define RULE_ACTION_HERO_DISABLE_WEAPON		25
#define RULE_ACTION_ENABLE_ENEMY		26
#define RULE_ACTION_DISABLE_ENEMY		27

#define RULE_ACTION_MAX				27

struct flow_rule_action_s {
    uint8_t type;
    union {
        uint16_t					unused;		// for actions that do not need data
        struct { uint8_t	count; }		lives;		// INC_LIVES
        struct { void		*sound_id; }		play_sound;	// PLAY_SOUND
        struct { uint8_t	flag; }			user_flag;	// SET_USER_FLAG, RESET_USER_FLAG
        struct { uint16_t	count; }		enemies;	// ENEMIES_ALIVE_*, ENEMIES_KILLED_*
        struct { uint8_t	function_id, param; }	custom;		// CALL_CUSTOM_FUNCTION
        struct { uint8_t	num_hotzone; }		hotzone;	// ENABLE/DISABLE_HOTZONE
        struct { uint8_t	num_btile; }		btile;		// ENABLE/DISABLE_BTILE
        struct { uint8_t	num_enemy; }		enemy;		// ENABLE/DISABLE_ENEMY
        struct { 
            uint8_t	num_screen;
            uint8_t	hero_x;
            uint8_t	hero_y;
            uint8_t	flags;
            }						warp_to_screen;	// WARP_TO_SCREEN
        struct { uint16_t	item_id; }		item;		// ADD_TO/REMOVE_FROM_INVENTORY
        struct { uint8_t	num_screen, flag; }	screen_flag;	// SET/RESET_SCREEN_FLAG
        struct { uint8_t	var_id, value; }	flow_var;	// FLOW_VAR_*
        struct { uint8_t	num_song; }		tracker_song;	// TRACKER_SELECT_SONG
        struct { uint16_t	num_effect; }		tracker_fx;	// TRACKER_PLAY_FX
    } data;
};

// flags for action WARP_TO_SCREEN
#define ACTION_WARP_TO_SCREEN_KEEP_HERO_X	(0x01)
#define ACTION_WARP_TO_SCREEN_KEEP_HERO_Y	(0x02)

// data definition for a rule
struct flow_rule_s {
    // what to check
    uint8_t num_checks;
    struct flow_rule_check_s *checks;
    // what to do if all checks are successful
    uint8_t num_actions;
    struct flow_rule_action_s *actions;
};

struct flow_rule_table_s {
    uint8_t num_rules;
    struct flow_rule_s **rules;
};

// function types for custom checks/actions
typedef uint8_t (*check_custom_function_t)( uint8_t param );
typedef void (*action_custom_function_t)( uint8_t param );

// executes user flow rules
void check_flow_rules( void );
void check_game_event_rules( void );

#endif //_FLOW_H
